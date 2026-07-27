#Requires AutoHotkey v2.0

#Include MonitorManager.ahk
#Include WindowManager.ahk
#Include VirtualDesktopManager.ahk
#Include Events.ahk
#Include MouseInput.ahk

class ClsContext {
    __New() {
        this.eventManager := ClsEventBus(this)
        this.eventManager.AddLazyRegistrar(EV_MOUSE_MOVED, this._SetupMouseMovedEvent.Bind(this))
        this.__rawInputWatcher := 0

        this.monitorManager := ClsMonitorManager(this)
        this.windowManager := ClsWindowManager(this)
        this.desktopManager := ClsVirtualDesktopManager(this)

        this.windowManager.RegisterEventManager(this.eventManager)
        this.desktopManager.RegisterEventManager(this.eventManager)
    }

    _SetupMouseMovedEvent() {
        this.__rawInputWatcher := ClsMouseRawInputHook(this.eventManager.Trigger.Bind(this.eventManager, EV_MOUSE_MOVED), 1)
    }
}