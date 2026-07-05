import CoreGraphics
import Foundation
import PhotoBookCore
import Synchronization
@testable import PhotoBookRender

/// Deterministic fixtures for the export suites: a Blurb Small Square book
/// (cover + N standard pages, one photo slot + optional text slot each) and
/// an in-memory ImageStore of solid-color images.
enum ExportFixtures {

    /// The bundled preset every geometry golden in Plan 6 is computed from.
    /// `fixturePresetMatchesBlurbSmallSquareData` pins its numbers.
    static let preset = PresetLibrary.preset(id: "blurb-small-square")!

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static func photoRef(_ n: Int, pixelWidth: Int = 1600, pixelHeight: Int = 1600,
                         isMissing: Bool = false) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: "p\(n)"), source: .file(bookmark: Data()),
                 pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                 captureDate: nil, isMissing: isMissing)
    }

    /// Cover (full-bleed photo + title text, like Plan 2's cover-hero) +
    /// `standardCount` standard pages, page n holding photo p(n) in a
    /// centered half-size slot. Library = p0 (cover) … p(standardCount).
    static func book(standardCount: Int, title: String = "Fixture") -> Book {
        var book = Book(title: title, presetID: preset.id, style: .standard)
        book.photoLibrary = (0...standardCount).map { photoRef($0) }
        var pages: [Page] = [
            Page(id: uuid(1000), role: .cover, origin: .template(id: "cover-hero"),
                 photoSlots: [PhotoSlot(id: uuid(1001), frame: .full,
                                        photoID: PhotoID(rawValue: "p0"),
                                        crop: .full, isLocked: false)],
                 textSlots: [TextSlot(id: uuid(1002),
                                      frame: NormRect(x: 0.08, y: 0.40, width: 0.84, height: 0.20),
                                      text: StyledText(string: title, fontName: "",
                                                       pointSizeFactor: 0.07,
                                                       colorHex: "#FFFFFF", alignment: .center),
                                      isLocked: false)],
                 isLocked: false)
        ]
        for n in 1...standardCount {
            pages.append(Page(
                id: uuid(n), role: .standard, origin: .template(id: "hero-inset"),
                photoSlots: [PhotoSlot(id: uuid(2000 + n),
                                       frame: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                       photoID: PhotoID(rawValue: "p\(n)"),
                                       crop: .full, isLocked: false)],
                textSlots: [], isLocked: false))
        }
        book.pages = pages
        return book
    }

    static func solidImage(width: Int, height: Int,
                           red: CGFloat = 0.8, green: CGFloat = 0.2, blue: CGFloat = 0.2) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// In-memory store: every library photo of `book` resolves to a solid
    /// image at its ref's pixel dimensions.
    static func store(for book: Book) -> StubImageStore {
        var images: [PhotoID: CGImage] = [:]
        for ref in book.photoLibrary {
            images[ref.id] = solidImage(width: ref.pixelWidth, height: ref.pixelHeight)
        }
        return StubImageStore(images: images)
    }

    static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photobooks-test-\(name)-\(UUID().uuidString).pdf")
    }
}

struct StubImageStore: ImageStore {
    var images: [PhotoID: CGImage]
    struct Missing: Error { let id: PhotoID }

    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
        try await fullImage(for: id)
    }
    func fullImage(for id: PhotoID) async throws -> CGImage {
        guard let image = images[id] else { throw Missing(id: id) }
        return image
    }
}

/// Fails exactly the given IDs; everything else resolves like the base store.
struct FailingImageStore: ImageStore {
    var base: StubImageStore
    var failingIDs: Set<PhotoID>
    struct Failure: Error {}

    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
        try await fullImage(for: id)
    }
    func fullImage(for id: PhotoID) async throws -> CGImage {
        if failingIDs.contains(id) { throw Failure() }
        return try await base.fullImage(for: id)
    }
}

/// Thread-safe progress capture (the exporter's callback is @Sendable).
final class ProgressRecorder: Sendable {
    private let storage = Mutex<[Double]>([])
    func record(_ value: Double) {
        storage.withLock { $0.append(value) }
    }
    var values: [Double] {
        storage.withLock { $0 }
    }
}
