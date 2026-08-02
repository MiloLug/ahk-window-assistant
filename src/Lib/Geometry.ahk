#Requires AutoHotkey v2.0

#include ../Config.ahk


class Geometry {
    /**
     * @description Intersection of two rectangles (touching edges don't count)
     * @param {(Array)} r1 - Rect
     * @param {(Array)} r2 - Rect
     * @returns {(Array|Integer)} - the intersection rect, or 0 if they don't overlap
     */
    static RectIntersection(r1, r2) {
        l := Max(r1[1], r2[1])
        t := Max(r1[2], r2[2])
        r := Min(r1[3], r2[3])
        b := Min(r1[4], r2[4])
        return (l < r && t < b) ? [l, t, r, b] : 0
    }

    /**
     * @description Subtract `cut` from `r`: the parts of r not covered by cut
     *
     * Full-width top/bottom bands + left/right middle strips.
     *
     * @param {(Array)} r - Rect
     * @param {(Array)} cut - Rect to subtract
     * @returns {(Array<Array>)} - 0..4 disjoint rects:
     *   - [r] when cut and r in disjoint
     *   - [] when cut covers r completely
     */
    static RectSubtract(r, cut) {
        inter := Geometry.RectIntersection(r, cut)
        if (!inter)
            return [r]
        out := []
        if (inter[2] > r[2])
            out.Push([r[1], r[2], r[3], inter[2]])
        if (inter[4] < r[4])
            out.Push([r[1], inter[4], r[3], r[4]])
        if (inter[1] > r[1])
            out.Push([r[1], inter[2], inter[1], inter[4]])
        if (inter[3] < r[3])
            out.Push([inter[3], inter[2], r[3], inter[4]])
        return out
    }

    /**
     * @description Parts of `rect` not covered by any of `occluders`
     *
     * @param {(Array)} rect - Rect
     * @param {(Array<Array>)} occluders - rects covering `rect`
     * @param {(Integer)} minDim - minimum fragment width/height to keep (smaller fragments are culled)
     * @param {(Integer)} maxFrags - working set limit - will bound to at most maxFrags largest
     *   visible parts per occluder
     * @returns {(Array<Array>)} - disjoint visible fragments (empty when fully covered)
     */
    static VisibleFragments(rect, occluders, minDim := Config.NAV_MIN_FRAGMENT_DIM, maxFrags := Config.NAV_MAX_FRAGMENTS) {
        frags := [rect]
        for cut in occluders {
            if (!Geometry.DoRectanglesIntersect(rect, cut))
                continue
            next := []
            for f in frags {
                for piece in Geometry.RectSubtract(f, cut) {
                    if (piece[3] - piece[1] >= minDim && piece[4] - piece[2] >= minDim)
                        next.Push(piece)
                }
            }
            if (next.Length > maxFrags)
                next := Geometry._LargestN(next, maxFrags)
            frags := next
            if (frags.Length == 0)
                break
        }
        return frags
    }

    /**
     * @description The largest-area fragment of `rect` left visible by `occluders`
     * @param {(Array)} rect - Rect
     * @param {(Array<Array>)} occluders - rects covering `rect`
     * @param {(VarRef)} visibleArea - out: total area of all kept fragments
     * @returns {(Array|Integer)} - largest fragment, or 0 (falsy) when fully covered
     */
    static LargestVisibleFragment(rect, occluders, &visibleArea) {
        visibleArea := 0
        best := 0
        bestArea := 0
        for f in Geometry.VisibleFragments(rect, occluders) {
            a := Geometry.GetArea(f)
            visibleArea += a
            if (a > bestArea) {
                bestArea := a
                best := f
            }
        }
        return best
    }

    /**
     * @description Keep the n largest-area rects
     */
    static _LargestN(rects, n) {
        kept := []
        used := Map()
        loop n {
            bestI := 0
            bestArea := -1
            for i, r in rects {
                if (!used.Has(i) && (area := Geometry.GetArea(r)) > bestArea) {
                    bestArea := area
                    bestI := i
                }
            }
            used[bestI] := 1
            kept.Push(rects[bestI])
        }
        return kept
    }

    /**
     * @description Check if two rectangles (r1 and r2) intersect
     * @param {(Array)} r1 - Rect
     * @param {(Array)} r2 - Rect
     * @returns {(Boolean)} - true if the rectangles intersect, false otherwise
     */
    static DoRectanglesIntersect(r1, r2) {
        return (
            r1[1] < r2[3] && r1[3] > r2[1] && r1[2] < r2[4] && r1[4] > r2[2]
        )
    }

    /**
     * @description Return the area of intersection of two rectangles r1 and r2
     * @param {(Array)} r1 - Rect
     * @param {(Array)} r2 - Rect
     * @returns {(Integer)} - the area of intersection, 0 if the rectangles don't intersect
     */
    static GetIntersectionArea(r1, r2) {
        if (!Geometry.DoRectanglesIntersect(r1, r2))
            return 0

        return (
            ((r1[3] < r2[3] ? r1[3] : r2[3]) - (r1[1] > r2[1] ? r1[1] : r2[1])) *
            ((r1[4] < r2[4] ? r1[4] : r2[4]) - (r1[2] > r2[2] ? r1[2] : r2[2]))
        )
    }

    /**
     * @description Create a rect from two points
     * @param {(Integer)} x1
     * @param {(Integer)} y1
     * @param {(Integer)} x2
     * @param {(Integer)} y2
     * @returns {(Array)} - the rect
     */
    static Rect(x1, y1, x2, y2) {
        return [x1, y1, x2, y2]
    }

    static RectsEqual(r1, r2) {
        return (
            r1[1] == r2[1]
            && r1[2] == r2[2]
            && r1[3] == r2[3]
            && r1[4] == r2[4]
        )
    }

    static GetArea(r) {
        return (r[3] - r[1]) * (r[4] - r[2])
    }

    static PointInRect(x, y, r) {
        return x >= r[1] && x <= r[3] && y >= r[2] && y <= r[4]
    }

    static RectCenter(r, &x, &y) {
        x := r[1] + (r[3] - r[1]) / 2
        y := r[2] + (r[4] - r[2]) / 2
    }
}