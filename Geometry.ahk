#Requires AutoHotkey v2.0


class Geometry {
    /**
     * @description
     * ```
     *      │         │
     *     sXY1......sXY2
     *      │         │
     * dir  │     1---│----- r
     *  │   │     │   │     │
     *  ↓   │     │   │     │
     *      │     ----│-----2
     *      ↓         ↓
     * ```
     * Calculates the distance between the `s` plane and `r` rectangle.
     * If they intersect, the distance is negative, otherwise - positive.
     * 
     * S defined by:
     *     points 1 (sX1, sY1) and 2 (sX2, sY2) for two boundaries
     *     direction - vertical or horizontal
     * 
     * R defined by:
     *     Top-Left point (rX1, rY1) and Bottom-Right point (rX2, rY2)
     * 
     * Returns the LENGTH of the intersection
     * 
     * @param {(Integer)} sX1
     * @param {(Integer)} sY1
     * @param {(Integer)} sX2
     * @param {(Integer)} sY2
     * @param {(Integer)} sDir - vertical or horizontal
     *   - 0 - horizontal
     *   - 1 - vertical
     * @param {(Array)} r - Rect
     */
    static CalcIntersectionDistance(sX1, sY1, sX2, sY2, sDir, r) {
        return (
            sDir == 0
                ? (r[2] < sY1 ? sY1 : r[2]) - (r[4] < sY2 ? sY2 : r[4])
                : (r[1] < sX1 ? sX1 : r[1]) - (r[3] < sX2 ? sX2 : r[3])
        )
    }

    /**
     * @description Check if two rectangles (r1 and r2) intersect
     * @param {(Array)} r1 - Rect
     * @param {(Array)} r2 - Rect
     * @returns {(Boolean)} - true if the rectangles intersect, false otherwise
     */
    static DoRectanglesIntersect(r1, r2) {
        return (
            r1[1] < r2[3] and r1[3] > r2[1] and r1[2] < r2[4] and r1[4] > r2[2]
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

    static Rect(x1, y1, x2, y2) {
        return [x1, y1, x2, y2]
    }

    static GetArea(r) {
        return (r[3] - r[1]) * (r[4] - r[2])
    }

    static PointInRect(x, y, r) {
        return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
    }

    static RectCenter(r, &x, &y) {
        x := r[1] + (r[3] - r[1]) / 2
        y := r[2] + (r[4] - r[2]) / 2
    }
}