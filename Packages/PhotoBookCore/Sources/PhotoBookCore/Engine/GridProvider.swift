/// Offers uniform grid layouts (equal cells, light center-crop via aspect-fill).
/// On framed pages it insets by the book's margin/gutter; on tiled pages it
/// drops the outer margin but keeps the gutter; on borderless pages it zeroes
/// both so the cells tile the page edge-to-edge.
public struct GridProvider: LayoutProvider {

    static let textBandHeight = 0.08

    public init() {}

    /// Same column choices as masonry: 2 for 2+ photos, +3 for 5+.
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

        return Self.columnCounts(for: count).map { cols in
            let boxes = GridLayout.boxes(count: count, content: content, gutter: gutter, columns: cols)
            return LayoutCandidate(
                // Distinct seed base from masonry so origins never collide.
                origin: .generated(GeneratedLayoutParams(seed: context.seed &+ 1000 &+ UInt64(cols), boxes: boxes)),
                photoSlotFrames: boxes, textSlotFrames: textFrames, family: .grid)
        }
    }
}
