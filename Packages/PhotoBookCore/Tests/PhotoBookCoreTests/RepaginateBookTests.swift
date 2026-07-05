import Foundation
import Testing
@testable import PhotoBookCore

@MainActor
@Suite struct RepaginateBookTests {

    private let preset = PresetLibrary.all()[0]

    private func photo(_ i: Int, weight: Int? = nil) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: "p\(i)"),
                 source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000,
                 captureDate: Date(timeIntervalSince1970: TimeInterval(i)),
                 userWeight: weight)
    }

    private func makeBook(_ count: Int) -> (BookEngine, Book) {
        let engine = BookEngine()
        let photos = (0..<count).map { photo($0) }
        let book = engine.makeBook(title: "T", photos: photos, preset: preset,
                                   style: BookStyle.standard, seed: 42)
        return (engine, book)
    }

    private func allPlacedPhotoIDs(_ book: Book) -> [PhotoID] {
        book.pages.flatMap { $0.photoSlots.compactMap(\.photoID) }
    }

    @Test func preservesEveryPhotoWhenNoWeightsChanged() {
        let (engine, book) = makeBook(12)
        let before = Set(allPlacedPhotoIDs(book))
        let after = engine.repaginateBook(book, preset: preset, seed: 7)
        #expect(Set(allPlacedPhotoIDs(after)) == before)
    }

    @Test func raisingAWeightGivesThatPhotoFewerCompanions() {
        let (engine, book0) = makeBook(12)
        var book = book0
        let target = book.pages
            .first(where: { $0.role == .standard && $0.photoSlots.count > 1 })!
            .photoSlots.compactMap(\.photoID).first!
        let idx = book.photoLibrary.firstIndex(where: { $0.id == target })!
        book.photoLibrary[idx].userWeight = ImportanceWeight.maxWeight

        let after = engine.repaginateBook(book, preset: preset, seed: 7)
        let pageWithTarget = after.pages.first { $0.photoSlots.contains { $0.photoID == target } }!
        #expect(pageWithTarget.photoSlots.count == 1)
        #expect(Set(allPlacedPhotoIDs(after)) == Set(allPlacedPhotoIDs(book)))
    }

    @Test func lockedPageIsUntouched() {
        let (engine, book0) = makeBook(12)
        var book = book0
        let lockedIdx = book.pages.firstIndex { $0.role == .standard }! + 1
        book.pages[lockedIdx].isLocked = true
        let lockedSnapshot = book.pages[lockedIdx]

        let after = engine.repaginateBook(book, preset: preset, seed: 7)
        let stillThere = after.pages.first { $0.id == lockedSnapshot.id }
        #expect(stillThere == lockedSnapshot)
    }

    @Test func coverPageIsUntouched() {
        let (engine, book) = makeBook(8)
        let cover = book.pages.first { $0.role == .cover }!
        let after = engine.repaginateBook(book, preset: preset, seed: 7)
        #expect(after.pages.first { $0.role == .cover } == cover)
    }

    @Test func isDeterministicForSameSeed() {
        let (engine, book) = makeBook(12)
        #expect(engine.repaginateBook(book, preset: preset, seed: 7)
             == engine.repaginateBook(book, preset: preset, seed: 7))
    }

    @Test func edgeStyleAndBackgroundOverridesSurvive() {
        let (engine, book0) = makeBook(12)
        var book = book0
        let idx = book.pages.firstIndex { $0.role == .standard && $0.spreadID == nil && !$0.isLocked }!
        book.pages[idx].edgeStyleOverride = .borderless
        book.pages[idx].backgroundColorHex = "#123456"
        let pageID = book.pages[idx].id
        let after = engine.repaginateBook(book, preset: preset, seed: 7)
        let same = after.pages.first { $0.id == pageID }!
        #expect(same.edgeStyleOverride == .borderless)
        #expect(same.backgroundColorHex == "#123456")
    }

    @Test func spreadMemberIsUntouched() throws {
        let (engine, book0) = makeBook(14)
        // Convert the first two interior standard pages into a spread.
        let leftID = book0.pages.first { $0.role == .standard && $0.spreadID == nil }!.id
        let withSpread = engine.convertToSpread(book0, leftPageID: leftID, preset: preset, seed: 1)
        // Only proceed if a spread was actually formed.
        let member = withSpread.pages.first { $0.spreadID != nil }
        try #require(member != nil)
        let snapshot = member!
        let after = engine.repaginateBook(withSpread, preset: preset, seed: 7)
        #expect(after.pages.first { $0.id == snapshot.id } == snapshot)
    }
}
