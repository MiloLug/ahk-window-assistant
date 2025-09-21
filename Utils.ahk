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

ArrReversedIter(arr) {
    i := arr.Length
    return (&val) => (
        i > 0 ? (val := arr[i--], true): false
    )
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


DebugDescribeWindow(hwnd) {
    return WinGetTitle(hwnd) " (" hwnd "), class: " WinGetClass(hwnd) ", PID: " WinGetPID(hwnd)
}

class WinCalls {
    static ChangeWindowMessageFilterEx(hwnd, message, action) {
        return DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", message, "UInt", action, "Ptr", 0, "Int")
    }

    static SendWmSize(windowHwnd, width, height) {
        SendMessage(WM_SIZE, 0, (width & 0xFFFF) | ((height & 0xFFFF) << 16), , windowHwnd)
    }

    static SendWmNccalcsize(windowHwnd, left, top, right, bottom) {
        rect := Buffer(16)
        NumPut(
            "Int", left,
            "Int", top,
            "Int", right,
            "Int", bottom,
            rect
        )
        SendMessage(WM_NCCALCSIZE, 0, rect,, windowHwnd)
    }

    static SendWmNchittest(windowHwnd, x, y) {
        return SendMessage(WM_NCHITTEST, 0, (x & 0xFFFF) | ((y & 0xFFFF) << 16),, windowHwnd)
    }

    static WinGetPosEx(windowHwnd, &x:=0, &y:=0, &width:=0, &height:=0, &right:=0, &bottom:=0, getOffset:=false, &offsetX:=0, &offsetY:=0, &offsetRight:=0, &offsetBottom:=0) {
        rect := Buffer(16,0)
        try {
            DllCall(
                "dwmapi\DwmGetWindowAttribute",
                "Ptr",  windowHwnd,                  ; hwnd
                "UInt", DWMWA_EXTENDED_FRAME_BOUNDS, ; dwAttribute
                "Ptr",  rect,                        ; pvAttribute
                "UInt", 16,                          ; cbAttribute
                "UInt"
            )
        } catch {
            return false
        }
        ; Populate the output variables
        x := NumGet(rect,  0, "Int")
        y := NumGet(rect,  4, "Int")
        right := NumGet(rect,  8, "Int")
        bottom := NumGet(rect, 12, "Int")
        width := (right - x)
        height := (bottom - y)

        if (getOffset) {
            gwrRect := Buffer(16, 0)
            DllCall("GetWindowRect", "Ptr", windowHwnd,"Ptr", gwrRect)

            ; Calculate offsets and update output variables
            offsetX := x - NumGet(gwrRect,0,"Int")
            offsetY := y - NumGet(gwrRect,4,"Int")
            offsetRight := NumGet(gwrRect,8,"Int") - right
            offsetBottom := NumGet(gwrRect,12,"Int") - bottom
        }
    }
}