#Requires AutoHotkey v2.0

#include Constants.ahk
#include Config.ahk
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
        this._watchWindowFocusWithKB := false

        this._freeDraggingWindowHwnd := 0
        this._freeResizingWindowHwnd := 0

        this._considerDesktopChangeAsMove := false
        this._UpdateMouseMoveTime_Bind := this._UpdateMouseMoveTime.Bind(this)
        this._OnVirtualDesktopChanged_Bind := this._OnVirtualDesktopChanged.Bind(this)

        this._lastDestroyTime := 0

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
        this._SetupWindowSwitchWatch_Bind := this._SetupWindowSwitchWatch.Bind(this)
        this._OnShellHookMessage_Bind := this._OnShellHookMessage.Bind(this)

        SetTimer(this._cleanDanglingObjects_Bind, 5000)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._cleanDanglingObjects_Bind, 0)
        this.UnregisterEventManager()
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
     * @param {(Boolean)} detectHidden
     * @param {(Boolean)} interactableOnly
     * @param {(Boolean)} detectMinimized
     */
    GetID(ahkWindowTitle, detectHidden:=false, interactableOnly:=true, detectMinimized:=true) {
        if (detectHidden) {
            prevDetectHidden := A_DetectHiddenWindows
            DetectHiddenWindows(1)
        }
        try {
            id := WinGetID(ahkWindowTitle)
            if (
                (not interactableOnly or this.IsInteractableWindow(id))
                and (detectMinimized or WinGetMinMax(id) != WIN_MINIMIZED)
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
     * @param {(Boolean)} detectHidden - whether to detect hidden windows
     * @param {(Boolean)} interactableOnly - whether to only return interactable windows
     * @param {(Boolean)} detectMinimized - whether to detect minimized windows
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
                    and (detectMinimized or WinGetMinMax(id) != WIN_MINIMIZED)
                )
                    res.Push(id)
            }
        } else {
            res := list
        }

        if (detectHidden) {
            DetectHiddenWindows(prevDetectHidden)
        }
        return res
    }

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

        style := WinGetExStyle(hwnd)
        if (style & WS_EX_TOOLWINDOW)
            return false

        if (!this._interactableFilter.TestWindow(hwnd))
            return false

        return true
    }

    SetConsiderDesktopChangeAsMove(consider) {
        if (this._considerDesktopChangeAsMove == consider)
            return

        this._considerDesktopChangeAsMove := consider

        if (this._eventManager == 0)
            return

        if (consider)
            this._eventManager.On(EV_VIRTUAL_DESKTOP_CHANGED, this._OnVirtualDesktopChanged_Bind)
        else
            this._eventManager.Off(EV_VIRTUAL_DESKTOP_CHANGED, this._OnVirtualDesktopChanged_Bind)
    }

    _OnShellHookMessage(message, id, *) {
        Critical(1)
        this._eventManager.Trigger(EV_SHELLHOOK, message, id)

        mouseJustMoved := A_TickCount - this._lastMouseMoveTime < Config.MOUSE_MOVE_TIMEOUT

        switch message {
            case HSHELL_FLASH:
                this._eventManager.Trigger(EV_WINDOW_FLASH, id, mouseJustMoved)
            case HSHELL_WINDOWCREATED:
                this._eventManager.Trigger(EV_NEW_WINDOW, id, mouseJustMoved)
            case HSHELL_WINDOWDESTROYED:
                this._lastDestroyTime := A_TickCount
                this._eventManager.Trigger(EV_WINDOW_DESTROYED, mouseJustMoved)
            case HSHELL_RUDEAPPACTIVATED, HSHELL_WINDOWACTIVATED:
                if (id != 0 and this._watchWindowFocusWithKB and not mouseJustMoved and A_TickCount - this._lastDestroyTime > 200) {
                    Sleep(10)
                    this._eventManager.Trigger(EV_WINDOW_FOCUSED_WITH_KB, id)
                }
        }
	}

    _UpdateMouseMoveTime(*) {
        if (A_TickCount > this._lastMouseMoveTime) {
            this._lastMouseMoveTime := A_TickCount
        }
    }

    _OnVirtualDesktopChanged(prev, new, restoredMouse) {
        if (restoredMouse)
            this._UpdateMouseMoveTime()
    }

    _SetupWindowSwitchWatch() {
        this._watchWindowFocusWithKB := true

        Hotkey('~*LButton', this._UpdateMouseMoveTime_Bind)
        Hotkey('~*RButton', this._UpdateMouseMoveTime_Bind)
        Hotkey('~*MButton', this._UpdateMouseMoveTime_Bind)
        this._eventManager.On(EV_MOUSE_MOVED, this._UpdateMouseMoveTime_Bind)

        if (this._considerDesktopChangeAsMove)
            this._eventManager.On(EV_VIRTUAL_DESKTOP_CHANGED, this._OnVirtualDesktopChanged_Bind)
    }

    RegisterEventManager(eventManager) {
        if (this._eventManager != 0)
            throw ClsWindowManagerError("Event manager already registered")
        this._eventManager := eventManager

        DllCall("RegisterShellHookWindow", "UInt", A_ScriptHwnd)
        this._messenger := DllCall("RegisterWindowMessage", "Str","SHELLHOOK")

        OnMessage(this._messenger, this._OnShellHookMessage_Bind)

        this._eventManager.AddLazyRegistrator(EV_WINDOW_FOCUSED_WITH_KB, this._SetupWindowSwitchWatch_Bind)
    }

    UnregisterEventManager() {
        if (this._eventManager == 0)
            return
        ; not that important if event manager is already broken or deleted
        try {
            this._eventManager.RemoveLazyRegistrator(EV_WINDOW_FOCUSED_WITH_KB, this._SetupWindowSwitchWatch_Bind)
        }
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
        if (!windowHwnd or (minMax := WinGetMinMax(windowHwnd)) == WIN_MINIMIZED)
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
            if (mouseXOffset == 0 and mouseYOffset == 0)
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
        if (!windowHwnd or WinGetMinMax(windowHwnd) != WIN_RESTORED)
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
            if (mouseXOffset == 0 and mouseYOffset == 0)
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

        if (this._freeDraggingWindowHwnd == windowHwnd or this._freeResizingWindowHwnd == windowHwnd)
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
        if (res == HTCAPTION or res == HTBORDER)
            return true

        WinGetPos(&windowX, &windowY, &windowW, &windowH, windowHwnd)
        if ((x > windowX and x < windowX + windowW) and (y > windowY and y < windowY + windowHeaderSize))
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
            if (!state.original and !state.external)
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
        if (invocation != 0 and force) {
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
                and !invocation.external
                and WinGetMinMax(windowHwnd) == WIN_RESTORED
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
        if (invocation != 0 and force) {
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