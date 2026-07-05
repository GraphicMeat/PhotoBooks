import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@Suite @MainActor struct ManualPlacementTests {

    private func makeModel() -> (BookEditorModel, UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo
        return (model, undo)
    }

    /// Select the first photo slot that has a bound photo.
    private func selectFirstPhoto(_ model: BookEditorModel) -> UUID {
        for page in model.book.pages {
            for slot in page.photoSlots where slot.photoID != nil {
                model.tapPhotoSlot(slot.id)
                return slot.id
            }
        }
        fatalError("fixture has no bound photo")
    }

    @Test func setPhotoSlotFrameLocksAndMovesSlot() {
        let (model, _) = makeModel()
        let slotID = selectFirstPhoto(model)
        let target = NormRect(x: 0.55, y: 0.55, width: 0.2, height: 0.2)

        model.setPhotoSlotFrame(slotID, to: target)

        let location = EditMutations.locatePhotoSlot(slotID, in: model.book)!
        let slot = model.book.pages[location.pageIndex].photoSlots[location.slotIndex]
        #expect(slot.frame == target)
        #expect(slot.isLocked == true)
        #expect(model.selectedSlotID == slotID)
    }
}
