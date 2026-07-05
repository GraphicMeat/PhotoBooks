import Foundation

/// A photo placement on a page. `frame` is page space (0–1 page coords);
/// `crop` is photo space (the visible rect within the photo, normalized to
/// the photo's own bounds).
public struct PhotoSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var frame: NormRect             // position on page
    public var photoID: PhotoID?           // nil = empty slot
    public var crop: NormRect              // visible rect within the photo
    public var isLocked: Bool              // manual edits auto-lock; engine skips locked slots

    public init(
        id: UUID = UUID(),
        frame: NormRect,
        photoID: PhotoID? = nil,
        crop: NormRect = .full,
        isLocked: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.photoID = photoID
        self.crop = crop
        self.isLocked = isLocked
    }
}

public enum TextAlignment: String, Codable, Sendable {
    case leading, center, trailing
}

/// Rich text styling for a text zone. No UI types — fonts are PostScript
/// names, colors are hex strings, sizes are fractions of page height so
/// text scales across print presets.
public struct StyledText: Codable, Equatable, Sendable {
    public var string: String
    public var fontName: String            // PostScript name; "" = style default
    public var pointSizeFactor: Double     // fraction of page height (scales across presets)
    public var colorHex: String            // "#RRGGBB"
    public var alignment: TextAlignment

    public init(
        string: String,
        fontName: String = "",
        pointSizeFactor: Double,
        colorHex: String = "#000000",
        alignment: TextAlignment = .leading
    ) {
        self.string = string
        self.fontName = fontName
        self.pointSizeFactor = pointSizeFactor
        self.colorHex = colorHex
        self.alignment = alignment
    }
}

/// A text zone on a page. The zone (frame) is fixed by the template;
/// freeform placement is v2.
public struct TextSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var frame: NormRect
    public var text: StyledText
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        frame: NormRect,
        text: StyledText,
        isLocked: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.text = text
        self.isLocked = isLocked
    }
}
