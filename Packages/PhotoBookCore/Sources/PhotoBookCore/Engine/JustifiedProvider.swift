/// The default layout provider: justified, zero-crop packing. Sizes every
/// slot to its photo's own aspect ratio and packs them to fill the page, so
/// nothing is cropped or zoomed. Replaces the crop-to-fill template/generative
/// providers for standard interior pages.
public struct JustifiedProvider: LayoutProvider {

    /// How many row-count arrangements to offer per page. The scorer picks the
    /// best for the chosen layout; the rest populate the alternatives strip.
    static let candidateCount = 3

    /// Reserved caption band height (fraction of page) when a text zone is
    /// requested — matches the other providers' caption bands.
    static let textBandHeight = 0.08

    /// Borderless pages are a deliberate edge-to-edge aesthetic: photos fill
    /// the page (aspect-fill) with no margins. That intentionally crops, so the
    /// no-crop justified packing does NOT apply there — full-bleed pages defer
    /// to the generative tiler.
    private let fullBleed = GenerativeProvider()

    public init() {}

    public func candidates(forPhotoCount count: Int, photos: [AnalyzedPhoto],
                           context: LayoutContext) -> [LayoutCandidate] {
        guard count >= 1, photos.count == count else { return [] }
        if context.edgeStyle.isFullBleed {
            return fullBleed.candidates(forPhotoCount: count, photos: photos, context: context)
        }

        let margin = context.edgeStyle.hasOuterMargin ? context.style.pageMargin : 0.0
        let gutter = context.edgeStyle.keepsGutter ? context.style.gutter : 0.0
        var content = NormRect.full.inset(by: margin)

        var textFrames: [NormRect] = []
        if context.needsTextZone {
            textFrames = [NormRect(x: content.x,
                                   y: content.y + content.height - Self.textBandHeight,
                                   width: content.width,
                                   height: Self.textBandHeight)]
            content = NormRect(x: content.x, y: content.y,
                               width: content.width,
                               height: content.height - Self.textBandHeight - gutter)
        }

        let aspects = photos.map(\.ref.aspectRatio)
        let arrangements = JustifiedLayout.arrangements(
            aspects: aspects, content: content,
            pageAspect: context.pageSize.aspectRatio, gutter: gutter)

        return arrangements.prefix(Self.candidateCount).map { arrangement in
            LayoutCandidate(
                origin: .generated(GeneratedLayoutParams(seed: context.seed, boxes: arrangement.boxes)),
                photoSlotFrames: arrangement.boxes,
                textSlotFrames: textFrames,
                family: .justified)
        }
    }
}
