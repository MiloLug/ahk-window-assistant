#Requires AutoHotkey v2.0
#SingleInstance Off
; Test entry point. Run with src/Main.ahk CLOSED (its mouse-follow quirk reacts to test windows).
; Output: OutputDebug always; stdout when piped. Exit code = fail count.
;
;   & "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tests\Main.ahk | Write-Output
;
; Trailing args filter which suites run - matched against case-file paths and suite names:
;
;   ... tests\Main.ahk geometry      ; cases/Geometry.ahk, cases/geometry/*, a suite named Geometry
;   ... tests\Main.ahk s14 s20       ; single scenarios
;   ... tests\Main.ahk cases/nav     ; a whole file or directory
;
; A new case file needs one #Include line below - #Include is compile-time, AHK has no globbing.

#Include TestCore.ahk
#Include cases/IniUtils.ahk
#Include cases/NavScenarios.ahk

CoordMode("Mouse", "Screen")
SetWinDelay(10)

Test.Run(A_Args)
