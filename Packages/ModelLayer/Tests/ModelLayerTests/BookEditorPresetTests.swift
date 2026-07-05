import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct BookEditorPresetTests {

    static let squarePreset = PresetLibrary.preset(id: "blurb-small-square")!
    static let sameClassPreset = PresetLibrary.preset(id: "blurb-mini-square")!
    static let crossClassPreset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func engineBook() -> Book {
        let photos = (0..<8).map { index in
            PhotoRef(id: PhotoID(rawValue: "f\(index)"),
                     source: .file(bookmark: Data([UInt8(index)])),
                     pixelWidth: index.isMultiple(of: 2) ? 1600 : 1000,
                     pixelHeight: index.isMultiple(of: 2) ? 1000 : 1600,
                     captureDate: Date(timeIntervalSinceReferenceDate: Double(index) * 7200))
        }
        return BookEngine().makeBook(title: "Preset Fixture", photos: photos,
                                     preset: Self.squarePreset, style: .standard, seed: 1)
    }

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: engineBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    @Test func switchingToTheCurrentPresetIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.changePreset(to: Self.squarePreset, seed: 7)
        #expect(document.book == before)
        #expect(!undo.canUndo)
        #expect(model.pagesNeedingReview.isEmpty)
    }

    @Test func sameClassSwitchChangesOnlyThePresetID() {
        let (model, document, undo) = makeModel()
        // Fixture lock outside the undo stack (the placeRemaining-test
        // pattern): locks must not matter for a same-class switch.
        document.mutate({ EditMutations.togglePageLock(in: &$0, pageID: $0.pages[1].id) },
                        undoManager: nil)
        let pagesBefore = document.book.pages
        model.changePreset(to: Self.sameClassPreset, seed: 7)
        #expect(document.book.presetID == "blurb-mini-square")
        #expect(document.book.pages == pagesBefore)        // byte-identical (normalized coords)
        #expect(model.pagesNeedingReview.isEmpty)          // nothing distorted, nothing to review
        #expect(model.preset.id == "blurb-mini-square")    // derived state follows
        undo.undo()
        #expect(document.book.presetID == "blurb-small-square")
        #expect(document.book.pages == pagesBefore)
    }

    @Test func crossClassSwitchRelayoutsUnlockedAndFlagsFrozenPages() {
        let (model, document, _) = makeModel()
        // Ensure at least two standard pages so we can lock one and check another.
        var book = document.book
        if book.pages.filter({ $0.role == .standard }).count < 2 {
            let extra = PhotoRef(id: PhotoID(rawValue: "xtra"),
                                 source: .file(bookmark: Data([0xFE])),
                                 pixelWidth: 800, pixelHeight: 600,
                                 captureDate: Date(timeIntervalSinceReferenceDate: 99 * 7200))
            book.photoLibrary.append(extra)
            book = BookEngine().placeRemaining(book, preset: Self.squarePreset, seed: 5)
            document.mutate({ $0 = book }, undoManager: nil)
        }
        let standardPages = document.book.pages.filter { $0.role == .standard }
        guard standardPages.count >= 2 else { return }

        let coverID = document.book.pages[0].id
        let lockedID = standardPages[0].id
        let unlockedPage = standardPages[1]
        model.togglePageLock(lockedID)
        let lockedBefore = document.book.pages.first(where: { $0.id == lockedID })!
        let unlockedSlotIDsBefore = unlockedPage.photoSlots.map(\.id)

        model.changePreset(to: Self.crossClassPreset, seed: 99)

        #expect(document.book.presetID == "blurb-standard-landscape")
        // Unlocked pages relaid out under the new preset…
        #expect(document.book.pages.first(where: { $0.id == unlockedPage.id })!
                    .photoSlots.map(\.id) != unlockedSlotIDsBefore)
        // …the locked page byte-identical (engine guarantee)…
        #expect(document.book.pages.first(where: { $0.id == lockedID }) == lockedBefore)
        // …and exactly the untouched pages flagged: the locked page plus
        // the cover (reshuffle never relayouts covers).
        #expect(model.pagesNeedingReview == [coverID, lockedID])
    }

    @Test func crossClassUndoRestoresBookAndEmptiesReviewSet() throws {
        let (model, document, undo) = makeModel()
        // Fixture lock outside the undo stack, so the one undo step below
        // is the preset switch itself.
        document.mutate({ EditMutations.togglePageLock(in: &$0, pageID: $0.pages[1].id) },
                        undoManager: nil)
        let before = try BookSerializer.encode(document.book)
        model.changePreset(to: Self.crossClassPreset, seed: 4242)
        #expect(try BookSerializer.encode(document.book) != before)
        #expect(!model.pagesNeedingReview.isEmpty)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
        #expect(model.pagesNeedingReview.isEmpty)          // flags keyed to the NEW presetID
    }

    @Test func openingAFlaggedPageClearsItsReviewFlag() {
        let (model, document, _) = makeModel()
        let lockedID = document.book.pages[1].id
        model.togglePageLock(lockedID)
        model.changePreset(to: Self.crossClassPreset, seed: 31)
        #expect(model.pagesNeedingReview.contains(lockedID))
        model.selectPage(lockedID)
        #expect(!model.pagesNeedingReview.contains(lockedID))
        #expect(model.pagesNeedingReview.contains(document.book.pages[0].id))  // cover still flagged
    }

    @Test func editingAFlaggedPageClearsItsReviewFlag() {
        let (model, document, _) = makeModel()
        let lockedID = document.book.pages[1].id
        model.togglePageLock(lockedID)
        model.changePreset(to: Self.crossClassPreset, seed: 31)
        #expect(model.pagesNeedingReview.contains(lockedID))
        model.togglePageLock(lockedID)     // unlocking IS an edit of that page
        #expect(!model.pagesNeedingReview.contains(lockedID))
    }
}
