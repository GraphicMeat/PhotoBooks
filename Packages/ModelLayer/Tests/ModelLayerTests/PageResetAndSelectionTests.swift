import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct PageResetAndSelectionTests {

    private func makeModel() -> (model: BookEditorModel, document: BookDocument) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        model.undoManager = UndoManager()
        return (model, document)
    }

    // MARK: Part 1 — selecting a photo selects its page

    @Test func tapPhotoSlotSelectsItsPage() {
        let (model, _) = makeModel()
        // slot1aID lives on page1.
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        #expect(model.selectedSlotID == EditMutationsTests.slot1aID)
        #expect(model.selectedPageID == EditMutationsTests.page1ID)
    }

    // MARK: Part 2 — reset clears userWeight on the page's photos

    @Test func resetClearsUserWeightOnPagePhotos() {
        let (model, document) = makeModel()
        // Select a placed photo, then bump its weight (materializes userWeight).
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        model.makeSelectedPhotoKey()
        model.makeSelectedPhotoKey()
        // At least one photo now carries a userWeight.
        #expect(document.book.photoLibrary.contains { $0.userWeight != nil })

        model.resetSelectedPageToDefault()

        // Every photo currently on the selected page has no userWeight.
        let pageID = model.selectedPageID
        #expect(pageID != nil)
        let page = document.book.pages.first { $0.id == pageID }
        #expect(page != nil)
        for slot in page!.photoSlots {
            guard let pid = slot.photoID,
                  let ref = document.book.photoLibrary.first(where: { $0.id == pid }) else { continue }
            #expect(ref.userWeight == nil)
        }
    }

    // MARK: Part 2 — reset clears background + edge-style overrides

    @Test func resetClearsBackgroundAndEdgeStyleOverrides() {
        let (model, document) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        model.setSelectedPageBackground("#123456")
        model.setSelectedPageEdgeStyle(.borderless)
        #expect(document.book.pages[1].backgroundColorHex != nil)
        #expect(document.book.pages[1].edgeStyleOverride != nil)

        model.selectPage(EditMutationsTests.page1ID)
        model.resetSelectedPageToDefault()

        let page = document.book.pages.first { $0.id == EditMutationsTests.page1ID }
        #expect(page?.backgroundColorHex == nil)
        #expect(page?.edgeStyleOverride == nil)
    }

    // MARK: Part 1 — selection follows the photo across a reflow

    @Test func selectionFollowsPhotoAfterReflow() {
        let (model, document) = makeModel()
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        // Capture the photo bound to the selected slot BEFORE the reflow.
        let loc0 = EditMutations.locatePhotoSlot(model.selectedSlotID!, in: document.book)!
        let photoID = document.book.pages[loc0.pageIndex].photoSlots[loc0.slotIndex].photoID
        #expect(photoID != nil)

        // Force a repaginateBook reflow (mints new slot IDs).
        model.makeSelectedPhotoKey()

        // Selection is non-nil and points at the slot now holding that photo.
        #expect(model.selectedSlotID != nil)
        let loc1 = EditMutations.locatePhotoSlot(model.selectedSlotID!, in: document.book)
        #expect(loc1 != nil)
        let nowPhotoID = loc1.map { document.book.pages[$0.pageIndex].photoSlots[$0.slotIndex].photoID }
        #expect(nowPhotoID == photoID)
    }
}
