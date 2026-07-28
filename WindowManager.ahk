#Requires AutoHotkey v2.0

#include Constants.ahk
#include Config.ahk
#include ForegroundWatcher.ahk
#include Navigators/SequenceNavigator.ahk
#include Navigators/SpatialNavigator.ahk

class ClsWindowManagerError extends Error {
    __New(message) {
        super(message)
    }
}

/**
 * @description A helper for invoking and leaving contexts that require setting a flag
 */
class ClsCountedFlagInvocation {
    __New(original := 0) {
        this.regTime := A_TickCount
        this.i := 1
        this.original := original
        this.external := false
        this.finished := false
    }

    Invoke() {
        this.i++
    }

    Leave() {
        return --this.i == 0
    }
}


class ClsWindowManager {
    __New(ctx) {
        this._ctx := ctx

        this._eventManager := 0
        this._messenger := 0

        this._lastMouseMoveTime := 0
        this._foregroundWatcher := 0

        this._freeDraggingWindowHwnd := 0
        this._freeResizingWindowHwnd := 0

        this._UpdateMouseMoveTime_Bind := this._UpdateMouseMoveTime.Bind(this)
        this._OnVirtualDesktopChanged_Bind := this._OnVirtualDesktopChanged.Bind(this)

        ; { windowHwnd: CountedFlagInvocation }
        this._topmostWindowsInvocations := Map()
        this._maximizedWindowsInvocations := Map()
        this._lowWinDelayInvocation := 0

        this._cleanDanglingObjects_Bind := this._CleanDanglingObjects.Bind(this)
        
        ; TODO: idk like... Setting this here? Maybe should move to config or something later
        this._interactableFilter := TitleFilter([
            "*",
            "!ahk_class XamlExplorerHostIslandWindow",  ; exclude the Alt-Tab and preview windows
            "!ahk_class Shell_TrayWnd",  ; exclude the taskbar
            "!ahk_class Shell_SecondaryTrayWnd",  ; exclude the secondary taskbar (on non-primary monitors)
            "!ahk_class Progman",  ; exclude the desktop
            "!ahk_class IME",  ; exclude the IME
            "!ahk_class Windows.UI.Core.CoreWindow",  ; exclude the start menu, search, etc.
            "!ahk_exe DesktopMate.exe",  ; exclude the desktop mate
            "!ahk_exe MateEngineX.exe",  ; exclude the mate engine
        ])
        this._navigators := Map()
        this.spatialNavigator := ClsSpatialWindowNavigator(ctx)
        this._SetupForegroundWatch_Bind := this._SetupForegroundWatch.Bind(this)
        this._SetupKBFocusDerivation_Bind := this._SetupKBFocusDerivation.Bind(this)
        this._DeriveKBFocus_Bind := this._DeriveKBFocus.Bind(this)
        this._OnShellHookMessage_Bind := this._OnShellHookMessage.Bind(this)

        SetTimer(this._cleanDanglingObjects_Bind, 5000)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._cleanDanglingObjects_Bind, 0)
        this.UnregisterEventManager()
        this._foregroundWatcher := 0
        this._topmostWindowsInvocations.Clear()
        this._maximizedWindowsInvocations.Clear()
        this._navigators.Clear()
    }

    /**
     * @description Set the filter for interactable windows.
     * 
     * Don't forget to add "*"
     * 
     * @param {(TitleFilter)} filter
     */
    SetInteractableWindowsFilter(filter) {
        this._interactableFilter := filter
    }

    /**
     * @description Get the window ID of a window or 0 if the window is non-interactive or doesn't exist
     * @param {(String)} ahkWindowTitle
     * @param {(Boolean)} detectHidden - if true, will detect hidden windows (DetectHiddenWindows ahk flag)
     * @param {(Boolean)} interactableOnly - if false, will return non-interactive windows as tooltips, disabled etc.
     * @param {(Boolean)} detectMinimized - if false, won't return minimized windows
     */
    GetID(ahkWindowTitle, detectHidden:=false, interactableOnly:=true, detectMinimized:=true) {
        if (detectHidden) {
            prevDetectHidden := A_DetectHiddenWindows
            DetectHiddenWindows(1)
        }
        try {
            id := WinGetID(ahkWindowTitle)
            if (
                (!interactableOnly || this.IsInteractableWindow(id))
                && (detectMinimized || WinGetMinMax(id) != WIN_MINIMIZED)
            )
                return id
        } finally {
            if (detectHidden) {
                DetectHiddenWindows(prevDetectHidden)
            }
        }
        return 0
    }

    /**
     * @description Get the list of window IDs of a window or an empty array if the window is non-interactive or doesn't exist
     * @param {(String)} ahkWindowTitle
     * @param {(Boolean)} detectHidden - if true, will detect hidden windows (DetectHiddenWindows ahk flag)
     * @param {(Boolean)} interactableOnly - if false, will return non-interactive windows as tooltips, disabled etc.
     * @param {(Boolean)} detectMinimized - if false, won't return minimized windows
     */
    GetList(ahkWindowTitle:='', detectHidden:=false, interactableOnly:=true, detectMinimized:=true) {
        if (detectHidden) {
            prevDetectHidden := DetectHiddenWindows(1)
        }
        list := WinGetList(ahkWindowTitle)
        
        res := []

        if (interactableOnly) {
            for id in list {
                if (
                    (this.IsInteractableWindow(id))
                    && (detectMinimized || WinGetMinMax(id) != WIN_MINIMIZED)
                )
                    res.Push(id)
            }
        } else {
            res := list
        }

        if (detectHidden)
            DetectHiddenWindows(prevDetectHidden)

        return res
    }

    /**
     * @description Check if a window is interactable, can be focused, not disabled etc.
     * @param {(Integer)} hwnd
     * @returns {(Boolean)}
     */
    IsInteractableWindow(hwnd) {
        if (!hwnd)
            return false

        try {
            style := WinGetStyle(hwnd)
        } catch {
            return false
        }
        if (!(style & WS_VISIBLE) || (style & WS_DISABLED))
            return false

        try {
            style := WinGetExStyle(hwnd)
        } catch {
            return false
        }
        if (style & WS_EX_TOOLWINDOW)
            return false

        if (!this._interactableFilter.TestWindow(hwnd))
            return false

        return true
    }

    _OnShellHookMessage(message, id, *) {
        Critical(1)
        this._eventManager.Trigger(EV_SHELLHOOK, message, id)

        mouseJustMoved := this.MouseJustMoved()

        switch message {
            case HSHELL_FLASH:
                this._eventManager.Trigger(EV_WINDOW_FLASH, id, mouseJustMoved)
            case HSHELL_WINDOWCREATED:
                this._eventManager.Trigger(EV_NEW_WINDOW, id, mouseJustMoved)
            case HSHELL_WINDOWDESTROYED:
                this._eventManager.Trigger(EV_WINDOW_DESTROYED, mouseJustMoved)
                ; focus falls back to another window after a destroy
                if (this._foregroundWatcher != 0)
                    this._foregroundWatcher.Poke()
            case HSHELL_RUDEAPPACTIVATED, HSHELL_WINDOWACTIVATED:
                ; the payload id is a tmp thing - it's only a hint,
                ; but the actual state already cold've changed
                if (this._foregroundWatcher != 0)
                    this._foregroundWatcher.Poke()
        }
	}

    /**
     * @description Whether the user physically moved or clicked the mouse recently
     * or SOMETHING happened that tells us
     * "the user is in control of the cursor, don't mess with it"
     * @returns {(Boolean)}
     */
    MouseJustMoved() {
        return A_TickCount - this._lastMouseMoveTime < Config.MOUSE_MOVE_TIMEOUT
    }

    /**
     * @description Activate a window
     * This must be used instead of the default WinActivate
     * so the internals of the window manager could know that it's an internal activation
     * and work with that info
     * @param {(Integer)} windowHwnd
     */
    ActivateWindow(windowHwnd) {
        if (!windowHwnd)
            return
        if (this._foregroundWatcher != 0)
            this._foregroundWatcher.Expect(windowHwnd)
        try {
            WinActivate(windowHwnd)
        } catch {
            OutputDebug("Failed to activate " DebugDescribeTarget(windowHwnd))
        }
    }

    _UpdateMouseMoveTime(*) {
        if (A_TickCount > this._lastMouseMoveTime)
            this._lastMouseMoveTime := A_TickCount
    }

    _OnVirtualDesktopChanged(prev, new, restoredMouse) {
        if (restoredMouse)
            this._UpdateMouseMoveTime()
    }

    _SetupForegroundWatch() {
        Hotkey('~*LButton', this._UpdateMouseMoveTime_Bind)
        Hotkey('~*RButton', this._UpdateMouseMoveTime_Bind)
        Hotkey('~*MButton', this._UpdateMouseMoveTime_Bind)
        this._eventManager.On(EV_MOUSE_MOVED, this._UpdateMouseMoveTime_Bind)
        this._eventManager.On(EV_VIRTUAL_DESKTOP_CHANGED, this._OnVirtualDesktopChanged_Bind)

        this._foregroundWatcher := ClsForegroundWatcher(this._ctx)
    }

    _SetupKBFocusDerivation() {
        this._eventManager.On(EV_FOREGROUND_CHANGED, this._DeriveKBFocus_Bind)
    }

    _DeriveKBFocus(newHwnd, prevHwnd, mouseJustMoved) {
        if (!mouseJustMoved)
            this._eventManager.Trigger(EV_WINDOW_FOCUSED_WITH_KB, newHwnd)
    }

    RegisterEventManager(eventManager) {
        if (this._eventManager != 0)
            throw ClsWindowManagerError("Event manager already registered")
        this._eventManager := eventManager

        DllCall("RegisterShellHookWindow", "UInt", A_ScriptHwnd)
        this._messenger := DllCall("RegisterWindowMessage", "Str","SHELLHOOK")

        OnMessage(this._messenger, this._OnShellHookMessage_Bind)

        this._eventManager.AddLazyRegistrar(EV_FOREGROUND_CHANGED, this._SetupForegroundWatch_Bind)
        this._eventManager.AddLazyRegistrar(EV_WINDOW_FOCUSED_WITH_KB, this._SetupKBFocusDerivation_Bind)
    }

    UnregisterEventManager() {
        if (this._eventManager == 0)
            return
        ; not that important if event manager is already broken or deleted
        try this._eventManager.RemoveLazyRegistrar(EV_FOREGROUND_CHANGED, this._SetupForegroundWatch_Bind)
        try this._eventManager.RemoveLazyRegistrar(EV_WINDOW_FOCUSED_WITH_KB, this._SetupKBFocusDerivation_Bind)
        try this._eventManager.Off(EV_FOREGROUND_CHANGED, this._DeriveKBFocus_Bind)
        this._eventManager := 0
        OnMessage(this._messenger, this._OnShellHookMessage_Bind, 0)
    }

    /**
     * @description Start dragging a window with mouse movement
     * @param {(Integer)} windowHwnd
     * @param {(FuncObj)} shouldStop
     * The {@link https://www.autohotkey.com/docs/v2/misc/Functor.htm|function object} to check if the drag should stop
     * 
     *         shouldStop(title) => Boolean
     */
    StartMouseWindowFreeDrag(windowHwnd, shouldStop) {
        if (!windowHwnd || (minMax := WinGetMinMax(windowHwnd)) == WIN_MINIMIZED)
            return

        MouseGetPos(&mouseXStart, &mouseYStart)
        WinGetPos(&windowX, &windowY, &windowW, &windowH, windowHwnd)
        this._freeDraggingWindowHwnd := windowHwnd

        ; If the window is maximized, then it's convenient ot restore it for moving
        ; for example, to move it to another screen
        if (minMax == WIN_MAXIMIZED) {
            this.InvokeWinRestored(windowHwnd)
            WinGetPos(,, &windowWR, &windowHR, windowHwnd)

            ; Calculate what mouse position SHOULD BE relative to the restored window
            mouseXWinR := (mouseXStart - windowX) / windowW * windowWR
            mouseYWinR := (mouseYStart - windowY) / windowH * windowHR

            ; Offset the window so the mouse is in the right spot
            windowX := mouseXStart - mouseXWinR
            windowY := mouseYStart - mouseYWinR

            WinMove(windowX, windowY,,, windowHwnd)
        }

        this.InvokeAlwaysOnTop(windowHwnd)
        this.InvokeLowWinDelay()
        loop {
            if (shouldStop(windowHwnd))
                break

            MouseGetPos(&mouseXOffset, &mouseYOffset)
            mouseXOffset -= mouseXStart
            mouseYOffset -= mouseYStart
            if (mouseXOffset == 0 && mouseYOffset == 0)
                continue

            WinMove(windowX + mouseXOffset, windowY + mouseYOffset,,, windowHwnd)
        }
        this.LeaveLowWinDelay()
        this.LeaveAlwaysOnTop(windowHwnd)
        if (minMax == WIN_MAXIMIZED)
            this.LeaveWinRestored(windowHwnd)
        this._freeDraggingWindowHwnd := 0
    }

    /**
     * @description Start resizing a window with mouse movement
     * @param {(Integer)} ahkWindowTitle
     * @param {(FuncObj)} shouldStop
     * The {@link https://www.autohotkey.com/docs/v2/misc/Functor.htm|function object} to check if the drag should stop
     * 
     *         shouldStop(title) => Boolean
     */
    StartMouseWindowFreeResize(windowHwnd, shouldStop) {
        if (!windowHwnd || WinGetMinMax(windowHwnd) != WIN_RESTORED)
            return
        MouseGetPos(&mouseXStart, &mouseYStart)
        WinGetPos(&windowX, &windowY, &windowW, &windowH, windowHwnd)

        hResizeDir := (mouseXStart < windowX + windowW / 2) ? -1 : 1
        hMoveDir := (1 - hResizeDir) / 2
        vResizeDir := (mouseYStart < windowY + windowH / 2) ? -1 : 1
        vMoveDir := (1 - vResizeDir) / 2

        this._freeResizingWindowHwnd := windowHwnd

        this.InvokeAlwaysOnTop(windowHwnd)
        loop {
            if (shouldStop(windowHwnd))
                break

            MouseGetPos(&mouseXOffset, &mouseYOffset)
            mouseXOffset -= mouseXStart
            mouseYOffset -= mouseYStart
            if (mouseXOffset == 0 && mouseYOffset == 0)
                continue

            WinMove(
                windowX + hMoveDir * mouseXOffset,
                windowY + vMoveDir * mouseYOffset,
                windowW + hResizeDir * mouseXOffset,
                windowH + vResizeDir * mouseYOffset,
                windowHwnd
            )
        }
        this.LeaveAlwaysOnTop(windowHwnd)
        this._freeResizingWindowHwnd := 0
    }

    /**
     * @description Check if a window is being dragged or resized
     * It makes its best to guess, but it's not 100% accurate, bear in mind.
     * @param {(Integer)} windowHwnd
     * @returns {(Boolean)}
     */
    IsDraggingWindow(windowHwnd) {
        if (!windowHwnd)
            return false

        windowHeaderSize := Config.WINDOW_HEADER_SIZE

        if (this._freeDraggingWindowHwnd == windowHwnd || this._freeResizingWindowHwnd == windowHwnd)
            return true

        if (!GetKeyState("LButton"))
            return false

        MouseGetPos(&x, &y, &mouseWindowHwnd)
        if (mouseWindowHwnd != windowHwnd)
            return false

        try {
            res := WinCalls.SendWmNchittest(windowHwnd, x, y)
        } catch {
            return false
        }
        if (res == HTCAPTION || res == HTBORDER)
            return true

        WinGetPos(&windowX, &windowY, &windowW, &windowH, windowHwnd)
        if ((x > windowX && x < windowX + windowW) && (y > windowY && y < windowY + windowHeaderSize))
            return true
    }

    IsAlwaysOnTop(windowHwnd) {
        if (!windowHwnd)
            return false
        return WinGetExStyle(windowHwnd) & WS_EX_TOPMOST
    }

    /**
     * @description Invoke always-on-top for a window when dragging, resizing, etc.
     * @param {(Integer)} windowHwnd
     */
    InvokeAlwaysOnTop(windowHwnd) {
        if (!windowHwnd)
            return
        ; Yes, this could be done way simpler, like just checking IsAlwaysOnTop
        ; But this way, we can distinguish between the user setting the window to top
        ; and the window being set to top temporarily, for example, when dragging a window
        state := this._topmostWindowsInvocations.Get(windowHwnd, 0)
        if (state == 0) {
            state := ClsCountedFlagInvocation(this.IsAlwaysOnTop(windowHwnd))
            this._topmostWindowsInvocations[windowHwnd] := state
            if (!state.original)
                WinSetAlwaysOnTop(1, windowHwnd)
        } else {
            state.Invoke()
        }
    }

    /**
     * @description Leave always on top for a window when dragging, resizing, etc.
     * @param {(Integer)} windowHwnd
     */
    LeaveAlwaysOnTop(windowHwnd) {
        if (!windowHwnd)
            return
        state := this._topmostWindowsInvocations.Get(windowHwnd, 0)
        if (state == 0) {
            return
        }

        if (state.Leave()) {
            ; If the user sets the window to top, we should leave it as is
            if (!state.original && !state.external)
                WinSetAlwaysOnTop(0, windowHwnd)
            this._topmostWindowsInvocations.Delete(windowHwnd)
        }
    }

    /**
     * @description Set the always on top state of a window
     * @param {(Integer)} windowHwnd
     * @param {(Integer)} state
     *   - `1` = on top
     *   - `0` = off top
     *   - `-1` = toggle
     * @param {(Boolean)} force
     *   - `true` = break the invocation chain
     *   - `false` = don't break the invocation chain
     */
    SetAlwaysOnTop(windowHwnd, state, force := true) {
        if (!windowHwnd)
            return
        invocation := this._topmostWindowsInvocations.Get(windowHwnd, 0)
        if (invocation != 0 && force) {
            invocation.external := true
        }
        WinSetAlwaysOnTop(state, windowHwnd)
    }

    /**
     * @description Invoke a state where the window is restored (not maximized or minimized)
     * 
     * **WHY**: In some cases, just using restore and returning the original state can go contrary to what user
     *   or other parts of the code do with the window.
     *   
     * For example, if the user maximizes while dragging. Why? Just because they can
     * 
     * @param windowHwnd - the window to invoke the state for
     */
    InvokeWinRestored(windowHwnd) {
        invocation := this._maximizedWindowsInvocations.Get(windowHwnd, 0)
        if (invocation == 0) {
            invocation := ClsCountedFlagInvocation(WinGetMinMax(windowHwnd))
            this._maximizedWindowsInvocations[windowHwnd] := invocation
            if (invocation.original != WIN_RESTORED)
                WinRestore(windowHwnd)
        } else {
            invocation.Invoke()
        }
    }

    LeaveWinRestored(windowHwnd) {
        invocation := this._maximizedWindowsInvocations.Get(windowHwnd, 0)
        if (invocation == 0) {
            return
        }
        if (invocation.Leave()) {
            if (
                invocation.original != WIN_RESTORED
                && !invocation.external
                && WinGetMinMax(windowHwnd) == WIN_RESTORED
            )
                this.SetMinMax(windowHwnd, invocation.original)
            this._maximizedWindowsInvocations.Delete(windowHwnd)
        }
    }

    /**
     * @description Set the maximized state of a window
     * @param {(Integer)} windowHwnd
     * @param {(Integer)} state
     *   - `1` = maximized
     *   - `0` = restored
     *   - `-1` = minimized
     * @param {(Boolean)} force
     *   - `true` = break the invocation chain
     *   - `false` = don't break the invocation chain
     */
    SetMinMax(windowHwnd, state, force := true) {
        invocation := this._maximizedWindowsInvocations.Get(windowHwnd, 0)
        if (invocation != 0 && force) {
            invocation.external := true
        }
        switch state {
            case WIN_MAXIMIZED:
                WinMaximize(windowHwnd)
            case WIN_RESTORED:
                WinRestore(windowHwnd)
            case WIN_MINIMIZED:
                WinMinimize(windowHwnd)
        }
    }

    /**
     * @description Invoke a state where A_WinDelay is 0
     * 
     * **WHY**: Not all cases by far require a 0 delay to look good,
     *   for example, resizing is horrible with such a low delay
     */
    InvokeLowWinDelay() {
        if (this._lowWinDelayInvocation == 0) {
            this._lowWinDelayInvocation := ClsCountedFlagInvocation(A_WinDelay)
            SetWinDelay(0)
        } else {
            this._lowWinDelayInvocation.Invoke()
        }
    }

    LeaveLowWinDelay() {
        if (this._lowWinDelayInvocation == 0)
            return
        if (this._lowWinDelayInvocation.Leave()) {
            if (A_WinDelay == 0)  ; if it's not 0, probably managed by something else
                SetWinDelay(this._lowWinDelayInvocation.original)
            this._lowWinDelayInvocation := 0
        }
    }

    _CleanDanglingObjects() {
        toDelete := []
        for windowHwnd, state in this._topmostWindowsInvocations {
            if (A_TickCount - state.regTime > 10000) {
                if (!WinExist(windowHwnd)) {
                    toDelete.Push(windowHwnd)
                }
            }
        }
        for windowHwnd in toDelete {
            this._topmostWindowsInvocations.Delete(windowHwnd)
        }
    }

    /**
     * @description Get the navigator for all app-specific windows
     * @param {(String)} ahkWindowTitle - exe name will be selected based on this window
     */
    GetAppNavigator(ahkWindowTitle:='A') {
        proc := WinGetProcessName(ahkWindowTitle)
        exeSelector := "ahk_exe " proc
        if (this._navigators.Has(exeSelector)) {
            return this._navigators[exeSelector]
        } else {
            return (
                this._navigators[exeSelector] := ClsSequenceWindowNavigator(this._ctx, exeSelector)
            )
        }
    }
}


/**
 * @description A class to manage windows
 * @param {(Context)} ctx - the context to use
 * @returns {(ClsWindowManagerACTUAL)} - the window manager
 */
class ClsWindowManagerACTUAL {
    __New(ctx) {
    }
}