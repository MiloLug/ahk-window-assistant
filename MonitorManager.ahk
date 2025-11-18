#Requires AutoHotkey v2.0

#include IterUtils.ahk
#include Geometry.ahk


class ClsMonitor {
    __New(index, rect, name) {
        this.index := index
        this.rect := rect
        this.name := name
    }

    static FromIndex(index) {
        MonitorGetWorkArea(index, &l, &t, &r, &b)
        name := MonitorGetName(index)
        return ClsMonitor(index, Geometry.Rect(l, t, r, b), name)
    }

    ToDebugString() {
        return "Monitor " this.index " - " this.name " - (" IterJoin(this.rect, ", ") ")"
    }
}


class ClsMonitorManager {
    __New(ctx) {
        this._ctx := ctx

        ; { monitorIndex: ClsMonitor }
        this._monitors := []

        ; Monitors naturally ordered by their position left-to-right, top-to-bottom
        ; Improves coordinate-based lookups
        this._monitorsOrdered := []

        this._UpdateMonitors()
        this._UpdateMonitors_Bind := this._UpdateMonitors.Bind(this)
        SetTimer(this._UpdateMonitors_Bind, 1000)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._UpdateMonitors_Bind, 0)
        this._UpdateMonitors_Bind := 0
        this._ctx := 0
    }

    ToDebugString() {
        ret := ""
        for monitor in this._monitorsOrdered {
            ret .= monitor.ToDebugString() "`n"
        }
        return ret
    }

    _UpdateMonitors() {
        count := MonitorGetCount()
        monitors := []
        diff := count != this._monitors.Length
        loop count {
            monitor := ClsMonitor.FromIndex(A_Index)
            monitors.Push(monitor)

            if (!diff)
                diff := !Geometry.RectsEqual(monitor.rect, this._monitors[A_Index])
        }

        this._monitorsOrdered := []
        static rectComparator(a, b) {
            ; Sort left-top to right-bottom
            yDiff := a.rect[2] - b.rect[2]
            if (Abs(yDiff) > Config.MONITOR_SAME_LEVEL_THRESHOLD) {
                return yDiff
            }
            return a.rect[1] - b.rect[1]
        }

        ArrSort(this._monitorsOrdered, rectComparator)
    }

    /**
     * @returns {(Number)} - 1-based index of the focused monitor
     */
    GetFocused() {
        MouseGetPos(&x, &y)
        return this.GetByCoords(x, y).index
    }

    /**
     * @description Get the monitor that contains the given coordinates
     * @param {(Number)} x - the x coordinate
     * @param {(Number)} y - the y coordinate
     * @returns {(ClsMonitor)} - the monitor that contains the given coordinates.
     * 
     * If no monitor is found, the primary monitor is returned.
     */
    GetByCoords(x, y) {
        for monitor in this._monitorsOrdered {
            if (Geometry.PointInRect(x, y, monitor.rect)) {
                return monitor
            }
        }
        return this._monitors[MonitorGetPrimary()]
    }

    /**
     * @description Get the monitor by its index
     * @param {(Number)} index - 1-based index of the monitor, compatible with ahk monitor indexing
     * @returns {(ClsMonitor)}
     */
    GetByIndex(index) {
        return this._monitors[index]
    }

    /**
     * @description Get all monitors
     * @returns {(Array<ClsMonitor>)} - all monitors
     */
    GetAll() {
        return this._monitorsOrdered
    }

    /**
     * @description Activate the monitor by its index
     * @param {(Number)} index - 1-based index of the monitor, compatible with ahk monitor indexing
     * @returns {(Boolean)} - true if the monitor was activated, false otherwise
     */
    Activate(index) {
        if (index < 0 || index > this._monitors.Length) {
            return false
        }
        monitor := this._monitors[index]
        Geometry.RectCenter(monitor.rect, &x, &y)
        WinActivate('ahk_class Progman')  ; To unfocus everything
        MouseMove(x, y)
        return true
    }
}