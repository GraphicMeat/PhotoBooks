import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct BookEditorEngineTests {

    static let preset = PresetLibrary.preset(id: "blurb-small-square")!

    private func engineBook() -> Book {
        let photos = (0..<8).map { index in
            PhotoRef(id: PhotoID(rawValue: "e\(index)"),
                     source: .file(bookmark: Data([UInt8(index)])),
                     pixelWidth: index.isMultiple(of: 2) ? 1600 : 1000,
                     pixelHeight: index.isMultiple(of: 2) ? 1000 : 1600,
                     captureDate: Date(timeIntervalSinceReferenceDate: Double(index) * 7200))
        }
        return BookEngine().makeBook(title: "Engine Fixture", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 1)
    }

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: engineBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    @Test func reshuffleBookLeavesLockedPageByteIdentical() throws {
        let (model, document, _) = makeModel()
        // Need at least two standard pages to lock one and check another.
        // If the fixture produces only one standard page, add extra photos.
        var book = document.book
        if book.pages.filter({ $0.role == .standard }).count < 2 {
            let extra = PhotoRef(id: PhotoID(rawValue: "extra"),
                                 source: .file(bookmark: Data([0xFF])),
                                 pixelWidth: 800, pixelHeight: 600,
                                 captureDate: Date(timeIntervalSinceReferenceDate: 99 * 7200))
            book.photoLibrary.append(extra)
            book = BookEngine().placeRemaining(book, preset: Self.preset, seed: 7)
            document.mutate({ $0 = book }, undoManager: nil)
        }
        let standardPages = document.book.pages.filter { $0.role == .standard }
        guard standardPages.count >= 2 else { return }

        let lockedPageID = standardPages[0].id
        model.togglePageLock(lockedPageID)
        let lockedBefore = document.book.pages.first(where: { $0.id == lockedPageID })!
        let otherPage = standardPages[1]
        let otherSlotIDsBefore = otherPage.photoSlots.map(\.id)

        model.reshuffleBook(seed: 99)

        #expect(document.book.pages.first(where: { $0.id == lockedPageID }) == lockedBefore)
        #expect(document.book.pages.first(where: { $0.id == otherPage.id })!.photoSlots.map(\.id)
                != otherSlotIDsBefore)
    }

    @Test func reshuffleBookUndoRestoresPreShuffleBook() throws {
        let (model, document, undo) = makeModel()
        let before = try BookSerializer.encode(document.book)
        model.reshuffleBook(seed: 4242)
        #expect(try BookSerializer.encode(document.book) != before)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
    }

    @Test func reshuffleSelectedPageTouchesOnlyThatPage() {
        let (model, document, _) = makeModel()
        let targetID = document.book.pages[1].id
        let before = document.book
        model.selectPage(targetID)
        model.reshuffleSelectedPage(seed: 31)
        for (index, page) in document.book.pages.enumerated() where page.id != targetID {
            #expect(page == before.pages[index])
        }
        #expect(document.book.pages[1].photoSlots.map(\.id)
                != before.pages[1].photoSlots.map(\.id))
    }

    @Test func reshufflePageWithoutSelectionIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.reshuffleSelectedPage(seed: 5)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    @Test func placeRemainingAppendsPagesAndEmptiesTray() {
        let (model, document, undo) = makeModel()
        let extras = (0..<4).map { index in
            PhotoRef(id: PhotoID(rawValue: "extra\(index)"),
                     source: .file(bookmark: Data([0xEE, UInt8(index)])),
                     pixelWidth: 1200, pixelHeight: 900,
                     captureDate: Date(timeIntervalSinceReferenceDate: Double(900 + index) * 3600))
        }
        document.mutate({ $0.photoLibrary.append(contentsOf: extras) }, undoManager: nil)
        #expect(model.unplacedPhotoIDs.count == 4)

        let pagesBefore = document.book.pages
        model.placeRemaining(seed: 7)

        #expect(document.book.pages.count > pagesBefore.count)
        #expect(model.unplacedPhotoIDs.isEmpty)
        // Existing pages untouched (engine guarantee; the wiring is pinned here).
        #expect(Array(document.book.pages.prefix(pagesBefore.count)) == pagesBefore)
        // The new tail holds exactly the extras.
        let tailPhotoIDs = document.book.pages[pagesBefore.count...]
            .flatMap { $0.photoSlots.compactMap(\.photoID) }
        #expect(Set(tailPhotoIDs) == Set(extras.map(\.id)))
        undo.undo()
        #expect(document.book.pages.count == pagesBefore.count)
        #expect(model.unplacedPhotoIDs.count == 4)
    }

    @Test func selectingAPageLoadsUpToEightAlternativesMatchingPhotoCount() {
        let (model, document, _) = makeModel()
        let page = document.book.pages[1]
        let photoCount = page.photoSlots.compactMap(\.photoID).count
        model.selectPage(page.id)
        #expect(!model.alternativeCandidates.isEmpty)
        #expect(model.alternativeCandidates.count <= 8)
        #expect(model.alternativeCandidates.allSatisfy { $0.photoSlotFrames.count == photoCount })
        model.selectPage(nil)
        #expect(model.alternativeCandidates.isEmpty)
    }
}
