import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct ReplaceModeTests {

    private func makeModel() -> BookEditorModel {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        model.undoManager = UndoManager()
        return model
    }

    private func twoBoundSlots(_ model: BookEditorModel) -> (UUID, UUID) {
        let ids = model.book.pages.flatMap { $0.photoSlots }
            .filter { $0.photoID != nil }.map(\.id)
        return (ids[0], ids[1])
    }

    @Test func secondSlotTapMovesSelectionAndDoesNotSwap() {
        let model = makeModel()
        let (a, b) = twoBoundSlots(model)
        let photoInA = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        model.tapPhotoSlot(a)
        model.tapPhotoSlot(b)
        #expect(model.selectedSlotID == b)
        let stillA = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        #expect(stillA == photoInA)
    }

    @Test func replaceModeSwapsOnNextSlotTap() {
        let model = makeModel()
        let (a, b) = twoBoundSlots(model)
        let pa = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        let pb = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == b }!.photoID
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        #expect(model.isReplacing == true)
        model.tapPhotoSlot(b)
        #expect(model.isReplacing == false)
        let newA = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        let newB = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == b }!.photoID
        #expect(newA == pb && newB == pa)
    }

    @Test func cancelReplaceLeavesPhotosUnchanged() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        let pa = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        model.cancelReplace()
        #expect(model.isReplacing == false)
        let stillA = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        #expect(stillA == pa)
    }

    @Test func trayAssignExitsReplaceMode() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        if let unplaced = model.unplacedPhotoIDs.first {
            model.assignFromTray(unplaced)
        } else {
            model.cancelReplace()
        }
        #expect(model.isReplacing == false)
    }

    @Test func sameSlotTapInReplaceModeIsNoOpExit() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        let pa = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        model.tapPhotoSlot(a)                 // tap the SAME slot
        #expect(model.isReplacing == false)
        let stillA = model.book.pages.flatMap { $0.photoSlots }.first { $0.id == a }!.photoID
        #expect(stillA == pa)                 // unchanged
    }

    @Test func beginReplaceWithNoSelectionStaysNotReplacing() {
        let model = makeModel()
        model.beginReplaceSelectedPhoto()
        #expect(model.isReplacing == false)
    }

    @Test func tappingTextSlotCancelsReplace() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        // find a text slot id if the fixture has one; else assert via selectPage instead
        let textID = model.book.pages.flatMap { $0.textSlots }.first?.id
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        if let textID { model.tapTextSlot(textID) } else { model.selectPage(model.book.pages.last?.id) }
        #expect(model.isReplacing == false)
    }

    @Test func selectingPageCancelsReplace() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        model.selectPage(model.book.pages.first?.id)
        #expect(model.isReplacing == false)
    }

    // MARK: Add from Library

    private func newPhoto(_ name: String) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: name), source: .file(bookmark: Data([0x02])),
                 pixelWidth: 1000, pixelHeight: 1000)
    }

    @Test func addLibraryPhotosDedupesByID() {
        let model = makeModel()
        let before = model.book.photoLibrary.count
        // "p5" already exists in the fixture library; "new1" does not.
        let added = model.addLibraryPhotos([newPhoto("p5"), newPhoto("new1")])
        #expect(added == [PhotoID(rawValue: "new1")])
        #expect(model.book.photoLibrary.count == before + 1)
        #expect(model.book.photoLibrary.filter { $0.id.rawValue == "p5" }.count == 1)
    }

    @Test func addSingleLibraryPhotoWhileReplacingAutoAssigns() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        #expect(model.isReplacing == true)
        model.addLibraryPhotos([newPhoto("swapIn")])
        #expect(model.isReplacing == false)        // replace completed
        let placed = model.book.pages.flatMap { $0.photoSlots }
            .first { $0.id == a }!.photoID
        #expect(placed == PhotoID(rawValue: "swapIn"))
    }

    @Test func addMultipleLibraryPhotosWhileReplacingKeepsReplaceArmed() {
        let model = makeModel()
        let (a, _) = twoBoundSlots(model)
        model.tapPhotoSlot(a)
        model.beginReplaceSelectedPhoto()
        model.addLibraryPhotos([newPhoto("n1"), newPhoto("n2")])
        // More than one picked → user chooses which to swap; still armed.
        #expect(model.isReplacing == true)
    }

    @Test func fileFixtureIsFolderSourced() {
        let model = makeModel()
        #expect(model.isFolderSourced == true)   // fixture photos are .file-sourced
    }
}
