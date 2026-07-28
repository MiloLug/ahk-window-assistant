#Requires AutoHotkey v2.0

#Include Context.ahk


ctx := ClsContext()

eventManager := ctx.eventManager
windowManager := ctx.windowManager
desktopManager := ctx.desktopManager

SetInteractableWindowsFilter(filter) {
    windowManager.SetInteractableWindowsFilter(filter)
}


MoveWindowToDesktop(ahkWindowTitle, number) {
    hwnd := windowManager.GetID(ahkWindowTitle)
    if (!hwnd)
        return
    if (number == -1)
        number := desktopManager.GetPreviousDesktopNum()
    desktopManager.MoveWindowToDesktop(hwnd, number)
}

GoToDesktop(n, restoreMousePosition:=true) {
    if (n == -1)
        n := desktopManager.GetPreviousDesktopNum()

    desktopManager.FillDesktops(n)

    try {
        activeHwnd := windowManager.GetID("A")
        if (activeHwnd && windowManager.IsDraggingWindow(activeHwnd)) {
            desktopManager.MoveWindowToDesktop(activeHwnd, n)
            restoreMousePosition := false
        }
    }
    desktopManager.GoToDesktop(n, restoreMousePosition, restoreMousePosition)
}

PinAndSetOnTop(ahkWindowTitle) {
    hwnd := windowManager.GetID(ahkWindowTitle)
    if (desktopManager.ToggleWindowPin(hwnd)) {
        windowManager.SetAlwaysOnTop(hwnd, 1)
    } else {
        windowManager.SetAlwaysOnTop(hwnd, 0)
    }
}

MoveMouseToWindow(windowHwnd) {
    try {
        WinGetPos(&winX, &winY, &winWidth, &winHeight, windowHwnd)
    } catch {
        OutputDebug("Failed to get position of " DebugDescribeTarget(windowHwnd))
        return false
    }
    mouseX := winX + winWidth * 0.5
    mouseY := winY + winHeight * 0.5
    DllCall("SetCursorPos", "Int", mouseX, "Int", mouseY)
    return true
}

WinMonActivate(windowHwnd) {
    OutputDebug("Activating " DebugDescribeTarget(windowHwnd))
    if (windowHwnd < 0) {
        ctx.monitorManager.Activate(-windowHwnd)
    } else if (windowHwnd > 0) {
        ctx.eventManager.Trigger(EV_WINDOW_FOCUSED_WITH_KB, windowHwnd)
    }
}

/**
 * @description Activate a spatial-nav target, then put the mouse on the visible fragment.
 */
NavActivate(target) {
    WinMonActivate(target)
    landRect := windowManager.spatialNavigator.PopLandRect()
    if (landRect) {
        Geometry.RectCenter(landRect, &x, &y)
        DllCall("SetCursorPos", "Int", x, "Int", y)
    }
}

GoToLeftWindow() {
    NavActivate(windowManager.spatialNavigator.GetLeft())
}
GoToRightWindow() {
    NavActivate(windowManager.spatialNavigator.GetRight())
}
GoToTopWindow() {
    NavActivate(windowManager.spatialNavigator.GetTop())
}
GoToBottomWindow() {
    NavActivate(windowManager.spatialNavigator.GetBottom())
}
GoDownLayer() {
    NavActivate(windowManager.spatialNavigator.GetLayerDown())
}
GoUpLayer() {
    NavActivate(windowManager.spatialNavigator.GetLayerUp())
}

SafeCloseCurrent() {
    switchTo := windowManager.spatialNavigator.ClosestOverlapped()
    id := windowManager.GetID("A")
    if (id != 0)
        WinClose(id)

    if (switchTo != 0)
        WinMonActivate(switchTo)
}

SwitchCapsLock() {
    if (GetKeyState("CapsLock", "T")) {
        SetCapsLockState('Off')
    } else {
        SetCapsLockState('On')
    }
}