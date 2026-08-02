#Requires AutoHotkey v2.0
#SingleInstance Off
; Why Off: any-user logon trigger may overlap two launchers and kill the 
#Include ..\src\Lib\Paths.ahk
#Include ..\src\Lib\IniUtils.ahk

; This script's purpose is essentially to wait for all required system resources to be loaded
; (for ex explorer.exe) before running the main part.
; Since it runs from SYSTEM and is any-user, it loads before interactive shell and has to
; do some manipulations to invoke the ahk process with required elevation
; read docs\elevation.md

;; --- Constants ---

TOKEN_ASSIGN_PRIMARY := 0x0001
TOKEN_DUPLICATE := 0x0002
TOKEN_QUERY := 0x0008
TOKEN_ADJUST_PRIVILEGES := 0x0020
MAXIMUM_ALLOWED := 0x02000000
SECURITY_IDENTIFICATION := 1
TOKEN_PRIMARY := 1
TOKEN_SESSION_ID := 12
SE_PRIVILEGE_ENABLED := 0x2
CREATE_BREAKAWAY_FROM_JOB := 0x01000000
ERROR_ACCESS_DENIED := 5
INVALID_SESSION_ID := 0xFFFFFFFF

DEST_ROOT := Paths.Root
TARGET := Paths.FromRoot("src\Main.ahk")

; Config setup
AHK_EXE := ""
LOG_FILE := ""
try {
    configIni := IniUtils.Load(Paths.FromRoot("config.ini"))
} catch as e {
    OutputDebug("[Launcher] config.ini is invalid: " e.Message)
    Exit(1)
}
if (!configIni.Has("launcher") || !configIni.Has("common")) {
    OutputDebug("[Launcher] config.ini doesn't have all required info. Copy the config.example.ini and set the required values.")
    Exit(1)
}
AHK_EXE := configIni["common"].Get("ahkPath", 0)
LOG_FILE := configIni["launcher"].Get("logPath", 0)

if (AHK_EXE == 0 || LOG_FILE == 0) {
    OutputDebug("[Launcher] config.ini should have ``ahkPath`` and ``launcher.logPath``")
    Exit(1)
}

READY_POLL_MS := 500
READY_MAX_TRIES := 240
READY_SETTLE_MS := 2000

;; --- Run ---

if !FileExist(AHK_EXE)
    Fail(4, "ahk exe missing: " AHK_EXE)
if !FileExist(TARGET)
    Fail(4, "target missing: " TARGET)

sessionId := WaitForShellSession()
if (sessionId = INVALID_SESSION_ID)
    Fail(1, "readiness gate timed out")

SpawnInSession(sessionId)
ExitApp(0)

;; --- Functions ---

; logging + error-exit
Fail(code, msg) {
    line := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [" code "] " msg "`n"
    OutputDebug("[Launcher] " line)
    try FileAppend(line, LOG_FILE)
    ExitApp(code)
}

; The logon trigger fires before explorer.exe exists - we need to wait
WaitForShellSession() {
    Loop READY_MAX_TRIES {
        sid := DllCall("kernel32\WTSGetActiveConsoleSessionId", "UInt")
        if (sid != INVALID_SESSION_ID && sid != 0 && IsShellRunningInSession(sid)) {
            Sleep(READY_SETTLE_MS)
            return sid
        }
        Sleep(READY_POLL_MS)
    }
    return INVALID_SESSION_ID
}

IsShellRunningInSession(sessionId) {
    if !DllCall("wtsapi32\WTSEnumerateProcessesW", "Ptr", 0, "UInt", 0, "UInt", 1
        , "Ptr*", &pInfo := 0, "UInt*", &count := 0, "Int")
        return false
    found := false
    Loop count {
        base := pInfo + (A_Index - 1) * 24  ; WTS_PROCESS_INFOW x64: SessionId@0, pProcessName@8
        if (NumGet(base, 0, "UInt") = sessionId) {
            namePtr := NumGet(base, 8, "Ptr")
            if (namePtr && StrGet(namePtr) = "explorer.exe") {
                found := true
                break
            }
        }
    }
    DllCall("wtsapi32\WTSFreeMemory", "Ptr", pInfo)
    return found
}

; Task Scheduler may hand SYSTEM its token with SeTcbPrivilege disabled, which
; SetTokenInformation(TokenSessionId) needs it
EnableTcbPrivilege() {
    if !DllCall("advapi32\OpenProcessToken", "Ptr", DllCall("GetCurrentProcess", "Ptr")
        , "UInt", TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, "Ptr*", &hToken := 0, "Int")
        return
    luid := Buffer(8, 0)
    if DllCall("advapi32\LookupPrivilegeValueW", "Ptr", 0, "Str", "SeTcbPrivilege", "Ptr", luid, "Int") {
        tp := Buffer(16, 0)  ; TOKEN_PRIVILEGES: count@0, LUID@4, attributes@12
        NumPut("UInt", 1, tp, 0)
        NumPut("Int64", NumGet(luid, 0, "Int64"), tp, 4)
        NumPut("UInt", SE_PRIVILEGE_ENABLED, tp, 12)
        DllCall("advapi32\AdjustTokenPrivileges", "Ptr", hToken, "Int", 0, "Ptr", tp, "UInt", 0, "Ptr", 0, "Ptr", 0, "Int")
    }
    DllCall("CloseHandle", "Ptr", hToken)
}

; Failure paths exit the process immediately, which frees all handles.
SpawnInSession(sessionId) {
    EnableTcbPrivilege()

    if !DllCall(
        "advapi32\OpenProcessToken",
        "Ptr", DllCall("GetCurrentProcess", "Ptr"),
        "UInt", TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY,
        "Ptr*", &hToken := 0,
        "Int"
    )
        Fail(2, "OpenProcessToken failed, err=" A_LastError)
    if !DllCall(
        "advapi32\DuplicateTokenEx",
        "Ptr", hToken,
        "UInt", MAXIMUM_ALLOWED,
        "Ptr", 0,
        "Int", SECURITY_IDENTIFICATION,
        "Int", TOKEN_PRIMARY,
        "Ptr*", &hTokenDup := 0,
        "Int"
    )
        Fail(2, "DuplicateTokenEx failed, err=" A_LastError)
    if !DllCall(
        "advapi32\SetTokenInformation",
        "Ptr", hTokenDup,
        "Int", TOKEN_SESSION_ID,
        "UInt*", &sessionId,
        "UInt", 4,
        "Int"
    )
        Fail(2, "SetTokenInformation(TokenSessionId) failed, err=" A_LastError)

    startupInfo := Buffer(104, 0)  ; STARTUPINFOW x64: cb@0, lpDesktop@16
    NumPut("UInt", 104, startupInfo, 0)
    desktop := "winsta0\default"
    NumPut("Ptr", StrPtr(desktop), startupInfo, 16)
    processInfo := Buffer(24, 0)  ; PROCESS_INFORMATION: hProcess@0, hThread@8

    ; Create the cmd line for the new process
    cmd := '"' AHK_EXE '" "' TARGET '"'
    cmdBuf := Buffer((StrLen(cmd) + 1) * 2, 0)
    StrPut(cmd, cmdBuf, "UTF-16")

    ; CREATE_BREAKAWAY_FROM_JOB escapes the task's job object - ending the task won't kill the WM
    ok := DllCall(
        "advapi32\CreateProcessAsUserW",
        "Ptr", hTokenDup,
        "Str", AHK_EXE,
        "Ptr", cmdBuf,
        "Ptr", 0,
        "Ptr", 0,
        "Int", 0,
        "UInt", CREATE_BREAKAWAY_FROM_JOB,
        "Ptr", 0,
        "Str", DEST_ROOT,
        "Ptr", startupInfo,
        "Ptr", processInfo,
        "Int"
    )
    if (!ok && A_LastError = ERROR_ACCESS_DENIED) {
        ; But some systems can forbid the CREATE_BREAKAWAY_FROM_JOB
        StrPut(cmd, cmdBuf, "UTF-16")
        ok := DllCall(
            "advapi32\CreateProcessAsUserW",
            "Ptr", hTokenDup,
            "Str", AHK_EXE,
            "Ptr", cmdBuf,
            "Ptr", 0,
            "Ptr", 0,
            "Int", 0,
            "UInt", 0,
            "Ptr", 0,
            "Str", DEST_ROOT,
            "Ptr", startupInfo,
            "Ptr", processInfo,
            "Int"
        )
    }
    if !ok
        Fail(3, "CreateProcessAsUserW failed, err=" A_LastError)

    DllCall("CloseHandle", "Ptr", NumGet(processInfo, 0, "Ptr"))
    DllCall("CloseHandle", "Ptr", NumGet(processInfo, 8, "Ptr"))
    DllCall("CloseHandle", "Ptr", hTokenDup)
    DllCall("CloseHandle", "Ptr", hToken)
}
