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
     * @param {(Integer)} rX1 - Top-Left point X
     * @param {(Integer)} rY1 - Top-Left point Y
     * @param {(Integer)} rX2 - Bottom-Right point X
     * @param {(Integer)} rY2 - Bottom-Right point Y
     */
    static CalcIntersectionDistance(sX1, sY1, sX2, sY2, sDir, rX1, rY1, rX2, rY2) {
        return (
            sDir == 0
                ? (rY1 < sY1 ? sY1 : rY1) - (rY2 < sY2 ? rY2 : sY2)
                : (rX1 < sX1 ? sX1 : rX1) - (rX2 < sX2 ? rX2 : sX2)
        )
    }

    /**
     * @description Check if two rectangles (r1 and r2) intersect
     * 
     * r1 defined by:
     *     Top-Left point (r1X1, r1Y1) and Bottom-Right point (r1X2, r1Y2)
     * 
     * r2 defined by:
     *     Top-Left point (r2X1, r2Y1) and Bottom-Right point (r2X2, r2Y2)
     * 
     * @param {(Integer)} r1X1
     * @param {(Integer)} r1Y1
     * @param {(Integer)} r1X2
     * @param {(Integer)} r1Y2
     * @param {(Integer)} r2X1
     * @param {(Integer)} r2Y1
     * @param {(Integer)} r2X2
     * @param {(Integer)} r2Y2
     * @returns {(Boolean)} - true if the rectangles intersect, false otherwise
     */
    static RectanglesIntersect(r1X1, r1Y1, r1X2, r1Y2, r2X1, r2Y1, r2X2, r2Y2) {
        return (
            r1X1 < r2X2 and r1X2 > r2X1 and r1Y1 < r2Y2 and r1Y2 > r2Y1
        )
    }

    /**
     * @description Return the area of intersection of two rectangles r1 and r2
     * 
     * r1 defined by:
     *     Top-Left point (r1X1, r1Y1) and Bottom-Right point (r1X2, r1Y2)
     * 
     * r2 defined by:
     *     Top-Left point (r2X1, r2Y1) and Bottom-Right point (r2X2, r2Y2)
     * 
     * @param {(Integer)} r1X1
     * @param {(Integer)} r1Y1
     * @param {(Integer)} r1X2
     * @param {(Integer)} r1Y2
     * @param {(Integer)} r2X1
     * @param {(Integer)} r2Y1
     * @param {(Integer)} r2X2
     * @param {(Integer)} r2Y2
     * @returns {(Integer)} - the area of intersection, 0 if the rectangles don't intersect
     */
    static GetIntersectionArea(r1X1, r1Y1, r1X2, r1Y2, r2X1, r2Y1, r2X2, r2Y2) {
        if (!Geometry.RectanglesIntersect(r1X1, r1Y1, r1X2, r1Y2, r2X1, r2Y1, r2X2, r2Y2))
            return 0

        return (
            ((r1X2 < r2X2 ? r1X2 : r2X2) - (r1X1 > r2X1 ? r1X1 : r2X1)) *
            ((r1Y2 < r2Y2 ? r1Y2 : r2Y2) - (r1Y1 > r2Y1 ? r1Y1 : r2Y1))
        )
    }
}