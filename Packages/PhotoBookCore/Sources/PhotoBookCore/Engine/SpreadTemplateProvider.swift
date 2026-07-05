import Foundation

/// Hand-designed 2-page spread layouts loaded from the bundled
/// `spread-templates.json`. Templates live on the DOUBLE-WIDE canvas (x spans
/// both facing pages, gutter at x=0.5); each yields a `Spread` blueprint whose
/// slots carry no photo until the engine binds them. Data, not code: new
/// spread layouts are new JSON entries.
public struct SpreadTemplateProvider: Sendable {

    struct Template: Codable, Equatable, Sendable {
        var id: String
        var photoCount: Int
        var photoFrames: [NormRect]
        var textFrames: [NormRect]
    }

    private struct TemplatesFile: Decodable {
        var comment: String
        var templates: [Template]
    }

    /// A missing or invalid bundled resource is a build defect, not a runtime
    /// condition — hence `fatalError`, same policy as `TemplateProvider`.
    static let bundled: [Template] = {
        guard let url = Bundle.module.url(forResource: "spread-templates", withExtension: "json") else {
            fatalError("PhotoBookCore: spread-templates.json missing from bundle resources")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TemplatesFile.self, from: data).templates
        } catch {
            fatalError("PhotoBookCore: spread-templates.json is invalid: \(error)")
        }
    }()

    private let templateList: [Template]

    public init() {
        self.templateList = Self.bundled
    }

    /// Every bundled spread blueprint, in file order (sorted by photoCount then
    /// id for a stable, deterministic ordering).
    public var allTemplates: [Spread] {
        templateList
            .sorted { a, b in
                if a.photoCount != b.photoCount { return a.photoCount < b.photoCount }
                return a.id < b.id
            }
            .map(Self.blueprint)
    }

    /// Spread blueprints whose photo count matches `count`, ordered by id for
    /// determinism. Slots carry no photoID — the engine binds photos at use.
    public func templates(forPhotoCount count: Int) -> [Spread] {
        templateList
            .filter { $0.photoCount == count }
            .sorted { $0.id < $1.id }
            .map(Self.blueprint)
    }

    private static func blueprint(_ template: Template) -> Spread {
        Spread(
            id: UUID(),
            origin: .template(id: template.id),
            photoSlots: template.photoFrames.map { SpreadPhotoSlot(frame: $0) },
            textSlots: template.textFrames.map {
                SpreadTextSlot(frame: $0,
                               text: StyledText(string: "", pointSizeFactor: 0.04))
            })
    }
}
