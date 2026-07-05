import Testing
@testable import PhotoBookCore
import Foundation

/// A per-page `backgroundColorHex` override must survive the engine's
/// page-rebuild paths (repaginate, reshuffle, revertSpread) — they reuse the
/// page id positionally and must carry the override too, exactly like
/// `edgeStyleOverride`.
@Suite struct BackgroundPreservationTests {
    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func ref(_ id: String, hours: Double) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000,
                 captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
    }
    private func book() -> Book {
        let photos = (0..<8).map { ref("bg\($0)", hours: Double($0) * 0.3) }
        return BookEngine().makeBook(title: "BG", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 4)
    }

    @Test func repaginatePreservesBackgroundOverride() throws {
        let engine = BookEngine()
        var b = book()
        // Pick a reshuffleable standard page that can increase (has a downstream run).
        let idx = try #require(b.pages.firstIndex { $0.role == .standard })
        b.pages[idx].backgroundColorHex = "#FF0000"
        let pageID = b.pages[idx].id

        let after = engine.repaginate(b, fromPageID: pageID, delta: +1,
                                      preset: Self.preset, seed: 9)
        let page = try #require(after.pages.first { $0.id == pageID })
        #expect(page.backgroundColorHex == "#FF0000")
    }

    @Test func reshufflePreservesBackgroundOverride() throws {
        let engine = BookEngine()
        var b = book()
        let idx = try #require(b.pages.firstIndex { $0.role == .standard })
        b.pages[idx].backgroundColorHex = "#00FF00"
        let pageID = b.pages[idx].id

        let after = engine.reshuffle(b, scope: .page(pageID), preset: Self.preset, seed: 11)
        let page = try #require(after.pages.first { $0.id == pageID })
        #expect(page.backgroundColorHex == "#00FF00")
    }
}
