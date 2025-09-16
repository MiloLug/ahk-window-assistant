#Requires AutoHotkey v2.0

ArrConcat(arr1, arr2) {
    ret := arr1.Clone()
    for item in arr2 {
        ret.Push(item)
    }
    return ret
}

Iter(iterable, mode:=1) {
    return HasMethod(iterable, "__Enum") ? iterable.__Enum(mode) : iterable
}

IterMap(iterable, func) {
    it := Iter(iterable)
    return (&item) => (
        res := it(&item), res and (item := func(res)),
        res
    )
}

ArrFlatMap(iterable, func) {
    ret := []

    for item in iterable {
        ret.Push(func(item)*)
    }
    return ret
}

IterJoin(iterable, separator) {
    it := Iter(iterable)
    if (!it(&item))
        return ""

    ret := "" item
    for item in it {
        ret .= separator item
    }
    return ret
}

IterKeys(iterable) {
    it := Iter(iterable, 2)
    return (&key) => it(&key)
}


/**
 * @description A class to filter windows by titles (class|exe|id)
 * @param {(String|Integer)[]} windowTitles - `"*" | "<prefix> <key>" | Integer`
 *   - `"*"`: match all windows
 *   - `"ahk_exe <exe>"`
 *   - `"ahk_class <class>"`
 *   - `"ahk_id <id>" | (Integer)`: Integer is recommended
 *   - `"!<prefix> <key>"`: exclude windows with the given prefix and key
 * @example Some filters
 *   - TitleFilter(["*"]): match all windows
 *   - TitleFilter(["ahk_exe explorer.exe"]): match all windows of explorer.exe
 *   - TitleFilter(["*", "!ahk_exe explorer.exe"]): match all windows except explorer.exe
 */
class TitleFilter {
    static allowedPrefixes := ["ahk_exe", "ahk_class", "ahk_id"]
    static _allPrefixes := Map(ArrFlatMap(TitleFilter.allowedPrefixes, (prefix) => [prefix, 1, "!" prefix, 1])*)

    __New(windowTitles) {
        ; { prefix: { title: true } }
        this._titlesMap := Map()
        this._matchAll := false
        this._hasExclusions := false

        this._CreateWindowTitlesMap(windowTitles)
    }

    _SanitizeMap() {
        for prefix, titles in this._titlesMap {
            negated := SubStr(prefix, 1, 1) == "!"
            if (this._matchAll and not negated) {
                titles.Clear()
            }
            opposite := negated ? prefix : "!" prefix

            toDelete := []
            for title in titles {
                if (not negated and this._titlesMap[opposite].Has(title)) {
                    toDelete.Push(title)
                }
            }
            for title in toDelete {
                titles.Delete(title)
            }
        }
    }

    DebugString() {
        ret := this._matchAll ? "*`n" : ""
        for prefix, titles in this._titlesMap {
            if (titles.Count == 0)
                continue
            ret .= prefix " " IterJoin(IterKeys(titles), "`n" prefix " ") "`n"
        }
        return ret
    }

    _CreateWindowTitlesMap(windowTitles) {
        if (windowTitles.Length == 0) {
            return
        }

        for prefix in TitleFilter._allPrefixes {
            this._titlesMap[prefix] := Map()
        }

        for title in windowTitles {
            if (title == "*") {
                this._matchAll := true
                continue
            }

            if (title is Number) {
                this._titlesMap["ahk_id"][title] := true
                continue
            }

            parsed := StrSplit(title, " ", " ", 2)
            if (parsed.Length == 2) {
                if (!TitleFilter._allPrefixes.Has(parsed[1])) {
                    throw ValueError("Invalid prefix: '" parsed[1] "'")
                }

                ; if the prefix is ahk_id or !ahk_id, just use hwnd
                if (parsed[1] == "ahk_id" or parsed[1] == "!ahk_id") {
                    parsed[2] := Number(parsed[2])
                }

                if (SubStr(parsed[1], 1, 1) == "!")
                    this._hasExclusions := true

                this._titlesMap[parsed[1]][parsed[2]] := true
            }
        }

        this._SanitizeMap()
    }

    /**
     * @description Test if a window is in the titles map
     * @param {(Integer)} hwnd - the window handle
     */
    TestWindow(hwnd) {
        try {
            if this._hasExclusions and (
                this._titlesMap["!ahk_exe"].Has(winExe := WinGetProcessName(hwnd))
                or this._titlesMap["!ahk_class"].Has(winClass := WinGetClass(hwnd))
                or this._titlesMap["!ahk_id"].Has(hwnd)
            ) {
                return false
            }
        } catch {
            return false
        }

        if (this._matchAll) {
            return true
        }
        return (
            this._titlesMap["ahk_exe"].Has(winExe)
            or this._titlesMap["ahk_class"].Has(winClass)
            or this._titlesMap["ahk_id"].Has(hwnd)
        )
    }

    /**
     * @description Merge two filters
     * @param {(TitleFilter)} other - the other filter
     * @param {(Boolean)} removeWildcard - if true, the wildcard (*) will be removed from the merged filter
     * @returns {(TitleFilter)} - the merged NEW filter
     */
    Merge(other, removeWildcard:=false) {
        newFilter := TitleFilter([])
        for prefix, titles in this._titlesMap {
            newFilter._titlesMap[prefix] := titles.Clone()
        }
        for prefix, titles in other._titlesMap {
            for title in titles {
                newFilter._titlesMap[prefix][title] := true
            }
        }
        newFilter._matchAll := not removeWildcard and (this._matchAll or other._matchAll)
        newFilter._hasExclusions := this._hasExclusions or other._hasExclusions
        newFilter._SanitizeMap()
        return newFilter
    }
}

ChangeWindowMessageFilterEx(hwnd, message, action) {
    return DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", message, "UInt", action, "Ptr", 0, "Int")
}

DescribeWindow(hwnd) {
    return WinGetTitle(hwnd) " (" hwnd "), class: " WinGetClass(hwnd) ", PID: " WinGetPID(hwnd)
}

/**
 * @description A class to handle sequential key/shortcut activations
 * It works like an abstract alt-tab, giving the number of current activation and some special case
 * for single activation (for example, -1)
 * 
 * @param {(Number)} period - the period in milliseconds to reset the counter
 * @param {(Function)} specialCase - the value to return when pressed only once
 */
class SequenceIntervalHandler {
    __New(period:=500) {
        this._period := period
        this._counter := 0
        this._lastActivationTime := 0
    }

    Next() {
        dT := A_TickCount - this._lastActivationTime
        this._lastActivationTime := A_TickCount
        if (dT > this._period) {
            this._counter := 0
        }
        return ++this._counter
    }
}