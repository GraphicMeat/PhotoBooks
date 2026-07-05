import Foundation

/// Stable identity of a photo within a book, independent of its source.
public struct PhotoID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Encode as a bare JSON string ("abc"), not a keyed container.
    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where a photo's original lives. Originals are referenced, never copied
/// (PhotoKit local identifiers / security-scoped file bookmarks).
public enum PhotoSource: Codable, Hashable, Sendable {
    case photoKit(localIdentifier: String)
    case file(bookmark: Data)
}

/// A reference to one photo: identity, source, and the metadata the layout
/// engine needs (pixel dimensions for aspect, capture date for sequencing).
public struct PhotoRef: Codable, Hashable, Sendable, Identifiable {
    public var id: PhotoID
    public var source: PhotoSource
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var captureDate: Date?          // nil = unknown; fallback ordering = library order
    public var isMissing: Bool             // asset deleted / bookmark stale
    /// On-device content-importance estimate in [0,1]; nil = not analyzed
    /// (treated as a normal, weight-1 photo). Populated by the import-time
    /// Vision pre-pass (ImageContentAnalyzer); consumed by ImportanceWeight.
    public var importance: Double?
    /// User override of the layout weight (how many photos share this photo's
    /// page). nil = derive from `importance` as before. Set by the editor's
    /// Bigger / Smaller / Make key actions; clamped to [1, ImportanceWeight.maxWeight].
    /// A larger weight lands the photo on a less-crowded page, so it appears bigger.
    public var userWeight: Int?

    public init(
        id: PhotoID,
        source: PhotoSource,
        pixelWidth: Int,
        pixelHeight: Int,
        captureDate: Date? = nil,
        isMissing: Bool = false,
        importance: Double? = nil,
        userWeight: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.captureDate = captureDate
        self.isMissing = isMissing
        self.importance = importance
        self.userWeight = userWeight
    }

    public var aspectRatio: Double { Double(pixelWidth) / Double(pixelHeight) }
}
