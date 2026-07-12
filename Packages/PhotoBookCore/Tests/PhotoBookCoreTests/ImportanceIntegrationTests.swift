import Foundation
import Testing
import PhotoBookCore

/// End-to-end contract for importance-based page density:
/// PhotoRef.importance → PhotoAnalyzer derives AnalyzedPhoto.weight via
/// ImportanceWeight → Paginator groups by summed weight, so a hero photo
/// (importance ≥ 0.80 → weight == Paginator.maxWeightPerPage) takes a page to
/// itself. Persistence + weight-derivation are unit-tested in isolation
/// elsewhere; this suite locks the full makeBook → persist → reopen → relayout
/// round-trip so the seams can't drift apart.
@Suite struct ImportanceIntegrationTests {

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }
    private let heroID = PhotoID(rawValue: "hero")

    /// 8 single-cluster photos. The hero (importance 0.9) sits in the middle of
    /// the sequence — deliberately NOT first, so it is not the cover lead and
    /// therefore appears on exactly one page. Every other photo has nil
    /// importance → weight 1. The hero is PORTRAIT (aspect 0.75) so it exercises
    /// importance → density (weight → solo page) WITHOUT tripping hero-spread
    /// promotion, which needs a near-landscape aspect (≥ heroAspectThreshold).
    private func photos() -> [PhotoRef] {
        (0..<8).map { i in
            let isHero = (i == 3)
            return PhotoRef(
                id: isHero ? heroID : PhotoID(rawValue: "p\(i)"),
                source: .file(bookmark: Data()),
                pixelWidth: isHero ? 3000 : 4000, pixelHeight: isHero ? 4000 : 3000,
                captureDate: Date(timeIntervalSinceReferenceDate: Double(i) * 0.2 * 3600),
                importance: isHero ? 0.9 : nil)
        }
    }

    /// True when the hero appears on exactly one page and that page holds only
    /// the hero (compactMap drops any empty slots, so extra unbound slots in a
    /// solo template don't matter).
    private func heroIsSolo(in book: Book) -> Bool {
        let heroPages = book.pages.filter { page in
            page.photoSlots.contains { $0.photoID == heroID }
        }
        guard heroPages.count == 1 else { return false }
        return heroPages[0].photoSlots.compactMap(\.photoID) == [heroID]
    }

    @Test func heroGetsSoloPageFromImportance() {
        let book = BookEngine().makeBook(title: "Trip", photos: photos(),
                                         preset: preset, style: .standard, seed: 99)
        #expect(heroIsSolo(in: book))
    }

    @Test func importanceSurvivesSaveLoadAndRelayout() throws {
        let book = BookEngine().makeBook(title: "Trip", photos: photos(),
                                         preset: preset, style: .standard, seed: 99)
        #expect(heroIsSolo(in: book))

        // Round-trip through serialization: the importance signal persists on
        // the ref, and the laid-out solo page survives reopening as-is.
        let decoded = try BookSerializer.decode(BookSerializer.encode(book))
        let heroRef = decoded.photoLibrary.first { $0.id == heroID }
        #expect(heroRef?.importance == 0.9)
        #expect(heroIsSolo(in: decoded))

        // Editing the reopened book re-derives weight from the persisted
        // importance (Vision never re-runs): a book-scope reshuffle keeps the
        // hero solo.
        let reshuffled = BookEngine().reshuffle(decoded, scope: .book,
                                                preset: preset, seed: 31)
        #expect(heroIsSolo(in: reshuffled))

        // And a fresh layout built purely from the decoded photoLibrary
        // reproduces the hero-solo page — proving the persisted importance
        // number alone drives analyze → weight → pagination end-to-end.
        let relaid = BookEngine().makeBook(title: "Trip", photos: decoded.photoLibrary,
                                           preset: preset, style: .standard, seed: 7)
        #expect(heroIsSolo(in: relaid))
    }
}
