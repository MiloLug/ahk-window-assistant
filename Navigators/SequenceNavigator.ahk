#Requires AutoHotkey v2.0

#include ../Config.ahk
#include ../Utils.ahk


class ClsBaseSequenceTimedNavigator {
    __New() {
        this._hwnds := []
        this._hwndsMap := Map()

        this._EndNavigation_Bind := this._EndNavigation.Bind(this)
        this._currentN := 1
        this._activateOnFinish := true

        ObjRelease(ObjPtr(this))
    }

    __Delete() {
        ObjAddRef(ObjPtr(this))
        SetTimer(this._EndNavigation_Bind, 0)
        this._EndNavigation_Bind := 0
        this._ctx := 0
    }

    /**
     * @description Update the current window
     * Should be called before updating the list for optimal performance
     */
    _UpdateCurrentHwnd(currentHwnd) {
        if (this._hwndsMap.Has(currentHwnd)) {
            ; Since it's already in the list, we can just move it to the front
            if (this._hwnds[1] != currentHwnd) {
                for i, hwnd in this._hwnds {
                    if (hwnd == currentHwnd) {
                        this._hwnds.RemoveAt(i)
                        this._hwnds.InsertAt(1, hwnd)
                        break
                    }
                }
            }
        } else {
            this._hwnds.InsertAt(1, currentHwnd)
            this._hwndsMap[currentHwnd] := true
        }
    }

    /**
     * @description Update the list of hwnds
     * Updates the list in a natural way, so the order of the hwnds is preserved as much as possible.
     */
    _ApplyExternalHwnds(externalHwnds) {
        newMap := Map()
        if (externalHwnds.Length == 0) {
            this._hwnds := []
            this._hwndsMap.Clear()
            return
        }
        ; if we have at least one window, consider it 'current' and don't move it around
        ; this way, if it's 0, we'll insert new hwnds at the beginning, otherwise at index = 2
        hasCurrent := this._hwnds.Length > 0

        ; Add new hwnds
        toAdd := []
        for windowHwnd in externalHwnds {
            newMap[windowHwnd] := true
            if (!this._hwndsMap.Has(windowHwnd)) {
                toAdd.Push(windowHwnd)
            }
        }
        if (toAdd.Length > 0) {
            ; 1st being the current window, so we will navigate to
            ; the new hwnds next
            this._hwnds.InsertAt(1 + hasCurrent, toAdd*)
        }

        ; Remove old hwnds
        i := this._hwnds.Length
        ; skip since we already know new hwnds exist
        lastNewI := toAdd.Length + hasCurrent
        while (i > lastNewI) {
            if (!newMap.Has(this._hwnds[i])) {
                this._hwnds.RemoveAt(i)
            }
            i--
        }
        this._hwndsMap := newMap
    }

    _GetSelected() {
        if (this._hwnds.Length == 0)
            return 0
        return this._hwnds[Mod(this._currentN - 1, this._hwnds.Length) + 1]
    }

    /**
     * @description Override this to update the hwnds list state with your values.
     * For example:
     * 
     *     self._UpdateCurrentHwnd(windowManager.GetID('A'))
     *     self._ApplyExternalHwnds(windowManager.GetList())
     * 
     */
    _UpdateHwnds() {
    }

    /**
     * @description Navigate to the next window
     * @param {(Boolean)} instant - if true, the window will be activated immediately
     */
    Next(instant:=true) {
        SetTimer(this._EndNavigation_Bind, 0)
        if (this._currentN == 1) {
            this._UpdateHwnds()
            if (this._hwnds.Length == 0) {
                return
            }
        }
        this._currentN++
        this._activateOnFinish := !instant
        if (instant) {
            selectedHwnd := this._GetSelected()
            if (selectedHwnd != 0)
                WinActivate(selectedHwnd)
        }
        SetTimer(this._EndNavigation_Bind, Config.NAVIGATION_DELAY)
    }

    /**
     * @description Called after we stop navigating, to reset the state
     */
    _EndNavigation() {
        if (this._activateOnFinish) {
            selectedHwnd := this._GetSelected()
            if (selectedHwnd != 0)
                WinActivate(selectedHwnd)
        }
        this._currentN := 1
    }
}


/**
 * @description A class to navigate through a collection of hwnds with Alt-Tab-like behavior
 * @param {(WindowManager)} windowManager - the window manager to use
 * @param {(String)} listSelector - the selector to use to get the list of hwnds
 * @param {(String)} currentSelector - the selector to use to get the current window
 */
class ClsSequenceWindowNavigator extends ClsBaseSequenceTimedNavigator {
    __New(ctx, listSelector:='', currentSelector:='A') {
        super.__New()
        this._ctx := ctx
        this._listSelector := listSelector
        this._currentSelector := currentSelector
    }

    _UpdateHwnds() {
        this._UpdateCurrentHwnd(WinGetID(this._currentSelector))
        this._ApplyExternalHwnds(this._ctx.windowManager.GetList(this._listSelector, true))
    }
}
