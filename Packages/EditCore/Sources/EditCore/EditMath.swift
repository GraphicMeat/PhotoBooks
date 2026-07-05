import CoreGraphics
import Foundation
import PhotoBookCore

// MARK: - Crop geometry (pure functions, golden-value tested)

/// The crop rect (in photo space, normalized to the photo's own bounds)
/// that fills a slot of `slotAspect` with NO letterbox, centered.
///
/// `photoAspect` = photo pixelWidth/pixelHeight; `slotAspect` = the slot's
/// TRUE on-page aspect (see `trueSlotAspect(of:pageSize:)` — a NormRect's
/// page-relative aspect must be corrected by the page's own aspect).
///
/// Math: the crop's pixel aspect must equal the slot aspect:
///   (crop.width · W) / (crop.height · H) = slotAspect
///   ⇒ crop.width / crop.height = slotAspect / photoAspect.
/// Fill without letterbox means one crop dimension is 1:
///   photo wider than slot  (photoAspect > slotAspect):
///     crop.height = 1, crop.width = slotAspect/photoAspect, centered in x.
///   photo taller than slot (photoAspect ≤ slotAspect):
///     crop.width = 1, crop.height = photoAspect/slotAspect, centered in y.
func defaultCrop(photoAspect: Double, slotAspect: Double) -> NormRect {
    guard photoAspect > 0, slotAspect > 0,
          photoAspect.isFinite, slotAspect.isFinite else { return .full }
    if photoAspect > slotAspect {
        let width = slotAspect / photoAspect
        return NormRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    } else {
        let height = photoAspect / slotAspect
        return NormRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }
}

/// A slot frame's TRUE aspect on a page of `pageSize`. `frame.aspectRatio`
/// is page-relative (0–1 space); multiplying by the page's aspect converts:
///   trueAspect = (frame.width·W) / (frame.height·H) = frame.aspectRatio · W/H.
public func trueSlotAspect(of frame: NormRect, pageSize: SizeInches) -> Double {
    frame.aspectRatio * pageSize.aspectRatio
}

/// Applies a pan + zoom gesture to a crop rect, keeping the crop inside the
/// photo and at the slot's aspect.
///
/// - `base`: the crop before the gesture (photo-normalized).
/// - `translation`: the drag translation in view points (drag right = positive
///   width). Dragging the photo right reveals photo to the LEFT, so the crop
///   window moves left: the pan maps through viewSize — `viewSize.width`
///   points correspond to the full visible crop width.
/// - `zoomDelta`: multiplicative magnification (2 = photo appears twice as
///   large, so the visible window halves). Applied about the base center.
/// - Aspect link: crop.width = ratio · crop.height with
///   ratio = slotAspect / photoAspect — keeps the crop's pixel aspect equal
///   to the slot's, so the slot never letterboxes (D5).
/// - Clamping: the window never exceeds the photo on either axis
///   (height ≤ min(1, 1/ratio)) and never shrinks below 1/8 of that maximum
///   (8× max zoom); x/y clamp to keep the window fully inside the photo.
///
/// Identity property: adjustedCrop(base: .full, translation: .zero,
/// zoomDelta: 1, …) == defaultCrop(photoAspect:slotAspect:) — a
/// non-conforming base (e.g. the engine's default `.full`) normalizes to
/// the centered aspect-fill crop on the first call.
public func adjustedCrop(base: NormRect, translation: CGSize, zoomDelta: Double,
                         photoAspect: Double, slotAspect: Double, viewSize: CGSize) -> NormRect {
    guard photoAspect > 0, slotAspect > 0, zoomDelta > 0,
          viewSize.width > 0, viewSize.height > 0,
          base.width > 0, base.height > 0 else { return base }

    let ratio = slotAspect / photoAspect

    // 1. Zoom about the base center, aspect-linked, clamped to [max/8, max].
    let maxHeight = min(1, 1 / ratio)
    let height = min(max(base.height / zoomDelta, maxHeight / 8), maxHeight)
    let width = height * ratio
    let centerX = base.x + base.width / 2
    let centerY = base.y + base.height / 2

    // 2. Pan: view points → crop-space offset (negative because dragging the
    //    image moves the window the opposite way).
    let panX = (Double(translation.width) / Double(viewSize.width)) * width
    let panY = (Double(translation.height) / Double(viewSize.height)) * height

    // 3. Clamp the window inside the photo.
    let x = min(max(centerX - width / 2 - panX, 0), 1 - width)
    let y = min(max(centerY - height / 2 - panY, 0), 1 - height)
    return NormRect(x: x, y: y, width: width, height: height)
}

// MARK: - Text size conversion

/// `StyledText.pointSizeFactor` (fraction of page height) shown to the user
/// as REAL print points on the current preset's trim height (72 pt/inch):
/// a 7×7 in book is 504 pt tall, so factor 0.05 displays as 25.2 pt (D13).
public func displayPoints(pointSizeFactor: Double, trimHeightInches: Double) -> Double {
    pointSizeFactor * trimHeightInches * 72
}

public func pointSizeFactor(displayPoints: Double, trimHeightInches: Double) -> Double {
    guard trimHeightInches > 0 else { return 0 }
    return displayPoints / (trimHeightInches * 72)
}
