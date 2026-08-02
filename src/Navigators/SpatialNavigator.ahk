#Requires AutoHotkey v2.0

#include ../Config.ahk
#include ../Constants.ahk
#include ../Lib/Utils.ahk
#include ../Lib/Geometry.ahk


/**
 * @description Directional window navigation.
 *
 * Core idea: navigate to what is visible. Every candidate is ranked by its visible
 * fragments (its rect minus every window above it in z, minus the source rect), so a
 * window partially covered by the current one is still a target by its parts.
 * Even monitors are considered targets, tho last-priority.
 *
 * To improve the consistency, it uses an undo stack, this way it won't teleport to some
 * random windows, when you do, for example, "left" and then "right" - you'd definitely expect to
 * go back to where you were.
 * 
 * Some more details:
 * - an undo stack of moves uses the opposite actions' map to know what is it to "undo"
 * - MRU: near-tie scores (within NAV_TIE_EPSILON) resolve to the most recently focused
 *   candidate, which makes overlapping stacks predictable
 * 
 * - LEFT space - to avoid repeating a lot of things, everything is mapped to be to the left of a target later
 *   I call this "LEFT space" down below
 * - SCREEN space - the usual Win32 and AHK screen coords
 * 
 * - In- and Off-beam - the rect is inside this (src) rect's band, if we were to extrude the src rect
 *   in the direction in question:
 * 
 *              +-------+
 *              |  off  |             <- off-beam
 *              +-------+ 
 * .................................
 * +------+   +------+  +------+
 * |  in  |   |  in  |  |  src |      <- the beam (src's y-span, extruded left)
 * +------+   +------+  +------+
 * .............|  in  |............  <- in-beam (has overlap)
 *              +------+
 *
 * @param {(ClsContext)} ctx - context (windowManager, monitorManager, eventManager etc)
 * @param {(String)} listSelector - selector for the candidate window list
 * @param {(String)} currentSelector - selector for the current window
 * @param {(Float)} intersectionThreshold - overlap ratio for ClosestOverlapped:
 *
 *         Sqrt(intersectionArea) / Sqrt(window1Area + window2Area) > intersectionThreshold
 */
class ClsSpatialWindowNavigator {
    ; direction codes: 0 = left, 1 = right, 2 = top, 3 = bottom (spatial),
    ; 4 = layer down, 5 = layer up (z-dive; "up" exists only as history walk-back)
    static LAYER_DOWN := 4
    static LAYER_UP := 5
    static _OPPOSITE := Map(
        0, 1,
        1, 0,
        2, 3,
        3, 2,
        4, 5,
        5, 4
    )

    __New(ctx, listSelector:='', currentSelector:='A', intersectionThreshold:=Config.NAVIGATION_INTERSECTION_THRESHOLD) {
        this._ctx := ctx
        this._listSelector := listSelector
        this._currentSelector := currentSelector
        this._intersectionThreshold := intersectionThreshold

        ; target (hwnd or -monitorIndex) -> monotonic recency counter
        this._mru := Map()
        this._mruCounter := 0

        ; undo stack of {from, to, dir} + one redo slot
        this._cameFrom := []
        this._redo := 0

        ; winning fragment of the last geometric pick, consumed by PopLandRect()
        this._landRect := 0

        this._subscribed := false
        this._OnForegroundChanged_Bind := this._OnForegroundChanged.Bind(this)
        this._OnKbFocused_Bind := this._OnKbFocused.Bind(this)
        this._OnDesktopChanged_Bind := this._OnDesktopChanged.Bind(this)
        this._OnMonitorsChanged_Bind := this._OnMonitorsChanged.Bind(this)
        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        if (this._subscribed && this._ctx) {
            try this._ctx.eventManager.Off(EV_FOREGROUND_CHANGED, this._OnForegroundChanged_Bind)
            try this._ctx.eventManager.Off(EV_WINDOW_FOCUSED_WITH_KB, this._OnKbFocused_Bind)
            try this._ctx.eventManager.Off(EV_VIRTUAL_DESKTOP_CHANGED, this._OnDesktopChanged_Bind)
            try this._ctx.eventManager.Off(EV_MONITORS_LAYOUT_CHANGED, this._OnMonitorsChanged_Bind)
        }
        this._OnForegroundChanged_Bind := 0
        this._OnKbFocused_Bind := 0
        this._OnDesktopChanged_Bind := 0
        this._OnMonitorsChanged_Bind := 0
        this._ctx := 0
    }

    ;; --- events / MRU / memory ---

    _EnsureSubscribed() {
        if (this._subscribed)
            return
        this._subscribed := true  ; before On(): the first On() runs registrars
        em := this._ctx.eventManager
        em.On(EV_FOREGROUND_CHANGED, this._OnForegroundChanged_Bind)
        em.On(EV_WINDOW_FOCUSED_WITH_KB, this._OnKbFocused_Bind)
        em.On(EV_VIRTUAL_DESKTOP_CHANGED, this._OnDesktopChanged_Bind)
        em.On(EV_MONITORS_LAYOUT_CHANGED, this._OnMonitorsChanged_Bind)
    }

    ; Handlers may run inside other components' Critical sections and the bus has no error
    ; isolation, so we need to keep them as safe as possible and also cheap

    _OnForegroundChanged(newHwnd, prevHwnd, mouseJustMoved, *) {
        try {
            ; shell transients and Progman must not count as organic moves
            if (!this._ctx.windowManager.IsInteractableWindow(newHwnd))
                return
            this._BumpMru(newHwnd)
            top := this._cameFrom.Length ? this._cameFrom[this._cameFrom.Length] : 0
            if (!top || newHwnd != top.to)
                this._ClearMemory()
        }
    }

    _OnKbFocused(hwnd, *) {
        ; fires for our own moves too which the foreground watcher suppresses
        try {
            if (hwnd > 0)
                this._BumpMru(hwnd)
        }
    }

    _OnDesktopChanged(prevDesktop, newDesktop, restoredMouse, *) {
        try this._ClearMemory()
    }

    _OnMonitorsChanged(*) {
        try this._ClearMemory()
    }

    _BumpMru(target) {
        this._mru[target] := ++this._mruCounter
        if (this._mru.Count > Config.NAV_MRU_MAX_SIZE)
            this._MruSweep()
    }

    _MruSweep() {
        dead := []
        for target in this._mru {
            if (target > 0) {
                alive := false
                try alive := WinExist(target) != 0
                if (!alive)
                    dead.Push(target)
            }
        }
        for target in dead
            this._mru.Delete(target)
    }

    _ClearMemory() {
        if (this._cameFrom.Length)
            this._cameFrom := []
        this._redo := 0
    }

    _PushMove(from, to, dir, fromLand, toLand) {
        ; land rects for stability, so the cursor can move to predictable places
        ; (matters with focus-follows-mouse)
        this._cameFrom.Push({from: from, to: to, dir: dir, fromLand: fromLand, toLand: toLand})
        if (this._cameFrom.Length > Config.NAV_CAMEFROM_DEPTH)
            this._cameFrom.RemoveAt(1)
        this._redo := 0
    }

    /**
     * @description Undo/redo invocation shared by every nav direction
     * Sets _landRect / _redo / the stack on success.
     * @param {(Integer)} cur - current target (hwnd or negated monitor index)
     * @param {(Integer)} side - direction code
     * @returns {(Integer)} - remembered target, or 0 for no memory hit
     */
    _TryMemoryReturn(cur, side) {
        ; came-from: opposite dir walks the undo stack back
        linkTo := cur
        while (this._cameFrom.Length) {
            top := this._cameFrom[this._cameFrom.Length]
            ; if the previous move haven't sent us here, than this history
            ; deviates and we can't just "undo"
            if (top.to != linkTo || side != ClsSpatialWindowNavigator._OPPOSITE[top.dir])
                break
            this._cameFrom.Pop()
            if (this._IsValidTarget(top.from)) {
                this._redo := top
                this._landRect := top.fromLand
                return top.from
            }
            linkTo := top.from  ; just ignore the dead window and go further in chain
        }
        ; and if it wasn't an opposite action - than we probably want to redo
        ; This way, we'll just redo the just-undone move to keep it stable and avoid new target search
        if (this._redo) {
            redo := this._redo
            if (redo.from == cur && side == redo.dir && this._IsValidTarget(redo.to)) {
                this._cameFrom.Push(redo)
                this._redo := 0
                this._landRect := redo.toLand
                return redo.to
            }
        }
        return 0
    }

    /**
     * @description Whether a remembered target can still be returned to.
     * Here non-visible target is OK! This way, we can return to a window, that
     * our own move has covered.
     */
    _IsValidTarget(target) {
        if (target < 0)
            return -target >= 1 && -target <= this._ctx.monitorManager.GetAll().Length
        try {
            return WinExist(target)
                && this._ctx.windowManager.IsInteractableWindow(target)
                && WinGetMinMax(target) != WIN_MINIMIZED
                && !WinCalls.IsCloaked(target)
        } catch {
            return false
        }
    }

    ;; --- sources / coordinates ---

    _GetCurrent() {
        try {
            hwnd := this._ctx.windowManager.GetID(this._currentSelector,,, false)
            if (hwnd && !WinCalls.IsCloaked(hwnd))
                return hwnd
        }
        return -this._ctx.monitorManager.GetFocused()
    }

    /**
     * @description Rect of a window or monitor target; never throws.
     * @returns {(Boolean)} - false on vanished window / degenerate rect / stale monitor index
     */
    _TryGetCoords(target, &rect) {
        if (target < 0) {
            try rect := this._ctx.monitorManager.GetByIndex(-target).workRect
            catch {
                return false
            }
            return true
        }
        if (!WinCalls.WinGetPosEx(target, &l, &t,,, &r, &b))
            return false
        if (r <= l || b <= t)
            return false
        rect := Geometry.Rect(l, t, r, b)
        return true
    }

    _GetTargets() {
        winList := this._ctx.windowManager.GetList(this._listSelector,,, false)
        for mon in this._ctx.monitorManager.GetAll() {
            winList.Push(-mon.index)
        }
        return winList
    }

    /**
     * @description Enumerate all nav candidates from top (by z order) to bottom
     * @param {(Integer)} cur - current target; won't be marked as a candidate
     * @returns {(Array)} - [{hwnd, rect, isCandidate}] in z order
     */
    _EnumEntries(cur) {
        entries := []
        for hwnd in this._ctx.windowManager.GetList(this._listSelector, false, false) {
            try {
                if (WinGetMinMax(hwnd) == WIN_MINIMIZED)
                    continue
                if (WinGetExStyle(hwnd) & WS_EX_TRANSPARENT)
                    continue
                ; the desktop/wallpaper windows span entire monitors - they're the
                ; backdrop, not occluders; as cutters they'd zero out every monitor's
                ; free-space fragments and kill the monitor fallback
                winClass := WinGetClass(hwnd)
                if (winClass == "Progman" || winClass == "WorkerW")
                    continue
            } catch {
                continue  ; window vanished mid-scan
            }
            if (WinCalls.IsCloaked(hwnd))
                continue
            if (!this._TryGetCoords(hwnd, &rect))
                continue
            isCandidate := false
            try isCandidate := hwnd != cur && this._ctx.windowManager.IsInteractableWindow(hwnd)
            entries.Push({hwnd: hwnd, rect: rect, isCandidate: isCandidate})
        }
        return entries
    }

    ;; --- the directional algorithm ---

    /**
     * @description Map a rect into the LEFT space for the given side: every direction becomes
     * "navigate left", so all the scoring and conditioning can be done just for one side.
     * left: identity | right: mirror X | top: transpose | bottom: transpose + mirror X
     */
    _ToLEFT(r, side) {
        switch side {
            case 0: return r
            case 1: return [-r[3], r[2], -r[1], r[4]]
            case 2: return [r[2], r[1], r[4], r[3]]
            case 3: return [-r[4], r[1], -r[2], r[3]]
        }
    }

    /**
     * @description Score one fragment piece against the source; push into pool.
     * Predicate is Android FocusFinder's overlap-tolerant rule:
     *   https://developer.android.com/reference/android/view/FocusFinder
     * 
     * RESULT:
     * No return value: a qualifying piece is pushed into pool as
     * {target, frag, score, inBeam, mru, z}.
     * 
     * Failed pieces just drop.
     * 
     * @param {(Array)} pool - accumulator of score entries
     * @param {(Integer)} target - owner of the piece: hwnd or negated monitor index
     * @param {(Array)} piece - fragment Rect in SCREEN space
     * @param {(Array)} srcLeft - source rect in LEFT space
     * @param {(Integer)} side - direction code 0-3
     * @param {(Integer)} z - target's z index (1 = topmost)
     */
    _EvalInto(pool, target, piece, srcLeft, side, z) {
        c := this._ToLEFT(piece, side)
        s := srcLeft
        if (!((s[3] > c[3] || s[1] >= c[3]) && s[1] > c[1]))
            return
        major := Max(0, s[1] - c[3])
        minor := Abs((s[2] + s[4]) - (c[2] + c[4])) / 2
        inBeam := c[4] > s[2] && c[2] < s[4]
        ; it should be gentle in-beam and strong off-beam
        score := major + (inBeam ? Config.NAV_MINOR_WEIGHT_INBEAM : Config.NAV_MINOR_WEIGHT_OFFBEAM) * minor
        pool.Push({target: target, frag: piece, score: score, inBeam: inBeam, mru: this._mru.Get(target, 0), z: z})
    }

    /**
     * @description Select the best score entry from the pool
     */
    _SelectBest(pool) {
        if (!pool.Length)
            return 0

        ; If there's anything in-beam - don't bother with checking off-beam targets
        ; so we need to know first if there's anything
        anyBeam := false
        for entry in pool {
            if (entry.inBeam) {
                anyBeam := true
                break
            }
        }

        sMin := ''
        for entry in pool {
            if (anyBeam && !entry.inBeam)
                continue
            ; score can't possibly be a string, so this is safe
            if (sMin == '' || entry.score < sMin)
                sMin := entry.score
        }

        best := 0
        for entry in pool {
            if (anyBeam && !entry.inBeam)
                continue
            if (entry.score > sMin + Config.NAV_TIE_EPSILON)
                continue
            if (!best || this._BandBetter(entry, best))
                best := entry
        }
        return best
    }

    _BandBetter(a, b) {
        if (a.mru != b.mru)
            return a.mru > b.mru  ; more recently focused wins
        if (a.score != b.score)
            return a.score < b.score
        if (a.z != b.z)
            return a.z < b.z      ; topmost wins
        return a.target < b.target
    }

    /**
     * @description Get the best window (or monitor) on the given side of the current one
     * @param {(Integer)} side - `0` left, `1` right, `2` top, `3` bottom
     * @returns {(Integer)} - hwnd > 0, negated monitor index < 0, or 0 for no move
     */
    _GetFromSide(side) {
        this._EnsureSubscribed()
        this._landRect := 0

        cur := this._GetCurrent()
        if (cur == 0)
            return 0

        ; memory first: opposite key walks back, same key redoes
        if (t := this._TryMemoryReturn(cur, side))
            return t

        entries := this._EnumEntries(cur)

        ; -- source rect --
        if (cur > 0) {
            if (!this._TryGetCoords(cur, &srcRect))
                return 0
        } else {
            ; source is a monitor: its free desktop fragment is where the user "is";
            ; the full workRect would contain every window and make them unreachable
            if (!this._TryGetCoords(cur, &monRect))
                return 0
            allRects := []
            for entry in entries
                allRects.Push(entry.rect)
            srcRect := Geometry.LargestVisibleFragment(monRect, allRects, &visArea)
            if (!srcRect) {
                MouseGetPos(&mx, &my)
                srcRect := Geometry.Rect(mx - 1, my - 1, mx + 1, my + 1)
            }
        }
        srcLeft := this._ToLEFT(srcRect, side)

        ; -- windows: visible fragments minus source, best qualifying piece per window --
        poolWin := []
        occluders := []
        for z, entry in entries {
            if (entry.isCandidate) {
                frags := Geometry.VisibleFragments(entry.rect, occluders)
                visArea := 0
                bestDim := 0
                for f in frags {
                    visArea += Geometry.GetArea(f)
                    dim := Min(f[3] - f[1], f[4] - f[2])
                    bestDim := Max(bestDim, dim)
                }
                ; visible share OR absolute size eligibility: a 200px pard of a huge
                ; window is a tiny fraction but still usable
                if (frags.Length && (
                    visArea / Geometry.GetArea(entry.rect) >= Config.NAV_MIN_VISIBLE_FRACTION
                    || bestDim >= Config.NAV_MIN_ELIGIBLE_DIM
                )) {
                    for f in frags {
                        for piece in Geometry.RectSubtract(f, srcRect) {
                            if (Min(piece[3] - piece[1], piece[4] - piece[2]) >= Config.NAV_MIN_FRAGMENT_DIM)
                                this._EvalInto(poolWin, entry.hwnd, piece, srcLeft, side, z)
                        }
                    }
                }
            }
            occluders.Push(entry.rect)
        }

        ; -- monitors: desktop free space, only when no windows found --
        ; (a desktop used where there's nothing there at all - any reachable window beats it)
        best := this._SelectBest(poolWin)
        if (!best) {
            poolMon := []
            srcCenterX := (srcRect[1] + srcRect[3]) / 2
            srcCenterY := (srcRect[2] + srcRect[4]) / 2
            for i, mon in this._ctx.monitorManager.GetAll() {
                if (cur < 0 && mon.index == -cur)
                    continue
                ; the source window's own monitor should not be targeted, so desktop gaps
                ; between windows must not capture directional focus
                if (cur > 0 && Geometry.PointInRect(srcCenterX, srcCenterY, mon.workRect))
                    continue
                frags := Geometry.VisibleFragments(mon.workRect, occluders, Config.NAV_MONITOR_MIN_FRAGMENT_DIM)
                if (!frags.Length)
                    continue
                for f in frags
                    this._EvalInto(poolMon, -mon.index, f, srcLeft, side, entries.Length + i)
            }
            best := this._SelectBest(poolMon)
        }

        if (!best)
            return 0

        this._PushMove(cur, best.target, side, srcRect, best.frag)
        this._landRect := best.frag
        return best.target
    }

    GetLeft() {
        return this._GetFromSide(0)
    }

    GetRight() {
        return this._GetFromSide(1)
    }

    GetTop() {
        return this._GetFromSide(2)
    }

    GetBottom() {
        return this._GetFromSide(3)
    }

    ;; --- layer navigation (dive down / rise up through the z-stack) ---

    /**
     * @description One layer down: the topmost not-yet-visited window below the
     * current one in z that overlaps it. Each switch raises its target, so
     * "which windows are behind me" comes not from the live
     * z-order, but from the history.
     * @returns {(Integer)} - hwnd > 0, negated monitor index < 0, or 0 for no move
     */
    GetLayerDown() {
        this._EnsureSubscribed()
        this._landRect := 0

        cur := this._GetCurrent()
        if (cur <= 0)
            return 0  ; the desktop is the bottom - nothing below it

        if (t := this._TryMemoryReturn(cur, ClsSpatialWindowNavigator.LAYER_DOWN))
            return t

        if (!this._TryGetCoords(cur, &curRect))
            return 0

        visited := this._VisitedDiveChain(cur)
        entries := this._EnumEntries(cur)

        ; scan strictly below cur in z
        startIdx := 1
        for i, entry in entries {
            if (entry.hwnd == cur) {
                startIdx := i + 1
                break
            }
        }
        loop (entries.Length - startIdx + 1) {
            entry := entries[startIdx + A_Index - 1]
            if (!entry.isCandidate || visited.Has(entry.hwnd))
                continue
            if (!Geometry.DoRectanglesIntersect(curRect, entry.rect))
                continue
            this._PushMove(cur, entry.hwnd, ClsSpatialWindowNavigator.LAYER_DOWN, curRect, entry.rect)
            this._landRect := entry.rect  ; full rect: the dive raises it, center is safe
            return entry.hwnd
        }

        ; pile exhausted, so use monitors
        mon := this._ctx.monitorManager.GetByCoords((curRect[1] + curRect[3]) / 2, (curRect[2] + curRect[4]) / 2)
        frag := this._MonitorFreeFragment(mon, entries)
        if (!frag)
            return 0
        this._PushMove(cur, -mon.index, ClsSpatialWindowNavigator.LAYER_DOWN, curRect, frag)
        this._landRect := frag
        return -mon.index
    }

    /**
     * @description Reverse of GetLayerDown - walk the dive history back.
     * @returns {(Integer)} - hwnd > 0, negated monitor index < 0, or 0 for no move
     */
    GetLayerUp() {
        this._EnsureSubscribed()
        this._landRect := 0
        return this._TryMemoryReturn(this._GetCurrent(), ClsSpatialWindowNavigator.LAYER_UP)
    }

    /**
     * @description Targets already visited by the current dive chain.
     * @returns {(Map)} - visited target -> true
     */
    _VisitedDiveChain(cur) {
        visited := Map(cur, true)
        linkTo := cur
        i := this._cameFrom.Length
        while (i >= 1) {
            entry := this._cameFrom[i]
            if (entry.dir != ClsSpatialWindowNavigator.LAYER_DOWN || entry.to != linkTo)
                break
            visited[entry.from] := true
            linkTo := entry.from
            i--
        }
        return visited
    }

    /**
     * @description Largest free-desktop fragment of a monitor's work area.
     *   0 when no fragment is meaningfully large.
     * @returns {(Array|Integer)} - Rect or 0
     */
    _MonitorFreeFragment(mon, entries) {
        occluders := []
        for entry in entries
            occluders.Push(entry.rect)
        best := 0
        bestArea := 0
        for f in Geometry.VisibleFragments(mon.workRect, occluders, Config.NAV_MONITOR_MIN_FRAGMENT_DIM) {
            if ((area := Geometry.GetArea(f)) > bestArea) {
                bestArea := area
                best := f
            }
        }
        return best
    }

    /**
     * @description The rect the last pick landed on. Consuming clears it.
     * @returns {(Array|Integer)} - Rect or 0
     */
    PopLandRect() {
        rect := this._landRect
        this._landRect := 0
        return rect
    }

    /**
     * @description Find the closest window or monitor, overlapped by the current window
     */
    ClosestOverlapped() {
        if ((curHwnd := this._GetCurrent()) <= 0)
            return curHwnd

        if (!this._TryGetCoords(curHwnd, &curRect))
            return 0
        curArea := Geometry.GetArea(curRect)

        winList := this._GetTargets()
        if (winList.Length == 0)
            return 0

        curZ := 1
        for z, winHwnd in winList {
            if (winHwnd == curHwnd) {
                curZ := z
                break
            }
        }

        loop (winList.Length - curZ) {
            checkingHwnd := winList[curZ + A_Index]
            if (checkingHwnd > 0 && WinCalls.IsCloaked(checkingHwnd))
                continue
            if (!this._TryGetCoords(checkingHwnd, &checkingRect))
                continue

            if (
                (interArea := Geometry.GetIntersectionArea(curRect, checkingRect)) > 0
                && Sqrt(interArea) / Sqrt(Geometry.GetArea(checkingRect) + curArea) > this._intersectionThreshold
            )
                return checkingHwnd
        }
        return 0
    }
}
