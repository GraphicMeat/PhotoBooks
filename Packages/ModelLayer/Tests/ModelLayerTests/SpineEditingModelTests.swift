import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import PhotoBookRender
import Testing
@testable import ModelLayer

/// The spine title is a styled text run like any other: it opens the SAME
/// text editor (font / size / color / alignment) and commits through it.
@MainActor
@Suite struct SpineEditingModelTests {

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo
        return (model, document, undo)
    }

    @Test func beginSpineEditingSeedsTheEditorWithTheResolvedSpineText() throws {
        let (model, document, _) = makeModel()
        model.beginSpineEditing()
        let context = try #require(model.textEditingContext)
        #expect(context.target == .spine)
        #expect(context.text == ExportPlan.spineText(for: document.book, preset: model.preset))
        #expect(context.text.string == document.book.title)
    }

    @Test func committingTheSpineWritesTheTitleAndTheStyleAndIsUndoable() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.beginSpineEditing()
        let context = model.textEditingContext!
        model.commitText(context, text: StyledText(string: "Camber Sands",
                                                   fontName: "Futura-Medium",
                                                   pointSizeFactor: 0.04,
                                                   colorHex: "#FF0000",
                                                   alignment: .leading))
        #expect(document.book.title == "Camber Sands")
        #expect(document.book.spineStyle == TextStyle(fontName: "Futura-Medium",
                                                      pointSizeFactor: 0.04,
                                                      colorHex: "#FF0000",
                                                      alignment: .leading))
        undo.undo()
        #expect(document.book == before)
    }

    @Test func committingASlotStillWritesThatSlotsText() {
        let (model, document, _) = makeModel()
        model.beginTextEditing(EditMutationsTests.page2TextID)
        let context = model.textEditingContext!
        #expect(context.target == .slot(EditMutationsTests.page2TextID))
        let text = StyledText(string: "Hello", fontName: "Helvetica",
                              pointSizeFactor: 0.05, colorHex: "#112233", alignment: .center)
        model.commitText(context, text: text)
        #expect(document.book.pages[2].textSlots[0].text == text)
        #expect(document.book.title == "Edit Fixture")     // the spine is untouched
    }

    /// Sheet routing keys on `id`; a slot and the spine must never collide.
    @Test func theSpineContextHasItsOwnStableIdentity() {
        let slotID = EditMutationsTests.page2TextID
        #expect(TextEditorContext(target: .spine, text: StyledText(string: "x", pointSizeFactor: 0.05)).id
                == TextEditorContext.spineID)
        #expect(TextEditorContext(target: .slot(slotID),
                                  text: StyledText(string: "x", pointSizeFactor: 0.05)).id == slotID)
    }
}
