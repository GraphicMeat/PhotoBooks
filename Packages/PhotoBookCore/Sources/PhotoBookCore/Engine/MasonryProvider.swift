/// Offers zero-crop column (masonry) layouts. On framed pages it insets by the
/// book's margin/gutter; on tiled pages it drops the outer margin but keeps the
/// gutter; on borderless pages it zeroes both so columns span the full page
/// width (photos stay whole, contain-to-height keeps the block on-page).
/// Mirrors `GenerativeProvider`'s edge-style margin/gutter handling.
public struct MasonryProvider: LayoutProvider {

    static let textBandHeight = 0.08

    public init() {}

    /// 2 columns for 2+ photos; additionally 3 columns for 5+ photos. Never more
    /// columns than photos.
    static func columnCounts(for count: Int) -> [Int] {
        var cols = [2]
        if count >= 5 { cols.append(3) }
        return cols.filter { $0 <= count }
    }

    public func candidates(forPhotoCount count: Int, photos: [AnalyzedPhoto],
                           context: LayoutContext) -> [LayoutCandidate] {
        guard count >= 2, photos.count == count else { return [] }
        let margin = context.edgeStyle.hasOuterMargin ? context.style.pageMargin : 0
        let gutter = context.edgeStyle.keepsGutter ? context.style.gutter : 0
        var content = NormRect.full.inset(by: margin)

        var textFrames: [NormRect] = []
        if context.needsTextZone {
            textFrames = [NormRect(x: content.x,
                                   y: content.y + content.height - Self.textBandHeight,
                                   width: content.width, height: Self.textBandHeight)]
            content = NormRect(x: content.x, y: content.y, width: content.width,
                               height: content.height - Self.textBandHeight - gutter)
        }

        let aspects = photos.map(\.ref.aspectRatio)
        return Self.columnCounts(for: count).map { cols in
            let boxes = MasonryLayout.boxes(aspects: aspects, content: content,
                                            pageAspect: context.pageSize.aspectRatio,
                                            gutter: gutter, columns: cols)
            return LayoutCandidate(
                origin: .generated(GeneratedLayoutParams(seed: context.seed &+ UInt64(cols), boxes: boxes)),
                photoSlotFrames: boxes, textSlotFrames: textFrames, family: .masonry)
        }
    }
}
