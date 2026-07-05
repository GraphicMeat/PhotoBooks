import Foundation

/// Which photo shape a template slot was designed for. `any` matches
/// everything — used by shape-neutral slots (e.g. square-ish grid cells).
enum OrientationHint: String, Codable, Sendable {
    case landscape, portrait, square, any

    func matches(_ orientation: Orientation) -> Bool {
        self == .any || rawValue == orientation.rawValue
    }
}

/// Hand-designed layouts loaded from the bundled `templates.json`.
/// Data, not code: new templates are new JSON entries.
public struct TemplateProvider: LayoutProvider {

    struct Template: Codable, Equatable, Sendable {
        var id: String
        var photoCount: Int
        var aspectClasses: [AspectClass]
        var photoFrames: [NormRect]
        var textFrames: [NormRect]
        var orientationHints: [OrientationHint]
        var borderless: Bool = false   // tiled edge-to-edge; absent in JSON → false

        enum CodingKeys: String, CodingKey {
            case id, photoCount, aspectClasses, photoFrames, textFrames, orientationHints, borderless
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            photoCount = try c.decode(Int.self, forKey: .photoCount)
            aspectClasses = try c.decode([AspectClass].self, forKey: .aspectClasses)
            photoFrames = try c.decode([NormRect].self, forKey: .photoFrames)
            textFrames = try c.decode([NormRect].self, forKey: .textFrames)
            orientationHints = try c.decode([OrientationHint].self, forKey: .orientationHints)
            borderless = try c.decodeIfPresent(Bool.self, forKey: .borderless) ?? false
        }
    }

    private struct TemplatesFile: Decodable {
        var comment: String
        var templates: [Template]
    }

    /// A missing or invalid bundled resource is a build defect, not a runtime
    /// condition — hence `fatalError`, same policy as `PresetLibrary`.
    static let bundled: [Template] = {
        guard let url = Bundle.module.url(forResource: "templates", withExtension: "json") else {
            fatalError("PhotoBookCore: templates.json missing from bundle resources")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TemplatesFile.self, from: data).templates
        } catch {
            fatalError("PhotoBookCore: templates.json is invalid: \(error)")
        }
    }()

    private let templates: [Template]

    public init() {
        self.templates = Self.bundled
    }

    /// Templates matching the photo count and the page's aspect class, ranked
    /// by orientation fit: number of slots whose hint matches the photo that
    /// would land in them (group order). Ties break by template id so the
    /// ordering is fully deterministic.
    ///
    /// When `context.edgeStyle.isFullBleed` is true (i.e. `.borderless`), only
    /// borderless templates are returned; otherwise only non-borderless templates.
    /// This keeps normal (framed/tiled) books from receiving full-bleed template
    /// layouts, and ensures borderless pages get real template options (the
    /// generative fallback covers gaps).
    public func candidates(forPhotoCount count: Int, photos: [AnalyzedPhoto],
                           context: LayoutContext) -> [LayoutCandidate] {
        let pageClass = AspectClass.classify(context.pageSize)
        return templates
            .filter { $0.photoCount == count
                       && $0.aspectClasses.contains(pageClass)
                       && $0.borderless == context.edgeStyle.isFullBleed }
            .map { template -> (template: Template, rank: Int) in
                let matches = zip(template.orientationHints, photos)
                    .count { hint, photo in hint.matches(photo.orientation) }
                return (template, matches)
            }
            .sorted { a, b in
                if a.rank != b.rank { return a.rank > b.rank }
                return a.template.id < b.template.id
            }
            .map { ranked in
                LayoutCandidate(origin: .template(id: ranked.template.id),
                                photoSlotFrames: ranked.template.photoFrames,
                                textSlotFrames: ranked.template.textFrames)
            }
    }
}
