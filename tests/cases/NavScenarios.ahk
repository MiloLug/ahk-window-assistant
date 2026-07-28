#Requires AutoHotkey v2.0
; Scenario checks for the spatial navigator + Geometry helpers.
; Spawns dummy Gui windows in canonical layouts and asserts where hjkl goes.
; Invoked by tests/Main.ahk - see there for how to run and how to filter suites.

#Include ../TestCore.ahk
#Include ../../src/Config.ahk
#Include ../../src/Constants.ahk
#Include ../../src/Lib/Geometry.ahk
#Include ../../src/Lib/Utils.ahk
#Include ../../src/Navigators/SpatialNavigator.ahk


;; === Suite registration ===

Test.InFile(A_LineFile)

Test.Suite("Geometry", RunGeometryChecks)

Test.Suite("S1 side-by-side", NavSuite(S1))
Test.Suite("S2 vertical", NavSuite(S2))
Test.Suite("S3 cascade chain", NavSuite(S3))
Test.Suite("S4 sliver", NavSuite(S4))
Test.Suite("S5 fully hidden", NavSuite(S5))
Test.Suite("S6 diagonal", NavSuite(S6))
Test.Suite("S7 beam priority", NavSuite(S7))
Test.Suite("S8 came-from memory", NavSuite(S8))
Test.Suite("S9 MRU tiebreak", NavSuite(S9))
Test.Suite("S9b MRU epsilon band", NavSuite(S9b))
Test.Suite("S15 both-sides window", NavSuite(S15))
Test.Suite("S13 own-monitor gap", NavSuite(S13))
Test.Suite("S16 landRect", NavSuite(S16))
Test.Suite("S14 cross-monitor", CtxNavSuite(S14))
Test.Suite("S18 monitor source", CtxNavSuite(S18))
; --- layer navigation (dive down / rise up) ---
Test.Suite("S20 dive chain + desktop", CtxNavSuite(S20))
Test.Suite("S21 up empty history", NavSuite(S21))
Test.Suite("S22 dive visited-skip", NavSuite(S22))
Test.Suite("S23 dive redo", NavSuite(S23))
Test.Suite("S24 dive/hjkl interleave", NavSuite(S24))
Test.Suite("S25 non-overlap not a dive target", CtxNavSuite(S25))
Test.Suite("S26 desktop round trip", CtxNavSuite(S26))
Test.Suite("S27 dead-entry contraction", NavSuite(S27))
Test.Suite("S28 hjkl contraction", NavSuite(S28))
; --- log-only ---
Test.Suite("DPI probe", () => DpiProbe(Test.Ctx))
Test.Suite("perf smoke", PerfSmokeInner)


;; === Fixture ===

; Suites take no arguments; scenarios take the fixture pieces they need. These adapters bridge
; the two, so scenario signatures stay readable.
NavSuite(fn) => () => (f := NavFixture(), fn(f.nav, f.bx, f.by))
CtxNavSuite(fn) => () => (f := NavFixture(), fn(f.ctx, f.nav, f.bx, f.by))

/**
 * @description Shared navigator fixture, built once and reset before every scenario.
 * The navigator is restricted to this process's windows: that keeps the user's real desktop out
 * of the asserts, and the same selector feeds both candidates and occluders.
 * LIMIT: production-list concerns (e.g. desktop-class windows excluded as cutters - Progman spans
 * all monitors and would zero every free fragment) can't regress here; those need the
 * unrestricted probe / manual checklist.
 * @returns {(Object)} {ctx, nav, workRect, bx, by} - bx/by = scenario origin, inset from workRect
 */
NavFixture() {
    static f := 0
    if (!f) {
        ctx := Test.Ctx
        base := ctx.monitorManager.GetByIndex(MonitorGetPrimary()).workRect
        f := {
            ctx: ctx,
            nav: ClsSpatialWindowNavigator(ctx, "ahk_pid " DllCall("GetCurrentProcessId")),
            workRect: base,  ; NOT `base:` - that key sets an object's prototype -> "Invalid base."
            bx: base[1] + 50,
            by: base[2] + 50
        }
    }
    ResetNav(f.nav)  ; belt and braces: scenarios reset explicitly, new ones may forget
    return f
}

;; === Geometry unit checks (pure, no windows) ===

RunGeometryChecks() {
    Guard("Geometry.RectIntersection", () => (
        AssertEq("RectIntersection: disjoint -> 0",
            Geometry.RectIntersection([0, 0, 10, 10], [20, 20, 30, 30]), 0),
        AssertEq("RectIntersection: touching edge -> 0",
            Geometry.RectIntersection([0, 0, 10, 10], [10, 0, 20, 10]), 0),
        AssertTrue("RectIntersection: overlap -> exact rect",
            RectsEq(Geometry.RectIntersection([0, 0, 10, 10], [5, 5, 20, 20]), [5, 5, 10, 10])),
        AssertTrue("RectIntersection: containment -> inner",
            RectsEq(Geometry.RectIntersection([0, 0, 100, 100], [10, 20, 30, 40]), [10, 20, 30, 40]))
    ))

    Guard("Geometry.RectSubtract", () => (
        SubtractDisjointCheck(),
        SubtractFullCoverCheck(),
        SubtractContainedCheck(),
        SubtractHalfCheck(),
        SubtractCornerCheck(),
        SubtractBandCheck()
    ))

    Guard("Geometry.VisibleFragments", () => (
        FragmentsNoOccludersCheck(),
        FragmentsCentralOccluderCheck(),
        FragmentsFullCoverCheck(),
        FragmentsMinDimCullCheck(),
        FragmentsTrimCheck()
    ))

    Guard("Geometry.LargestVisibleFragment", () => (
        LargestUncoveredCheck(),
        LargestHalfCoveredCheck(),
        LargestFullCoverCheck()
    ))
}

SubtractDisjointCheck() {
    out := Geometry.RectSubtract([0, 0, 10, 10], [50, 50, 60, 60])
    AssertTrue("RectSubtract: disjoint -> [r]", out.Length == 1 && RectsEq(out[1], [0, 0, 10, 10]))
}

SubtractFullCoverCheck() {
    out := Geometry.RectSubtract([10, 10, 20, 20], [0, 0, 100, 100])
    AssertEq("RectSubtract: full cover -> empty", out.Length, 0)
}

SubtractContainedCheck() {
    r := [0, 0, 100, 100]
    cut := [20, 30, 60, 70]
    out := Geometry.RectSubtract(r, cut)
    conserved := SumAreas(out) + Geometry.GetIntersectionArea(r, cut) == Geometry.GetArea(r)
    AssertTrue("RectSubtract: contained cut -> 4 bands, area conserved", out.Length == 4 && conserved)
}

SubtractHalfCheck() {
    out := Geometry.RectSubtract([0, 0, 100, 100], [50, -10, 200, 110])
    AssertTrue("RectSubtract: right half cut -> 1 left band",
        out.Length == 1 && RectsEq(out[1], [0, 0, 50, 100]))
}

SubtractCornerCheck() {
    r := [0, 0, 100, 100]
    cut := [60, 60, 150, 150]
    out := Geometry.RectSubtract(r, cut)
    conserved := SumAreas(out) + Geometry.GetIntersectionArea(r, cut) == Geometry.GetArea(r)
    AssertTrue("RectSubtract: corner cut -> 2 pieces, area conserved", out.Length == 2 && conserved)
}

SubtractBandCheck() {
    out := Geometry.RectSubtract([0, 0, 100, 100], [-10, 40, 110, 60])
    AssertTrue("RectSubtract: horizontal band -> top+bottom",
        out.Length == 2 && SumAreas(out) == 100 * 80)
}

FragmentsNoOccludersCheck() {
    out := Geometry.VisibleFragments([0, 0, 100, 100], [])
    AssertTrue("VisibleFragments: no occluders -> [rect]",
        out.Length == 1 && RectsEq(out[1], [0, 0, 100, 100]))
}

FragmentsCentralOccluderCheck() {
    r := [0, 0, 100, 100]
    occ := [[25, 25, 75, 75]]
    out := Geometry.VisibleFragments(r, occ)
    AssertTrue("VisibleFragments: central occluder -> 4 pieces, area conserved",
        out.Length == 4 && SumAreas(out) == Geometry.GetArea(r) - 50 * 50)
}

FragmentsFullCoverCheck() {
    out := Geometry.VisibleFragments([10, 10, 20, 20], [[0, 0, 100, 100]])
    AssertEq("VisibleFragments: fully covered -> empty", out.Length, 0)
}

FragmentsMinDimCullCheck() {
    ; occluder leaves a 10px-wide strip; default cull is Config.NAV_MIN_FRAGMENT_DIM (16)
    out := Geometry.VisibleFragments([0, 0, 100, 100], [[10, -10, 110, 110]])
    AssertEq("VisibleFragments: sub-minDim sliver culled", out.Length, 0)
}

FragmentsTrimCheck() {
    ; a comb of cuts producing > NAV_MAX_FRAGMENTS pieces must stay bounded
    r := [0, 0, 1000, 1000]
    occ := []
    loop 25
        occ.Push([(A_Index - 1) * 40 + 20, -10, (A_Index - 1) * 40 + 40, 1010])
    out := Geometry.VisibleFragments(r, occ)
    AssertTrue("VisibleFragments: fragment list bounded by NAV_MAX_FRAGMENTS",
        out.Length > 0 && out.Length <= Config.NAV_MAX_FRAGMENTS)
}

LargestUncoveredCheck() {
    best := Geometry.LargestVisibleFragment([0, 0, 100, 50], [], &visArea := 0)
    AssertTrue("LargestVisibleFragment: uncovered -> rect itself, full visArea",
        RectsEq(best, [0, 0, 100, 50]) && visArea == 100 * 50)
}

LargestHalfCoveredCheck() {
    best := Geometry.LargestVisibleFragment([0, 0, 100, 100], [[-10, -10, 40, 110]], &visArea := 0)
    AssertTrue("LargestVisibleFragment: left covered -> right piece",
        RectsEq(best, [40, 0, 100, 100]) && visArea == 60 * 100)
}

LargestFullCoverCheck() {
    best := Geometry.LargestVisibleFragment([10, 10, 20, 20], [[0, 0, 50, 50]], &visArea := 0)
    AssertTrue("LargestVisibleFragment: covered -> 0 and visArea 0", best == 0 && visArea == 0)
}

;; === Window scenarios ===

; Reset navigator side-state between scenarios. No try: a field rename must fail loudly
; here, not silently disable resets and contaminate scenarios.
ResetNav(nav) {
    nav._cameFrom := []
    nav._redo := 0
    nav._mru := Map()
    nav._landRect := 0
}

S1(nav, BX, BY) {
    wins := [a := ClsTestWin(BX, BY, 500, 400, "NAV A"), b := ClsTestWin(BX + 600, BY, 500, 400, "NAV B")]
    try {
        ResetNav(nav)
        FocusWin(b.hwnd)
        AssertEq("S1: left from B -> A", nav.GetLeft(), a.hwnd)
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S1: right from A -> B", nav.GetRight(), b.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S2(nav, BX, BY) {
    wins := [a := ClsTestWin(BX, BY, 500, 300, "NAV A"), b := ClsTestWin(BX, BY + 400, 500, 300, "NAV B")]
    try {
        ResetNav(nav)
        FocusWin(b.hwnd)
        AssertEq("S2: top from B -> A", nav.GetTop(), a.hwnd)
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S2: bottom from A -> B", nav.GetBottom(), b.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S3(nav, BX, BY) {
    ; created bottom -> top: C under B under A, diagonal cascade, each peeks out up-left
    wins := [c := ClsTestWin(BX, BY, 600, 450, "NAV C"), b := ClsTestWin(BX + 200, BY + 150, 600, 450, "NAV B"), a := ClsTestWin(BX + 400, BY + 300, 600, 450, "NAV A")]
    try {
        ResetNav(nav)
        FocusWin(a.hwnd)
        r1 := nav.GetLeft()
        AssertEq("S3: left from A -> B (overlapping cascade)", r1, b.hwnd)
        if (r1 == b.hwnd) {
            FocusWin(b.hwnd)
            AssertEq("S3: left from B -> C", nav.GetLeft(), c.hwnd)
            FocusWin(c.hwnd)
            AssertEq("S3: right from C pops memory -> B", nav.GetRight(), b.hwnd)
            FocusWin(b.hwnd)
            AssertEq("S3: right from B pops memory -> A", nav.GetRight(), a.hwnd)
        }
    } finally {
        DestroyWins(wins)
    }
}

S4(nav, BX, BY) {
    ; SMALL under BIG, peeking 150px out to the left -> target
    wins := [small := ClsTestWin(BX + 150, BY + 50, 300, 300, "NAV SMALL"), big := ClsTestWin(BX + 300, BY, 700, 500, "NAV BIG")]
    try {
        ResetNav(nav)
        FocusWin(big.hwnd)
        AssertEq("S4a: left from BIG -> SMALL (visible sliver)", nav.GetLeft(), small.hwnd)
    } finally {
        DestroyWins(wins)
    }

    ; sub-threshold sliver (~8px peek) must be skipped
    wins2 := [small2 := ClsTestWin(BX + 292, BY + 50, 300, 300, "NAV SMALL2"), big2 := ClsTestWin(BX + 300, BY, 700, 500, "NAV BIG2")]
    try {
        ResetNav(nav)
        FocusWin(big2.hwnd)
        AssertNeq("S4b: 8px sliver is not a target", nav.GetLeft(), small2.hwnd)
    } finally {
        DestroyWins(wins2)
    }
}

S5(nav, BX, BY) {
    ; HID fully inside BIG (under it); FAR fully left. Left from BIG must go FAR, not HID.
    wins := [hid := ClsTestWin(BX + 700, BY + 100, 300, 250, "NAV HID"), far := ClsTestWin(BX, BY + 50, 300, 400, "NAV FAR"), big := ClsTestWin(BX + 600, BY, 700, 500, "NAV BIG")]
    try {
        ResetNav(nav)
        FocusWin(big.hwnd)
        AssertEq("S5: left from BIG -> FAR (hidden window skipped)", nav.GetLeft(), far.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S6(nav, BX, BY) {
    wins := [d := ClsTestWin(BX, BY, 300, 250, "NAV D"), a := ClsTestWin(BX + 600, BY + 500, 400, 300, "NAV A")]
    try {
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S6: diagonal reachable via left", nav.GetLeft(), d.hwnd)
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S6: diagonal reachable via top", nav.GetTop(), d.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S7(nav, BX, BY) {
    ; from S: FARBEAM is left + same row (in-beam), NEAROFF is left + far below (off-beam) but closer on x
    wins := [
        farbeam := ClsTestWin(BX, BY + 250, 300, 200, "NAV FARBEAM"),
        nearoff := ClsTestWin(BX + 550, BY + 700, 200, 150, "NAV NEAROFF"),
        s := ClsTestWin(BX + 800, BY + 200, 400, 300, "NAV S")
    ]
    try {
        ResetNav(nav)
        FocusWin(s.hwnd)
        AssertEq("S7: in-beam far beats off-beam near", nav.GetLeft(), farbeam.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S8(nav, BX, BY) {
    ; A -> right -> B sets memory; A2 (geometrically better from B) created after;
    ; left from B must return A (memory), then right from A redoes to B; from A2 it's geometric.
    wins := [a := ClsTestWin(BX, BY + 100, 300, 250, "NAV A"), b := ClsTestWin(BX + 700, BY + 100, 400, 300, "NAV B")]
    a2 := 0
    try {
        ResetNav(nav)
        FocusWin(a.hwnd)
        r1 := nav.GetRight()
        AssertEq("S8: right from A -> B", r1, b.hwnd)
        if (r1 == b.hwnd) {
            wins.Push(a2 := ClsTestWin(BX + 400, BY + 120, 250, 200, "NAV A2"))  ; closer to B, in-beam
            FocusWin(b.hwnd)
            AssertEq("S8: left from B -> A via memory (not closer A2)", nav.GetLeft(), a.hwnd)
            FocusWin(a.hwnd)
            AssertEq("S8: right from A redoes -> B", nav.GetRight(), b.hwnd)
            FocusWin(a2.hwnd)
            AssertEq("S8: right from A2 (no memory match) -> B geometric", nav.GetRight(), b.hwnd)
        }
    } finally {
        DestroyWins(wins)
    }
}

S9(nav, BX, BY) {
    ; two mirror-symmetric candidates below source -> exact score tie -> MRU decides
    wins := [
        c1 := ClsTestWin(BX + 100, BY + 500, 300, 200, "NAV C1"),
        c2 := ClsTestWin(BX + 600, BY + 500, 300, 200, "NAV C2"),
        s := ClsTestWin(BX + 300, BY, 400, 300, "NAV S")
    ]
    try {
        ResetNav(nav)
        FocusWin(s.hwnd)
        nav._mru[c1.hwnd] := 1
        nav._mru[c2.hwnd] := 2
        AssertEq("S9: tie -> more recent C2", nav.GetBottom(), c2.hwnd)
        ResetNav(nav)
        nav._mru[c1.hwnd] := 2
        nav._mru[c2.hwnd] := 1
        FocusWin(s.hwnd)
        AssertEq("S9: tie -> more recent C1", nav.GetBottom(), c1.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S9b(nav, BX, BY) {
    ; scores unequal but within NAV_TIE_EPSILON (~20px apart): MRU must still decide,
    ; even in favor of the geometrically-farther candidate
    wins := [
        d1 := ClsTestWin(BX + 100, BY, 300, 140, "NAV D1"),
        d2 := ClsTestWin(BX + 80, BY + 160, 300, 140, "NAV D2"),
        s := ClsTestWin(BX + 700, BY, 400, 300, "NAV S")
    ]
    try {
        ResetNav(nav)
        FocusWin(s.hwnd)
        nav._mru[d1.hwnd] := 1
        nav._mru[d2.hwnd] := 2
        AssertEq("S9b: near-tie -> more recent (farther) D2", nav.GetLeft(), d2.hwnd)
        ResetNav(nav)
        nav._mru[d1.hwnd] := 2
        nav._mru[d2.hwnd] := 1
        FocusWin(s.hwnd)
        AssertEq("S9b: near-tie -> more recent (nearer) D1", nav.GetLeft(), d1.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S18(ctx, nav, BX, BY) {
    ; focus the desktop (Progman is interactable-filtered, so _GetCurrent falls back to
    ; the monitor under the mouse) and navigate from the desktop's free fragment into a
    ; window. W is a near-full-height left column so the largest free fragment is
    ; unambiguously the right-side block, with W strictly to its left.
    base := ctx.monitorManager.GetByIndex(MonitorGetPrimary()).workRect
    wins := [w := ClsTestWin(base[1] + 30, base[2] + 60, 400, (base[4] - base[2]) - 150, "NAV W")]
    try {
        ResetNav(nav)
        DllCall("SetCursorPos", "Int", base[3] - 200, "Int", (base[2] + base[4]) / 2)
        WinActivate("ahk_class Progman")
        Sleep(150)
        AssertEq("S18: left from desktop free fragment -> window", nav.GetLeft(), w.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S15(nav, BX, BY) {
    ; OVER created after SRC got focus: fully visible on top, protruding BOTH sides.
    ; Old predicate can't reach it in either direction; fragment model reaches it in both.
    wins := [src := ClsTestWin(BX + 300, BY, 400, 350, "NAV SRC")]
    try {
        ResetNav(nav)
        FocusWin(src.hwnd)
        wins.Push(over := ClsTestWin(BX, BY + 60, 1000, 220, "NAV OVER"))
        Sleep(80)
        AssertEq("S15: both-sides window reachable via left", nav.GetLeft(), over.hwnd)
        ResetNav(nav)
        AssertEq("S15: both-sides window reachable via right", nav.GetRight(), over.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S13(nav, BX, BY) {
    ; W far left with a big desktop gap before S: gap must not become a target (own monitor excluded)
    wins := [w := ClsTestWin(BX, BY + 50, 300, 300, "NAV W"), s := ClsTestWin(BX + 600, BY, 500, 400, "NAV S")]
    try {
        ResetNav(nav)
        FocusWin(s.hwnd)
        AssertEq("S13: left goes to W, not own-monitor desktop gap", nav.GetLeft(), w.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S16(nav, BX, BY) {
    ; sliver target: landing rect must lie inside the visible sliver, left of BIG's edge
    wins := [small := ClsTestWin(BX + 150, BY + 50, 300, 300, "NAV SMALL"), big := ClsTestWin(BX + 300, BY, 700, 500, "NAV BIG")]
    try {
        ResetNav(nav)
        FocusWin(big.hwnd)
        target := nav.GetLeft()
        land := nav.PopLandRect()
        bigRect := big.Rect()
        smallRect := small.Rect()
        okTarget := target == small.hwnd
        okLand := (land is Array)
            && land[1] >= smallRect[1] - 1 && land[3] <= bigRect[1] + 1
            && land[2] >= smallRect[2] - 1 && land[4] <= smallRect[4] + 1
        AssertTrue("S16: landRect inside visible sliver", okTarget && okLand)
        AssertEq("S16: PopLandRect drains", nav.PopLandRect(), 0)
    } finally {
        DestroyWins(wins)
    }
}

S14(ctx, nav, BX, BY) {
    ; BX/BY unused: both windows are placed off the monitors' own work rects
    monitors := ctx.monitorManager.GetAll()
    if (monitors.Length < 2) {
        Report("SKIP: S14 cross-monitor (single monitor)")
        return
    }
    ; source on the monitor under the primary work area; target = the other one
    primaryIdx := MonitorGetPrimary()
    srcMon := ctx.monitorManager.GetByIndex(primaryIdx)
    otherMon := 0
    for m in monitors {
        if (m.index != primaryIdx) {
            otherMon := m
            break
        }
    }
    srcW := otherW := 0
    wins := []
    try {
        sw := srcMon.workRect
        ow := otherMon.workRect
        wins.Push(srcW := ClsTestWin(sw[1] + 100, sw[2] + 100, 500, 400, "NAV SRCMON"))
        ; cover the other monitor's work area entirely
        wins.Push(otherW := ClsTestWin(ow[1], ow[2], ow[3] - ow[1], ow[4] - ow[2], "NAV COVER"))
        WinMove(ow[1], ow[2], ow[3] - ow[1], ow[4] - ow[2], otherW.hwnd)
        Sleep(80)

        goingLeft := (ow[1] + ow[3]) / 2 < (sw[1] + sw[3]) / 2
        ResetNav(nav)
        FocusWin(srcW.hwnd)
        r1 := goingLeft ? nav.GetLeft() : nav.GetRight()
        AssertEq("S14: toward covered monitor -> its window, not desktop", r1, otherW.hwnd)

        try otherW.gui.Destroy()
        Sleep(120)
        ResetNav(nav)
        FocusWin(srcW.hwnd)
        r2 := goingLeft ? nav.GetLeft() : nav.GetRight()
        AssertEq("S14: toward empty monitor -> monitor target", r2, -otherMon.index)
    } finally {
        DestroyWins(wins)
    }
}

;; === Layer navigation scenarios ===
; Harness rule: between presses, FocusWin() EXACTLY the returned target - in production
; the activation raises it; here a mismatched focus would also desync the came-from
; stack's `top.to` from the real foreground.

; Truly-free sub-rect of `rect` on the LIVE desktop. The pid-restricted navigator only
; knows its own windows, but parking the mouse over a real one makes desktop focus
; unreliable (hover-focus utilities re-steal the foreground moments later). 0 if none.
TrueFreeSpot(rect) {
    occ := []
    for hwnd in WinGetList('') {
        try {
            cls := WinGetClass(hwnd)
            if (cls == "Progman" || cls == "WorkerW")
                continue
            if (WinGetMinMax(hwnd) == WIN_MINIMIZED)
                continue
            if (WinCalls.IsCloaked(hwnd))
                continue
            if (!WinCalls.WinGetPosEx(hwnd, &l, &t, , , &r, &b))
                continue
            occ.Push(Geometry.Rect(l, t, r, b))
        } catch {
            continue
        }
    }
    best := 0
    bestArea := 0
    for f in Geometry.VisibleFragments(rect, occ, 24) {
        if ((a := Geometry.GetArea(f)) > bestArea) {
            bestArea := a
            best := f
        }
    }
    return best
}

; Focus the desktop with the mouse parked on genuinely empty space inside `land`.
; Returns false (after reporting a SKIP) when the live desktop leaves no free spot.
FocusDesktopAt(land, label) {
    spot := TrueFreeSpot(land)
    if (!spot) {
        Report("SKIP: " label " (no free desktop spot on the live desktop)")
        return false
    }
    DllCall("SetCursorPos", "Int", (spot[1] + spot[3]) / 2, "Int", (spot[2] + spot[4]) / 2)
    WinActivate("ahk_class Progman")
    Sleep(150)
    return true
}

S20(ctx, nav, BX, BY) {
    ; 3-pile: each press goes exactly one layer down; past the bottom the desktop is
    ; the final layer; up retraces the whole chain; exhausted history -> no-op.
    wins := [
        c := ClsTestWin(BX + 160, BY + 160, 500, 400, "NAV C"),
        b := ClsTestWin(BX + 80, BY + 80, 500, 400, "NAV B"),
        a := ClsTestWin(BX, BY, 500, 400, "NAV A")
    ]
    try {
        cRect := c.Rect()
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S20: down 1 -> B", nav.GetLayerDown(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S20: down 2 -> C", nav.GetLayerDown(), c.hwnd)
        FocusWin(c.hwnd)

        expMon := ctx.monitorManager.GetByCoords((cRect[1] + cRect[3]) / 2, (cRect[2] + cRect[4]) / 2)
        AssertEq("S20: down 3 (pile exhausted) -> desktop", nav.GetLayerDown(), -expMon.index)
        land := nav.PopLandRect()
        AssertTrue("S20: desktop land rect avoids the pile", (land is Array)
            && !Geometry.DoRectanglesIntersect(land, a.Rect())
            && !Geometry.DoRectanglesIntersect(land, b.Rect())
            && !Geometry.DoRectanglesIntersect(land, cRect))
        ; simulate the landing: mouse onto genuinely free desktop inside the fragment.
        ; A busy live desktop (hover-focus utilities re-steal over real windows) falls
        ; back to pinning the pop logic directly - integration runs when it can.
        if (FocusDesktopAt(land, "S20 desktop round trip")) {
            AssertEq("S20: up 1 (from desktop) -> C", nav.GetLayerUp(), c.hwnd)
        } else {
            AssertEq("S20: up 1 pop (unit fallback) -> C",
                nav._TryMemoryReturn(-expMon.index, ClsSpatialWindowNavigator.LAYER_UP), c.hwnd)
        }
        AssertTrue("S20: memory return parks on C's rect", RectsEq(nav.PopLandRect(), cRect))
        FocusWin(c.hwnd)
        AssertEq("S20: up 2 -> B", nav.GetLayerUp(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S20: up 3 -> A", nav.GetLayerUp(), a.hwnd)
        FocusWin(a.hwnd)
        AssertEq("S20: up 4 (history exhausted) -> no-op", nav.GetLayerUp(), 0)

        ; determinism: the round trip restored the original z-order - same dive again
        ResetNav(nav)
        AssertEq("S20: repeat down 1 -> B", nav.GetLayerDown(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S20: repeat down 2 -> C", nav.GetLayerDown(), c.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S21(nav, BX, BY) {
    ; up strictly retraces dives: nothing to retrace -> nothing happens
    wins := [w := ClsTestWin(BX, BY, 500, 400, "NAV W")]
    try {
        ResetNav(nav)
        FocusWin(w.hwnd)
        AssertEq("S21: up with empty history -> no-op", nav.GetLayerUp(), 0)
        AssertTrue("S21: stack and redo untouched", nav._cameFrom.Length == 0 && nav._redo == 0)
    } finally {
        DestroyWins(wins)
    }
}

S22(nav, BX, BY) {
    ; the ping-pong killer: after X -> Y raised Y above X, down from Y must skip the
    ; already-visited X (live z alone would bounce Y <-> X forever) and reach Z
    wins := [
        z := ClsTestWin(BX + 160, BY + 160, 500, 400, "NAV Z"),
        y := ClsTestWin(BX + 80, BY + 80, 500, 400, "NAV Y"),
        x := ClsTestWin(BX, BY, 500, 400, "NAV X")
    ]
    try {
        ResetNav(nav)
        FocusWin(x.hwnd)
        AssertEq("S22: down from X -> Y", nav.GetLayerDown(), y.hwnd)
        FocusWin(y.hwnd)  ; raises Y above X
        AssertEq("S22: down from Y skips visited X -> Z", nav.GetLayerDown(), z.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S23(nav, BX, BY) {
    ; down,down,up,down: the last down re-dives via the redo slot, not a fresh pick
    wins := [
        z := ClsTestWin(BX + 160, BY + 160, 500, 400, "NAV Z"),
        y := ClsTestWin(BX + 80, BY + 80, 500, 400, "NAV Y"),
        x := ClsTestWin(BX, BY, 500, 400, "NAV X")
    ]
    try {
        ResetNav(nav)
        FocusWin(x.hwnd)
        AssertEq("S23: down 1 -> Y", nav.GetLayerDown(), y.hwnd)
        FocusWin(y.hwnd)
        AssertEq("S23: down 2 -> Z", nav.GetLayerDown(), z.hwnd)
        FocusWin(z.hwnd)
        AssertEq("S23: up -> Y", nav.GetLayerUp(), y.hwnd)
        FocusWin(y.hwnd)
        AssertEq("S23: down redoes -> Z", nav.GetLayerDown(), z.hwnd)
        AssertEq("S23: stack depth restored", nav._cameFrom.Length, 2)
    } finally {
        DestroyWins(wins)
    }
}

S24(nav, BX, BY) {
    ; dirs 4/5 share the came-from stack with hjkl: i, l, h, u unwinds the exact path
    wins := [
        b := ClsTestWin(BX + 60, BY + 60, 500, 400, "NAV B"),
        a := ClsTestWin(BX, BY, 500, 400, "NAV A"),
        c := ClsTestWin(BX + 700, BY, 400, 300, "NAV C")
    ]
    try {
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S24: down A -> B", nav.GetLayerDown(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S24: right B -> C", nav.GetRight(), c.hwnd)
        FocusWin(c.hwnd)
        AssertEq("S24: left pops -> B", nav.GetLeft(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S24: up pops the dive -> A", nav.GetLayerUp(), a.hwnd)
    } finally {
        DestroyWins(wins)
    }
}

S25(ctx, nav, BX, BY) {
    ; disjoint window is not "below" the current one - down goes to the desktop layer
    wins := [
        w1 := ClsTestWin(BX, BY, 400, 300, "NAV W1"),
        w2 := ClsTestWin(BX + 600, BY + 400, 400, 300, "NAV W2")
    ]
    try {
        r1 := w1.Rect()
        expMon := ctx.monitorManager.GetByCoords((r1[1] + r1[3]) / 2, (r1[2] + r1[4]) / 2)
        ResetNav(nav)
        FocusWin(w1.hwnd)
        AssertEq("S25: down with no overlap -> desktop, not the disjoint window",
            nav.GetLayerDown(), -expMon.index)
    } finally {
        DestroyWins(wins)
    }
}

S26(ctx, nav, BX, BY) {
    ; lone window: desktop is one layer down; rising from the desktop is the round trip
    ; (source is a monitor - GetLayerUp must not bail on cur < 0)
    wins := [w := ClsTestWin(BX, BY, 500, 400, "NAV W")]
    try {
        wRect := w.Rect()
        expMon := ctx.monitorManager.GetByCoords((wRect[1] + wRect[3]) / 2, (wRect[2] + wRect[4]) / 2)
        ResetNav(nav)
        FocusWin(w.hwnd)
        AssertEq("S26: down from lone window -> desktop", nav.GetLayerDown(), -expMon.index)
        land := nav.PopLandRect()
        AssertTrue("S26: land rect is free desktop, not the window",
            (land is Array) && !Geometry.DoRectanglesIntersect(land, wRect))
        if (FocusDesktopAt(land, "S26 up-from-desktop")) {
            AssertEq("S26: up from desktop -> the window", nav.GetLayerUp(), w.hwnd)
        } else {
            AssertEq("S26: up pop (unit fallback) -> the window",
                nav._TryMemoryReturn(-expMon.index, ClsSpatialWindowNavigator.LAYER_UP), w.hwnd)
        }
    } finally {
        DestroyWins(wins)
    }
}

S27(nav, BX, BY) {
    ; a window closed mid-chain must not block the walk back: the pop contracts
    ; through the dead entry and returns the next valid ancestor
    wins := [
        z := ClsTestWin(BX + 160, BY + 160, 500, 400, "NAV Z"),
        y := ClsTestWin(BX + 80, BY + 80, 500, 400, "NAV Y"),
        x := ClsTestWin(BX, BY, 500, 400, "NAV X")
    ]
    try {
        ResetNav(nav)
        FocusWin(x.hwnd)
        AssertEq("S27: down 1 -> Y", nav.GetLayerDown(), y.hwnd)
        FocusWin(y.hwnd)
        AssertEq("S27: down 2 -> Z", nav.GetLayerDown(), z.hwnd)
        FocusWin(z.hwnd)
        try y.gui.Destroy()
        Sleep(120)
        AssertEq("S27: up contracts through dead Y -> X", nav.GetLayerUp(), x.hwnd)
        AssertEq("S27: contraction drained the stack", nav._cameFrom.Length, 0)
    } finally {
        DestroyWins(wins)
    }
}

S28(nav, BX, BY) {
    ; contraction also applies to hjkl (deliberate change): a dead mid-chain window
    ; must not block the walk back. A2 (created after the chain, closer to C) makes
    ; the outcomes distinguishable: memory returns A, a geometric pick would take A2.
    wins := [
        a := ClsTestWin(BX, BY, 300, 300, "NAV A"),
        b := ClsTestWin(BX + 400, BY, 300, 300, "NAV B"),
        c := ClsTestWin(BX + 1100, BY, 300, 300, "NAV C")
    ]
    try {
        ResetNav(nav)
        FocusWin(a.hwnd)
        AssertEq("S28: right 1 -> B", nav.GetRight(), b.hwnd)
        FocusWin(b.hwnd)
        AssertEq("S28: right 2 -> C", nav.GetRight(), c.hwnd)
        FocusWin(c.hwnd)
        wins.Push(a2 := ClsTestWin(BX + 700, BY + 20, 300, 260, "NAV A2"))
        Sleep(80)
        try b.gui.Destroy()
        Sleep(120)
        AssertEq("S28: left contracts through dead B -> A, not closer A2", nav.GetLeft(), a.hwnd)
        AssertEq("S28: contraction drained the stack", nav._cameFrom.Length, 0)
    } finally {
        DestroyWins(wins)
    }
}

;; === DPI probe (log-only) ===

DpiProbe(ctx) {
    Report("--- DPI probe ---")
    Report("A_ScreenDPI=" A_ScreenDPI)
    for m in ctx.monitorManager.GetAll()
        Report("Monitor " m.index " rect=" RectStr(m.rect) " work=" RectStr(m.workRect))
    probe := ClsTestWin(200, 200, 300, 200, "NAV DPIPROBE")
    try {
        Sleep(50)
        WinGetPos(&px, &py, &pw, &ph, probe.hwnd)
        r := probe.Rect()
        Report("Probe WinGetPos=[" px ", " py ", " (px + pw) ", " (py + ph) "] WinGetPosEx=" RectStr(r))
    } finally {
        DestroyWins([probe])
    }
}

;; === Perf smoke (log-only) ===

PerfSmokeInner() {
    ; 30 cascading rects; compute fragments of each against all rects above it, 100x
    rects := []
    loop 30
        rects.Push([(A_Index - 1) * 60, (A_Index - 1) * 40, (A_Index - 1) * 60 + 800, (A_Index - 1) * 40 + 600])
    t0 := Qpc()
    loop 100 {
        occ := []
        for r in rects {
            Geometry.VisibleFragments(r, occ)
            occ.Push(r)
        }
    }
    t1 := Qpc()
    Report(Format("PERF: 100x 30-window cascade fragment pipeline = {:.1f} ms total ({:.2f} ms/keypress-equivalent)", t1 - t0, (t1 - t0) / 100))
}
