/// Seeded recursive partition of the page rectangle. Aspect-agnostic: covers
/// any page size and any photo mix — including the all-panorama batches the
/// template library cannot. Deterministic: the same `LayoutContext.seed`
/// always yields the same boxes, and each candidate carries its boxes inside
/// `GeneratedLayoutParams`, so reopening a document never re-runs layout.
public struct GenerativeProvider: LayoutProvider {

    /// Distinct candidates per request: enough to give the scorer and the
    /// alternatives strip a real choice without flooding either.
    static let candidateCount = 3

    /// Split fractions clamp to [0.25, 0.75]: no recursion step may produce
    /// a region thinner than a quarter of its parent — slivers crop photos
    /// into ribbons and read as layout bugs.
    static let minSplitFraction = 0.25

    /// Split position jitter: ±6% of the parent region. Enough to make
    /// candidates visually distinct, small enough to keep balance.
    static let positionJitter = 0.12

    /// Reserved caption band height (fraction of page) when the context asks
    /// for a text zone — matches the template library's caption bands.
    static let textBandHeight = 0.08

    /// A group mean aspect above this reads as landscape (stack into rows);
    /// below `portraitAspectThreshold` reads as portrait (side by side). The
    /// gap around 1.0 is the square band that defers to the region's aspect.
    /// Matches PhotoAnalyzer's 0.05 square tolerance.
    static let landscapeAspectThreshold = 1.05
    static let portraitAspectThreshold = 0.95

    public init() {}

    public func candidates(forPhotoCount count: Int, photos: [AnalyzedPhoto],
                           context: LayoutContext) -> [LayoutCandidate] {
        guard count >= 1, photos.count == count else { return [] }
        var seedSource = SplitMix64(seed: context.seed)
        return (0..<Self.candidateCount).map { _ in
            makeCandidate(photos: photos, context: context, seed: seedSource.next())
        }
    }

    private func makeCandidate(photos: [AnalyzedPhoto], context: LayoutContext,
                               seed: UInt64) -> LayoutCandidate {
        var rng = SplitMix64(seed: seed)
        let effectiveMargin = context.edgeStyle.hasOuterMargin ? context.style.pageMargin : 0.0
        let effectiveGutter = context.edgeStyle.keepsGutter ? context.style.gutter : 0.0
        var content = NormRect.full.inset(by: effectiveMargin)
        var textFrames: [NormRect] = []
        if context.needsTextZone {
            textFrames = [NormRect(x: content.x,
                                   y: content.y + content.height - Self.textBandHeight,
                                   width: content.width,
                                   height: Self.textBandHeight)]
            content.height -= Self.textBandHeight + effectiveGutter
        }
        var boxes: [NormRect] = []
        partition(photos, in: content, pageAspect: context.pageSize.aspectRatio,
                  gutter: effectiveGutter, rng: &rng, into: &boxes)
        return LayoutCandidate(origin: .generated(GeneratedLayoutParams(seed: seed, boxes: boxes)),
                               photoSlotFrames: boxes,
                               textSlotFrames: textFrames)
    }

    /// Guillotine partition: recursively cut the region in two, photo order
    /// preserved (boxes[i] hosts photos[i]). Siblings are always separated by
    /// exactly one gutter, so the whole tree is overlap-free by construction.
    private func partition(_ photos: [AnalyzedPhoto], in region: NormRect, pageAspect: Double,
                           gutter: Double, rng: inout SplitMix64, into boxes: inout [NormRect]) {
        if photos.count <= 1 {
            boxes.append(region)
            return
        }

        // 1. Split the photo run near the middle, jittered ±1 for variety.
        var splitIndex = photos.count / 2
        if photos.count > 2 {
            let offset = Int(rng.next() % 3) - 1            // -1, 0, +1
            splitIndex = min(max(splitIndex + offset, 1), photos.count - 1)
        }
        let firstGroup = Array(photos[..<splitIndex])
        let secondGroup = Array(photos[splitIndex...])

        // 2. Direction follows the photos' orientation so each slot keeps the
        //    shape of the photo it hosts: landscape photos are STACKED into
        //    full-width rows (horizontal cut → wide slots), portrait photos are
        //    placed SIDE BY SIDE (vertical cut → tall slots). A landscape photo
        //    therefore never lands in a narrow vertical slot. Square-ish groups
        //    fall back to matching the region's own aspect. Pages are
        //    orientation-pure (the paginator guarantees no landscape+portrait
        //    mix), so the group mean reliably reflects one orientation.
        let meanAspect = photos.reduce(0.0) { $0 + $1.ref.aspectRatio } / Double(photos.count)
        let regionAspect = region.aspectRatio * pageAspect
        let splitVertically: Bool
        if meanAspect > Self.landscapeAspectThreshold {
            splitVertically = false                       // landscape → stack (wide slots)
        } else if meanAspect < Self.portraitAspectThreshold {
            splitVertically = true                        // portrait → side by side (tall slots)
        } else {
            splitVertically = regionAspect >= meanAspect  // square-ish → match the region
        }

        // 3. Position proportional to each side's photo count, perturbed by
        //    the seeded RNG, clamped so neither side becomes a sliver.
        let proportional = Double(firstGroup.count) / Double(photos.count)
        let jitter = (unitDouble(&rng) - 0.5) * Self.positionJitter
        let fraction = min(max(proportional + jitter, Self.minSplitFraction),
                           1 - Self.minSplitFraction)

        if splitVertically {
            let firstWidth = (region.width - gutter) * fraction
            let left = NormRect(x: region.x, y: region.y,
                                width: firstWidth, height: region.height)
            let right = NormRect(x: region.x + firstWidth + gutter, y: region.y,
                                 width: region.width - gutter - firstWidth, height: region.height)
            partition(firstGroup, in: left, pageAspect: pageAspect, gutter: gutter,
                      rng: &rng, into: &boxes)
            partition(secondGroup, in: right, pageAspect: pageAspect, gutter: gutter,
                      rng: &rng, into: &boxes)
        } else {
            let firstHeight = (region.height - gutter) * fraction
            let top = NormRect(x: region.x, y: region.y,
                               width: region.width, height: firstHeight)
            let bottom = NormRect(x: region.x, y: region.y + firstHeight + gutter,
                                  width: region.width, height: region.height - gutter - firstHeight)
            partition(firstGroup, in: top, pageAspect: pageAspect, gutter: gutter,
                      rng: &rng, into: &boxes)
            partition(secondGroup, in: bottom, pageAspect: pageAspect, gutter: gutter,
                      rng: &rng, into: &boxes)
        }
    }

    /// Uniform Double in [0, 1) from the top 53 bits — the standard conversion.
    private func unitDouble(_ rng: inout SplitMix64) -> Double {
        Double(rng.next() >> 11) * 0x1.0p-53
    }
}
