/// How a page's photos meet the page edge. Two orthogonal spacing decisions
/// (outer margin, inter-photo gutter) collapsed into three meaningful modes:
///
/// - `.framed`     — outer margin + gutter (the book default)
/// - `.tiled`      — NO outer margin, gutter kept: photos fill to the page edge
///                   but stay separated by gaps
/// - `.borderless` — NO margin, NO gutter: photos tile edge-to-edge, touching
public enum EdgeStyle: String, Codable, Sendable, CaseIterable, Equatable {
    case framed
    case tiled
    case borderless

    /// Only `.framed` keeps the book's outer page margin; the others bleed to
    /// the page edge (margin 0).
    public var hasOuterMargin: Bool { self == .framed }

    /// `.framed` and `.tiled` keep the inter-photo gutter; only `.borderless`
    /// zeroes it so photos touch.
    public var keepsGutter: Bool { self != .borderless }

    /// `.borderless` is the deliberate full-bleed aesthetic that defers to the
    /// generative tiler (aspect-fill, intentional crop). `.framed`/`.tiled` use
    /// the normal zero-crop packing.
    public var isFullBleed: Bool { self == .borderless }
}
