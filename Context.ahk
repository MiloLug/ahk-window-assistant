#Requires AutoHotkey v2.0

#Include MonitorManager.ahk
#Include WindowManager.ahk
#Include VirtualDesktopManager.ahk
#Include Events.ahk

class ClsContext {
    __New() {
        this.eventManager := ClsEventBus(this)
        this.monitorManager := ClsMonitorManager(this)
        this.windowManager := ClsWindowManager(this)
        this.desktopManager := ClsVirtualDesktopManager(this)

        this.windowManager.RegisterEventManager(this.eventManager)
        this.desktopManager.RegisterEventManager(this.eventManager)
    }
}