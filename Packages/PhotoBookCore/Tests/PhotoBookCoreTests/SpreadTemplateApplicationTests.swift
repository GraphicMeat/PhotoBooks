import Foundation
import Testing
import PhotoBookCore

/// Task B5: `BookEngine.spreadLayoutOptions` + `applySpreadTemplate`. Builds
/// spread fixtures directly (spread + sliced member pages), mirroring
/// `Spread.slice()`'s own contract, so the count/order of bound photos is
/// fully controlled without depending on pagination.
@Suite struct SpreadTemplateApplicationTests {

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }

    private func ref(_ id: String, width: Int = 4000, height: Int = 3000,
                     salientCenter: NormPoint? = nil) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: width, pixelHeight: height, salientCenter: salientCenter)
    }

    /// A book with exactly one spread whose photos (in order) are `ids`, plus
    /// its two sliced member pages. Original frames are arbitrary equal-width
    /// columns — only the photoID *order* in `spread.photoSlots` matters for
    /// `applySpreadTemplate`.
    private func bookWithSpread(_ refs: [PhotoRef]) -> (book: Book, spreadID: UUID) {
        let n = refs.count
        let slots = refs.enumerated().map { i, ref in
            SpreadPhotoSlot(frame: NormRect(x: Double(i) / Double(n), y: 0,
                                            width: 1.0 / Double(n), height: 1),
                            photoID: ref.id)
        }
        let spreadID = UUID()
        let spread = Spread(id: spreadID,
                            origin: .generated(GeneratedLayoutParams(seed: 1, boxes: slots.map(\.frame))),
                            photoSlots: slots, textSlots: [])
        let sliced = spread.slice()
        let leftPage = Page(role: .standard, origin: spread.origin,
                            photoSlots: sliced.left.photoSlots, textSlots: sliced.left.textSlots,
                            spreadID: spreadID, half: .left)
        let rightPage = Page(role: .standard, origin: spread.origin,
                             photoSlots: sliced.right.photoSlots, textSlots: sliced.right.textSlots,
                             spreadID: spreadID, half: .right)
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.photoLibrary = refs
        book.pages = [leftPage, rightPage]
        book.spreads = [spread]
        return (book, spreadID)
    }

    // MARK: - spreadLayoutOptions

    @Test func optionsForThreePhotoSpreadIncludeAllThreeCountTemplates() {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let options = engine.spreadLayoutOptions(for: spreadID, in: book, preset: preset)
        let ids = Set(options.map(\.id))
        #expect(ids.isSuperset(of: [
            "spread-center-columns-3", "spread-split-two-thirds-3",
            "spread-panorama-band-3", "spread-three-up", "spread-hero-strip"
        ]))
        #expect(options.allSatisfy { $0.photoCount == 3 })
    }

    @Test func optionsExcludeMismatchedCounts() {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let options = engine.spreadLayoutOptions(for: spreadID, in: book, preset: preset)
        let ids = Set(options.map(\.id))
        #expect(!ids.contains("spread-panorama"))       // count 1
        #expect(!ids.contains("spread-two-up"))         // count 2
        #expect(!ids.contains("spread-split-two-thirds")) // count 2
        #expect(!ids.contains("spread-center-columns-5")) // count 5
    }

    @Test func optionsForUnknownSpreadIDAreEmpty() {
        let engine = BookEngine()
        let (book, _) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        #expect(engine.spreadLayoutOptions(for: UUID(), in: book, preset: preset).isEmpty)
    }

    // MARK: - applySpreadTemplate

    @Test func applyRebindsSamePhotoIDsInTemplateSlotOrder() throws {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("spread-center-columns-3", to: spreadID,
                                                in: book, preset: preset)
        let spread = try #require(result.spreads.first { $0.id == spreadID })
        #expect(spread.photoSlots.map(\.photoID) == [PhotoID(rawValue: "a"),
                                                      PhotoID(rawValue: "b"),
                                                      PhotoID(rawValue: "c")])

        let template = try #require(
            SpreadTemplateProvider().rawTemplates(forPhotoCount: 3)
                .first { $0.id == "spread-center-columns-3" })
        #expect(spread.photoSlots.map(\.frame) == template.photoFrames)
        if case .template(let id) = spread.origin {
            #expect(id == "spread-center-columns-3")
        } else {
            Issue.record("expected .template origin")
        }
    }

    @Test func applyReslicesMemberPagesConsistently() throws {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("spread-center-columns-3", to: spreadID,
                                                in: book, preset: preset)
        let spread = try #require(result.spreads.first { $0.id == spreadID })
        let expectedSliced = spread.slice()
        let left = try #require(result.pages.first { $0.spreadID == spreadID && $0.half == .left })
        let right = try #require(result.pages.first { $0.spreadID == spreadID && $0.half == .right })
        #expect(left.photoSlots == expectedSliced.left.photoSlots)
        #expect(right.photoSlots == expectedSliced.right.photoSlots)
    }

    @Test func applyTwiceIsByteIdentical() throws {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let first = engine.applySpreadTemplate("spread-hero-strip", to: spreadID, in: book, preset: preset)
        let second = engine.applySpreadTemplate("spread-hero-strip", to: spreadID, in: first, preset: preset)
        // Re-applying the SAME template to its own already-applied result must
        // be a byte-identical no-change (idempotent apply).
        #expect(try BookSerializer.encode(first) == BookSerializer.encode(second))

        // And applying fresh from the original book twice independently also
        // produces byte-identical results.
        let a = engine.applySpreadTemplate("spread-three-up", to: spreadID, in: book, preset: preset)
        let b = engine.applySpreadTemplate("spread-three-up", to: spreadID, in: book, preset: preset)
        #expect(try BookSerializer.encode(a) == BookSerializer.encode(b))
    }

    @Test func applyWithMismatchedCountIsANoOp() {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        // "spread-two-up" is a count-2 template; the spread has 3 photos.
        let result = engine.applySpreadTemplate("spread-two-up", to: spreadID, in: book, preset: preset)
        #expect(result == book)
    }

    @Test func applyWithUnknownTemplateIDIsANoOp() {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("does-not-exist", to: spreadID, in: book, preset: preset)
        #expect(result == book)
    }

    @Test func applyWithUnknownSpreadIDIsANoOp() {
        let engine = BookEngine()
        let (book, _) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("spread-center-columns-3", to: UUID(),
                                                in: book, preset: preset)
        #expect(result == book)
    }

    // MARK: - Gutter-safe crop wiring

    /// `spread-panorama-band-3`'s first slot ({x:0,y:0.25,w:1,h:0.5}) straddles
    /// the gutter. A photo with a dead-center salient point must get a
    /// gutter-safe (non-`.full`) crop on that slot, mirroring `buildSpread`'s
    /// wiring of `GutterSafeCrop`.
    @Test func gutterSafeCropAppliedToStraddlingSlotWithSalientCenter() throws {
        let engine = BookEngine()
        // Ultra-wide photo (aspect 12) so it has slack against the band slot's
        // own aspect (width 1 / height 0.5 on a 2.5 spreadAspect canvas → 5.0).
        let wide = ref("wide", width: 12000, height: 1000, salientCenter: NormPoint(x: 0.5, y: 0.5))
        let (book, spreadID) = bookWithSpread([wide, ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("spread-panorama-band-3", to: spreadID,
                                                in: book, preset: preset)
        let spread = try #require(result.spreads.first { $0.id == spreadID })
        let straddling = try #require(spread.photoSlots.first { $0.photoID == wide.id })
        #expect(straddling.crop != .full)
    }

    @Test func nonStraddlingOrNoSalientCenterKeepsFullCrop() throws {
        let engine = BookEngine()
        let (book, spreadID) = bookWithSpread([ref("a"), ref("b"), ref("c")])
        let result = engine.applySpreadTemplate("spread-center-columns-3", to: spreadID,
                                                in: book, preset: preset)
        let spread = try #require(result.spreads.first { $0.id == spreadID })
        // None of these photos carry a salientCenter, so every slot stays .full.
        #expect(spread.photoSlots.allSatisfy { $0.crop == .full })
    }
}
