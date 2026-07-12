import Foundation

/// The document root. Serialized as `book.json` inside the `.photobook`
/// package by the app layer (Plan 4).
public struct Book: Codable, Equatable, Sendable {
    /// Bumped 1 → 2 for first-class spreads (the `spreads` registry and per-page
    /// `spreadID`/`half` bindings). v1 documents migrate forward by gaining an
    /// empty registry and nil bindings.
    ///
    /// Bumped 2 → 3 for per-photo content importance (`PhotoRef.importance`).
    /// The field is optional and additive, so a v2 document decodes unchanged
    /// (absent key → nil); the migration only re-stamps the version.
    ///
    /// Bumped 3 → 4 for the back-cover page (`backCover`). Optional and additive:
    /// a v3 document decodes with `backCover == nil`; the migration only
    /// re-stamps the version.
    ///
    /// v4→v5: PhotoRef.salientCenter (optional, additive — decodeIfPresent → nil)
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var title: String
    public var presetID: String
    public var style: BookStyle
    public var photoLibrary: [PhotoRef]
    public var pages: [Page]               // pages[0] with role == .cover when present
    public var spreads: [Spread]           // first-class 2-page spreads; pages bind via spreadID
    /// The back cover: a `role == .backCover` page (full-bleed photo, no text).
    /// Part of the cover *sheet*, NOT the interior `pages[]` reading flow, so
    /// pagination/spread-pairing never touch it. `nil` = plain background back
    /// (books with ≤1 photo, or pre-v4 documents until rebuilt).
    public var backCover: Page?

    public init(title: String, presetID: String, style: BookStyle) {
        self.schemaVersion = Book.currentSchemaVersion
        self.title = title
        self.presetID = presetID
        self.style = style
        self.photoLibrary = []
        self.pages = []
        self.spreads = []
        self.backCover = nil
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, title, presetID, style, photoLibrary, pages, spreads, backCover
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        title         = try c.decode(String.self, forKey: .title)
        presetID      = try c.decode(String.self, forKey: .presetID)
        style         = try c.decode(BookStyle.self, forKey: .style)
        photoLibrary  = try c.decode([PhotoRef].self, forKey: .photoLibrary)
        pages         = try c.decode([Page].self, forKey: .pages)
        // Absent in pre-spread (v1) JSON → empty registry (back-compat).
        spreads       = try c.decodeIfPresent([Spread].self, forKey: .spreads) ?? []
        // Absent in pre-v4 JSON → nil (back-compat).
        backCover     = try c.decodeIfPresent(Page.self, forKey: .backCover)
    }
}

public enum BookSerializerError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case corruptData(String)
}

/// Deterministic serialization: pretty-printed JSON with stable (sorted) key
/// order, so identical books encode to identical bytes — the foundation of
/// the "same inputs + same seed = identical Book" invariant.
public enum BookSerializer {

    public static func encode(_ book: Book) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(book)
    }

    public static func decode(_ data: Data) throws -> Book {
        let decoder = JSONDecoder()

        // 1. Probe only the schema version (tolerates unknown future keys).
        let version: Int
        do {
            version = try decoder.decode(SchemaProbe.self, from: data).schemaVersion
        } catch {
            throw BookSerializerError.corruptData("Cannot read schemaVersion: \(error)")
        }

        // 2. Gate: only versions 1...current are decodable.
        guard version >= 1, version <= Book.currentSchemaVersion else {
            throw BookSerializerError.unsupportedSchemaVersion(version)
        }

        // 3. Run migrations (no-op while currentSchemaVersion == 1).
        let migrated = try migrate(data, from: version)

        // 4. Full decode.
        do {
            return try decoder.decode(Book.self, from: migrated)
        } catch {
            throw BookSerializerError.corruptData("Cannot decode Book: \(error)")
        }
    }

    private struct SchemaProbe: Decodable {
        var schemaVersion: Int
    }

    /// Migration scaffold: applies one step per version until current. Each
    /// step (see `migrationStep`) advances the payload one version; a v1
    /// document chains v1 → v2 → v3.
    private static func migrate(_ data: Data, from version: Int) throws -> Data {
        var data = data
        var version = version
        while version < Book.currentSchemaVersion {
            data = try migrationStep(data, from: version)
            version += 1
        }
        return data
    }

    /// One migration step: transforms version `version` JSON into version
    /// `version + 1` JSON.
    private static func migrationStep(_ data: Data, from version: Int) throws -> Data {
        switch version {
        case 1:
            // 1 → 2: first-class spreads. A v1 book has no `spreads` registry
            // and no per-page `spreadID`/`half`; the absent keys already decode
            // to empty/nil via `decodeIfPresent`, so this step only injects an
            // empty registry and re-stamps the version.
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BookSerializerError.corruptData("v1 payload is not a JSON object")
            }
            if object["spreads"] == nil { object["spreads"] = [] }
            object["schemaVersion"] = 2
            return try JSONSerialization.data(withJSONObject: object)
        case 2:
            // 2 → 3: per-photo importance. `PhotoRef.importance` is optional and
            // absent in v2 JSON; it decodes to nil via the synthesized
            // decodeIfPresent. This step only re-stamps the version.
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BookSerializerError.corruptData("v2 payload is not a JSON object")
            }
            object["schemaVersion"] = 3
            return try JSONSerialization.data(withJSONObject: object)
        case 3:
            // 3 → 4: back cover. `backCover` is optional and absent in v3 JSON;
            // it decodes to nil via decodeIfPresent. This step only re-stamps.
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BookSerializerError.corruptData("v3 payload is not a JSON object")
            }
            object["schemaVersion"] = 4
            return try JSONSerialization.data(withJSONObject: object)
        case 4:
            // 4 → 5: photo salient center. `PhotoRef.salientCenter` is optional
            // and absent in v4 JSON; it decodes to nil via decodeIfPresent.
            // This step only re-stamps the version.
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BookSerializerError.corruptData("v4 payload is not a JSON object")
            }
            object["schemaVersion"] = 5
            return try JSONSerialization.data(withJSONObject: object)
        default:
            throw BookSerializerError.unsupportedSchemaVersion(version)
        }
    }
}
