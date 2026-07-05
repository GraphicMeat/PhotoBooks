/// Justified, zero-crop packing for a 2-page SPREAD — the spread analogue of
/// `JustifiedLayout`. The spread is authored on a double-wide canvas
/// (x ∈ 0…1 spans BOTH facing pages, gutter at x = 0.5), whose true aspect is
/// `2 · trimAspect`. Each photo's box is sized to the photo's OWN aspect, so an
/// aspect-fill render with a `.full` crop shows the whole photo — no zoom, no
/// crop, proportions preserved across the spread.
///
/// Wide photos naturally land in boxes that may straddle the gutter; `Spread`'s
/// `slice()` splits such a box into complementary half-crops that reconstruct
/// the whole photo across the spine (the panorama effect). Pure and
/// deterministic: same inputs always yield the same boxes.
enum JustifiedSpreadLayout {

    /// Boxes in double-wide canvas space, each sized to its photo's own aspect
    /// (zero crop), packed to fill `content`. `spreadAspect` is the canvas's
    /// true aspect (`2 · trimSize.aspectRatio`). Empty `aspects` → empty result.
    static func boxes(aspects: [Double], content: NormRect,
                      spreadAspect: Double, gutter: Double) -> [NormRect] {
        guard !aspects.isEmpty else { return [] }
        // The spread canvas is just a very wide "page": delegate to the single
        // page packer with the canvas aspect. The no-crop invariant
        // (box.aspectRatio * spreadAspect == photoAspect) is inherited directly.
        return JustifiedLayout.boxes(aspects: aspects, content: content,
                                     pageAspect: spreadAspect, gutter: gutter)
    }
}
