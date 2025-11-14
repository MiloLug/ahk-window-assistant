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
        this._monitors := []
        this._monitorsOrdered := []
        loop count {
            monitor := ClsMonitor.FromIndex(A_Index)
            this._monitors.Push(monitor)
            this._monitorsOrdered.Push(monitor)
        }

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

    GetFocused() {
        MouseGetPos(&x, &y)
        return this.GetByCoords(x, y).index
    }

    GetByCoords(x, y) {
        for monitor in this._monitorsOrdered {
            if (Geometry.PointInRect(x, y, monitor.rect)) {
                return monitor
            }
        }
        return 1
    }

    GetByIndex(index) {
        return this._monitors[index]
    }

    GetAll() {
        return this._monitorsOrdered
    }

    Activate(index) {
        if (index < 0 || index > this._monitors.Length) {
            return false
        }
        monitor := this._monitors[index]
        Geometry.RectCenter(monitor.rect, &x, &y)
        WinActivate('ahk_class Progman')
        MouseMove(x, y)
        return true
    }
}