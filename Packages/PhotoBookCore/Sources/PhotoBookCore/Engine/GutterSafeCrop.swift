import Foundation

/// Biases a spread slot's crop so a salient subject doesn't land in the fold.
///
/// A photo that straddles the spine (canvas x = 0.5) loses whatever content
/// sits in the gutter when the book is bound. When a photo carries a
/// `salientCenter` (top-left-origin normalized image space), we shift the
/// visible horizontal window of the slot so the salient point projects OUTSIDE
/// a band centered on the gutter.
///
/// The returned crop's pixel aspect exactly matches the slot's physical aspect
/// (full height, width `slotAspect/photoAspect`), so the renderer's
/// center-pinned aspect-fill (`SlotGeometry.imageDrawRect`) is an exact fit and
/// the salient x maps linearly across the slot — no re-cropping surprises.
enum GutterSafeCrop {
    /// Fraction of spread width centered on x = 0.5 that content should avoid.
    static let gutterBand = 0.08

    /// For a spread slot straddling the gutter: returns a crop rect
    /// (source-photo normalized space) shifted horizontally by the minimum
    /// amount so the salient center's projection onto the spread lands outside
    /// the gutter band. Returns nil (caller keeps existing crop) when:
    /// salientCenter is nil, the slot doesn't straddle the gutter, the photo has
    /// no horizontal slack (not wider than the slot), or the salient point
    /// already projects outside the band.
    static func crop(
        slotFrame: NormRect,          // double-wide canvas space
        photoAspect: Double,          // pixel w/h
        spreadAspect: Double,         // 2 × page trim aspect
        salientCenter: NormPoint?
    ) -> NormRect? {
        guard let salient = salientCenter else { return nil }
        guard slotFrame.width > 0, slotFrame.height > 0,
              photoAspect > 0, spreadAspect > 0 else { return nil }

        // Straddle test mirrors Spread.slice()'s epsilon style.
        let g = Spread.gutter
        guard slotFrame.x < g - 1e-12, slotFrame.maxX > g + 1e-12 else { return nil }

        // The slot's physical aspect on the double-wide canvas. A crop of full
        // height and width `cropW = slotAspect/photoAspect` has pixel aspect
        // `cropW·photoAspect = slotAspect`, i.e. it fits the slot exactly.
        // cropW < 1 only when the photo is WIDER than the slot; otherwise the
        // visible window already spans the full photo width — no horizontal
        // slack, so shifting is impossible (vertical bias is out of scope).
        let slotAspect = (slotFrame.width * spreadAspect) / slotFrame.height
        let cropW = slotAspect / photoAspect
        guard cropW < 1 - 1e-12 else { return nil }

        // Default centered window, and the linear projection of the salient x
        // through it onto spread (canvas) x. A point outside the visible window
        // is clamped to the slot edge (not visible → treat as at the edge).
        let defaultCropX = (1 - cropW) / 2
        func projected(cropX: Double) -> Double {
            let t = min(max((salient.x - cropX) / cropW, 0), 1)
            return slotFrame.x + t * slotFrame.width
        }

        let halfBand = gutterBand / 2
        let leftEdge = g - halfBand
        let rightEdge = g + halfBand

        let current = projected(cropX: defaultCropX)
        guard current > leftEdge, current < rightEdge else { return nil }  // already safe

        // Escape via the NEARER band edge (tie at the gutter → left, so the
        // result is deterministic). Projection is linear and monotonically
        // DECREASING in cropX, so the nearer target edge is also the minimal
        // cropX shift.
        let targetEdge = (current <= g) ? leftEdge : rightEdge
        // Invert slotX = slotFrame.x + ((salient.x - cropX)/cropW)·slotFrame.width
        //   ⇒ cropX = salient.x − cropW·(targetEdge − slotFrame.x)/slotFrame.width
        let rawCropX = salient.x - cropW * (targetEdge - slotFrame.x) / slotFrame.width
        // Clamp into the valid window range; if clamping prevents full escape,
        // this is still a valid, partially-improved crop (best effort).
        let cropX = min(max(rawCropX, 0), 1 - cropW)

        return NormRect(x: cropX, y: 0, width: cropW, height: 1)
    }
}
