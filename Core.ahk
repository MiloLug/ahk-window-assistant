#Requires AutoHotkey v2.0

#Include VirtualDesktopManager.ahk
#Include Events.ahk
#Include WindowManager.ahk


eventManager := ClsEventBus()
desktopManager := ClsVirtualDesktopManager()
windowManager := CslWindowManager()

windowManager.RegisterEventManager(eventManager)
desktopManager.RegisterEventManager(eventManager)


SetNonInteractiveWindowsFilter(filter) {
    windowManager.SetNonInteractiveWindowsFilter(filter)
}


MoveWindowToDesktop(ahkWindowTitle, number) {
    hwnd := windowManager.GetID(ahkWindowTitle)
    if (hwnd == 0) {
        return
    }
    if (number == -1) {
        number := desktopManager.GetPreviousDesktopNum()
    }
    desktopManager.MoveWindowToDesktop(hwnd, number)
}

GoToDesktop(n, restoreMousePosition:=true) {
    if (n == -1) {
        n := desktopManager.GetPreviousDesktopNum()
    }
    desktopManager.FillDesktops(n)

    try {
        activeHwnd := windowManager.GetID("A")
        if (activeHwnd and windowManager.IsDraggingWindow(activeHwnd)) {
            MoveWindowToDesktop(activeHwnd, n)
            restoreMousePosition := false
        }
    } catch {
    }
    desktopManager.GoToDesktop(n, restoreMousePosition, restoreMousePosition)
}

PinAndSetOnTop(ahkWindowTitle) {
    hwnd := windowManager.GetID(ahkWindowTitle)
    if (desktopManager.ToggleWindowPin(hwnd)) {
        OutputDebug("Pinning window " hwnd)
        windowManager.SetAlwaysOnTop(hwnd, 1)
    } else {
        OutputDebug("Unpinning window " hwnd)
        windowManager.SetAlwaysOnTop(hwnd, 0)
    }
}

MoveMouseToWindow(windowHwnd) {
    try {
        WinGetPos(&winX, &winY, &winWidth, &winHeight, windowHwnd)
        mouseX := winX + winWidth * 0.5
        mouseY := winY + winHeight * 0.5
        DllCall("SetCursorPos", "Int", mouseX, "Int", mouseY)
    } catch {
        OutputDebug("Failed to get position of window " windowHwnd)
    }
}

GoToLeftWindow() {
    windowHwnd := windowManager.WinGetLeft()
    if (windowHwnd != 0) {
        WinActivate(windowHwnd)
    }
}
GoToRightWindow() {
    windowHwnd := windowManager.WinGetRight()
    if (windowHwnd != 0) {
        WinActivate(windowHwnd)
    }
}
GoToTopWindow() {
    windowHwnd := windowManager.WinGetTop()
    if (windowHwnd != 0) {
        WinActivate(windowHwnd)
    }
}
GoToBottomWindow() {
    windowHwnd := windowManager.WinGetBottom()
    if (windowHwnd != 0) {
        WinActivate(windowHwnd)
    }
}

SafeWinClose(ahkWindowTitle) {
    id := windowManager.GetID(ahkWindowTitle)
    if (id != 0)
        WinClose(id)
}