#Requires AutoHotkey v2.0


; TODO: Maybe... I don't really need to complicate things to this extent???
class ClsEventBus {
    __New() {
        ; { eventId: { (originalHandler): { once: bool } } }
        this._events := Map()

        ; { eventId: { (firstRegistrationCallback): 1 } }
        this._lazyRegistrators := Map()

        this.AddLazyRegistrator(EV_MOUSE_MOVED, this._SetupMouseMovedEvent.Bind(this))
        this.__rawInputWatcher := 0
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ; Maybe add some trigger on remove here
        ObjAddRef(ObjPtr(this))
        OutputDebug("Event bus deleted")
    }

    _SetupMouseMovedEvent() {
        this.__rawInputWatcher := ClsMouseRawInputHook(this.Trigger.Bind(this, EV_MOUSE_MOVED), 1)
    }

    On(eventId, handler, once := false) {
        if (!this._events.Has(eventId)) {
            this._events[eventId] := Map()
        }
        this._events[eventId][handler] := { once: once }

        if (this._lazyRegistrators.Has(eventId)) {
            regs := this._lazyRegistrators[eventId]
            this._lazyRegistrators.Delete(eventId)
            for reg in regs {
                reg()
            }
        }
    }

    AddLazyRegistrator(eventId, handler) {
        if (!this._lazyRegistrators.Has(eventId)) {
            this._lazyRegistrators[eventId] := Map()
        }
        this._lazyRegistrators[eventId][handler] := 1
    }

    RemoveLazyRegistrator(eventId, handler) {
        if (this._lazyRegistrators.Has(eventId)) {
            this._lazyRegistrators[eventId].Delete(handler)
        }
    }

    Trigger(eventId, args*) {
        if (this._events.Has(eventId)) {
            toDelete := []
            for handler, config in this._events[eventId] {
                handler(args*)
                if (config.once) {
                    toDelete.Push(handler)
                }
            }
            for handler in toDelete {
                this._events[eventId].Delete(handler)
            }
        }
    }

    Off(eventId, handler) {
        if (this._events.Has(eventId)) {
            this._events[eventId].Delete(handler)
        }
    }
}

/**
 * @description A class to hook the mouse raw input - {@link https://www.autohotkey.com/boards/viewtopic.php?t=134109|author and details}
 * 
 * It gives only offsets, not absolute coordinates. For coordinates, call MouseGetPos()
 * @param {(FuncObj)} Callback - the callback to call when the mouse raw input is received
 * @param {(Integer)} EventType - the event type to hook
 *  - 1 = only mouse movement
 *  - 2 = only mouse clicks
 *  - 3 = both events
 * @param {(Integer)} UsagePage - HID Usage Page (1 = Generic Desktop Controls)
 * @param {(Integer)} UsageId - HID Usage ID (2 = Mouse, 6 = Keyboard within page 1)
 */
class ClsMouseRawInputHook {
    __New(Callback, EventType:=3, UsagePage:=1, UsageId:=2) {
        static DevSize := 8 + A_PtrSize, RIDEV_INPUTSINK := 0x00000100
        this.RAWINPUTDEVICE := Buffer(DevSize, 0), this.EventType := EventType
        this.__Callback := this.__MouseRawInputProc.Bind(this), this.Callback := Callback
        NumPut("UShort", UsagePage, "UShort", UsageId, "UInt", RIDEV_INPUTSINK, "Ptr", A_ScriptHwnd, this.RAWINPUTDEVICE)
        DllCall("RegisterRawInputDevices", "Ptr", this.RAWINPUTDEVICE, "UInt", 1, "UInt", DevSize)
        OnMessage(WM_INPUT, this.__Callback)
        ObjRelease(ObjPtr(this)) ; Otherwise this object can't be destroyed because of the BoundFunc above
    }
    __Delete() {
        static RIDEV_REMOVE := 0x00000001, DevSize := 8 + A_PtrSize
        NumPut("Uint", RIDEV_REMOVE, this.RAWINPUTDEVICE, 4)
        DllCall("RegisterRawInputDevices", "Ptr", this.RAWINPUTDEVICE, "UInt", 1, "UInt", DevSize)
        ObjAddRef(ObjPtr(this))
        OnMessage(WM_INPUT, this.__Callback, 0)
        this.__Callback := 0
    }
    __MouseRawInputProc(wParam, lParam, *) {
        ; RawInput statics
        static iSize := 0, sz := 0, offsets := {usFlags: (8+2*A_PtrSize), usButtonFlags: (12+2*A_PtrSize), usButtonData: (14+2*A_PtrSize), x: (20+A_PtrSize*2), y: (24+A_PtrSize*2)}, uRawInput
        ; Find size of rawinput data - only needs to be run the first time.
        if (!iSize) {
            r := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", &iSize, "UInt", 8 + (A_PtrSize * 2))
            uRawInput := Buffer(iSize, 0)
        }

        if !DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", uRawInput, "UInt*", &sz := iSize, "UInt", 8 + (A_PtrSize * 2))
            return

        ; Read buffered RawInput data and accumulate the offsets
        device := NumGet(uRawInput, 8, "UPtr"), x_offset := 0, y_offset := 0, usButtonFlags := 0, usButtonData := 0, CallbackQueue := []

        ProcessInputBuffer:
        if NumGet(uRawInput, "UInt") = 1 ; Skip RIM_TYPEKEYBOARD
            goto ProcessCallbacks

        usFlags := NumGet(uRawInput, offsets.usFlags, "UShort")
        if (usButtonFlagsRaw := NumGet(uRawInput, offsets.usButtonFlags, "UShort")) {
            if (usButtonFlagsRaw & 0x400 || usButtonFlagsRaw & 0x800)
                usButtonData += NumGet(uRawInput, offsets.usButtonData, "Short")
            else if (this.EventType = 2) { ; Return if a mouse click is detected and callback only want clicks
                usButtonFlags |= usButtonFlagsRaw
                goto ProcessCallbacks
            }
        }
        usButtonFlags |= usButtonFlagsRaw, x_offset += NumGet(uRawInput, offsets.x, "Int"), y_offset += NumGet(uRawInput, offsets.y, "Int")

        if DllCall("GetRawInputBuffer", "Ptr", uRawInput, "UInt*", &sz := iSize, "UInt", 8 + (A_PtrSize * 2)) {
            if NumGet(uRawInput, 8, "UPtr") != device { ; If the message is from a different device then reset parameters
                AddCallbackToQueue()
                device := NumGet(uRawInput, 8, "UPtr"), x_offset := 0, y_offset := 0, usButtonFlags := 0, usButtonData := 0, usFlags := NumGet(uRawInput, offsets.usFlags, "ushort")
            }
            goto ProcessInputBuffer
        }

        ProcessCallbacks:
        AddCallbackToQueue()
        for Args in CallbackQueue
            pCallback := CallbackCreate(this.Callback.Bind(Args*)), DllCall(pCallback), CallbackFree(pCallback)
        
        AddCallbackToQueue() {
            if (this.EventType & 1 && !(x_offset = 0 && y_offset = 0)) || (this.EventType & 2 && usButtonFlags)
                CallbackQueue.Push([x_offset, y_offset, {flags: usFlags, buttonFlags: usButtonFlags, buttonData: usButtonData, device:device}])
        }
    }
}