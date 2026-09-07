import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

/// Issue #5, model half: selecting, replacing, cropping and locking a photo on
/// the back cover, plus renaming the book (the spine text).
@MainActor
@Suite struct BackCoverEditingModelTests {

    static let backPageID = EditMutationsTests.uuid("D0")
    static let backSlotID = EditMutationsTests.uuid("D1")

    private func makeModel() -> (model: BookEditorModel, document: BookDocument) {
        var book = EditMutationsTests.fixtureBook()
        book.backCover = Page(id: Self.backPageID, role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: Self.backSlotID, frame: .full,
                                                     photoID: PhotoID(rawValue: "p5"))],
                              textSlots: [])
        let document = BookDocument(book: book)
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        model.undoManager = UndoManager()
        return (model, document)
    }

    // MARK: Selection — the reported symptom (no blue box, no popover)

    @Test func tappingTheBackCoverPhotoSelectsIt() {
        let (model, _) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        #expect(model.selectedSlotID == Self.backSlotID)
        #expect(model.selectedPageID == Self.backPageID)
        #expect(model.selectedSlotHasPhoto)
    }

    @Test func tappingTheSameBackCoverPhotoAgainDeselects() {
        let (model, _) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        model.tapPhotoSlot(Self.backSlotID)
        #expect(model.selectedSlotID == nil)
    }

    @Test func selectingTheBackCoverOffersNoInteriorLayoutOptions() {
        let (model, _) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        model.tapPhotoSlot(Self.backSlotID)
        // The back cover is not laid out by the engine — a stale template strip
        // from the previously selected interior page would do nothing.
        #expect(model.layoutOptionsByCount.isEmpty)
        #expect(!model.canTryAnotherSelectedLayout)
        #expect(!model.canIncreaseSelectedPageDensity)
        #expect(!model.selectedPhotoCanGrow)
    }

    // MARK: Editing

    @Test func replacingSwapsTheBackCoverPhotoWithAnInteriorOne() {
        let (model, document) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        model.beginReplaceSelectedPhoto()
        #expect(model.isReplacing)
        model.tapPhotoSlot(EditMutationsTests.slot1aID)
        #expect(document.book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(document.book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p5"))
        #expect(!model.isReplacing)
    }

    @Test func trayAssignmentFillsTheBackCoverSlot() {
        let (model, document) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        model.assignFromTray(PhotoID(rawValue: "p3"))
        #expect(document.book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p3"))
    }

    @Test func cropEditorOpensOnTheBackCoverPhoto() {
        let (model, _) = makeModel()
        model.beginCropEditing(Self.backSlotID)
        #expect(model.cropEditingContext?.slotID == Self.backSlotID)
        model.commitCrop(slotID: Self.backSlotID,
                         crop: NormRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        #expect(model.book.backCover?.photoSlots[0].crop.width == 0.5)
    }

    @Test func lockTogglesOnTheBackCoverPhoto() {
        let (model, document) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        #expect(!model.selectedSlotIsLocked)
        model.toggleSelectedSlotLock()
        #expect(model.selectedSlotIsLocked)
        #expect(document.book.backCover?.photoSlots[0].isLocked == true)
    }

    @Test func resetToAutoLayoutUnlocksTheBackCoverSlotWithoutTouchingPages() {
        let (model, document) = makeModel()
        model.tapPhotoSlot(Self.backSlotID)
        model.toggleSelectedSlotLock()
        let pagesBefore = document.book.pages
        model.resetSelectedPhotoToAutoLayout()
        #expect(document.book.backCover?.photoSlots[0].isLocked == false)
        #expect(document.book.pages == pagesBefore)
    }

    @Test func manualPlacementWritesTheBackCoverSlotFrame() {
        let (model, document) = makeModel()
        let frame = NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        model.setPhotoSlotFrame(Self.backSlotID, to: frame)
        #expect(document.book.backCover?.photoSlots[0].frame == frame)
    }

    @Test func editingTheBackCoverIsUndoable() {
        let (model, document) = makeModel()
        let undo = UndoManager()
        model.undoManager = undo
        model.tapPhotoSlot(Self.backSlotID)
        model.assignFromTray(PhotoID(rawValue: "p3"))
        #expect(document.book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p3"))
        undo.undo()
        #expect(document.book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p5"))
    }

    // MARK: Rename (the spine)

    @Test func renameBookChangesTheSpineTitle() {
        let (model, document) = makeModel()
        model.renameBook(to: "Easter 2026 at Camber Sands")
        #expect(document.book.title == "Easter 2026 at Camber Sands")
    }

    @Test func renameBookIgnoresBlankInputAndIsUndoable() {
        let (model, document) = makeModel()
        let undo = UndoManager()
        model.undoManager = undo
        let original = document.book.title
        model.renameBook(to: "   ")
        #expect(document.book.title == original)
        model.renameBook(to: "Camber Sands")
        undo.undo()
        #expect(document.book.title == original)
    }
}
