#Requires AutoHotkey v2.0
; IniUtils: whole-file Map load over IniRead + %VAR% template expansion.
#Include ../../src/Lib/IniUtils.ahk

Test.InFile(A_LineFile)

Test.Suite("IniUtils.Load", TestIniLoad)
Test.Suite("IniUtils.ExpandVars", TestIniExpandVars)

TestIniLoad() {
    path := A_Temp "\IniUtilsTest-" A_TickCount ".ini"
    FileAppend("
    ( Join`r`n
    [setup]
    path = C:\Somewhere

    [launcher]
    ahkPath = C:\Tools\AutoHotkey64.exe
    logPath = %SystemRoot%\Temp\test.log
    )", path)
    try {
        ini := IniUtils.Load(path)
        AssertTrue("both sections load", ini.Has("setup") && ini.Has("launcher"))
        AssertEq("plain value", ini["setup"]["path"], "C:\Somewhere")
        AssertEq("lookup is case-insensitive", ini["Launcher"]["AHKPATH"], "C:\Tools\AutoHotkey64.exe")
        AssertEq("%SystemRoot% expands in values", ini["launcher"]["logPath"], A_WinDir "\Temp\test.log")
    } finally {
        try FileDelete(path)
    }

    threw := false
    try IniUtils.Load(A_Temp "\IniUtilsTest-missing-" A_TickCount ".ini")
    catch
        threw := true
    AssertTrue("missing file throws", threw)
}

TestIniExpandVars() {
    AssertEq("env var expands", IniUtils.ExpandVars("%SystemRoot%\x"), A_WinDir "\x")
    AssertEq("unset var stays literal", IniUtils.ExpandVars("keep %NoSuchVarAnywhere% here"), "keep %NoSuchVarAnywhere% here")
    AssertEq("lone percent untouched", IniUtils.ExpandVars("plain 50% value"), "plain 50% value")
    AssertEq("two vars in one value", IniUtils.ExpandVars("%SystemRoot%|%SystemRoot%"), A_WinDir "|" A_WinDir)
}
