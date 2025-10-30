; Requires:
;   VirtualDesktopAccessor.dll (https://github.com/Ciantic/VirtualDesktopAccessor)

#include Constants.ahk
#include Config.ahk
#include Utils.ahk


class VirtualDesktopError extends Error {
}


class ClsVirtualDesktopManager {
    __New() {
        dllPath := A_ScriptDir . "\VirtualDesktopAccessor.dll"
        
        ; Check if DLL exists before attempting to load
        if (!FileExist(dllPath)) {
            MsgBox(
                "ERROR: VirtualDesktopAccessor.dll not found!`n`n"
                . "Expected location: " dllPath "`n`n"
                . "Please download it from:`n"
                . "https://github.com/Ciantic/VirtualDesktopAccessor`n`n"
                . "Script will now exit.",
                "Missing DLL", "Icon!"
            )
            ExitApp(1)
        }
        
        try {
            this._hVD := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
            if (!this._hVD) {
                throw Error("LoadLibrary returned null")
            }
        } catch as err {
            MsgBox(
                "ERROR: Failed to load VirtualDesktopAccessor.dll`n`n"
                . "Error: " err.Message "`n`n"
                . "This might be due to:`n"
                . "- Missing Visual C++ Redistributable`n"
                . "- Incompatible DLL version`n"
                . "- Windows version mismatch`n`n"
                . "Script will now exit.",
                "DLL Load Error", "Icon!"
            )
            ExitApp(1)
        }

        this._hProcGetDesktopCount := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "GetDesktopCount", "Ptr")
        this._hProcGoToDesktopNumber := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "GoToDesktopNumber", "Ptr")
        this._hProcGetCurrentDesktopNumber := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "GetCurrentDesktopNumber", "Ptr")
        this._hProcIsWindowOnCurrentVirtualDesktop := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "IsWindowOnCurrentVirtualDesktop", "Ptr")
        this._hProcIsWindowOnDesktopNumber := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "IsWindowOnDesktopNumber", "Ptr")
        this._hProcMoveWindowToDesktopNumber := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "MoveWindowToDesktopNumber", "Ptr")
        this._hProcGetDesktopName := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "GetDesktopName", "Ptr")
        this._hProcSetDesktopName := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "SetDesktopName", "Ptr")
        this._hProcCreateDesktop := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "CreateDesktop", "Ptr")
        this._hProcRemoveDesktop := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "RemoveDesktop", "Ptr")
        this._hProcGetWindowDesktopNumber := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "GetWindowDesktopNumber", "Ptr")

        this._hProcRegisterPostMessageHook := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "RegisterPostMessageHook", "Ptr")
        this._hProcUnregisterPostMessageHook := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "UnregisterPostMessageHook", "Ptr")

        this._hProcIsPinnedWindow := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "IsPinnedWindow", "Ptr")
        this._hProcPinWindow := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "PinWindow", "Ptr")
        this._hProcUnpinWindow := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "UnPinWindow", "Ptr")

        this._hProcIsPinnedApp := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "IsPinnedApp", "Ptr")
        this._hProcPinApp := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "PinApp", "Ptr")
        this._hProcUnpinApp := DllCall("GetProcAddress", "Ptr", this._hVD, "AStr", "UnPinApp", "Ptr")

        this._eventManager := 0
        this._currentDesktop := DllCall(this._hProcGetCurrentDesktopNumber, "Int")
        this._lastDesktop := this._currentDesktop
        this._mousePositions := []
        this._hasRestoredMousePosition := false

        ; #DLLBUG-1
        this._DesktopChangeChecker_Binds := Map()
        this._tmpCurrentDesktop := this._currentDesktop
        this._OnVirtualDesktopManagerMessage_Bind := this._OnVirtualDesktopManagerMessage.Bind(this)
        ; #DLLBUG-1 end

        this.RegisterPostMessageHook(A_ScriptHwnd, MSG_VIRTUAL_DESKTOP_MENAGER)
        OnMessage(MSG_VIRTUAL_DESKTOP_MENAGER, this._OnVirtualDesktopManagerMessage_Bind)

        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        OnMessage(MSG_VIRTUAL_DESKTOP_MENAGER, this._OnVirtualDesktopManagerMessage_Bind, 0)
        this._OnVirtualDesktopManagerMessage_Bind := 0
    }

    GetCurrentDesktopNum() {
        return this._currentDesktop
    }

    GetCount() {
        res := DllCall(this._hProcGetDesktopCount, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to get desktop count")
        }
        return res
    }

    GetWindowDesktopNum(windowHwnd) {
        res := DllCall(this._hProcGetWindowDesktopNumber, "Ptr", windowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to get window desktop number")
        }
        return res
    }

    IsWindowOnCurrentDesktop(windowHwnd) {
        res := DllCall(this._hProcIsWindowOnCurrentVirtualDesktop, "Ptr", windowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to check if window is on current desktop")
        }
        return res
    }

    IsWindowOnDesktop(windowHwnd, num) {
        res := DllCall(this._hProcIsWindowOnDesktopNumber, "Ptr", windowHwnd, "Int", num, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to check if window is on desktop")
        }
        return res
    }

    MoveWindowToDesktop(windowHwnd, num) {
        res := DllCall(this._hProcMoveWindowToDesktopNumber, "Ptr", windowHwnd, "Int", num, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to move window " windowHwnd " to desktop " num)
        }
    }
    
    SetDesktopName(num, name) {
        name_utf8 := Buffer(1024, 0)
        StrPut(name, name_utf8, "UTF-8")
        res := DllCall(this._hProcSetDesktopName, "Int", num, "Ptr", name_utf8, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to set desktop name")
        }
    }

    GetDesktopName(num) {
        utf8_buffer := Buffer(1024, 0)
        res := DllCall(this._hProcGetDesktopName, "Int", num, "Ptr", utf8_buffer, "Ptr", utf8_buffer.Size, "Int")
        if (res == 1) {
            return StrGet(utf8_buffer, 1024, "UTF-8")
        }
        if (res == -1) {
            throw VirtualDesktopError("Failed to get desktop name")
        }
        return ""
    }

    _DesktopChangeChecker(hwnd) {
        ; #DLLBUG-1
        realCurrent := DllCall(this._hProcGetCurrentDesktopNumber, "Int")
        if (realCurrent != this._tmpCurrentDesktop) {
            ; Only the message handler should set currentDesktop, so use another variable here
            PostMessage(MSG_VIRTUAL_DESKTOP_MENAGER, this._tmpCurrentDesktop, realCurrent, , hwnd)
            this._tmpCurrentDesktop := realCurrent
        }
    }

    RegisterPostMessageHook(processHwnd, messageOffsetNum) {
        ; TODO: Change this after bugfix in the DLL | Search project for #DLLBUG-1

        if (!this._DesktopChangeChecker_Binds.Has(processHwnd)) {
            WinCalls.ChangeWindowMessageFilterEx(processHwnd, MSG_VIRTUAL_DESKTOP_MENAGER, MSGFLT_ALLOW)
            SetTimer(
                this._DesktopChangeChecker_Binds[processHwnd] := this._DesktopChangeChecker.Bind(this, processHwnd),
                100
            )
        }
        
        ; Right now the event manager of the accessor is broken when run as Admin, so I use this polyfill
        
        ; if (res != 1) {
        ;     throw VirtualDesktopError("Failed to change window message filter")
        ; }
        ; res := DllCall(this._hProcRegisterPostMessageHook, "Ptr", processHwnd, "Int", messageOffsetNum, "Int")
        ; if (res == -1) {
        ;     throw VirtualDesktopError("Failed to register post message hook")
        ; }
    }

    UnregisterPostMessageHook(processHwnd) {
        ; #DLLBUG-1
        if (this._DesktopChangeChecker_Binds.Has(processHwnd)) {
            SetTimer(this._DesktopChangeChecker_Binds[processHwnd], 0)
            this._DesktopChangeChecker_Binds.Delete(processHwnd)
            WinCalls.ChangeWindowMessageFilterEx(processHwnd, MSG_VIRTUAL_DESKTOP_MENAGER, MSGFLT_RESET)
        }

        ; res := DllCall(this._hProcUnregisterPostMessageHook, "Ptr", processHwnd, "Int")
        ; if (res == -1) {
        ;     throw VirtualDesktopError("Failed to unregister post message hook")
        ; }
    }

    IsPinnedWindow(windowHwnd) {
        if (!windowHwnd)
            return false
        res := DllCall(this._hProcIsPinnedWindow, "Ptr", windowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to check if window is pinned")
        }
        return res
    }

    PinWindow(windowHwnd) {
        if (!windowHwnd)
            return
        res := DllCall(this._hProcPinWindow, "Ptr", windowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to pin window")
        }
    }

    UnpinWindow(windowHwnd) {
        if (!windowHwnd)
            return
        res := DllCall(this._hProcUnpinWindow, "Ptr", windowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to unpin window")
        }
    }

    IsPinnedApp(appWindowHwnd) {
        if (!appWindowHwnd)
            return false
        res := DllCall(this._hProcIsPinnedApp, "Ptr", appWindowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to check if app is pinned")
        }
        return res
    }

    PinApp(appWindowHwnd) {
        if (!appWindowHwnd)
            return
        res := DllCall(this._hProcPinApp, "Ptr", appWindowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to pin app")
        }
    }

    UnpinApp(appWindowHwnd) {
        if (!appWindowHwnd)
            return
        res := DllCall(this._hProcUnpinApp, "Ptr", appWindowHwnd, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to unpin app")
        }
    }

    CreateDesktop() {
        res := DllCall(this._hProcCreateDesktop, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to create desktop")
        }
        this._mousePositions.Push(0)
        return res
    }

    /**
     * @description Fill the mouse positions array up to `maxNum` (1-indexed)
     * @param {(Integer)} maxNum
     */
    _FillMousePositions(maxNum) {
        if (maxNum > this._mousePositions.Length) {
            loop (maxNum - this._mousePositions.Length) {
                this._mousePositions.Push(0)
            }
        }
    }

    /**
     * @description Save the mouse position for the given desktop number (0-indexed)
     * @param {(Integer)} num
     */
    SaveMousePosition(num) {
        num++
        this._FillMousePositions(num)
        MouseGetPos(&x, &y)
        this._mousePositions[num] := [x, y]
    }

    /**
     * @description Restore the mouse position for the given desktop number (0-indexed)
     * @param {(Integer)} num
     */
    RestoreMousePosition(num) {
        num++
        if (num <= this._mousePositions.Length and this._mousePositions[num] != 0) {
            DllCall("SetCursorPos", "Int", this._mousePositions[num][1], "Int", this._mousePositions[num][2])
            this._hasRestoredMousePosition := true
        }
    }

    /**
     * @param {(Integer)} num 0-indexed
     * @param {(Boolean)} rememberMousePosition
     * - `true` Remember the mouse position on the current desktop
     * @param {(Boolean)} restoreMousePosition
     * - `true` Restore mouse position on the target desktop
     */
    GoToDesktop(num, rememberMousePosition:=true, restoreMousePosition:=true) {
        if (num == this._currentDesktop or num < 0)
            return

        if (rememberMousePosition)
            this.SaveMousePosition(this._currentDesktop)
        
        res := DllCall(this._hProcGoToDesktopNumber, "Int", num, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to go to desktop " num)
        }

        if (restoreMousePosition)
            this.RestoreMousePosition(num)
    }

    /**
     * @returns {(Integer)} 0-indexed
     */
    GetPreviousDesktopNum() {
        return this._lastDesktop
    }

    /**
     * @description Remove the desktop at `removeNum` and go to `goToNum`
     * @param {(Integer)} removeNum 0-indexed
     * @param {(Integer)} goToNum 0-indexed
     * - `-1` Go to the current desktop
     * @param {(Boolean)} restoreMousePosition
     */
    RemoveDesktop(removeNum, goToNum:=-1, restoreMousePosition:=true) {
        if (goToNum == -1) {
            goToNum := this._currentDesktop
        }
        if (removeNum == goToNum) {
            throw VirtualDesktopError("Removed desktop and go-to desktop cannot be the same: " removeNum)
        }
        if (removeNum < this._mousePositions.Length) {
            this._mousePositions.RemoveAt(removeNum + 1)
        }
        if (goToNum > removeNum) {
            goToNum--  ; Removed a desktop before this one, offset needed
        }
        if (this._lastDesktop > removeNum) {
            this._lastDesktop--
        } else if (this._lastDesktop == removeNum) {
            this._lastDesktop := goToNum
        }
        res := DllCall(this._hProcRemoveDesktop, "Int", removeNum, "Int", goToNum, "Int")
        if (res == -1) {
            throw VirtualDesktopError("Failed to remove desktop")
        }

        if (restoreMousePosition)
            this.RestoreMousePosition(goToNum)
    }

    /**
     * @description Create desktops up to and INCLUDING `lastNum`
     * @param {(Integer)} lastNum 0-indexed
     */
    FillDesktops(lastNum) {
        while (this.GetCount() <= lastNum) {
            this.CreateDesktop()
        }
    }

    /**
     * @description Event handler for the virtual desktop manager message
     * @param {(Integer)} prevDesktop 0-indexed
     * @param {(Integer)} newDesktop 0-indexed
     * @param {(Integer)} msg
     * @param {(Integer)} hwnd
     */
    _OnVirtualDesktopManagerMessage(prevDesktop, newDesktop, msg, hwnd) {
        Critical(1)
        OutputDebug("VDM: prev>" prevDesktop " new>" newDesktop " msg>" msg " hwnd>" hwnd)

        this._lastDesktop := this._currentDesktop
        this._currentDesktop := newDesktop
        if (this._eventManager != 0)
            this._eventManager.Trigger(EV_VIRTUAL_DESKTOP_CHANGED, prevDesktop, newDesktop, this._hasRestoredMousePosition)
        this._hasRestoredMousePosition := false
    }

    RegisterEventManager(eventManager) {
        if (this._eventManager != 0) {
            throw VirtualDesktopError("Event manager already registered")
        }
        this._eventManager := eventManager
    }

    /**
     * @description Toggle the pin state of a window
     * @param {(Integer)} windowHwnd
     * @returns {(Boolean)}
     * - true: Pinned
     * - false: Unpinned
     */
    ToggleWindowPin(windowHwnd) {
        if (this.IsPinnedWindow(windowHwnd)) {
            this.UnpinWindow(windowHwnd)
            return false
        } else {
            this.PinWindow(windowHwnd)
            return true
        }
    }

    /**
     * @description Toggle the pin state of an app window
     * @param {(Integer)} appWindowHwnd
     * @returns {(Integer)}
     * - 0: Unpinned
     * - 1: Pinned
     */
    ToggleAppPin(appWindowHwnd) {
        if (this.IsPinnedApp(appWindowHwnd)) {
            this.UnpinApp(appWindowHwnd)
            return false
        } else {
            this.PinApp(appWindowHwnd)
            return true
        }
    }
}