import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@Suite @MainActor struct TextPlacementTests {

    private func makeModel() -> (BookEditorModel, UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo
        return (model, undo)
    }

    @Test func addTextSlotSelectsAndOpensEditor() {
        let (model, _) = makeModel()
        let before = model.book.pages[1].textSlots.count
        model.addTextSlot(toPageID: EditMutationsTests.page1ID)

        #expect(model.book.pages[1].textSlots.count == before + 1)
        let newID = model.book.pages[1].textSlots.last!.id
        #expect(model.selectedTextSlotID == newID)
        #expect(model.selectedSlotID == nil)
        #expect(model.textEditingContext?.slotID == newID)   // editor opened
    }

    @Test func addTextIsUndoable() {
        let (model, undo) = makeModel()
        model.addTextSlot(toPageID: EditMutationsTests.page1ID)
        #expect(model.book.pages[1].textSlots.count == 1)
        undo.undo()
        #expect(model.book.pages[1].textSlots.count == 0)
    }

    @Test func setTextSlotFrameMovesAndLocks() {
        let (model, _) = makeModel()
        let target = NormRect(x: 0.1, y: 0.6, width: 0.3, height: 0.12)
        model.setTextSlotFrame(EditMutationsTests.page2TextID, to: target)

        let loc = EditMutations.locateTextSlot(EditMutationsTests.page2TextID, in: model.book)!
        let slot = model.book.pages[loc.pageIndex].textSlots[loc.slotIndex]
        #expect(slot.frame == target)
        #expect(slot.isLocked)
    }

    @Test func removeSelectedTextSlotDeletesAndClearsSelection() {
        let (model, _) = makeModel()
        model.tapTextSlot(EditMutationsTests.page2TextID)
        #expect(model.selectedTextSlotID == EditMutationsTests.page2TextID)

        model.removeSelectedTextSlot()

        #expect(EditMutations.locateTextSlot(EditMutationsTests.page2TextID, in: model.book) == nil)
        #expect(model.selectedTextSlotID == nil)
    }

    @Test func canAddTextGatedToStandardPage() {
        let (model, _) = makeModel()
        model.selectPage(EditMutationsTests.coverPageID)      // cover
        #expect(model.canAddTextToSelectedPage == false)
        model.selectPage(EditMutationsTests.page1ID)          // standard
        #expect(model.canAddTextToSelectedPage == true)
    }

    @Test func reshufflePreservesLockedTextBox() {
        let (model, _) = makeModel()
        model.addTextSlot(toPageID: EditMutationsTests.page1ID)
        let id = model.book.pages[1].textSlots.last!.id
        let placed = NormRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1)
        model.setTextSlotFrame(id, to: placed)

        model.reshuffleBook()

        let loc = EditMutations.locateTextSlot(id, in: model.book)
        #expect(loc != nil)                                   // survived reshuffle
        let slot = model.book.pages[loc!.pageIndex].textSlots[loc!.slotIndex]
        #expect(slot.frame == placed)                         // untouched
    }
}
