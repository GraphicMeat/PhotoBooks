import Foundation
import Testing
import PhotoBookCore

@Suite struct BookEngineTests {

    /// 14 photos: three time clusters, mixed orientations, two undated
    /// photos at the end — exercises every analyzer path.
    private func fixturePhotos() -> [PhotoRef] {
        func ref(_ id: String, width: Int, height: Int, hours: Double?) -> PhotoRef {
            PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                     pixelWidth: width, pixelHeight: height,
                     captureDate: hours.map { Date(timeIntervalSinceReferenceDate: $0 * 3600) })
        }
        return [
            ref("p01", width: 4000, height: 3000, hours: 0),
            ref("p02", width: 3000, height: 4000, hours: 0.2),
            ref("p03", width: 3000, height: 3000, hours: 0.4),
            ref("p04", width: 4000, height: 3000, hours: 0.6),
            ref("p05", width: 3000, height: 4000, hours: 5),
            ref("p06", width: 4000, height: 3000, hours: 5.2),
            ref("p07", width: 4000, height: 3000, hours: 5.4),
            ref("p08", width: 3000, height: 4000, hours: 5.6),
            ref("p09", width: 6000, height: 2000, hours: 10),
            ref("p10", width: 6000, height: 2000, hours: 10.2),
            ref("p11", width: 4000, height: 3000, hours: 10.4),
            ref("p12", width: 3000, height: 4000, hours: 10.6),
            ref("p13", width: 4000, height: 3000, hours: nil),
            ref("p14", width: 3000, height: 3000, hours: nil)
        ]
    }

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }

    private func makeBook(seed: UInt64 = 99) -> Book {
        BookEngine().makeBook(title: "Trip", photos: fixturePhotos(), preset: preset,
                              style: .standard, seed: seed)
    }

    private func encodePage(_ page: Page) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(page)
    }

    // MARK: makeBook

    @Test func makeBookIsByteStableAcrossRuns() throws {
        let first = try BookSerializer.encode(makeBook())
        let second = try BookSerializer.encode(makeBook())
        #expect(first == second)
    }

    @Test func differentSeedsProduceDifferentBooks() throws {
        let a = try BookSerializer.encode(makeBook(seed: 1))
        let b = try BookSerializer.encode(makeBook(seed: 2))
        #expect(a != b)
    }

    @Test func coverIsFirstPageWithLeadPhotoAndTitle() throws {
        let book = makeBook()
        let cover = try #require(book.pages.first)
        #expect(cover.role == .cover)
        #expect(cover.photoSlots.count == 1)
        // Lead photo = chronologically first = p01.
        #expect(cover.photoSlots[0].photoID == PhotoID(rawValue: "p01"))
        #expect(cover.photoSlots[0].frame == .full)
        #expect(cover.textSlots.count == 1)
        #expect(cover.textSlots[0].text.string == "Trip")
        // Exactly one cover.
        #expect(book.pages.count(where: { $0.role == .cover }) == 1)
    }

    @Test func everyPhotoIsPlacedOnInteriorPages() {
        let book = makeBook()
        let interior = book.pages.dropFirst()
        var placed: [PhotoID] = []
        for page in interior {
            #expect((1...8).contains(page.photoSlots.count))   // PagePacker fills up to 8/page
            #expect(page.photoSlots.allSatisfy { $0.photoID != nil })
            placed.append(contentsOf: page.photoSlots.compactMap(\.photoID))
        }
        #expect(Set(placed) == Set(fixturePhotos().map(\.id)))  // everything placed
        // The only photos that may appear more than once are panoramas, which
        // auto-promote to a spread and so are sliced onto both half-pages.
        let panoIDs = Set(fixturePhotos()
            .filter { $0.aspectRatio >= BookEngine.panoramaAspectThreshold }
            .map(\.id))
        let duplicated = Set(placed.filter { id in placed.filter { $0 == id }.count > 1 })
        #expect(duplicated.isSubset(of: panoIDs))
    }

    @Test func libraryOrderIsPreservedNotResorted() {
        // photoLibrary keeps the caller's order; only pagination is
        // chronological.
        let book = makeBook()
        #expect(book.photoLibrary.map(\.id) == fixturePhotos().map(\.id))
    }

    @Test func emptyPhotoListYieldsEmptyBook() {
        let book = BookEngine().makeBook(title: "Empty", photos: [], preset: preset,
                                         style: .standard, seed: 1)
        #expect(book.pages.isEmpty)
        #expect(book.photoLibrary.isEmpty)
    }

    @Test func singlePhotoYieldsCoverPlusHeroPage() {
        let photos = [fixturePhotos()[0]]
        let book = BookEngine().makeBook(title: "One", photos: photos, preset: preset,
                                         style: .standard, seed: 1)
        #expect(book.pages.count == 2)
        #expect(book.pages[0].role == .cover)
        #expect(book.pages[1].photoSlots.count == 1)
    }

    // MARK: reshuffle

    @Test func reshuffleLeavesLockedPageByteIdentical() throws {
        let engine = BookEngine()
        var book = makeBook()
        book.pages[2].isLocked = true
        let lockedBefore = try encodePage(book.pages[2])

        let shuffled = engine.reshuffle(book, scope: .book, preset: preset, seed: 777)
        #expect(try encodePage(shuffled.pages[2]) == lockedBefore)

        // Unlocked interior pages DID get fresh slot identities.
        #expect(shuffled.pages[1].photoSlots.map(\.id) != book.pages[1].photoSlots.map(\.id))
    }

    @Test func reshuffleLeavesPagesWithLockedSlotsUntouched() throws {
        let engine = BookEngine()
        var book = makeBook()
        book.pages[1].photoSlots[0].isLocked = true
        let before = try encodePage(book.pages[1])
        let shuffled = engine.reshuffle(book, scope: .book, preset: preset, seed: 777)
        #expect(try encodePage(shuffled.pages[1]) == before)
    }

    @Test func reshuffleKeepsPageIdentityPhotosAndCover() {
        let engine = BookEngine()
        let book = makeBook()
        let shuffled = engine.reshuffle(book, scope: .book, preset: preset, seed: 777)
        #expect(shuffled.pages.count == book.pages.count)
        #expect(shuffled.pages.map(\.id) == book.pages.map(\.id))
        #expect(shuffled.pages[0] == book.pages[0])             // cover untouched
        for (new, old) in zip(shuffled.pages.dropFirst(), book.pages.dropFirst()) {
            // Same photos, same grouping — reshuffle re-picks layout only.
            #expect(Set(new.photoSlots.compactMap(\.photoID))
                == Set(old.photoSlots.compactMap(\.photoID)))
        }
    }

    @Test func reshufflePageScopeTouchesOnlyThatPage() throws {
        let engine = BookEngine()
        let book = makeBook()
        let targetID = book.pages[3].id
        let shuffled = engine.reshuffle(book, scope: .page(targetID), preset: preset, seed: 31)
        for (index, page) in shuffled.pages.enumerated() where page.id != targetID {
            #expect(try encodePage(page) == encodePage(book.pages[index]))
        }
        #expect(shuffled.pages[3].photoSlots.map(\.id) != book.pages[3].photoSlots.map(\.id))
    }

    @Test func reshuffleIsDeterministic() throws {
        let engine = BookEngine()
        let book = makeBook()
        let a = try BookSerializer.encode(engine.reshuffle(book, scope: .book, preset: preset, seed: 5))
        let b = try BookSerializer.encode(engine.reshuffle(book, scope: .book, preset: preset, seed: 5))
        #expect(a == b)
    }

    // MARK: alternatives

    @Test func alternativesAreScoredBestFirstAndLimited() throws {
        let engine = BookEngine()
        let book = makeBook()
        let page = book.pages[1]
        let alternatives = engine.alternatives(for: page.id, in: book, preset: preset, limit: 5)
        #expect(!alternatives.isEmpty)
        #expect(alternatives.count <= 5)

        // Re-score the returned candidates with the same inputs: the
        // sequence must be non-increasing. (The scorer ignores context.seed,
        // so any seed reproduces the scores.)
        let analyzed = PhotoAnalyzer.analyze(book.photoLibrary)
        let byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })
        let photos = page.photoSlots.compactMap { $0.photoID.flatMap { byID[$0] } }
        let context = LayoutContext(pageSize: preset.trimSize, style: book.style,
                                    needsTextZone: !page.textSlots.isEmpty, seed: 0)
        let scorer = LayoutScorer()
        let scores = alternatives.map {
            scorer.score($0, photos: photos, context: context, previousPage: book.pages[0])
        }
        for (current, next) in zip(scores, scores.dropFirst()) {
            #expect(current >= next)
        }
    }

    @Test func alternativesRespectLimitExactly() {
        let engine = BookEngine()
        let book = makeBook()
        // Find the first interior page with ≥ 2 photos so we can assert the
        // limit cap is working (a 1-photo page only ever has 1 alternative).
        let multiPage = book.pages.dropFirst().first { $0.photoSlots.count >= 2 }
        guard let page = multiPage else { return }
        let two = engine.alternatives(for: page.id, in: book, preset: preset, limit: 2)
        #expect(two.count == 2)
        #expect(engine.alternatives(for: page.id, in: book, preset: preset, limit: 0).isEmpty)
    }

    @Test func alternativesAreStableAcrossCalls() {
        let engine = BookEngine()
        let book = makeBook()
        let first = engine.alternatives(for: book.pages[1].id, in: book, preset: preset, limit: 4)
        let second = engine.alternatives(for: book.pages[1].id, in: book, preset: preset, limit: 4)
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.origin == b.origin)
            #expect(a.photoSlotFrames == b.photoSlotFrames)
        }
    }

    @Test func alternativesForUnknownPageAreEmpty() {
        let engine = BookEngine()
        let book = makeBook()
        #expect(engine.alternatives(for: UUID(), in: book, preset: preset, limit: 3).isEmpty)
    }

    // MARK: placeRemaining

    @Test func placeRemainingAppendsUnplacedPhotosAtTheTail() {
        let engine = BookEngine()
        var book = makeBook()
        let originalPageCount = book.pages.count
        let extras = (0..<5).map { index in
            PhotoRef(id: PhotoID(rawValue: "extra\(index)"), source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: Double(100 + index) * 3600))
        }
        book.photoLibrary.append(contentsOf: extras)

        let placed = engine.placeRemaining(book, preset: preset, seed: 55)
        // Existing pages untouched.
        for index in 0..<originalPageCount {
            #expect(placed.pages[index] == book.pages[index])
        }
        // New tail pages hold exactly the extras.
        let tailPhotoIDs = placed.pages[originalPageCount...]
            .flatMap { $0.photoSlots.compactMap(\.photoID) }
        #expect(Set(tailPhotoIDs) == Set(extras.map(\.id)))
        for page in placed.pages[originalPageCount...] {
            #expect(page.role == .standard)
            #expect((1...9).contains(page.photoSlots.count))
        }
    }

    // MARK: repaginate

    /// Returns every placed photo ID across all standard pages.
    private func placedPhotoIDs(in book: Book) -> Set<PhotoID> {
        Set(book.pages.filter { $0.role == .standard }
            .flatMap { $0.photoSlots.compactMap(\.photoID) })
    }

    @Test func repaginateIncreasesEditedPageAndReflowsTail() {
        let engine = BookEngine()
        let book = makeBook()
        // Find a standard reshuffleable page that is not the last standard
        // page, and that has at least 2 photos so an increase is meaningful
        // (requires a downstream photo to absorb).
        let standardPages = book.pages.filter { $0.role == .standard }
        guard standardPages.count >= 2 else { return }
        // Pick the first interior standard page with ≥2 photos.
        let target = standardPages.first(where: { $0.photoSlots.count >= 2 && !$0.isLocked })!
        let beforeCount = target.photoSlots.count
        let beforePlaced = placedPhotoIDs(in: book)

        let result = engine.repaginate(book, fromPageID: target.id, delta: +1,
                                        preset: preset, seed: 42)

        let resultTarget = result.pages.first(where: { $0.id == target.id })!
        #expect(resultTarget.photoSlots.count == beforeCount + 1)
        #expect(placedPhotoIDs(in: result) == beforePlaced)   // no loss, no dupe
    }

    @Test func repaginateDecreaseMovesPhotoDownstream() {
        let engine = BookEngine()
        let book = makeBook()
        let standardPages = book.pages.filter { $0.role == .standard }
        guard standardPages.count >= 2 else { return }
        // Find a page with ≥2 photos to decrease.
        let target = standardPages.first(where: { $0.photoSlots.count >= 2 && !$0.isLocked })!
        let beforeCount = target.photoSlots.count
        let beforePlaced = placedPhotoIDs(in: book)

        let result = engine.repaginate(book, fromPageID: target.id, delta: -1,
                                        preset: preset, seed: 43)

        let resultTarget = result.pages.first(where: { $0.id == target.id })!
        #expect(resultTarget.photoSlots.count == beforeCount - 1)
        #expect(placedPhotoIDs(in: result) == beforePlaced)
    }

    @Test func repaginateStopsAtLockedDownstreamPage() throws {
        let engine = BookEngine()
        var book = makeBook()
        let standardPages = book.pages.filter { $0.role == .standard }
        guard standardPages.count >= 3 else { return }

        // Lock the second standard page so repaginate on the first must stop there.
        let firstStandard = standardPages[0]
        let secondStandard = standardPages[1]
        let secondIdx = book.pages.firstIndex(where: { $0.id == secondStandard.id })!
        book.pages[secondIdx].isLocked = true

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lockedBefore = try encoder.encode(book.pages[secondIdx])

        let result = engine.repaginate(book, fromPageID: firstStandard.id, delta: +1,
                                        preset: preset, seed: 44)

        // The locked page must be byte-identical.
        let lockedAfterIdx = result.pages.firstIndex(where: { $0.id == secondStandard.id })!
        let lockedAfter = try encoder.encode(result.pages[lockedAfterIdx])
        #expect(lockedAfter == lockedBefore)
    }

    @Test func repaginateNoOpAtBoundaries() {
        let engine = BookEngine()
        let book = makeBook()
        let standardPages = book.pages.filter { $0.role == .standard }

        // +1 on the last standard page: no downstream photo to absorb → no-op.
        let lastStandard = standardPages.last!
        let resultLast = engine.repaginate(book, fromPageID: lastStandard.id, delta: +1,
                                            preset: preset, seed: 45)
        #expect(resultLast == book)

        // -1 on a 1-photo page → no-op.
        if let onePage = standardPages.first(where: { $0.photoSlots.count == 1 }) {
            let resultOne = engine.repaginate(book, fromPageID: onePage.id, delta: -1,
                                               preset: preset, seed: 46)
            #expect(resultOne == book)
        }
    }

    @Test func repaginateIsDeterministic() throws {
        let engine = BookEngine()
        let book = makeBook()
        let standardPages = book.pages.filter { $0.role == .standard }
        guard let target = standardPages.first(where: { $0.photoSlots.count >= 2 && !$0.isLocked }) else { return }

        let a = try BookSerializer.encode(engine.repaginate(book, fromPageID: target.id,
                                                             delta: +1, preset: preset, seed: 99))
        let b = try BookSerializer.encode(engine.repaginate(book, fromPageID: target.id,
                                                             delta: +1, preset: preset, seed: 99))
        #expect(a == b)
    }

    @Test func placeRemainingIsANoOpWhenEverythingIsPlaced() {
        let engine = BookEngine()
        let book = makeBook()
        let placed = engine.placeRemaining(book, preset: preset, seed: 55)
        #expect(placed == book)
    }

    @Test func placeRemainingIsDeterministic() throws {
        let engine = BookEngine()
        var book = makeBook()
        book.photoLibrary.append(
            PhotoRef(id: PhotoID(rawValue: "extra"), source: .file(bookmark: Data()),
                     pixelWidth: 3000, pixelHeight: 4000))
        let a = try BookSerializer.encode(engine.placeRemaining(book, preset: preset, seed: 8))
        let b = try BookSerializer.encode(engine.placeRemaining(book, preset: preset, seed: 8))
        #expect(a == b)
    }

    // MARK: edgeStyleCandidate

    /// PagePacker is pure/deterministic, so a packed book stays byte-stable
    /// across runs (the merge logic itself is covered by PagePackerTests).
    @Test func packedMakeBookIsByteStable() throws {
        #expect(try BookSerializer.encode(makeBook()) == BookSerializer.encode(makeBook()))
    }

    @Test func edgeStyleCandidateIsFullBleedForOnePhotoPage() throws {
        let engine = BookEngine()
        // Use a single photo so makeBook produces cover + exactly one
        // standard interior page with one slot — exactly the shape we need.
        let photos = [
            PhotoRef(id: PhotoID(rawValue: "solo"), source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: 0))
        ]
        let book = engine.makeBook(title: "Solo", photos: photos, preset: preset,
                                   style: .standard, seed: 1)
        let page = try #require(book.pages.first { $0.role == .standard && $0.photoSlots.count == 1 })
        let cand = engine.edgeStyleCandidate(for: page.id, in: book,
                                             edgeStyle: .borderless, preset: preset)
        let frame = try #require(cand?.photoSlotFrames.first)
        #expect(frame.x == 0 && frame.y == 0 && frame.width == 1 && frame.height == 1)
    }
}
