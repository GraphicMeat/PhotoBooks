import Foundation

/// Templates target an aspect class, not an exact trim size. Preset switches
/// within the same class are instant (normalized coords just rescale);
/// cross-class switches trigger relayout.
public enum AspectClass: String, Codable, Sendable {
    case square, landscape, portrait
}

/// A print service page format. Data-driven: new services/sizes are new
/// entries in presets.json, no code changes.
public struct PrintPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String                  // e.g. "blurb-small-square"
    public var displayName: String
    public var trimSize: SizeInches
    public var bleed: Double               // inches, each edge
    public var safeMargin: Double          // inches, from trim
    public var minPages: Int
    public var maxPages: Int
    public var spineBase: Double           // spine inches = spineBase + spinePerPage * pageCount
    public var spinePerPage: Double

    public init(
        id: String,
        displayName: String,
        trimSize: SizeInches,
        bleed: Double,
        safeMargin: Double,
        minPages: Int,
        maxPages: Int,
        spineBase: Double,
        spinePerPage: Double
    ) {
        self.id = id
        self.displayName = displayName
        self.trimSize = trimSize
        self.bleed = bleed
        self.safeMargin = safeMargin
        self.minPages = minPages
        self.maxPages = maxPages
        self.spineBase = spineBase
        self.spinePerPage = spinePerPage
    }

    /// Derived from trim size — computed, never encoded. Square wins inside
    /// a 5% tolerance band (matches the engine's orientation tolerance).
    public var aspectClass: AspectClass {
        let aspect = trimSize.aspectRatio
        if abs(aspect - 1) < 0.05 { return .square }
        return aspect > 1 ? .landscape : .portrait
    }
}

/// Loads the bundled presets.json. A missing or invalid bundled resource is
/// a build defect, not a runtime condition — hence `fatalError`, not `throws`
/// (the contract pins `all()` and `preset(id:)` as non-throwing).
public enum PresetLibrary {

    private struct PresetsFile: Decodable {
        var comment: String
        var presets: [PrintPreset]
    }

    private static let presets: [PrintPreset] = {
        guard let url = Bundle.module.url(forResource: "presets", withExtension: "json") else {
            fatalError("PhotoBookCore: presets.json missing from bundle resources")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PresetsFile.self, from: data).presets
        } catch {
            fatalError("PhotoBookCore: presets.json is invalid: \(error)")
        }
    }()

    public static func all() -> [PrintPreset] {
        presets
    }

    public static func preset(id: String) -> PrintPreset? {
        presets.first { $0.id == id }
    }
}
