/// Everything a layout provider needs to know about the page it is filling.
public struct LayoutContext: Sendable {
    public var pageSize: SizeInches
    public var style: BookStyle
    public var needsTextZone: Bool
    public var seed: UInt64
    /// The page's resolved edge mode. Providers zero the outer margin for
    /// `.tiled`/`.borderless`, zero the gutter only for `.borderless`, and defer
    /// to the generative full-bleed tiler for `.borderless`.
    public var edgeStyle: EdgeStyle

    public init(pageSize: SizeInches, style: BookStyle, needsTextZone: Bool, seed: UInt64,
                edgeStyle: EdgeStyle = .framed) {
        self.pageSize = pageSize
        self.style = style
        self.needsTextZone = needsTextZone
        self.seed = seed
        self.edgeStyle = edgeStyle
    }
}

/// Which layout style produced a candidate. Used only by the strip to keep its
/// per-count options diverse (not persisted; `Page` stores `origin`).
public enum LayoutFamily: Sendable, Equatable {
    case justified, masonry, grid
}

/// One possible page layout: slot frames plus the origin tag that the chosen
/// candidate carries into the `Page` (template id, or serialized generative
/// params so documents never re-run layout on open).
public struct LayoutCandidate: Sendable {
    public var origin: LayoutOrigin
    public var photoSlotFrames: [NormRect]     // count == photo group count
    public var textSlotFrames: [NormRect]      // empty if no text zones
    public var family: LayoutFamily

    public init(origin: LayoutOrigin, photoSlotFrames: [NormRect], textSlotFrames: [NormRect],
                family: LayoutFamily = .justified) {
        self.origin = origin
        self.photoSlotFrames = photoSlotFrames
        self.textSlotFrames = textSlotFrames
        self.family = family
    }
}

/// Both providers (template + generative) implement this; the scorer is
/// provider-blind, so candidates compete purely on merit.
public protocol LayoutProvider: Sendable {
    func candidates(forPhotoCount count: Int, photos: [AnalyzedPhoto],
                    context: LayoutContext) -> [LayoutCandidate]
}

extension AspectClass {
    /// Same 5% square tolerance as `PrintPreset.aspectClass`, exposed for
    /// classifying arbitrary page sizes (providers receive a `SizeInches`,
    /// not a preset).
    static func classify(_ size: SizeInches) -> AspectClass {
        let aspect = size.aspectRatio
        if abs(aspect - 1) < 0.05 { return .square }
        return aspect > 1 ? .landscape : .portrait
    }
}
