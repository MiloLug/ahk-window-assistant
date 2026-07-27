#Requires AutoHotkey v2.0

/**
 * @description Configuration constants/defaults
 * Centralizes all constants for easier tuning and maintenance
 */
class Config {
    /**
     * Consider desktop change as mouse move
     * If true, the system will consider desktop change WITH mouse position restoration as mouse move
     * TODO: explain why this is important
     */
    static CONSIDER_DESKTOP_CHANGE_AS_MOVE := true

    /**
     * Mouse movement detection timeout in milliseconds
     * Used to determine if the user recently moved mouse manually
     */
    static MOUSE_MOVE_TIMEOUT := 500
    
    /**
     * Navigation sequence timeout in milliseconds
     * How long to wait before finalizing Alt-Tab-like navigation
     */
    static NAVIGATION_DELAY := 250
    
    /**
     * Approximate window header/title bar size in pixels
     * Used for drag detection heuristics
     * Note: This is approximate and may vary with Windows theme/DPI/individual applications
     */
    static WINDOW_HEADER_SIZE := 25
    
    /**
     * Intersection threshold for spatial navigation (0.0 - 1.0)
     * Higher = stricter overlap requirement for considering windows as "overlapping"
     */
    static NAVIGATION_INTERSECTION_THRESHOLD := 0.1

    /**
     * Consider monitors as being on the same level (same row, y)
     * withing this threshold in pixels, while sorting them 'naturally'
     */
    static MONITOR_SAME_LEVEL_THRESHOLD := 400

    /**
     * Delay in ms between a monitor-change hint (WM_DISPLAYCHANGE / work-area
     * WM_SETTINGCHANGE) and re-reading the monitor list. Mode switches emit hints
     * in bursts while displays settle down
     */
    static MONITOR_SETTLE_DELAY := 400

    /**
     * Poll interval in ms for monitor layout. Broadcasts can be missed
     * sometimes, so better leave this be
     */
    static MONITOR_POLL_INTERVAL := 10000

    /**
     * Delay in ms between a foreground-change hint (WinEvent/shell hook) and reading
     * GetForegroundWindow. Hooks fire mid-transition: the hwnd may be 0, cloaked or
     * transient, so wait for the OS to settle before reading the state
     */
    static FOREGROUND_SETTLE_DELAY := 50

    /**
     * Poll interval in ms for foreground changes. The hooks sometimes miss transitions.
     * This value is the worst-case detection latency
     */
    static FOREGROUND_POLL_INTERVAL := 250

    /**
     * Window in ms during which a foreground change to an Expect()-ed hwnd is committed
     * without an event
     */
    static FOREGROUND_EXPECT_TIMEOUT := 500
}

