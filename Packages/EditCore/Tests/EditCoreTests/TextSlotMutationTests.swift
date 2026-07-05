import Foundation
import PhotoBookCore
import Testing
@testable import EditCore

@Suite struct TextSlotMutationTests {

    @Test func addTextSlotAppendsLockedDefaultBox() {
        var book = EditMutationsTests.fixtureBook()
        let before = book.pages[1].textSlots.count       // page1: 0 text slots
        let id = UUID()
        EditMutations.addTextSlot(in: &book, pageID: EditMutationsTests.page1ID, id: id)

        #expect(book.pages[1].textSlots.count == before + 1)
        let slot = book.pages[1].textSlots.last!
        #expect(slot.id == id)
        #expect(slot.isLocked)                            // pinned freeform overlay
        #expect(slot.text.string == "Text")
        #expect(slot.frame.width > 0 && slot.frame.height > 0)
    }

    @Test func addTextSlotNoOpForUnknownPage() {
        var book = EditMutationsTests.fixtureBook()
        let copy = book
        EditMutations.addTextSlot(in: &book, pageID: UUID(), id: UUID())
        #expect(book == copy)
    }

    @Test func setTextFrameMovesAndKeepsLocked() {
        var book = EditMutationsTests.fixtureBook()
        let target = NormRect(x: 0.10, y: 0.60, width: 0.30, height: 0.12)
        EditMutations.setTextFrame(in: &book, slotID: EditMutationsTests.page2TextID, frame: target)

        let loc = EditMutations.locateTextSlot(EditMutationsTests.page2TextID, in: book)!
        let slot = book.pages[loc.pageIndex].textSlots[loc.slotIndex]
        #expect(slot.frame == target)
        #expect(slot.isLocked)
    }

    @Test func setTextFrameNoOpForUnknownSlot() {
        var book = EditMutationsTests.fixtureBook()
        let copy = book
        EditMutations.setTextFrame(in: &book, slotID: UUID(), frame: .full)
        #expect(book == copy)
    }

    @Test func removeTextSlotDeletesIt() {
        var book = EditMutationsTests.fixtureBook()
        #expect(EditMutations.locateTextSlot(EditMutationsTests.page2TextID, in: book) != nil)
        EditMutations.removeTextSlot(in: &book, slotID: EditMutationsTests.page2TextID)
        #expect(EditMutations.locateTextSlot(EditMutationsTests.page2TextID, in: book) == nil)
    }

    @Test func removeTextSlotNoOpForUnknownSlot() {
        var book = EditMutationsTests.fixtureBook()
        let copy = book
        EditMutations.removeTextSlot(in: &book, slotID: UUID())
        #expect(book == copy)
    }
}
