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
    __New() {
        ; { monitorIndex: ClsMonitor }
        this._monitors := []
        ; Monitors naturally ordered by their position left-to-right, top-to-bottom
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

        ; TODO: Actually have no idea if I'll need this bit...
        static rectComparator(a, b) {
            ; Sort left-top to right-bottom
            yDiff := a.rect[2] - b.rect[2]
            threshold := 400  ; Consider same row within this threshold
            if (Abs(yDiff) > threshold) {
                return yDiff
            }
            return a.rect[1] - b.rect[1]
        }

        ArrSort(this._monitorsOrdered, rectComparator)
    }
}