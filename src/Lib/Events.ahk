#Requires AutoHotkey v2.0

#include ../Constants.ahk


class ClsEventBus {
    __New(ctx) {
        this._ctx := ctx

        ; { eventId: { (originalHandler): { once: bool } } }
        this._events := Map()

        ; { eventId: { (firstRegistrationCallback): 1 } }
        this._lazyRegistrars := Map()

        this.__rawInputWatcher := 0
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ; Maybe add some trigger on remove here
        ObjAddRef(ObjPtr(this))
    }

    /**
     * @description Add a handler for an event
     * @param {(Integer)} eventId - the event id
     * @param {(FuncObj)} handler - the handler to call when the event is triggered
     * 
     *         handler(args*) => Any
     * 
     * @param {(Boolean)} once - whether the handler should be called only once
     */
    On(eventId, handler, once := false) {
        if (!this._events.Has(eventId)) {
            this._events[eventId] := Map()
        }
        this._events[eventId][handler] := { once: once }

        if (this._lazyRegistrars.Has(eventId)) {
            regs := this._lazyRegistrars[eventId]
            this._lazyRegistrars.Delete(eventId)
            for reg in regs {
                reg()
            }
        }
    }

    /**
     * @description Add a lazy registrar for an event
     * 
     * This is used to initialize some infrastructure that the event needs, when it's first "listened" to.
     * For example, to setup a mouse input hook.
     * This improves the startup time, memory usage etc, since we don't need to do any listening unless it's needed. 
     * 
     * @param {(Integer)} eventId - the event id
     * @param {(FuncObj)} handler - the handler to call when the event is triggered
     */
    AddLazyRegistrar(eventId, handler) {
        if (!this._lazyRegistrars.Has(eventId))
            this._lazyRegistrars[eventId] := Map()
        this._lazyRegistrars[eventId][handler] := 1
    }

    /**
     * @description Remove a lazy registrar for an event
     * @param {(Integer)} eventId - the event id
     * @param {(FuncObj)} handler - the handler to remove
     */
    RemoveLazyRegistrar(eventId, handler) {
        if (this._lazyRegistrars.Has(eventId))
            this._lazyRegistrars[eventId].Delete(handler)
    }

    /**
     * @description Trigger an event
     * @param {(Integer)} eventId - the event id
     * @param {(Any)} args* - the arguments to pass to the handlers
     */
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

    /**
     * @description Remove a handler for an event
     * @param {(Integer)} eventId - the event id
     * @param {(FuncObj)} handler - the handler to remove
     */
    Off(eventId, handler) {
        if (this._events.Has(eventId)) {
            this._events[eventId].Delete(handler)
        }
    }
}
