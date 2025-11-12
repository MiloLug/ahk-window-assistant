#Requires AutoHotkey v2.0

#include ../Config.ahk
#include ../Utils.ahk


/**
 * @description A class to navigate through a collection of windows with Alt-Tab-like behavior
 * @param {(WindowManager)} windowManager - the window manager to use
 * @param {(String)} listSelector - the selector to use to get the list of windows
 * @param {(String)} currentSelector - the selector to use to get the current window
 */
class ClsSequenceWindowNavigator {
    __New(ctx, listSelector:='', currentSelector:='A') {
        this._ctx := ctx
        this._windows := []
        this._windowsMap := Map()
        this._listSelector := listSelector
        this._currentSelector := currentSelector

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
    _UpdateCurrentWindow() {
        currentHwnd := WinGetID(this._currentSelector)
        if (this._windowsMap.Has(currentHwnd)) {
            ; Since it's already in the list, we can just move it to the front
            if (this._windows[1] != currentHwnd) {
                for i, hwnd in this._windows {
                    if (hwnd == currentHwnd) {
                        this._windows.RemoveAt(i)
                        this._windows.InsertAt(1, hwnd)
                        break
                    }
                }
            }
        } else {
            this._windows.InsertAt(1, currentHwnd)
            this._windowsMap[currentHwnd] := true
        }
    }

    /**
     * @description Update the list of windows
     * Updates the list in a natural way, so the order of the windows is preserved as much as possible.
     */
    _UpdateWindowsList() {
        newMap := Map()
        newWindows := this._ctx.windowManager.GetList(this._listSelector, true)
        if (newWindows.Length == 0) {
            this._windows := []
            this._windowsMap.Clear()
            return
        }
        ; if we have at least one window, consider it 'current' and don't move it around
        ; this way, if it's 0, we'll insert new windows at the beginning, otherwise at index = 2
        hasCurrent := this._windows.Length > 0

        ; Add new windows
        toAdd := []
        for windowHwnd in newWindows {
            newMap[windowHwnd] := true
            if (!this._windowsMap.Has(windowHwnd)) {
                toAdd.Push(windowHwnd)
            }
        }
        if (toAdd.Length > 0) {
            ; 1st being the current window, so we will navigate to
            ; the new windows next
            this._windows.InsertAt(1 + hasCurrent, toAdd*)
        }

        ; Remove old windows
        i := this._windows.Length
        ; skip since we already know new windows exist
        lastNewI := toAdd.Length + hasCurrent
        while (i > lastNewI) {
            if (!newMap.Has(this._windows[i])) {
                this._windows.RemoveAt(i)
            }
            i--
        }
        this._windowsMap := newMap
    }

    _GetSelected() {
        if (this._windows.Length == 0)
            return 0
        return this._windows[Mod(this._currentN - 1, this._windows.Length) + 1]
    }

    /**
     * @description Navigate to the next window
     * @param {(Boolean)} instant - if true, the window will be activated immediately
     */
    Next(instant:=true) {
        SetTimer(this._EndNavigation_Bind, 0)
        if (this._currentN == 1) {
            this._UpdateCurrentWindow()
            this._UpdateWindowsList()

            if (this._windows.Length == 0) {
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