import Foundation

/// Pure, soft edge-snapping for manually placed photo slots. Snapping only
/// translates the frame (size is preserved) and never resolves overlap — it
/// nudges edges onto nearby alignment lines when within `threshold`.
public enum SlotSnapper {

    public static func snap(_ frame: NormRect, pageInsetX: Double, pageInsetY: Double,
                            neighbors: [NormRect], threshold: Double) -> NormRect {
        let dx = bestShift(minEdge: frame.x, maxEdge: frame.maxX,
                           lines: verticalLines(pageInsetX: pageInsetX, neighbors: neighbors),
                           threshold: threshold)
        let dy = bestShift(minEdge: frame.y, maxEdge: frame.maxY,
                           lines: horizontalLines(pageInsetY: pageInsetY, neighbors: neighbors),
                           threshold: threshold)
        return NormRect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height)
    }

    /// Candidate x-lines: page content margins + every neighbor's left/right.
    private static func verticalLines(pageInsetX: Double, neighbors: [NormRect]) -> [Double] {
        var lines = [pageInsetX, 1.0 - pageInsetX]
        for n in neighbors { lines.append(n.x); lines.append(n.maxX) }
        return lines
    }

    /// Candidate y-lines: page content margins + every neighbor's top/bottom.
    private static func horizontalLines(pageInsetY: Double, neighbors: [NormRect]) -> [Double] {
        var lines = [pageInsetY, 1.0 - pageInsetY]
        for n in neighbors { lines.append(n.y); lines.append(n.maxY) }
        return lines
    }

    /// Best translation along one axis: consider snapping either the min edge
    /// or the max edge to the nearest line, and pick the smallest in-threshold
    /// shift. Returns 0 when nothing is close enough.
    private static func bestShift(minEdge: Double, maxEdge: Double,
                                  lines: [Double], threshold: Double) -> Double {
        var best = 0.0
        var bestDist = threshold
        for line in lines {
            for shift in [line - minEdge, line - maxEdge] {
                let dist = abs(shift)
                if dist < bestDist {
                    bestDist = dist
                    best = shift
                }
            }
        }
        return best
    }
}
