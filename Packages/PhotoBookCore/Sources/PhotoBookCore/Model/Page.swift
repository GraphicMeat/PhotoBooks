import Foundation

/// Serialized result of the generative layout provider. Spec invariant:
/// generated layouts serialize their params (seed + partition boxes), so
/// reopening a document never re-runs layout and never drifts.
public struct GeneratedLayoutParams: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var boxes: [NormRect]

    public init(seed: UInt64, boxes: [NormRect]) {
        self.seed = seed
        self.boxes = boxes
    }
}

/// Which provider produced a page's layout.
public enum LayoutOrigin: Codable, Equatable, Sendable {
    case template(id: String)
    case generated(GeneratedLayoutParams)
}

public enum PageRole: String, Codable, Sendable {
    case standard, cover, backCover
}

/// One page of the book. The cover is a dedicated page with `role == .cover`
/// (front photo + title + spine text), kept at `pages[0]` when present.
public struct Page: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var role: PageRole
    public var origin: LayoutOrigin
    public var photoSlots: [PhotoSlot]
    public var textSlots: [TextSlot]
    public var isLocked: Bool              // page-level lock (slot locks are separate)
    /// Per-page edge-style override. `nil` = inherit from `book.style.edgeStyle`.
    public var edgeStyleOverride: EdgeStyle?
    /// When this page is one half of a first-class spread, the owning spread's
    /// id; `nil` for an independent page. Absent in JSON → nil (back-compat).
    public var spreadID: UUID?
    /// Which half of the owning spread this page renders. `nil` when `spreadID`
    /// is nil. Absent in JSON → nil (back-compat).
    public var half: SpreadHalf?
    /// Per-page background override. `nil` = inherit `book.style.backgroundColorHex`.
    /// Absent in JSON → nil (synthesized Codable, back-compat — same as the
    /// other optional fields above).
    public var backgroundColorHex: String?

    public init(
        id: UUID = UUID(),
        role: PageRole = .standard,
        origin: LayoutOrigin,
        photoSlots: [PhotoSlot] = [],
        textSlots: [TextSlot] = [],
        isLocked: Bool = false,
        edgeStyleOverride: EdgeStyle? = nil,
        spreadID: UUID? = nil,
        half: SpreadHalf? = nil,
        backgroundColorHex: String? = nil
    ) {
        self.id = id
        self.role = role
        self.origin = origin
        self.photoSlots = photoSlots
        self.textSlots = textSlots
        self.isLocked = isLocked
        self.edgeStyleOverride = edgeStyleOverride
        self.spreadID = spreadID
        self.half = half
        self.backgroundColorHex = backgroundColorHex
    }

    /// The background hex actually painted for this page: the per-page
    /// override, or the supplied book default when no override is set.
    public func effectiveBackgroundHex(bookDefault: String) -> String {
        backgroundColorHex ?? bookDefault
    }
}

// MARK: - Codable (explicit: migrate legacy "borderlessOverride" Bool? →
// "edgeStyleOverride" EdgeStyle?. All other fields decode as before; absent
// optional keys stay nil for back-compat.)
extension Page {
    enum CodingKeys: String, CodingKey {
        case id, role, origin, photoSlots, textSlots, isLocked
        case edgeStyleOverride
        case borderlessOverride   // legacy, decode-only
        case spreadID, half, backgroundColorHex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        role       = try c.decode(PageRole.self, forKey: .role)
        origin     = try c.decode(LayoutOrigin.self, forKey: .origin)
        photoSlots = try c.decode([PhotoSlot].self, forKey: .photoSlots)
        textSlots  = try c.decodeIfPresent([TextSlot].self, forKey: .textSlots) ?? []
        isLocked   = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        if let style = try c.decodeIfPresent(EdgeStyle.self, forKey: .edgeStyleOverride) {
            edgeStyleOverride = style
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .borderlessOverride) {
            edgeStyleOverride = legacy ? .borderless : .framed
        } else {
            edgeStyleOverride = nil
        }
        spreadID           = try c.decodeIfPresent(UUID.self, forKey: .spreadID)
        half               = try c.decodeIfPresent(SpreadHalf.self, forKey: .half)
        backgroundColorHex = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(origin, forKey: .origin)
        try c.encode(photoSlots, forKey: .photoSlots)
        try c.encode(textSlots, forKey: .textSlots)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encodeIfPresent(edgeStyleOverride, forKey: .edgeStyleOverride)
        try c.encodeIfPresent(spreadID, forKey: .spreadID)
        try c.encodeIfPresent(half, forKey: .half)
        try c.encodeIfPresent(backgroundColorHex, forKey: .backgroundColorHex)
        // legacy "borderlessOverride" intentionally not re-emitted.
    }
}
