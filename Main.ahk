#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
InstallKeybdHook()
SetWinDelay(10)  ; This won't affect such things as moving windows, they invoke delay 0 internally
CoordMode("Mouse", "Screen")

SetWorkingDir(A_ScriptDir)

A_MenuMaskKey := "vkE8"

#Include Core.ahk
#Include WindowsQuirks.ahk

;; === Settings ===

; Try best to focus these windows when they are created OR have notifications
UseFlashFocusWindows(TitleFilter([
    "ahk_exe consent.exe",
    "ahk_exe Flow.Launcher.exe",
    "ahk_exe explorer.exe",
]))

; Sometimes the mouse doesn't follow window focus when alt-tabbing, for example, when the desktop is focused
UseFixMouseOnKBWindowFocus()

; Consider mouse position restoration as mouse move, when switching desktops
UseDesktopChangeAsMouseMove()


;; === Bindings ===

!1::GoToDesktop(0)
!2::GoToDesktop(1)
!3::GoToDesktop(2)
!4::GoToDesktop(3)
!5::GoToDesktop(4)
!6::GoToDesktop(5)
!7::GoToDesktop(6)
!8::GoToDesktop(7)
!9::GoToDesktop(8)
!0::GoToDesktop(-1)
!b::GoToDesktop(-1)

!+1::MoveWindowToDesktop("A", 0)
!+2::MoveWindowToDesktop("A", 1)
!+3::MoveWindowToDesktop("A", 2)
!+4::MoveWindowToDesktop("A", 3)
!+5::MoveWindowToDesktop("A", 4)
!+6::MoveWindowToDesktop("A", 5)
!+7::MoveWindowToDesktop("A", 6)
!+8::MoveWindowToDesktop("A", 7)
!+9::MoveWindowToDesktop("A", 8)
!+0::MoveWindowToDesktop("A", -1)
!+b::MoveWindowToDesktop("A", -1)

!^C::SafeWinClose("A")

!P::desktopManager.ToggleWindowPin(windowManager.GetID("A"))
!^P::PinAndSetOnTop("A")

!^LButton::windowManager.StartMouseWindowFreeDrag(
    windowManager.GetID("A"), (windowHwnd) => !GetKeyState("LButton", "P"))
!^RButton::windowManager.StartMouseWindowFreeResize(
    windowManager.GetID("A"), (windowHwnd) => !GetKeyState("RButton", "P"))

!l::GoToRightWindow()
!h::GoToLeftWindow()
!k::GoToTopWindow()
!j::GoToBottomWindow()
!i::GoToNextOverlappingWindow()


!+Tab::windowManager.GetAppNavigator().Next()