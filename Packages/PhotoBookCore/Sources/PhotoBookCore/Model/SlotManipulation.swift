import Foundation

/// Which corner of a photo slot is being dragged to resize it.
public enum SlotCorner: Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    /// True when this corner sits on the frame's left (min-x) edge.
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    /// True when this corner sits on the frame's top (min-y) edge.
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// Pure geometry for manual photo placement. All inputs/outputs are in
/// normalized 0–1 page space (`NormRect`).
public enum SlotManipulation {

    /// Translate a slot frame by a normalized delta; size is unchanged.
    public static func move(_ frame: NormRect, byNormDelta dx: Double, _ dy: Double) -> NormRect {
        NormRect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height)
    }

    /// Resize `frame` by dragging `corner` with a normalized delta, holding
    /// the frame's aspect ratio (width/height) constant so the photo's visual
    /// shape and crop are unchanged. The corner opposite `corner` stays fixed.
    /// The result is clamped so `min(width, height)` never drops below
    /// `minShortSide`.
    public static func resize(_ frame: NormRect, corner: SlotCorner,
                              byNormDelta dx: Double, _ dy: Double,
                              minShortSide: Double) -> NormRect {
        guard frame.width > 0, frame.height > 0 else { return frame }
        let aspect = frame.width / frame.height   // held constant

        // Fixed anchor = the corner opposite the dragged one.
        let anchorX = corner.isLeft ? frame.maxX : frame.x
        let anchorY = corner.isTop ? frame.maxY : frame.y

        // Moving corner's new position after the drag.
        let movingX = (corner.isLeft ? frame.x : frame.maxX) + dx
        let movingY = (corner.isTop ? frame.y : frame.maxY) + dy

        // Raw box from anchor to moved corner, then fit to the held aspect by
        // taking the dimension that requires the larger box (cover behavior).
        let rawW = abs(anchorX - movingX)
        let rawH = abs(anchorY - movingY)
        var width: Double
        var height: Double
        if rawH <= 0 || rawW / rawH > aspect {
            width = rawW
            height = width / aspect
        } else {
            height = rawH
            width = height * aspect
        }

        // Clamp so the short side stays usable; scale up uniformly if needed.
        let shortSide = min(width, height)
        if shortSide < minShortSide, shortSide > 0 {
            let scale = minShortSide / shortSide
            width *= scale
            height *= scale
        }

        // Place the box so the anchor corner is fixed.
        let x = corner.isLeft ? anchorX - width : anchorX
        let y = corner.isTop ? anchorY - height : anchorY
        return NormRect(x: x, y: y, width: width, height: height)
    }

    /// Resize `frame` by dragging `corner`, changing width and height
    /// INDEPENDENTLY (no held aspect) — the text-box behavior: the box
    /// reshapes to control wrapping while the font size is set separately.
    /// The corner opposite `corner` stays fixed; each side is clamped so it
    /// never drops below `minShortSide`.
    public static func resizeFree(_ frame: NormRect, corner: SlotCorner,
                                  byNormDelta dx: Double, _ dy: Double,
                                  minShortSide: Double) -> NormRect {
        // Fixed anchor = the corner opposite the dragged one.
        let anchorX = corner.isLeft ? frame.maxX : frame.x
        let anchorY = corner.isTop ? frame.maxY : frame.y

        // Moving corner's new position after the drag.
        let movingX = (corner.isLeft ? frame.x : frame.maxX) + dx
        let movingY = (corner.isTop ? frame.y : frame.maxY) + dy

        let width = max(minShortSide, abs(anchorX - movingX))
        let height = max(minShortSide, abs(anchorY - movingY))

        let x = corner.isLeft ? anchorX - width : anchorX
        let y = corner.isTop ? anchorY - height : anchorY
        return NormRect(x: x, y: y, width: width, height: height)
    }
}
