import CoreGraphics
import PhotoBookCore

/// The single source of layout math for both renderers.
///
/// Every mapping from the model's normalized 0–1 page space into concrete
/// drawing coordinates lives here — the SwiftUI screen renderer (this plan)
/// and the Core Graphics PDF renderer (Plan 6) call these same pure
/// functions, which is what makes the app WYSIWYG by construction.
/// Internal, but Plan 6 extends this file rather than re-deriving any math.
///
/// Coordinate convention: top-left origin, y down (SwiftUI's convention).
/// The PDF renderer flips its CGContext once and then uses these unchanged.
enum SlotGeometry {

    /// Maps a normalized page-space frame to a concrete rect in a render
    /// area of `renderSize` (the rendered page in points or pixels).
    static func rect(for frame: NormRect, in renderSize: CGSize) -> CGRect {
        CGRect(
            x: frame.x * renderSize.width,
            y: frame.y * renderSize.height,
            width: frame.width * renderSize.width,
            height: frame.height * renderSize.height
        )
    }

    /// Where the FULL image must be drawn so that `crop` (the visible rect
    /// within the photo, normalized to the photo's own bounds) fills
    /// `slotRect`. The caller clips to `slotRect` and draws the whole image
    /// into the returned rect; what remains visible is exactly the crop.
    ///
    /// The math: the crop region in image pixels is
    ///   (crop.x·W, crop.y·H, crop.width·W, crop.height·H).
    /// The uniform scale that makes the crop region cover the slot is
    ///   scale = max(slotRect.width / cropPixelWidth, slotRect.height / cropPixelHeight)
    /// (aspect-fill: when the crop's aspect differs from the slot's — e.g.
    /// the engine's default `.full` crop — the larger scale wins and the
    /// excess is clipped symmetrically). The crop's center is pinned to the
    /// slot's center, so the full image's origin is
    ///   slotCenter − cropCenterInPixels·scale
    /// and its size is (W·scale, H·scale).
    static func imageDrawRect(
        slotRect: CGRect,
        crop: NormRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGRect {
        let imageWidth = Double(pixelWidth)
        let imageHeight = Double(pixelHeight)
        let cropPixelWidth = crop.width * imageWidth
        let cropPixelHeight = crop.height * imageHeight
        guard cropPixelWidth > 0, cropPixelHeight > 0 else { return slotRect }

        let scale = max(slotRect.width / cropPixelWidth, slotRect.height / cropPixelHeight)
        let cropCenterX = (crop.x + crop.width / 2) * imageWidth
        let cropCenterY = (crop.y + crop.height / 2) * imageHeight

        return CGRect(
            x: slotRect.midX - cropCenterX * scale,
            y: slotRect.midY - cropCenterY * scale,
            width: imageWidth * scale,
            height: imageHeight * scale
        )
    }

    /// Font size in points for a text run rendered on a page of
    /// `renderHeight` points. `pointSizeFactor` is the model's
    /// resolution-independent size (fraction of page height), so the same
    /// factor yields 30 pt on a 600 pt preview and 180 pt on a 3600 pt PDF
    /// page — identical proportions.
    static func fontPoints(factor: Double, renderHeight: Double) -> Double {
        factor * renderHeight
    }

    /// Corner radius in points. `BookStyle.cornerRadius` is normalized to
    /// the minimum page dimension (same convention as `pageMargin`).
    static func cornerRadius(style: BookStyle, in renderSize: CGSize) -> Double {
        style.cornerRadius * Double(min(renderSize.width, renderSize.height))
    }

    /// Pixel budget for a slot thumbnail: the slot's longest side at 2×
    /// (Retina), rounded UP to a 256 px bucket. Bucketing keeps cache keys
    /// stable while a window resizes, and rounding up means the cached
    /// thumbnail is never softer than the slot needs.
    static func thumbnailPixelSize(for slotSize: CGSize) -> Int {
        let longestSide = max(slotSize.width, slotSize.height, 1)
        let retina = Double(longestSide) * 2
        let bucket = (Int(retina.rounded(.up)) + 255) / 256 * 256
        return max(256, bucket)
    }
}
