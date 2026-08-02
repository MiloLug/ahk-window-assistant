#Requires AutoHotkey v2.0

#include ../Constants.ahk
#include ../Config.ahk

/**
 * @description Foreground window change watcher.
 *
 * Collects all window change hints (WinEvent hook, shell hook pokes, polling etc)
 * to produce the final best-effort EV_FOREGROUND_CHANGED
 */
class ClsForegroundWatcher {
    __New(ctx) {
        this._ctx := ctx

        this._lastHwnd := DllCall("GetForegroundWindow", "Ptr")
        this._expectedHwnd := 0
        this._expectedTime := 0
        this._ownPid := DllCall("GetCurrentProcessId", "UInt")

        ; Two distinct binds on purpose: the settle timer and the periodic
        ; poll must stay independent timers, or restarting one would cancel the other
        this._VerifySettle_Bind := this._Verify.Bind(this)
        this._VerifyPoll_Bind := this._Verify.Bind(this)

        this._pWinEventProc := CallbackCreate(this._OnWinEvent.Bind(this), "F", 7)
        this._hWinEventHook := DllCall("SetWinEventHook",
            "UInt", EVENT_SYSTEM_FOREGROUND, "UInt", EVENT_SYSTEM_FOREGROUND,
            "Ptr", 0, "Ptr", this._pWinEventProc, "UInt", 0, "UInt", 0,
            "UInt", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS, "Ptr")

        SetTimer(this._VerifyPoll_Bind, Config.FOREGROUND_POLL_INTERVAL)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._VerifySettle_Bind, 0)
        SetTimer(this._VerifyPoll_Bind, 0)
        if (this._hWinEventHook)
            DllCall("UnhookWinEvent", "Ptr", this._hWinEventHook)
        if (this._pWinEventProc)
            CallbackFree(this._pWinEventProc)
        this._hWinEventHook := 0
        this._pWinEventProc := 0
        this._VerifySettle_Bind := 0
        this._VerifyPoll_Bind := 0
        this._ctx := 0
    }

    /**
     * @description Hint that the foreground may have changed - schedules a verify
     * after the OS settles. Restarting the one-shot timer on every hint gives a
     * trailing debounce: rapid switches collapse into one verify of the final state.
     */
    Poke() {
        SetTimer(this._VerifySettle_Bind, -Config.FOREGROUND_SETTLE_DELAY)
    }

    /**
     * @description Mark the next foreground change to this hwnd as our own switch,
     * so it commits silently instead of firing EV_FOREGROUND_CHANGED. Expires after
     * Config.FOREGROUND_EXPECT_TIMEOUT in case the activation failed.
     * @param {(Integer)} hwnd
     */
    Expect(hwnd) {
        this._expectedHwnd := hwnd
        this._expectedTime := A_TickCount
        this.Poke()
    }

    _OnWinEvent(hHook, event, hwnd, idObject, idChild, idThread, time) {
        ; the hook payload hwnd is a mid-transition snapshot - never trust it
        this.Poke()
    }

    _Verify(*) {
        Critical(1)

        hwnd := DllCall("GetForegroundWindow", "Ptr")
        ; mid-transition or desktop
        if (hwnd == 0)
            return
        if (hwnd == this._lastHwnd)
            return

        ; Avoid handling our own windows
        DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid := 0)
        if (pid == this._ownPid)
            return

        ; DWM-cloaked (e.g. ApplicationFrameHost transition frames):
        ; uncloaked real window arrives with the next hint or poll tick
        if (WinCalls.IsCloaked(hwnd, onError=false))
            return

        prevHwnd := this._lastHwnd
        this._lastHwnd := hwnd

        expected := this._expectedHwnd
        this._expectedHwnd := 0
        if (hwnd == expected && A_TickCount - this._expectedTime < Config.FOREGROUND_EXPECT_TIMEOUT) {
            OutputDebug("FG: self-switch to " hwnd)
            return
        }

        mouseJustMoved := this._ctx.windowManager.MouseJustMoved()
        this._ctx.eventManager.Trigger(EV_FOREGROUND_CHANGED, hwnd, prevHwnd, mouseJustMoved)
    }
}
