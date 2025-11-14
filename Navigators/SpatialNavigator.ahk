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
    __New(ctx, listSelector:='', currentSelector:='A', intersectionThreshold:=Config.NAVIGATION_INTERSECTION_THRESHOLD) {
        this._ctx := ctx
        this._listSelector := listSelector
        this._currentSelector := currentSelector
        this._intersectionThreshold := intersectionThreshold
    }

    _GetCurrent() {
        try {
            hwnd := this._ctx.windowManager.GetID(this._currentSelector,,, false)
            if (hwnd)
                return hwnd
        }
        return -this._ctx.monitorManager.GetFocused()
    }

    _GetCoords(hwnd) {
        if (hwnd < 0) {
            return this._ctx.monitorManager.GetByIndex(-hwnd).rect
        } else {
            WinCalls.WinGetPosEx(hwnd, &l, &t,,, &r, &b)
            return Geometry.Rect(l, t, r, b)
        }
    }

    _GetTargets() {
        winList := this._ctx.windowManager.GetList(this._listSelector,,, false)
        for mon in this._ctx.monitorManager.GetAll() {
            winList.Push(-mon.index)
        }
        return winList
    }

    /**
     * @description Traverse to the nearest topmost window by going upwards through overlapping windows
     * @param {(Array)} distList - array of [distance-from-point, windowHwnd, windowRect, zIndex (0 = top)]
     */
    _TraverseToNearestTopmost(distList) {
        ArrSort(distList, (a, b) => a[1] - b[1]) ; Sort by distance asc

        closest := distList[1]
        closestArea := Geometry.GetArea(closest[3])
        closestZ := closest[4]
        closestDistance := closest[1]

        prevChecking := 0

        for i, checking in distList {
            checkingZ := checking[4]

            ; Here we need all intersecting windows ABOVE the closest
            if (
                checkingZ < closestZ
                and (interArea := Geometry.GetIntersectionArea(closest[3], checking[3])) > 0
                and Sqrt(interArea) / Sqrt(Geometry.GetArea(checking[3]) + closestArea) > this._intersectionThreshold
            ) {
                ; Then if we have some window that is above that closest,
                ; and it isn't being overlapped by something even higher...
                ; Then we can return it, since it should be the closest one while also being on top of all other windows.
                ; Since even if there is something higher but further away, it isn't the target we want
                if (prevChecking != 0) {
                    if (checkingZ < prevChecking[4]) {
                        if (Geometry.DoRectanglesIntersect(prevChecking[3], checking[3])) {
                            prevChecking := checking
                        } else {
                            return prevChecking[2]
                        }
                    }
                } else {
                    prevChecking := checking
                }
            }
        }

        if (prevChecking != 0) {
            return prevChecking[2]
        }
        return closest[2]
    }

    _IsVisible(winRects, checkingZ, checkingRect) {
        checkingArea := Geometry.GetArea(checkingRect)
        for z, winRect in winRects {
            if (z >= checkingZ)
                break

            interArea := Geometry.GetIntersectionArea(checkingRect, winRect)
            if (
                interArea > 0
                and Sqrt(interArea) / Sqrt(checkingArea + Geometry.GetArea(winRect)) > this._intersectionThreshold
            )
                return false
        }
        return true
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
        curHwnd := this._GetCurrent()
        OutputDebug("Current: " DebugDescribeTarget(curHwnd))
        if (curHwnd == 0) {
            return curHwnd
        }
        curRect := this._GetCoords(curHwnd)

        winList := this._GetTargets()
        if (winList.Length == 0)
            return 0

        distances := []
        winRects := []

        switch side {
            case 0:
                for z, winHwnd in winList {
                    checkRect := this._GetCoords(winHwnd)
                    winRects.Push(checkRect)
                    if (checkRect[3] <= curRect[1] and this._IsVisible(winRects, z, checkRect))
                        distances.Push([
                            Geometry.CalcIntersectionDistance(curRect, 1, checkRect),
                            winHwnd,
                            checkRect,
                            z
                        ])
                }
            case 1:
                for z, winHwnd in winList {
                    checkRect := this._GetCoords(winHwnd)
                    winRects.Push(checkRect)
                    if (checkRect[1] >= curRect[3] and this._IsVisible(winRects, z, checkRect))
                        distances.Push([
                            Geometry.CalcIntersectionDistance(curRect, 1, checkRect),
                            winHwnd,
                            checkRect,
                            z
                        ])
                }
            case 2:
                for z, winHwnd in winList {
                    checkRect := this._GetCoords(winHwnd)
                    winRects.Push(checkRect)
                    if (checkRect[4] <= curRect[2] and this._IsVisible(winRects, z, checkRect))
                        distances.Push([
                            Geometry.CalcIntersectionDistance(curRect, 0, checkRect),
                            winHwnd,
                            checkRect,
                            z
                        ])
                }
            case 3:
                for z, winHwnd in winList {
                    checkRect := this._GetCoords(winHwnd)
                    winRects.Push(checkRect)
                    if (checkRect[2] >= curRect[4] and this._IsVisible(winRects, z, checkRect))
                        distances.Push([
                            Geometry.CalcIntersectionDistance(curRect, 0, checkRect),
                            winHwnd,
                            checkRect,
                            z
                        ])
                }
        }

        if (distances.Length == 0)
            return 0

        return this._TraverseToNearestTopmost(distances)
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
            curHwnd := this._ctx.windowManager.GetID(this._currentSelector)
        } catch {
            return 0
        }
        curRect := this._GetCoords(curHwnd)

        winList := this._ctx.windowManager.GetList(this._listSelector)
        if (winList.Length == 0)
            return 0

        for winHwnd in ArrReversedIter(winList) {
            checkRect := this._GetCoords(winHwnd)
            if (
                winHwnd != curHwnd
                and Geometry.DoRectanglesIntersect(curRect, checkRect)
            ) {
                return winHwnd
            }
        }
        return 0
    }
}