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

    /**
     * Below this share of visible area a window (or monitor desktop) is treated as hidden
     * for spatial navigation
     */
    static NAV_MIN_VISIBLE_FRACTION := 0.05

    /**
     * Visible fragments thinner than this (px, either axis) are culled during subtraction:
     * unusable parts must not attract directional focus. A window peeking 10px out from
     * behind another is not a target, so the movement skips it for whatever is next
     */
    static NAV_MIN_FRAGMENT_DIM := 16

    /**
     * A window is still a nav target regardless of visible fraction if its largest visible
     * fragment is at least this wide and tall (px): a 200px strip of a huge maximized window
     * is only ~4% visible yet usable
     */
    static NAV_MIN_ELIGIBLE_DIM := 48

    /**
     * Perpendicular-offset weight when the candidate fragment shares the source's row/column
     * (in-beam): mostly a gentle tiebreak, travel-axis distance dominates. A neighbor 20px
     * left but 125px off-center scores 20 + 0.15*125 = 38.75 and beats one 500px left and
     * perfectly centered (500) - raising this to 4.0 would change that selection
     */
    static NAV_MINOR_WEIGHT_INBEAM := 0.15

    /**
     * Perpendicular-offset weight for out-of-beam (diagonal) candidates: strong enough to
     * prefer roughly-aligned targets, weak enough to keep diagonals reachable. With nothing
     * in the beam, a target 200px away but only 182px off-axis (200 + 2*182 = 565) beats a
     * closer one 100px away and 310px off (720)
     */
    static NAV_MINOR_WEIGHT_OFFBEAM := 2.0

    /**
     * Scores within this many px count as a near-tie and are resolved by focus recency (MRU)
     * instead of raw geometry - this is what makes overlapping stacks feel predictable
     */
    static NAV_TIE_EPSILON := 40

    /**
     * A monitor's free-desktop fragment must be at least this wide and tall (px) to be a
     * target - thin desktop slivers between windows are not meaningful destinations
     */
    static NAV_MONITOR_MIN_FRAGMENT_DIM := 200

    /**
     * Moves remembered for opposite-direction walk back (left,left then right,right returns along
     * the same path). Small on purpose: older entries are usually stale anyway.
     * Also bounds the layer-movement (z axis) visit chain
     */
    static NAV_CAMEFROM_DEPTH := 8

    /**
     * Spatial-nav MRU map size that triggers a dead-hwnd sweep; bounds memory without a timer
     */
    static NAV_MRU_MAX_SIZE := 64

    /**
     * Working-set bound for visibility fragments per window; bounds worst-case cascades
     */
    static NAV_MAX_FRAGMENTS := 16
}

