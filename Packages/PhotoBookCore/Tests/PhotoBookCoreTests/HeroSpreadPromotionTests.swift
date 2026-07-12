import Foundation
import CryptoKit
import Testing
@testable import PhotoBookCore

/// B4: importance-driven auto-promotion of a hero photo (importance ≥ 0.80 AND
/// aspect ≥ 1.2) to a full 2-page spread, with per-cluster + spacing caps.
@Suite struct HeroSpreadPromotionTests {

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }

    private func ref(_ id: String, w: Int, h: Int, importance: Double?, hours: Double) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: w, pixelHeight: h,
                 captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600),
                 importance: importance)
    }

    private func makeBook(_ photos: [PhotoRef], seed: UInt64 = 99) -> Book {
        BookEngine().makeBook(title: "Trip", photos: photos, preset: preset,
                              style: .standard, seed: seed)
    }

    /// IDs of every photo bound into a spread's slots.
    private func spreadPhotoIDs(_ book: Book) -> Set<PhotoID> {
        Set(book.spreads.flatMap { $0.photoSlots.compactMap(\.photoID) })
    }

    // MARK: (a) single landscape hero among many mid-importance photos

    @Test func singleLandscapeHeroPromotesToOneSpread() {
        var photos = (0..<20).map {
            ref("m\($0)", w: 4000, h: 3000, importance: 0.3, hours: Double($0) * 0.1)
        }
        // Hero in the middle (not the cover lead), landscape aspect 1.5.
        photos.insert(ref("hero", w: 6000, h: 4000, importance: 0.85, hours: 1.05), at: 10)

        let book = makeBook(photos)
        #expect(book.spreads.count == 1)
        #expect(spreadPhotoIDs(book).contains(PhotoID(rawValue: "hero")))
    }

    // MARK: (b) two heroes in the SAME cluster → only one spread

    @Test func twoHeroesSameClusterYieldOneSpread() {
        var photos = (0..<8).map {
            ref("m\($0)", w: 4000, h: 3000, importance: 0.3, hours: Double($0) * 0.1)
        }
        // Both heroes share cluster 0 (all within the same 3h window).
        photos.insert(ref("heroA", w: 6000, h: 4000, importance: 0.85, hours: 0.25), at: 3)
        photos.insert(ref("heroB", w: 6000, h: 4000, importance: 0.85, hours: 0.55), at: 6)

        let book = makeBook(photos)
        #expect(book.spreads.count == 1)          // cluster cap: one hero per cluster
    }

    // MARK: (c) two heroes, different clusters, TOO CLOSE (< 6 pages) → one spread

    @Test func secondHeroWithinSpacingIsNotPromoted() {
        let photos = [
            ref("p0", w: 4000, h: 3000, importance: 0.3, hours: 0.0),   // cover lead + cluster 0
            ref("p1", w: 4000, h: 3000, importance: 0.3, hours: 0.1),
            ref("p2", w: 4000, h: 3000, importance: 0.3, hours: 0.2),
            ref("heroA", w: 6000, h: 4000, importance: 0.85, hours: 0.3),  // cluster 0
            ref("heroB", w: 6000, h: 4000, importance: 0.85, hours: 6.0),  // cluster 1 (>3h gap)
        ]
        let book = makeBook(photos)
        #expect(book.spreads.count == 1)          // spacing cap blocks heroB
        #expect(spreadPhotoIDs(book).contains(PhotoID(rawValue: "heroA")))
        #expect(!spreadPhotoIDs(book).contains(PhotoID(rawValue: "heroB")))
    }

    // MARK: (d) two heroes, different clusters, FAR APART (≥ 6 pages) → both promoted

    @Test func secondHeroBeyondSpacingIsPromoted() {
        var photos: [PhotoRef] = [
            ref("p0", w: 4000, h: 3000, importance: 0.3, hours: 0.0),
            ref("heroA", w: 6000, h: 4000, importance: 0.85, hours: 0.2),  // cluster 0
        ]
        // 40 spacer photos in cluster 1 → well over 6 standard pages between heroes.
        photos += (0..<40).map {
            ref("s\($0)", w: 4000, h: 3000, importance: 0.3, hours: 6.0 + Double($0) * 0.05)
        }
        photos.append(ref("heroB", w: 6000, h: 4000, importance: 0.85, hours: 12.0))  // cluster 2

        let book = makeBook(photos)
        #expect(book.spreads.count == 2)
        let ids = spreadPhotoIDs(book)
        #expect(ids.contains(PhotoID(rawValue: "heroA")))
        #expect(ids.contains(PhotoID(rawValue: "heroB")))
    }

    // MARK: (e) portrait hero (aspect < 1.2) is NOT promoted

    @Test func portraitHeroIsNotPromoted() {
        var photos = (0..<8).map {
            ref("m\($0)", w: 4000, h: 3000, importance: 0.3, hours: Double($0) * 0.1)
        }
        // High importance but portrait (aspect 0.7) → fails the aspect gate.
        photos.insert(ref("tall", w: 2100, h: 3000, importance: 0.85, hours: 0.35), at: 4)

        let book = makeBook(photos)
        #expect(book.spreads.isEmpty)
    }

    // MARK: (f) no-hero book is BYTE-IDENTICAL to the pre-B4 baseline

    /// Mixed aspects + importance values, none meeting (importance ≥ 0.80 AND
    /// aspect ≥ 1.2): a near-landscape below threshold (0.7 / 1.5) and a
    /// high-importance PORTRAIT (0.85 / 0.7) both exercise the promotion guard
    /// without ever firing it. Hash captured from pre-B4 code; must not move.
    private func noHeroFixture() -> [PhotoRef] {
        [
            ref("a", w: 4000, h: 3000, importance: 0.2, hours: 0.0),
            ref("b", w: 3000, h: 4000, importance: 0.5, hours: 0.2),
            ref("c", w: 6000, h: 4000, importance: 0.7, hours: 0.4),   // landscape 1.5, below imp threshold
            ref("d", w: 3000, h: 3000, importance: 0.1, hours: 0.6),
            ref("e", w: 2100, h: 3000, importance: 0.85, hours: 5.0),  // portrait 0.7, fails aspect gate
            ref("f", w: 4000, h: 3000, importance: 0.3, hours: 5.2),
            ref("g", w: 4000, h: 3000, importance: 0.6, hours: 5.4),
            ref("h", w: 3000, h: 4000, importance: nil, hours: 5.6),
            ref("i", w: 4000, h: 3000, importance: 0.4, hours: 10.0),
            ref("j", w: 3000, h: 4000, importance: 0.55, hours: 10.2),
        ]
    }

    @Test func noHeroBookIsByteIdenticalToBaseline() throws {
        let data = try BookSerializer.encode(makeBook(noHeroFixture(), seed: 99))
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // Baseline hash from pre-B4 code (see test doc). If you intentionally
        // changed engine or serialization output, re-capture this hash from the
        // new baseline; an UNEXPECTED change here is a determinism regression.
        #expect(hex == "d00433d7f3104350e3d8f8e317aacb0934fb7b5fc6377efc84a441d68311eae6")
    }
}
