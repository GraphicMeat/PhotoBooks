/// One style consumed by both layout providers and both renderers.
/// Future themes = swap the style, zero relayout.
public struct BookStyle: Equatable, Sendable {
    public var pageMargin: Double          // normalized (fraction of min page dimension)
    public var gutter: Double              // normalized spacing between slots
    public var cornerRadius: Double        // normalized; 0 = square corners
    public var backgroundColorHex: String
    public var defaultFontName: String
    public var edgeStyle: EdgeStyle        // whole-book edge mode; default .framed

    public init(
        pageMargin: Double,
        gutter: Double,
        cornerRadius: Double,
        backgroundColorHex: String,
        defaultFontName: String,
        edgeStyle: EdgeStyle = .framed
    ) {
        self.pageMargin = pageMargin
        self.gutter = gutter
        self.cornerRadius = cornerRadius
        self.backgroundColorHex = backgroundColorHex
        self.defaultFontName = defaultFontName
        self.edgeStyle = edgeStyle
    }

    public static let standard = BookStyle(
        pageMargin: 0.05,
        gutter: 0.02,
        cornerRadius: 0,
        backgroundColorHex: "#FFFFFF",
        defaultFontName: "HelveticaNeue"
    )
}

// MARK: - Codable (explicit: new "edgeStyle" key, with back-compat migration
// from the legacy "borderless" Bool. Old JSON with neither key → .framed.)
extension BookStyle: Codable {
    enum CodingKeys: String, CodingKey {
        case pageMargin, gutter, cornerRadius, backgroundColorHex, defaultFontName
        case edgeStyle
        case borderless   // legacy, decode-only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pageMargin           = try c.decode(Double.self,  forKey: .pageMargin)
        gutter               = try c.decode(Double.self,  forKey: .gutter)
        cornerRadius         = try c.decode(Double.self,  forKey: .cornerRadius)
        backgroundColorHex   = try c.decode(String.self,  forKey: .backgroundColorHex)
        defaultFontName      = try c.decode(String.self,  forKey: .defaultFontName)
        if let style = try c.decodeIfPresent(EdgeStyle.self, forKey: .edgeStyle) {
            edgeStyle = style
        } else {
            // Legacy migration: borderless:true → .borderless, else → .framed.
            let legacy = try c.decodeIfPresent(Bool.self, forKey: .borderless) ?? false
            edgeStyle = legacy ? .borderless : .framed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pageMargin,         forKey: .pageMargin)
        try c.encode(gutter,             forKey: .gutter)
        try c.encode(cornerRadius,       forKey: .cornerRadius)
        try c.encode(backgroundColorHex, forKey: .backgroundColorHex)
        try c.encode(defaultFontName,    forKey: .defaultFontName)
        try c.encode(edgeStyle,          forKey: .edgeStyle)
        // legacy "borderless" key intentionally not re-emitted.
    }
}
