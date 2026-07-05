import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct PhotoEmphasisTests {

    private func makeModel() -> (BookEditorModel, UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo
        return (model, undo)
    }

    /// Select the first photo slot that has a bound photo.
    private func selectFirstPhoto(_ model: BookEditorModel) -> PhotoID {
        for page in model.book.pages {
            for slot in page.photoSlots where slot.photoID != nil {
                model.tapPhotoSlot(slot.id)
                return slot.photoID!
            }
        }
        fatalError("fixture has no bound photo")
    }

    private func userWeight(_ model: BookEditorModel, _ id: PhotoID) -> Int? {
        model.book.photoLibrary.first { $0.id == id }?.userWeight
    }

    @Test func biggerRaisesUserWeightByOne() {
        let (model, _) = makeModel()
        let id = selectFirstPhoto(model)
        let start = model.selectedPhotoWeight!
        model.makeSelectedPhotoBigger()
        #expect(userWeight(model, id) == min(start + 1, ImportanceWeight.maxWeight))
    }

    @Test func smallerLowersButNeverBelowOne() {
        let (model, _) = makeModel()
        let id = selectFirstPhoto(model)
        for _ in 0..<(ImportanceWeight.maxWeight + 2) { model.makeSelectedPhotoSmaller() }
        #expect(userWeight(model, id) == 1)
    }

    @Test func makeKeyIsRepeatableAndCapsAtMaxWeight() {
        let (m, _) = makeModel()
        let pid = selectFirstPhoto(m)
        for _ in 0..<10 { m.makeSelectedPhotoKey() }
        #expect(userWeight(m, pid) == ImportanceWeight.maxWeight)
    }

    @Test func weightChangeIsOneUndoStep() {
        let (model, undo) = makeModel()
        let id = selectFirstPhoto(model)
        let before = userWeight(model, id)
        model.makeSelectedPhotoBigger()
        #expect(userWeight(model, id) != before)
        undo.undo()
        #expect(userWeight(model, id) == before)
    }

    @Test func canGrowAndCanShrinkReflectBounds() {
        let (model, _) = makeModel()
        _ = selectFirstPhoto(model)
        for _ in 0..<(ImportanceWeight.maxWeight + 2) { model.makeSelectedPhotoSmaller() }
        #expect(model.selectedPhotoCanShrink == false)
        #expect(model.selectedPhotoCanGrow == true)
    }

    @Test func weightMutationWithNoSelectionIsNoOp() {
        let (model, undo) = makeModel()
        let before = model.book
        model.makeSelectedPhotoBigger()   // nothing selected
        #expect(model.book == before)
        #expect(undo.canUndo == false)
    }
}
