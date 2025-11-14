#Requires AutoHotkey v2.0


class Geometry {
    /**
     * @description
     * ```
     *   1---------r1
     *   │         │
     *   │     1---------r2
     *   ------│---2     │
     *         │         │
     *         ----------2
     * ```
     * Calculate weighted intersection distance between two rectangles.
     * If they intersect, the distance is negative, otherwise - positive.
     * 
     * @param {(Array)} r1 - Rect
     * @param {(Array)} r2 - Rect
     * @param {(Float)} kx - Weight of distance on X
     * @param {(Float)} ky - Weight of distance on Y
     * @returns {(Float)} - The intersection distance
     */
    static CalcWeightedIntersectionDistance(r1, r2, kx, ky) {
        return (
            ((r2[1] < r1[1] ? r1[1] : r2[1]) - (r2[3] > r1[3] ? r1[3] : r2[3])) * kx
            + ((r2[2] < r1[2] ? r1[2] : r2[2]) - (r2[4] > r1[4] ? r1[4] : r2[4])) * ky
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