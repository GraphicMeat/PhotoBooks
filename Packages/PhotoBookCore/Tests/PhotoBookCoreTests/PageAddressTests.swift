import Foundation
import Testing
@testable import PhotoBookCore

/// `PageAddress` is what makes the back cover reachable: it lives OUTSIDE
/// `Book.pages[]`, so an index alone can never name it (issue #5).
@Suite struct PageAddressTests {

    private func book() -> Book {
        var book = Book(title: "T", presetID: "p", style: .standard)
        book.pages = [
            Page(id: UUID(), role: .cover, origin: .template(id: "cover-hero"),
                 photoSlots: [PhotoSlot(id: UUID(), frame: .full, photoID: PhotoID(rawValue: "p1"))]),
            Page(id: UUID(), origin: .template(id: "one-up"),
                 photoSlots: [PhotoSlot(id: UUID(), frame: .full, photoID: PhotoID(rawValue: "p2"))])
        ]
        book.backCover = Page(
            id: UUID(), role: .backCover, origin: .template(id: "backcover-hero"),
            photoSlots: [PhotoSlot(id: UUID(), frame: .full, photoID: PhotoID(rawValue: "p3"))])
        return book
    }

    @Test func pageAtAddressReadsInteriorPagesAndTheBackCover() {
        let book = book()
        #expect(book.page(at: .page(1))?.id == book.pages[1].id)
        #expect(book.page(at: .backCover)?.id == book.backCover?.id)
    }

    @Test func pageAtAddressIsNilOutOfRangeAndWithoutABackCover() {
        var book = book()
        #expect(book.page(at: .page(9)) == nil)
        book.backCover = nil
        #expect(book.page(at: .backCover) == nil)
    }

    @Test func updatePageWritesThroughToTheBackCover() {
        var book = book()
        book.updatePage(at: .backCover) { $0.photoSlots[0].isLocked = true }
        #expect(book.backCover?.photoSlots[0].isLocked == true)
    }

    @Test func updatePageWritesThroughToAnInteriorPage() {
        var book = book()
        book.updatePage(at: .page(1)) { $0.isLocked = true }
        #expect(book.pages[1].isLocked)
    }

    @Test func updatePageIsANoOpForAnEmptyAddress() {
        var book = book()
        book.backCover = nil
        let before = book
        book.updatePage(at: .backCover) { $0.isLocked = true }
        book.updatePage(at: .page(9)) { $0.isLocked = true }
        #expect(book == before)
    }

    @Test func pageAddressesCoverEveryEditableSurface() {
        var book = book()
        let all: [PageAddress] = [.page(0), .page(1), .backCover]
        #expect(book.pageAddresses == all)
        book.backCover = nil
        let interior: [PageAddress] = [.page(0), .page(1)]
        #expect(book.pageAddresses == interior)
    }
}
