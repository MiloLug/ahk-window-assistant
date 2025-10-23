#Requires AutoHotkey v2.0

#Include Core.ahk
#Include Utils.ahk

/**
 * @description Fix mouse sometimes not following window focus when alt-tabbing,
 * closing with keyboard, etc.
 * @param {(TitleFilter)} focusTitles - titles of windows to focus
 */
UseFixMouseOnKBWindowFocus(focusTitles:=0) {
    eventManager.On(EV_WINDOW_FOCUSED_WITH_KB, MouseFollowFocus)
    MouseFollowFocus(newHwnd) {
        if (
            !windowManager.IsInteractiveWindow(newHwnd)
            or (focusTitles and not focusTitles.TestWindow(newHwnd))
        )
            return

        try {
            WinActivate(newHwnd)
            MoveMouseToWindow(newHwnd)
            OutputDebug("Focused window on KB: " newHwnd)
        } catch {
            OutputDebug("Failed to focus window on KB: " newHwnd)
        }
    }
}

/**
 * @description Fix flashing and new window focus (for example, the consent window for UAC)
 * @param {(TitleFilter)} focusTitles - titles of windows to focus
 * @param {(Boolean)} dontStealMouse - if true, don't focus when mouse is moving/was just moved
 */
UseFlashFocusWindows(focusTitles:=0, dontStealMouse:=true) {
    eventManager.On(EV_WINDOW_FLASH, FocusNewWindow)
    eventManager.On(EV_NEW_WINDOW, FocusNewWindow)
    FocusNewWindow(hwnd, mouseJustMoved) {
        if (
            (mouseJustMoved and dontStealMouse)
            or !windowManager.IsInteractiveWindow(hwnd)
            or (focusTitles and not focusTitles.TestWindow(hwnd))
        )
            return

        try {
            WinActivate(hwnd)
            MoveMouseToWindow(hwnd)
            OutputDebug("Focused new window: " hwnd)
        } catch {
            OutputDebug("Failed to focus new window: " hwnd)
        }
    }
}

UseDesktopChangeAsMouseMove() {
    windowManager.SetConsiderDesktopChangeAsMove(true)
}