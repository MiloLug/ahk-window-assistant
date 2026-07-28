#Requires AutoHotkey v2.0

#include IterUtils.ahk
#include Geometry.ahk
#include Constants.ahk
#include Config.ahk


class ClsMonitor {
    __New(index, rect, workRect, name) {
        this.index := index
        this.rect := rect          ; full display rect
        this.workRect := workRect  ; work area (without taskbar etc)
        this.name := name
    }

    static FromIndex(index) {
        MonitorGet(index, &l, &t, &r, &b)
        MonitorGetWorkArea(index, &wl, &wt, &wr, &wb)
        name := MonitorGetName(index)
        return ClsMonitor(index, Geometry.Rect(l, t, r, b), Geometry.Rect(wl, wt, wr, wb), name)
    }

    ToDebugString() {
        return "Monitor " this.index " - " this.name " - (" IterJoin(this.rect, ", ") ")"
    }
}


/**
 * @description A class to manage the monitors
 *
 * It keeps track of current monitors and their positions.
 *
 * Same shape as ClsForegroundWatcher: unreliable hints (WM_DISPLAYCHANGE,
 * work-area WM_SETTINGCHANGE) funnel through a trailing-debounce _Poke() into
 * the diff-gated _UpdateMonitors, which re-reads the authoritative monitor list
 * and fires EV_MONITORS_LAYOUT_CHANGED only on real change. A slow safety poll
 * guarantees completeness when a broadcast is missed.
 *
 * @param {(Context)} ctx - the context to use
 * @returns {(ClsMonitorManager)} - the monitor manager
 */
class ClsMonitorManager {
    __New(ctx) {
        this._ctx := ctx

        ; { monitorIndex: ClsMonitor }
        this._monitors := []

        ; Monitors ordered for better spatial search
        this._monitorsOrdered := []

        ; Two binds because:
        ; the settle timer and the periodic poll must stay independent timers,
        ; or restarting one would cancel the other
        this._UpdateSettle_Bind := this._UpdateMonitors.Bind(this)
        this._UpdatePoll_Bind := this._UpdateMonitors.Bind(this)
        this._OnDisplayChange_Bind := this._OnDisplayChange.Bind(this)
        this._OnSettingChange_Bind := this._OnSettingChange.Bind(this)

        this._UpdateMonitors()

        ; A_ScriptHwnd is a hidden top-level window, so it receives these broadcasts
        OnMessage(WM_DISPLAYCHANGE, this._OnDisplayChange_Bind)
        OnMessage(WM_SETTINGCHANGE, this._OnSettingChange_Bind)
        SetTimer(this._UpdatePoll_Bind, Config.MONITOR_POLL_INTERVAL)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        OnMessage(WM_DISPLAYCHANGE, this._OnDisplayChange_Bind, 0)
        OnMessage(WM_SETTINGCHANGE, this._OnSettingChange_Bind, 0)
        SetTimer(this._UpdateSettle_Bind, 0)
        SetTimer(this._UpdatePoll_Bind, 0)
        this._UpdateSettle_Bind := 0
        this._UpdatePoll_Bind := 0
        this._OnDisplayChange_Bind := 0
        this._OnSettingChange_Bind := 0
        this._ctx := 0
    }

    ToDebugString() {
        ret := ""
        for monitor in this._monitorsOrdered {
            ret .= monitor.ToDebugString() "`n"
        }
        return ret
    }

    /**
     * @description Hint that the monitor layout may have changed
     */
    _Poke() {
        SetTimer(this._UpdateSettle_Bind, -Config.MONITOR_SETTLE_DELAY)
    }

    _OnDisplayChange(wParam, lParam, msg, hwnd) {
        ; resolution/topology changed; fires in bursts during mode switches
        this._Poke()
    }

    _OnSettingChange(wParam, lParam, msg, hwnd) {
        ; WM_SETTINGCHANGE fires on many kinds of things
        ; this will filter to taskbar moved / resized / auto-hidden
        if (wParam == SPI_SETWORKAREA)
            this._Poke()
    }

    _UpdateMonitors(*) {
        Critical(1)

        count := MonitorGetCount()
        monitors := []
        noUpdates := count == this._monitors.Length

        loop count {
            monitor := ClsMonitor.FromIndex(A_Index)
            monitors.Push(monitor)

            if (noUpdates)
                noUpdates := (
                    Geometry.RectsEqual(monitor.rect, this._monitors[A_Index].rect)
                    && Geometry.RectsEqual(monitor.workRect, this._monitors[A_Index].workRect)
                )
        }
        if (noUpdates)
            return

        this._monitors := monitors
        this._monitorsOrdered := this._SortNaturally(monitors.Clone())

        OutputDebug("Monitors changed:`n" this.ToDebugString())
        this._ctx.eventManager.Trigger(EV_MONITORS_LAYOUT_CHANGED)
    }

    /**
     * @description Sort monitors naturally: left-to-right, top-to-bottom

     * @param {(Array<ClsMonitor>)} monitors - sorted in place
     * @returns {(Array<ClsMonitor>)}
     */
    _SortNaturally(monitors) {
        ArrSort(monitors, (a, b) => a.rect[2] - b.rect[2])

        rows := Map()
        row := 0
        anchorY := 0
        for monitor in monitors {
            if (row == 0 || monitor.rect[2] - anchorY > Config.MONITOR_SAME_LEVEL_THRESHOLD) {
                row += 1
                anchorY := monitor.rect[2]
            }
            rows[monitor] := row
        }

        ; the final index tiebreak because ArrSort is unstable
        ArrSort(monitors, (a, b) => (
            rows[a] != rows[b] ? rows[a] - rows[b]
            : a.rect[1] != b.rect[1] ? a.rect[1] - b.rect[1]
            : a.rect[2] != b.rect[2] ? a.rect[2] - b.rect[2]
            : a.index - b.index
        ))
        return monitors
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
     * @returns {(ClsMonitor)} - the monitor whose display area contains the point
     */
    GetByCoords(x, y) {
        for monitor in this._monitorsOrdered {
            if (Geometry.PointInRect(x, y, monitor.rect)) {
                return monitor
            }
        }
        ; the live primary index can diff from the cached array between a topology
        ; change and settling
        idx := MonitorGetPrimary()
        return this._monitors.Has(idx) ? this._monitors[idx] : this._monitors[1]
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
     * @description Get all monitors in natural order
     * @returns {(Array<ClsMonitor>)} - live internal array. !don't mutate!
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
        if (index < 1 || index > this._monitors.Length) {
            return false
        }
        monitor := this._monitors[index]
        Geometry.RectCenter(monitor.workRect, &x, &y)
        WinActivate('ahk_class Progman')  ; To unfocus everything
        MouseMove(x, y)
        return true
    }
}
