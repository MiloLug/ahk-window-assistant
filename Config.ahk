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
     * Used to determine if user recently moved mouse manually
     */
    static MOUSE_MOVE_TIMEOUT := 500
    
    /**
     * Navigation sequence timeout in milliseconds
     * How long to wait before finalizing Alt-Tab-like navigation
     */
    static NAVIGATION_DELAY := 500
    
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
}

