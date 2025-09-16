#Requires AutoHotkey v2.0

#include Constants.ahk


class WindowManagerError extends Error {
    __New() => this
}

class CountedFlagInvocation {
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


class WindowCollectionNavigator {
    __New(windowManager, listSelector:='', currentSelector:='A') {
        this._windowManager := windowManager
        this._windows := []
        this._windowsMap := Map()
        this._listSelector := listSelector
        this._currentSelector := currentSelector

        this._FinishNavigation_Bind := this._FinishNavigation.Bind(this)
        this._currentN := 1

        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._FinishNavigation_Bind, 0)
        this._FinishNavigation_Bind := 0
    }

    _StartNavigation() {
        newMap := Map()
        currentHwnd := WinGetID(this._currentSelector)
        newWindows := this._windowManager.GetList(this._listSelector, true)
        if (newWindows.Length == 0) {
            this._windows := []
            this._windowsMap.Clear()
            return
        }

        ; Manage current window
        if (this._windowsMap.Has(currentHwnd)) {
            if (this._windows[1] != currentHwnd) {
                for i, hwnd in this._windows {
                    if (hwnd == currentHwnd) {
                        this._windows.RemoveAt(i)
                        this._windows.InsertAt(1, hwnd)
                        break
                    }
                }
            }
        } else {
            this._windows.InsertAt(1, currentHwnd)
            this._windowsMap[currentHwnd] := true
        }

        ; Add new windows
        newOffset := 1

        for windowHwnd in newWindows {
            newMap[windowHwnd] := true
            if (!this._windowsMap.Has(windowHwnd)) {
                newOffset++
                this._windows.InsertAt(2, windowHwnd)
            }
        }

        ; Remove old windows
        i := this._windows.Length
        while (i > newOffset) {
            if (!newMap.Has(this._windows[i])) {
                this._windows.RemoveAt(i)
            }
            i--
        }
        this._windowsMap := newMap
    }

    /**
     * @description Navigate to the next window
     */
    Next(instant:=true) {
        SetTimer(this._FinishNavigation_Bind, 0)
        if (this._currentN == 1) {
            this._StartNavigation()
        }
        this._currentN++
        SetTimer(this._FinishNavigation_Bind, 500)
        if (instant) {
            WinActivate(this._windows[Mod(this._currentN - 1, this._windows.Length) + 1])
        }
    }

    /**
     * @description Called after we stop navigating to reset the state
     */
    _FinishNavigation() {
        this._currentN := 1
    }
}

class LazyWindowManager {
    __New() {
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

        this._cleanDanglingObjects_Bind := this._CleanDanglingObjects.Bind(this)
        this._nonInteractiveFilter := TitleFilter([
            "*",
            "!ahk_class XamlExplorerHostIslandWindow",  ; exclude the Alt-Tab and preview windows
            "!ahk_class Shell_TrayWnd",  ; exclude the taskbar
            "!ahk_class Shell_SecondaryTrayWnd",  ; exclude the secondary taskbar (on non-primary monitors)
            "!ahk_class Progman",  ; exclude the desktop
            "!ahk_class IME",  ; exclude the IME
            "!ahk_class Windows.UI.Core.CoreWindow",  ; exclude the start menu, search, etc.
        ])
        this._navigators := Map()

        SetTimer(this._cleanDanglingObjects_Bind, 5000)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._cleanDanglingObjects_Bind, 0)
        this._cleanDanglingObjects_Bind := 0
        this._OnVirtualDesktopChanged_Bind := 0
        this._UpdateMouseMoveTime_Bind := 0
        this._eventManager := 0
        this._messenger := 0
        this._topmostWindowsInvocations.Clear()
        this._maximizedWindowsInvocations.Clear()
        this._navigators.Clear()
    }

    /**
     * @description Get the window ID of a window or 0 if the window is non-interactive or doesn't exist
     * @param {(String)} ahkWindowTitle
     */
    GetID(ahkWindowTitle, hidden:=false) {
        if (hidden) {
            prevDetectHidden := A_DetectHiddenWindows
            DetectHiddenWindows(1)
        }
        try {
            id := WinGetID(ahkWindowTitle)
            if (this.IsInteractiveWindow(id))
                return id
        } finally {
            if (hidden) {
                DetectHiddenWindows(prevDetectHidden)
            }
        }
        return 0
    }

    /**
     * @description Get the list of window IDs of a window or an empty array if the window is non-interactive or doesn't exist
     * @param {(String)} ahkWindowTitle
     * @param {(Boolean)} hidden
     */
    GetList(ahkWindowTitle:='', hidden:=false) {
        if (hidden) {
            prevDetectHidden := DetectHiddenWindows(1)
        }
        list := WinGetList(ahkWindowTitle)
        
        res := []
        for id in list {
            if (this.IsInteractiveWindow(id))
                res.Push(id)
        }

        if (hidden) {
            DetectHiddenWindows(prevDetectHidden)
        }
        return res
    }

    IsInteractiveWindow(hwnd) {
        style := WinGetStyle(hwnd)
        if (!(style & WS_VISIBLE) || (style & WS_DISABLED))
            return false

        style := WinGetExStyle(hwnd)
        if (style & WS_EX_TOOLWINDOW)
            return false

        if (!this._nonInteractiveFilter.TestWindow(hwnd))
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

        mouseJustMoved := A_TickCount - this._lastMouseMoveTime < 500

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
        if (this._eventManager != 0) {
            throw WindowManagerError("Event manager already registered")
        }
        this._eventManager := eventManager

        DllCall("RegisterShellHookWindow", "UInt", A_ScriptHwnd)
        this._messenger := DllCall("RegisterWindowMessage", "Str","SHELLHOOK")

        OnMessage(this._messenger, this._OnShellHookMessage.Bind(this))

        this._eventManager.AddLazyRegistrator(EV_WINDOW_FOCUSED_WITH_KB, () => this._SetupWindowSwitchWatch())
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
        minMax := WinGetMinMax(windowHwnd)

        ; We shouldn't move minimized windows
        if (minMax == -1)
            return

        MouseGetPos(&mouseX1, &mouseY1)
        WinGetPos(&windowX1, &windowY1, &windowW1, &windowH1, windowHwnd)
        this._freeDraggingWindowHwnd := windowHwnd

        ; If the window is maximized, then it's convenient ot restore it for moving
        ; for example, to move it to another screen
        if (minMax != WIN_RESTORED) {
            this.InvokeWinRestored(windowHwnd)
            MouseGetPos(&mouseX1, &mouseY1)
            WinGetPos(&windowX1R, &windowY1R, &windowW1R, &windowH1R, windowHwnd)

            mouseX1Win := (mouseX1 - windowX1) / windowW1 * windowW1R
            mouseY1Win := (mouseY1 - windowY1) / windowH1 * windowH1R

            mouseX1 := windowX1R + mouseX1Win
            mouseY1 := windowY1R + mouseY1Win
            windowX1 := windowX1R
            windowY1 := windowY1R
        }

        this.InvokeAlwaysOnTop(windowHwnd)
        loop {
            if (shouldStop(windowHwnd))
                break

            MouseGetPos(&mouseX2, &mouseY2)
            mouseX2 -= mouseX1
            mouseY2 -= mouseY1
            if (mouseX2 == 0 and mouseY2 == 0)
                continue

            WinMove(windowX1 + mouseX2, windowY1 + mouseY2,,, windowHwnd)
        }
        this.LeaveAlwaysOnTop(windowHwnd)
        this.LeaveWinRestored(windowHwnd)
        this._freeDraggingWindowHwnd := 0
    }

    SendSizeUpdated(windowHwnd, width, height) {
        SendMessage(WM_SIZE, 0, (width & 0xFFFF) | ((height & 0xFFFF) << 16), , windowHwnd)
    }

    SendCalcSize(windowHwnd, left, top, right, bottom) {
        rect := Buffer(16)
        NumPut(
            "Int", left,
            "Int", top,
            "Int", right,
            "Int", bottom,
            rect
        )
        ;SendMessage(WM_SIZING, 0, rect,, windowHwnd)
        SendMessage(WM_NCCALCSIZE, 0, rect,, windowHwnd)
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
        ; We shouldn't move maximized windows
        if WinGetMinMax(windowHwnd)
            return
        MouseGetPos(&mouseX1, &mouseY1)
        WinGetPos(&windowX1, &windowY1, &windowW1, &windowH1, windowHwnd)

        if (mouseX1 < windowX1 + windowW1 / 2)
            hResize := 1
        else
            hResize := -1

        if (mouseY1 < windowY1 + windowH1 / 2)
            vResize := 1
        else
            vResize := -1

        ; top    4 5
        ; bottom 7 8
        if (vResize == 1) {
            if (hResize == 1)
                wParam := 4
            else
                wParam := 5
        } else {
            if (hResize == 1)
                wParam := 7
            else
                wParam := 8
        }

        this._freeResizingWindowHwnd := windowHwnd
        SendMessage(WM_ENTERSIZEMOVE, 0, 0, , windowHwnd)

        this.InvokeAlwaysOnTop(windowHwnd)
        loop {
            if shouldStop(windowHwnd)
                break

            MouseGetPos(&mouseX2, &mouseY2)
            mouseX2 -= mouseX1
            mouseY2 -= mouseY1

            windowW2 := windowW1 - hResize * mouseX2
            windowH2 := windowH1 - vResize * mouseY2
            windowX2 := windowX1 + (hResize + 1) / 2 * mouseX2
            windowY2 := windowY1 + (vResize + 1) / 2 * mouseY2
            WinMove(
                windowX2,
                windowY2,
                windowW2,
                windowH2,
                windowHwnd
            )
            ; TODO: I'm not sure if this works or IF IT'S NEEDED AT ALL. Need to fix the painting issue when resizing somehow
            this.SendCalcSize(windowHwnd, windowX2, windowY2, windowX2 + windowW2, windowY2 + windowH2)
            PostMessage(WM_PAINT,,, , windowHwnd)
        }
        this.LeaveAlwaysOnTop(windowHwnd)
        SendMessage(WM_EXITSIZEMOVE, 0, 0, , windowHwnd)
        this.SendSizeUpdated(windowHwnd, windowW2, windowH2)
        this._freeResizingWindowHwnd := 0
    }

    /**
     * @description Check if a window is being dragged or resized
     * It makes its best to guess, but it's not 100% accurate, bear in mind.
     * @param {(Integer)} windowHwnd
     * @returns {(Boolean)}
     */
    IsDraggingWindow(windowHwnd) {
        windowHeaderSize := 25

        if (this._freeDraggingWindowHwnd == windowHwnd or this._freeResizingWindowHwnd == windowHwnd)
            return true

        if (!GetKeyState("LButton"))
            return false

        MouseGetPos(&x, &y, &mouseWindowHwnd)
        if (mouseWindowHwnd != windowHwnd)
            return false

        try {
            res := SendMessage(WM_NCHITTEST, 0, (x & 0xFFFF) | ((y & 0xFFFF) << 16),, windowHwnd)
        } catch {
            return false
        }
        if (res == HTCAPTION or res == HTBORDER) {
            return true
        }

        WinGetPos(&windowX, &windowY, &windowW, &windowH, windowHwnd)
        if ((x > windowX and x < windowX + windowW) and (y > windowY and y < windowY + windowHeaderSize)) {
            return true
        }
    }

    IsAlwaysOnTop(windowHwnd) {
        return WinGetExStyle(windowHwnd) & WS_EX_TOPMOST
    }

    /**
     * @description Invoke always on top for a window when dragging, resizing, etc.
     * @param {(Integer)} windowHwnd
     */
    InvokeAlwaysOnTop(windowHwnd) {
        ; Yes, this could be done way simpler, like just checking IsAlwaysOnTop
        ; But this way, we can distinguish between the user setting the window to top
        ; and the window being set to top temporarily, for example, when dragging a window
        state := this._topmostWindowsInvocations.Get(windowHwnd, 0)
        if (state == 0) {
            state := CountedFlagInvocation(this.IsAlwaysOnTop(windowHwnd))
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
        invocation := this._topmostWindowsInvocations.Get(windowHwnd, 0)
        if (invocation != 0 and force) {
            invocation.external := true
        }
        WinSetAlwaysOnTop(state, windowHwnd)
    }

    InvokeWinRestored(windowHwnd) {
        invocation := this._maximizedWindowsInvocations.Get(windowHwnd, 0)
        if (invocation == 0) {
            invocation := CountedFlagInvocation(WinGetMinMax(windowHwnd))
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
            if (invocation.original != WIN_RESTORED and !invocation.external)
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
     * @description Get the window to the left of the mouse cursor
     * @returns {(Integer)} windowHwnd, 0 if no window is found
     */
    WinGetLeft() {
        try {
            curHwnd := WinGetID("A")
        } catch {
            return 0
        }
        WinGetPos(&curX, &curY, &curWinW, &curWinH, curHwnd)
        cX := curX + curWinW / 2
        cY := curY + curWinH / 2

        winList := WinGetList()
        if (winList.Length == 0)
            return 0

        closestHwnd := 0
        closestD := 0xFFFF

        for winHwnd in winList {
            if (winHwnd == curHwnd or winHwnd == 0)
                continue
            WinGetPos(&winX, &winY, &winW, &winH, winHwnd)
            winX := winX + winW / 2
            winY := winY + winH / 2
            if (winX < cX and this.IsInteractiveWindow(winHwnd)) {
                d := this._CalcHLogicalDistance(winX, winY, cX, cY)
                if (d < closestD) {
                    closestHwnd := winHwnd
                    closestD := d
                }
            }
        }

        return closestHwnd
    }

    _CalcHLogicalDistance(x1, y1, x2, y2) {
        dX := (x1 - x2) / 10
        dY := (y1 - y2) / 10 * 8
        return Sqrt(dX * dX + dY * dY)
    }

    _CalcVLogicalDistance(x1, y1, x2, y2) {
        dX := (x1 - x2) * 8
        dY := y1 - y2
        return Sqrt(dX * dX + dY * dY)
    }

    /**
     * @description Get the window to the right of the current window
     * @returns {(Integer)} windowHwnd, 0 if no window is found
     */
    WinGetRight() {
        try {
            curHwnd := WinGetID("A")
        } catch {
            return 0
        }
        WinGetPos(&curX, &curY, &curWinW, &curWinH, curHwnd)
        cX := curX + curWinW / 2
        cY := curY + curWinH / 2

        winList := WinGetList()
        if (winList.Length == 0)
            return 0

        closestHwnd := 0
        closestD := 0xFFFF

        for winHwnd in winList {
            if (winHwnd == curHwnd)
                continue
            WinGetPos(&winX, &winY, &winW, &winH, winHwnd)
            winX := winX + winW / 2
            winY := winY + winH / 2
            if (winX > cX and this.IsInteractiveWindow(winHwnd)) {
                d := this._CalcHLogicalDistance(winX, winY, cX, cY)
                if (d < closestD) {
                    closestHwnd := winHwnd
                    closestD := d
                }
            }
        }

        return closestHwnd
    }

    /**
     * @description Get the window to the top of the current window
     * @returns {(Integer)} windowHwnd, 0 if no window is found
     */
    WinGetTop() {
        try {
            curHwnd := WinGetID("A")
        } catch {
            return 0
        }
        WinGetPos(&curX, &curY, &curWinW, &curWinH, curHwnd)
        cX := curX + curWinW / 2
        cY := curY + curWinH / 2

        winList := WinGetList()
        if (winList.Length == 0)
            return 0

        closestHwnd := 0
        closestD := 0xFFFF

        for winHwnd in winList {
            if (winHwnd == curHwnd or winHwnd == 0)
                continue
            WinGetPos(&winX, &winY, &winW, &winH, winHwnd)
            winX := winX + winW / 2
            winY := winY + winH / 2
            if (winY < cY and this.IsInteractiveWindow(winHwnd)) {
                d := this._CalcVLogicalDistance(winX, winY, cX, cY)
                if (d < closestD) {
                    closestHwnd := winHwnd
                    closestD := d
                }
            }
        }

        return closestHwnd
    }

    /**
     * @description Get the window to the bottom of the current window
     * @returns {(Integer)} windowHwnd, 0 if no window is found
     */
    WinGetBottom() {
        try {
            curHwnd := WinGetID("A")
        } catch {
            return 0
        }
        WinGetPos(&curX, &curY, &curWinW, &curWinH, curHwnd)
        cX := curX + curWinW / 2
        cY := curY + curWinH / 2

        winList := WinGetList()
        if (winList.Length == 0)
            return 0

        closestHwnd := 0
        closestD := 0xFFFF
        
        for winHwnd in winList {
            if (winHwnd == curHwnd or winHwnd == 0)
                continue
            WinGetPos(&winX, &winY, &winW, &winH, winHwnd)
            winX := winX + winW / 2
            winY := winY + winH / 2
            if (winY > cY and this.IsInteractiveWindow(winHwnd)) {
                d := this._CalcVLogicalDistance(winX, winY, cX, cY)
                if (d < closestD) {
                    closestHwnd := winHwnd
                    closestD := d
                }
            }
        }

        return closestHwnd
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
                this._navigators[exeSelector] := WindowCollectionNavigator(this, exeSelector)
            )
        }
    }
}