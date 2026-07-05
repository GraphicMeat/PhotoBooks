import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct BookEditorModelTests {

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    // MARK: Selection + swap state machine (D12)

    @Test func tapSelectsThenDeselectsSameSlot() {
        let (model, document, _) = makeModel()
        let before = document.book
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        #expect(model.selectedSlotID == EditMutationsTests.slot1aID)
        #expect(document.book == before)        // selecting never mutates
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        #expect(model.selectedSlotID == nil)
        #expect(document.book == before)
    }

    @Test func replaceSecondSlotSwapsAndClearsSelection() {
        let (model, document, _) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.beginReplaceSelectedPhoto()                 // swap now requires explicit replace mode
        model.tapPhotoSlot(EditMutationsTests.slot2aID)
        #expect(model.selectedSlotID == nil)
        #expect(document.book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p4"))
        #expect(document.book.pages[2].photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(document.book.pages[1].photoSlots[0].isLocked)
        #expect(document.book.pages[2].photoSlots[0].isLocked)
    }

    @Test func swapUndoesInOneStep() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.beginReplaceSelectedPhoto()                 // swap now requires explicit replace mode
        model.tapPhotoSlot(EditMutationsTests.slot2aID)
        #expect(undo.canUndo)
        undo.undo()
        #expect(document.book == before)        // BOTH slots restored together
    }

    @Test func tapTextSlotTogglesAndClearsPhotoSelection() {
        let (model, _, _) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.tapTextSlot(EditMutationsTests.coverTextID)
        #expect(model.selectedSlotID == nil)
        #expect(model.selectedTextSlotID == EditMutationsTests.coverTextID)
        model.tapTextSlot(EditMutationsTests.coverTextID)
        #expect(model.selectedTextSlotID == nil)
    }

    @Test func slotSelectionSurvivesPageNavigation() {
        let (model, _, _) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.selectPage(EditMutationsTests.page2ID)
        #expect(model.selectedSlotID == EditMutationsTests.slot1aID)   // cross-spread swap works
    }

    // MARK: Tray

    @Test func assignFromTrayRequiresASelectedSlot() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.assignFromTray(PhotoID(rawValue: "p5"))
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    @Test func assignFromTrayAssignsLocksAndKeepsSelection() {
        let (model, document, _) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.emptySlotID)
        model.assignFromTray(PhotoID(rawValue: "p5"))
        let slot = document.book.pages[2].photoSlots[1]
        #expect(slot.photoID == PhotoID(rawValue: "p5"))
        #expect(slot.isLocked)
        #expect(model.selectedSlotID == EditMutationsTests.emptySlotID)
        #expect(model.unplacedPhotoIDs.isEmpty)
    }

    @Test func removeSelectedPhotoEmptiesSlotAndPhotoReturnsToTray() {
        let (model, document, _) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        #expect(model.selectedSlotHasPhoto)
        model.removeSelectedPhoto()
        #expect(document.book.pages[1].photoSlots[0].photoID == nil)
        #expect(model.unplacedPhotoIDs == [PhotoID(rawValue: "p2"), PhotoID(rawValue: "p5")])
        #expect(!model.selectedSlotHasPhoto)
    }

    // MARK: Crop + text commits

    @Test func commitCropLocksSlotAndUndoRestores() {
        let (model, document, undo) = makeModel()
        let before = document.book
        let crop = NormRect(x: 0.2, y: 0, width: 0.4, height: 0.6)
        model.commitCrop(slotID: EditMutationsTests.slot1bID, crop: crop)
        #expect(document.book.pages[1].photoSlots[1].crop == crop)
        #expect(document.book.pages[1].photoSlots[1].isLocked)
        undo.undo()
        #expect(document.book == before)
    }

    @Test func commitTextWritesStyledText() {
        let (model, document, _) = makeModel()
        let text = StyledText(string: "Hello", fontName: "Helvetica",
                              pointSizeFactor: 0.05, colorHex: "#112233", alignment: .center)
        model.commitText(slotID: EditMutationsTests.page2TextID, text: text)
        #expect(document.book.pages[2].textSlots[0].text == text)
        #expect(document.book.pages[2].textSlots[0].isLocked)
    }

    // MARK: Page + slot locks, reorder

    @Test func togglePageLockFlipsAndIsUndoable() {
        let (model, document, undo) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        model.toggleSelectedPageLock()
        #expect(document.book.pages[1].isLocked)
        #expect(model.selectedPageIsLocked)
        undo.undo()
        #expect(!document.book.pages[1].isLocked)
    }

    @Test func toggleSelectedSlotLockFlipsAndIsUndoable() {
        let (model, document, undo) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.toggleSelectedSlotLock()
        #expect(document.book.pages[1].photoSlots[0].isLocked)
        #expect(model.selectedSlotIsLocked)
        undo.undo()
        #expect(!document.book.pages[1].photoSlots[0].isLocked)
        // Unlock (spec: returns content to the engine's pool).
        model.toggleSelectedSlotLock()
        model.toggleSelectedSlotLock()
        #expect(!document.book.pages[1].photoSlots[0].isLocked)
    }

    @Test func movePagesKeepsCoverPinned() {
        let (model, document, undo) = makeModel()
        model.movePages(fromStandardOffsets: IndexSet([1]), toStandardOffset: 0)
        #expect(document.book.pages.map(\.id) == [EditMutationsTests.coverPageID,
                                                  EditMutationsTests.page2ID,
                                                  EditMutationsTests.page1ID])
        undo.undo()
        #expect(document.book.pages.map(\.id) == [EditMutationsTests.coverPageID,
                                                  EditMutationsTests.page1ID,
                                                  EditMutationsTests.page2ID])
    }

    // MARK: Editor contexts

    @Test func cropEditorContextDerivesTrueSlotAspect() {
        let (model, _, _) = makeModel()
        let context = model.cropEditorContext(forSlot: EditMutationsTests.slot1aID)
        #expect(context != nil)
        #expect(context?.photoID == PhotoID(rawValue: "p2"))
        #expect(context?.baseCrop == .full)
        #expect(context.map { abs($0.photoAspect - 1.0) < 1e-12 } == true)
        // 0.425×0.9 frame on a square page: true aspect = 0.425/0.9 (D6).
        #expect(context.map { abs($0.slotAspect - 0.425 / 0.9) < 1e-12 } == true)
        // Empty slot has nothing to crop.
        #expect(model.cropEditorContext(forSlot: EditMutationsTests.emptySlotID) == nil)
    }

    @Test func textEditorContextReturnsCurrentText() {
        let (model, _, _) = makeModel()
        let context = model.textEditorContext(forSlot: EditMutationsTests.coverTextID)
        #expect(context?.text.string == "Edit Fixture")
        #expect(model.textEditorContext(forSlot: UUID()) == nil)
    }

    // MARK: Undo hygiene

    @Test func noOpMutationRegistersNoUndo() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.applyAlternative(
            LayoutCandidate(origin: .template(id: "x"), photoSlotFrames: [.full], textSlotFrames: []),
            to: UUID())
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }
}
