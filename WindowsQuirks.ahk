#Requires AutoHotkey v2.0

#Include Core.ahk
#Include Utils.ahk

/**
 * @description Fix mouse sometimes not following window focus when alt-tabbing,
 * closing with keyboard, etc.
 * @param {(TitleFilter)} focusTitles - titles of windows to focus
 */
UseFixMouseOnKBWindowFocus(focusTitles) {
    eventManager.On(EV_WINDOW_FOCUSED_WITH_KB, MouseFollowFocus)
    MouseFollowFocus(newHwnd) {
        try {
            hwnd := WinGetID(newHwnd)
        } catch {
            return
        }

        if (focusTitles.TestWindow(hwnd)) {
            OutputDebug("Focusing window on KB: " hwnd)
            WinActivate(hwnd)
            MoveMouseToWindow(hwnd)
        }
    }
}

/**
 * @description Fix flashing and new window focus (for example, the consent window for UAC)
 * @param {(TitleFilter)} focusTitles - titles of windows to focus
 * @param {(Boolean)} dontStealMouse - if true, don't focus when mouse is moving/was just moved
 */
UseFlashFocusWindows(focusTitles, dontStealMouse:=true) {
    eventManager.On(EV_WINDOW_FLASH, FocusNewWindow)
    eventManager.On(EV_NEW_WINDOW, FocusNewWindow)
    FocusNewWindow(hwnd, mouseJustMoved) {
        if (mouseJustMoved and dontStealMouse)
            return

        OutputDebug("Focusing new window " hwnd)
        try {
            if (focusTitles.TestWindow(hwnd)) {
                WinActivate(hwnd)
                MoveMouseToWindow(hwnd)
                OutputDebug("Focused new window " hwnd)
            }
        }
    }
}

UseDesktopChangeAsMouseMove() {
    windowManager.SetConsiderDesktopChangeAsMove(true)
}