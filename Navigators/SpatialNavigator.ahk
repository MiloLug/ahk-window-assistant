#Requires AutoHotkey v2.0

#include ../Config.ahk
#include ../Utils.ahk
#include ../Geometry.ahk


/**
 * @description A class to navigate through a collection of windows with spatial behavior
 * @param {(WindowManager)} windowManager - the window manager to use
 * @param {(String)} listSelector - the selector to use to get the list of windows
 * @param {(String)} currentSelector - the selector to use to get the current window
 * @param {(Float)} intersectionThreshold - the threshold for considering a window as intersecting with the current window. The check is:
 * 
 *         Sqrt(intersectionArea) / Sqrt(window1Area + window2Area) > intersectionThreshold
 */
class ClsSpatialWindowNavigator {
    __New(windowManager, listSelector:='', currentSelector:='A', intersectionThreshold:=Config.NAVIGATION_INTERSECTION_THRESHOLD) {
        this._windowManager := windowManager
        this._listSelector := listSelector
        this._currentSelector := currentSelector
        this._currentHwnd := 0
        this._intersectionThreshold := intersectionThreshold
    }

    _CalcLogicalDistance(x1, y1, x2, y2, xCost:=1, yCost:=1) {
        dX := (x1 - x2) * xCost
        dY := (y1 - y2) * yCost
        return Sqrt(dX * dX + dY * dY)
    }

    _GetCoords(hwnd, &w, &h, &l, &r, &t, &b) {
        WinCalls.WinGetPosEx(hwnd, &l, &t, &w, &h, &r, &b)
    }

    /**
     * @description Traverse to the nearest topmost window by going upwards through overlapping windows
     * @param {(Array)} distList - array of [distance-from-point, windowHwnd, left, right, top, bottom, width, height]
     * @param {(Integer)} currentIndex - the index of the current window in the list
     */
    _TraverseToNearestTopmost(distList, currentIndex) {
        current := distList[currentIndex]
        currentArea := current[7] * current[8]

        nearestDistance := 0xFFFFFFFF
        nearestIndex := currentIndex

        i := currentIndex - 1
        while (i > 0) {
            checking := distList[i]
            interArea := Geometry.GetIntersectionArea(
                current[3], current[5], current[4], current[6],
                checking[3], checking[5], checking[4], checking[6]
            )
            checkingArea := checking[7] * checking[8]
            if (
                interArea > 0
                and Sqrt(interArea) / Sqrt(checkingArea + currentArea) > this._intersectionThreshold
                and checking[1] < nearestDistance
            ) {
                nearestDistance := checking[1]
                nearestIndex := i
            }
            i--
        }

        ; If it's still the same window or the first one, then there are no more overlapping windows
        if (nearestIndex == currentIndex || nearestIndex == 1) {
            return distList[nearestIndex][2]
        }

        ; We can go to the next overlapping window
        if (nearestIndex > 0) {
            return this._TraverseToNearestTopmost(distList, nearestIndex)
        }

        return 0
    }

    /**
     * @description Find the closest window in the list
     * @param {(Array)} distList - array of [distance-from-point, windowHwnd, left, right, top, bottom, width, height]
     */
    _TraverseToNearest(distList) {
        nearestDistance := 0xFFFFFFFF
        nearestIndex := 0

        for i, checking in distList {
            ; We search for the smallest distance, and overlapping windows have negative distance,
            ; so the more they overlap, the smaller (bigger negative) the distance.
            ; And then not overlapping windows will be the next closest candidates
            if (checking[1] < nearestDistance) {
                nearestDistance := checking[1]
                nearestIndex := i
            }
        }

        if (nearestIndex > 1) {
            ; Most likely, we want to move to the nearest AND topmost window.
            ; So we need to go through the list of windows on top of the current closest
            return this._TraverseToNearestTopmost(distList, nearestIndex)
        }

        if (nearestIndex == 1) {
            return distList[1][2]
        }

        return 0
    }

    /**
     * @description Get the closest window from a side
     * @param {(Integer)} side - the side to get the closest window from
     *   - `0` - left
     *   - `1` - right
     *   - `2` - top
     *   - `3` - bottom
     */
    _GetFromSide(side) {
        try {
            curHwnd := this._windowManager.GetID(this._currentSelector)
        } catch {
            return 0
        }
        this._GetCoords(curHwnd, &w, &h, &l, &r, &t, &b)

        winList := this._windowManager.GetList(this._listSelector)
        if (winList.Length == 0)
            return 0

        distances := []

        ; I know, this is ugly, but it's faster than assigning a filter function to each side
        switch side {
            case 0:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wR <= l)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 0, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 1:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wL >= r)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 0, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 2:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wB <= t)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 1, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
            case 3:
                for winHwnd in winList {
                    this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
                    if (wT >= b)
                        distances.Push([
                            Geometry.CalcIntersectionDistance(l, t, r, b, 1, wL, wT, wR, wB),
                            winHwnd,
                            wL, wR, wT, wB, wW, wH
                        ])
                }
        }

        if (distances.Length == 0)
            return 0

        return this._TraverseToNearest(distances)
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

    /**
     * @description Find the next overlapping window in Z-order
     */
    NextOverlapping() {
        try {
            curHwnd := this._windowManager.GetID(this._currentSelector)
        } catch {
            return 0
        }
        this._GetCoords(curHwnd, &w, &h, &l, &r, &t, &b)

        winList := this._windowManager.GetList(this._listSelector)
        if (winList.Length == 0)
            return 0

        for winHwnd in ArrReversedIter(winList) {
            this._GetCoords(winHwnd, &wW, &wH, &wL, &wR, &wT, &wB)
            if (
                winHwnd != curHwnd
                and wL <= r and wR >= l and wT <= b and wB >= t
                ; to avoid overlapping with neighboring windows
                and wL != r and wT != b and wR != l and wB != t
            ) {
                OutputDebug("Overlapping window: " winHwnd)
                return winHwnd
            }
        }
        return 0
    }
}