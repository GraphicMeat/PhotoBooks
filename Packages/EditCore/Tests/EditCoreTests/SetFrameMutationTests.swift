import Foundation
import PhotoBookCore
import Testing
@testable import EditCore

@Suite struct SetFrameMutationTests {

    @Test func setFrameUpdatesFrameAndLocks() {
        var book = EditMutationsTests.fixtureBook()
        let newFrame = NormRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        EditMutations.setFrame(in: &book, slotID: EditMutationsTests.slot1aID, frame: newFrame)
        #expect(book.pages[1].photoSlots[0].frame == newFrame)
        #expect(book.pages[1].photoSlots[0].isLocked)
    }

    @Test func setFrameNoOpForUnknownSlot() {
        var book = EditMutationsTests.fixtureBook()
        let before = book
        EditMutations.setFrame(in: &book, slotID: UUID(), frame: .full)
        #expect(book == before)
    }
}
