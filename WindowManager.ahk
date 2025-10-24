#Requires AutoHotkey v2.0

#include Constants.ahk
#include Geometry.ahk


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

/**
 * @description A class to navigate through a collection of windows with Alt-Tab-like behavior
 * @param {(WindowManager)} windowManager - the window manager to use
 * @param {(String)} listSelector - the selector to use to get the list of windows
 * @param {(String)} currentSelector - the selector to use to get the current window
 */
class ClsSequenceWindowNavigator {
    __New(windowManager, listSelector:='', currentSelector:='A') {
        this._windowManager := windowManager
        this._windows := []
        this._windowsMap := Map()
        this._listSelector := listSelector
        this._currentSelector := currentSelector

        this._EndNavigation_Bind := this._EndNavigation.Bind(this)
        this._currentN := 1
        this._activateOnFinish := true

        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._EndNavigation_Bind, 0)
        this._EndNavigation_Bind := 0
        this._windowManager := 0
    }

    /**
     * @description Update the current window
     * Should be called before updating the list for optimal performance
     */
    _UpdateCurrentWindow() {
        currentHwnd := WinGetID(this._currentSelector)
        if (this._windowsMap.Has(currentHwnd)) {
            ; Since it's already in the list, we can just move it to the front
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
    }

    /**
     * @description Update the list of windows
     * Updates the list in a natural way, so the order of the windows is preserved as much as possible.
     */
    _UpdateWindowsList() {
        newMap := Map()
        newWindows := this._windowManager.GetList(this._listSelector, true)
        if (newWindows.Length == 0) {
            this._windows := []
            this._windowsMap.Clear()
            return
        }
        ; if we have at least one window, consider it 'current' and don't move it around
        ; this way, if it's 0, we'll insert new windows at the beginning, otherwise at index = 2
        hasCurrent := this._windows.Length > 0

        ; Add new windows
        toAdd := []
        for windowHwnd in newWindows {
            newMap[windowHwnd] := true
            if (!this._windowsMap.Has(windowHwnd)) {
                toAdd.Push(windowHwnd)
            }
        }
        if (toAdd.Length > 0) {
            ; 1st being the current window, so we will navigate to
            ; the new windows next
            this._windows.InsertAt(1 + hasCurrent, toAdd*)
        }

        ; Remove old windows
        i := this._windows.Length
        ; skip since we already know new windows exist
        lastNewI := toAdd.Length + hasCurrent
        while (i > lastNewI) {
            if (!newMap.Has(this._windows[i])) {
                this._windows.RemoveAt(i)
            }
            i--
        }
        this._windowsMap := newMap
    }

    _GetSelected() {
        return this._windows[Mod(this._currentN - 1, this._windows.Length) + 1]
    }

    /**
     * @description Navigate to the next window
     * @param {(Boolean)} instant - if true, the window will be activated immediately
     */
    Next(instant:=true) {
        SetTimer(this._EndNavigation_Bind, 0)
        if (this._currentN == 1) {
            this._UpdateCurrentWindow()
            this._UpdateWindowsList()

            if (this._windows.Length == 0) {
                return
            }
        }
        this._currentN++
        this._activateOnFinish := !instant
        if (instant) {
            WinActivate(this._GetSelected())
        }
        SetTimer(this._EndNavigation_Bind, 500)
    }

    /**
     * @description Called after we stop navigating, to reset the state
     */
    _EndNavigation() {
        if (this._activateOnFinish) {
            WinActivate(this._GetSelected())
        }
        this._currentN := 1
    }
}


/**
 * @description A class to navigate through a collection of windows with spatial behavior
 * @param {(WindowManager)} windowManager - the window manager to use
 * @param {(String)} listSelector - the selector to use to get the list of windows
 * @param {(String)} currentSelector - the selector to use to get the current window
 * @param {(Float)} intersectionThreshold - the threshold for considering a window as intersecting with the current window. The check is:
 * 
 *         Sqrt(intersectionArea) / Sqrt(window1Area + window2Area) > intersectionThreshold
 */
class ClsSpatialWindowNavigator {
    __New(windowManager, listSelector:='', currentSelector:='A', intersectionThreshold:=0.1) {
        this._windowManager := windowManager
        this._listSelector := listSelector
        this._currentSelector := currentSelector
        this._currentHwnd := 0
        this._intersectionThreshold := intersectionThreshold

        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        this._windowManager := 0
    }

    _CalcLogicalDistance(x1, y1, x2, y2, xCost:=1, yCost:=1) {
        dX := (x1 - x2) * xCost
        dY := (y1 - y2) * yCost
        return Sqrt(dX * dX + dY * dY)
    }

    _GetCoords(hwnd, &w, &h, &l, &r, &t, &b) {
        WinCalls.WinGetPosEx(hwnd, &l, &t, &w, &h, &r, &b)
    }

    /**
     * @description Traverse to the nearest topmost window by going upwards through overlapping windows
     * @param {(Array)} distList - array of [distance-from-point, windowHwnd, left, right, top, bottom, width, height]
     * @param {(Integer)} currentIndex - the index of the current window in the list
     */
    _TraverseToNearestTopmost(distList, currentIndex) {
        current := distList[currentIndex]
        currentArea := current[7] * current[8]

        nearestDistance := 0xFFFFFFFF
        nearestIndex := currentIndex

        i := currentIndex - 1
        while (i > 0) {
            checking := distList[i]
            interArea := Geometry.GetIntersectionArea(
                current[3], current[5], current[4], current[6],
                checking[3], checking[5], checking[4], checking[6]
            )
            checkingArea := checking[7] * checking[8]
            if (
                interArea > 0
                and Sqrt(interArea) / Sqrt(checkingArea + currentArea) > this._intersectionThreshold
                and checking[1] < nearestDistance
            ) {
                nearestDistance := checking[1]
                nearestIndex := i
            }
            i--
        }

        ; If it's still the same window or the first one, then there are no more overlapping windows
        if (nearestIndex == currentIndex || nearestIndex == 1) {
            return distList[nearestIndex][2]
        }

        ; We can go to the next overlapping window
        if (nearestIndex > 0) {
            return this._TraverseToNearestTopmost(distList, nearestIndex)
        }

        return 0
    }

    /**
     * @description Find the closest window in the list
     * @param {(Array)} distList - array of [distance-from-point, windowHwnd, left, right, top, bottom, width, height]
     */
    _TraverseToNearest(distList) {
        nearestDistance := 0xFFFFFFFF
        nearestIndex := 0

        for i, checking in distList {
            ; We search for the smallest distance, and overlapping windows have negative distance,
            ; so the more they overlap, the smaller (bigger negative) the distance.
            ; And then not overlapping windows will be the next closest candidates
            if (checking[1] < nearestDistance) {
                nearestDistance := checking[1]
                nearestIndex := i
            }
        }

        if (nearestIndex > 1) {
            ; Most likely, we want to move to the nearest AND topmost window.
            ; So we need to go through the list of windows on top of the current closest
            return this._TraverseToNearestTopmost(distList, nearestIndex)
        }

        if (nearestIndex == 1) {
            return distList[1][2]
        }

        return 0
    }

    /**
     * @description Get the closest window from a side
     * @param {(Integer)} side - the side to get the closest window from
     *   - `0` - left
     *   - `1` - right
     *   - `2` - top
     *   - `3` - bottom
     */
    _GetFromSide(side) {
        try {
            curHwnd := this._windowManager.GetID(this._currentSelector)
        } catch {
            return 0
        }
        this._GetCoords(curHwnd, &w, &h, &l, &r, &t, &b)

        winList := this._windowManager.GetList(this._listSelector)
        if (winList.Length == 0)
            return 0

        distances := []

        ; I know, this is ugly, but it's faster than assigning a filter function to each side
        switch side {
            case 0:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wR <= l)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 0, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 1:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wL >= r)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 0, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 2:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wB <= t)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 1, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 3:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wT >= b)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 1, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
        }

        if (distances.Length == 0)
            return 0

        return this._TraverseToNearest(distances)
    }

    GetLeft() {
        return this._GetFromSide(0)
    }

    GetRight() {
        return this._GetFromSide(1)
    }

    GetTop() {
        return this._GetFromSide(2)
    }

    GetBottom() {
        return this._GetFromSide(3)
    }

    /**
     * @description Find the next overlapping window in Z-order
     */
    NextOverlapping() {
        try {
            curHwnd := this._windowManager.GetID(this._currentSelector)
        } catch {
            return 0
        }
        this._GetCoords(curHwnd, &w, &h, &l, &r, &t, &b)

        winList := this._windowManager.GetList(this._listSelector)
        if (winList.Length == 0)
            return 0

        for winHwnd in ArrReversedIter(winList) {
            this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
            if (
                winHwnd != curHwnd
                and wL <= r and wR >= l and wT <= b and wB >= t
                ; to avoid overlapping with neighboring windows
                and wL != r and wT != b and wR != l and wB != t
            ) {
                OutputDebug("Overlapping window: " winHwnd)
                return winHwnd
            }
        }
        return 0
    }
}

class CslWindowManager {
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
        this._lowWinDelayInvocation := 0

        this._cleanDanglingObjects_Bind := this._CleanDanglingObjects.Bind(this)
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
        this.spatialNavigator := ClsSpatialWindowNavigator(this)
        this._SetupWindowSwitchWatch_Bind := this._SetupWindowSwitchWatch.Bind(this)
        this._OnShellHookMessage_Bind := this._OnShellHookMessage.Bind(this)

        SetTimer(this._cleanDanglingObjects_Bind, 5000)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._cleanDanglingObjects_Bind, 0)
        this.UnregisterEventManager()
        this._cleanDanglingObjects_Bind := 0
        this._OnVirtualDesktopChanged_Bind := 0
        this._UpdateMouseMoveTime_Bind := 0
        this._eventManager := 0
        this._messenger := 0
        this._topmostWindowsInvocations.Clear()
        this._maximizedWindowsInvocations.Clear()
        this._navigators.Clear()
        this._interactableFilter := 0
        this._spatialNavigator := 0
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
     */
    GetID(ahkWindowTitle, detectHidden:=false) {
        if (detectHidden) {
            prevDetectHidden := A_DetectHiddenWindows
            DetectHiddenWindows(1)
        }
        try {
            id := WinGetID(ahkWindowTitle)
            if (this.IsInteractiveWindow(id))
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
     * @param {(Boolean)} detectHidden
     */
    GetList(ahkWindowTitle:='', detectHidden:=false) {
        if (detectHidden) {
            prevDetectHidden := DetectHiddenWindows(1)
        }
        list := WinGetList(ahkWindowTitle)
        
        res := []
        for id in list {
            if (this.IsInteractiveWindow(id))
                res.Push(id)
        }

        if (detectHidden) {
            DetectHiddenWindows(prevDetectHidden)
        }
        return res
    }

    IsInteractiveWindow(hwnd) {
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
        this._eventManager.RemoveLazyRegistrator(EV_WINDOW_FOCUSED_WITH_KB, this._SetupWindowSwitchWatch_Bind)
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

        MouseGetPos(&mouseX1, &mouseY1)
        WinGetPos(&windowX1, &windowY1, &windowW1, &windowH1, windowHwnd)
        this._freeDraggingWindowHwnd := windowHwnd

        ; If the window is maximized, then it's convenient ot restore it for moving
        ; for example, to move it to another screen
        if (minMax != WIN_RESTORED) {
            this.InvokeWinRestored(windowHwnd)
            WinGetPos(&windowX1R, &windowY1R, &windowW1R, &windowH1R, windowHwnd)

            ; Mouse position in the resized window
            mouseX1Win := (mouseX1 - windowX1) / windowW1 * windowW1R
            mouseY1Win := (mouseY1 - windowY1) / windowH1 * windowH1R

            windowX1 := mouseX1 - mouseX1Win
            windowY1 := mouseY1 - mouseY1Win

            WinMove(windowX1, windowY1,,, windowHwnd)
        }

        this.InvokeAlwaysOnTop(windowHwnd)
        this.InvokeLowWinDelay()
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
        this.LeaveLowWinDelay()
        this.LeaveAlwaysOnTop(windowHwnd)
        if (minMax != WIN_RESTORED)
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
            WinCalls.SendWmNccalcsize(windowHwnd, windowX2, windowY2, windowX2 + windowW2, windowY2 + windowH2)
            PostMessage(WM_PAINT,,, , windowHwnd)
        }
        this.LeaveAlwaysOnTop(windowHwnd)
        SendMessage(WM_EXITSIZEMOVE, 0, 0, , windowHwnd)
        WinCalls.SendWmSize(windowHwnd, windowW2, windowH2)
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

        windowHeaderSize := 25

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
                this._navigators[exeSelector] := ClsSequenceWindowNavigator(this, exeSelector)
            )
        }
    }
}