#Requires AutoHotkey v2.0

; Test harness: suite registry, asserts, and the dummy-window utilities scenarios build on.
; Case files under cases/ register suites; tests/Main.ahk invokes Test.Run(A_Args).
;
; Context.ahk, NOT Core.ahk: Core has top-level `ctx := ClsContext()` plus the app globals, and
; tests build their own context so the production instance is never a hidden dependency.

#Include ../src/Config.ahk
#Include ../src/Constants.ahk
#Include ../src/Context.ahk
#Include ../src/Lib/Geometry.ahk
#Include ../src/Lib/Utils.ahk
#Include ../src/Lib/Paths.ahk


/**
 * @description Suite registry + runner. Static: there is exactly one run per process.
 */
class Test {
    static _suites := []
    static _file := ""
    static _pass := 0
    static _fail := 0
    static _ctx := 0

    /**
     * @description Shared context, built on first use. One per run - ClsContext installs hooks
     * and timers, so a per-suite instance would stack them.
     * @returns {(ClsContext)}
     */
    static Ctx {
        get {
            if (!Test._ctx)
                Test._ctx := ClsContext()
            return Test._ctx
        }
    }

    /**
     * @description Tag the suites registered after this call with their source file. Call once at
     * the top of a case file as `Test.InFile(A_LineFile)` - A_LineFile inside Test.Suite would
     * name this file instead of the caller's.
     * @param {(String)} path full path of the case file
     */
    static InFile(path) {
        Test._file := path
    }

    /**
     * @description Register a suite. Runs in registration order unless filtered out.
     * @param {(String)} name shown in reports, matchable by the CLI filter
     * @param {(Func)} fn takes no arguments; a throw is caught and counted as one FAIL
     */
    static Suite(name, fn) {
        Test._suites.Push({ name: name, file: Test._file, fn: fn })
    }

    /**
     * @description Path of a suite's case file relative to tests/, forward-slashed, for filtering.
     * @param {(String)} path full path
     * @returns {(String)}
     */
    static _RelPath(path) {
        prefix := Paths.FromRoot("tests\")
        if (SubStr(path, 1, StrLen(prefix)) = prefix)
            path := SubStr(path, StrLen(prefix) + 1)
        return StrReplace(path, "\", "/")
    }

    /**
     * @description Does any filter term hit this suite? Deliberately vague: a term is a
     * case-insensitive substring test against both the relative case-file path (so dir names,
     * file names and partials all work: "geometry", "cases/nav", "cases/") and the suite name
     * (so "s14" reaches a single scenario).
     * @param {(Object)} suite registry entry
     * @param {(Array)} terms filter terms; empty means "everything"
     * @returns {(Boolean)}
     */
    static _Matches(suite, terms) {
        if (!terms.Length)
            return true
        rel := Test._RelPath(suite.file)
        for term in terms {
            needle := StrReplace(term, "\", "/")
            if (InStr(rel, needle) || InStr(suite.name, needle))
                return true
        }
        return false
    }

    /**
     * @description Filter, run, report, exit. Exit code = fail count (0 = green), or 1 when the
     * filter matched nothing - a typo must not read as a clean run.
     * @param {(Array)} args usually A_Args; no args = run everything
     */
    static Run(args) {
        terms := []
        for a in args {
            if (a != "")
                terms.Push(a)
        }

        Report("=== tests start ===")
        if (terms.Length)
            Report("FILTER: " Join(terms, " "))
        WarnIfMainRunning()

        selected := []
        for suite in Test._suites {
            if (Test._Matches(suite, terms))
                selected.Push(suite)
        }

        skipped := Test._suites.Length - selected.Length
        if (!selected.Length) {
            Report("ERROR: no suites matched the filter (" Test._suites.Length " registered)")
            ExitApp(1)
        }
        Report("RUNNING: " selected.Length " suite(s)" (skipped ? ", " skipped " filtered out" : ""))
        if (terms.Length) {
            for suite in selected
                Report("  - " Test._RelPath(suite.file) " :: " suite.name)
        }

        for suite in selected {
            try {
                suite.fn.Call()
            } catch as e {
                Fail(suite.name " threw: " e.Message " @ " e.File ":" e.Line)
            }
        }

        Report("=== tests done: " Test._pass " passed, " Test._fail " failed"
            . (skipped ? " (" skipped " suite(s) filtered out)" : "") " ===")
        ExitApp(Test._fail)
    }
}


;; === Reporting + asserts ===

Report(msg) {
    OutputDebug(msg "`n")
    try FileAppend(msg "`n", "*")
}

Join(items, sep) {
    out := ""
    for item in items
        out .= (A_Index > 1 ? sep : "") item
    return out
}

Ok(label) {
    Test._pass += 1
    Report("PASS: " label)
}

Fail(label) {
    Test._fail += 1
    Report("FAIL: " label)
}

AssertTrue(label, cond) {
    cond ? Ok(label) : Fail(label)
}

AssertEq(label, actual, expected) {
    if (actual == expected)
        Ok(label)
    else
        Fail(label " | expected=" TargetStr(expected) " actual=" TargetStr(actual))
}

AssertNeq(label, actual, notExpected) {
    if (actual != notExpected)
        Ok(label)
    else
        Fail(label " | got the forbidden target " TargetStr(notExpected))
}

TargetStr(t) {
    if (t is Array)
        return RectStr(t)
    try return DebugDescribeTarget(t)
    return String(t)
}

RectStr(r) {
    return "[" r[1] ", " r[2] ", " r[3] ", " r[4] "]"
}

RectsEq(r1, r2) {
    return r1[1] == r2[1] && r1[2] == r2[2] && r1[3] == r2[3] && r1[4] == r2[4]
}

SumAreas(rects) {
    total := 0
    for r in rects
        total += Geometry.GetArea(r)
    return total
}

; Run a block, turn throws into FAILs instead of aborting the whole script. Test.Run already
; guards each suite; this is for sub-grouping inside one.
Guard(label, fn) {
    try {
        fn()
    } catch as e {
        Fail(label " threw: " e.Message " @ " e.File ":" e.Line)
    }
}

Qpc() {
    static freq := 0
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &count := 0)
    return count / freq * 1000.0  ; ms
}


;; === Dummy window utilities ===

class ClsTestWin {
    __New(x, y, w, h, title) {
        this.gui := Gui("-DPIScale", title)
        this.gui.Show("x" x " y" y " w" w " h" h " NA")
        this.hwnd := this.gui.Hwnd
    }

    Rect() {
        WinCalls.WinGetPosEx(this.hwnd, &l, &t, , , &r, &b)
        return Geometry.Rect(l, t, r, b)
    }
}

DestroyWins(wins) {
    for w in wins {
        try w.gui.Destroy()
    }
    Sleep(80)
}

FocusWin(hwnd) {
    WinActivate(hwnd)
    if (!WinWaitActive(hwnd, , 1))
        throw Error("Could not activate test window " hwnd)
    Sleep(80)  ; let DWM/foreground settle
}

; Substring match under SetTitleMatchMode(2): an AHK script's window title is its full script
; path, and matching "\src\Main.ahk" dodges drive-letter case while never hitting tests\Main.ahk.
WarnIfMainRunning() {
    prevMatch := A_TitleMatchMode
    prevHidden := A_DetectHiddenWindows
    SetTitleMatchMode(2)
    DetectHiddenWindows(1)
    try {
        if (WinExist("\src\Main.ahk ahk_class AutoHotkey"))
            Report("WARNING: Main.ahk is running - its mouse-follow quirk may interfere with scenarios")
    } finally {
        SetTitleMatchMode(prevMatch)
        DetectHiddenWindows(prevHidden)
    }
}
