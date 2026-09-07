import Foundation
import PhotoBookCore
import Testing
@testable import EditCore

/// Issue #5: the back cover was uneditable because every mutation addressed
/// slots as an index into `book.pages[]`, and `book.backCover` lives outside
/// that array. These pin the back cover as a first-class editing surface.
@Suite struct BackCoverEditingTests {

    static let backPageID = EditMutationsTests.uuid("D0")
    static let backSlotID = EditMutationsTests.uuid("D1")

    /// The canonical edit fixture plus a back cover holding p5 (the photo the
    /// fixture leaves unplaced in `pages[]`).
    static func book() -> Book {
        var book = EditMutationsTests.fixtureBook()
        book.backCover = Page(id: backPageID, role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: backSlotID, frame: .full,
                                                     photoID: PhotoID(rawValue: "p5"))],
                              textSlots: [])
        return book
    }

    // MARK: Locating

    @Test func locatePhotoSlotFindsBackCoverSlots() {
        let book = Self.book()
        let location = EditMutations.locatePhotoSlot(Self.backSlotID, in: book)
        #expect(location?.page == .backCover)
        #expect(location?.slotIndex == 0)
    }

    @Test func locatePhotoSlotStillFindsInteriorSlots() {
        let book = Self.book()
        let location = EditMutations.locatePhotoSlot(EditMutationsTests.slot1aID, in: book)
        #expect(location?.page == .page(1))
        #expect(location?.slotIndex == 0)
    }

    // MARK: Editing

    @Test func assignPhotoWritesToTheBackCover() {
        var book = Self.book()
        EditMutations.assignPhoto(in: &book, photoID: PhotoID(rawValue: "p2"),
                                  toSlot: Self.backSlotID, pageSize: EditMutationsTests.pageSize)
        #expect(book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(book.backCover?.photoSlots[0].isLocked == true)
    }

    @Test func swapExchangesBackCoverAndInteriorPhotos() {
        var book = Self.book()
        EditMutations.swapPhotos(in: &book, slotA: Self.backSlotID, slotB: EditMutationsTests.slot1aID,
                                 pageSize: EditMutationsTests.pageSize)
        #expect(book.backCover?.photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p5"))
    }

    @Test func removePhotoEmptiesTheBackCoverSlot() {
        var book = Self.book()
        EditMutations.removePhoto(in: &book, fromSlot: Self.backSlotID)
        #expect(book.backCover?.photoSlots[0].photoID == nil)
        #expect(book.backCover?.photoSlots[0].crop == .full)
    }

    @Test func setCropWritesToTheBackCover() {
        var book = Self.book()
        let crop = NormRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        EditMutations.setCrop(in: &book, slotID: Self.backSlotID, crop: crop)
        #expect(book.backCover?.photoSlots[0].crop == crop)
        #expect(book.backCover?.photoSlots[0].isLocked == true)
    }

    @Test func setFrameWritesToTheBackCover() {
        var book = Self.book()
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        EditMutations.setFrame(in: &book, slotID: Self.backSlotID, frame: frame)
        #expect(book.backCover?.photoSlots[0].frame == frame)
        #expect(book.backCover?.photoSlots[0].isLocked == true)
    }

    @Test func slotLockTogglesOnTheBackCover() {
        var book = Self.book()
        EditMutations.togglePhotoSlotLock(in: &book, slotID: Self.backSlotID)
        #expect(book.backCover?.photoSlots[0].isLocked == true)
        EditMutations.setPhotoSlotLock(in: &book, slotID: Self.backSlotID, isLocked: false)
        #expect(book.backCover?.photoSlots[0].isLocked == false)
    }

    // MARK: Tray

    @Test func aPhotoOnlyOnTheBackCoverCountsAsPlaced() {
        let book = Self.book()
        #expect(!EditMutations.unplacedPhotoIDs(in: book).contains(PhotoID(rawValue: "p5")))
    }

    @Test func removingAPhotoFromTheBookClearsTheBackCoverSlot() {
        var book = Self.book()
        EditMutations.removePhotoFromBook(in: &book, photoID: PhotoID(rawValue: "p5"))
        #expect(book.backCover?.photoSlots[0].photoID == nil)
        #expect(!book.photoLibrary.contains { $0.id == PhotoID(rawValue: "p5") })
    }

    // MARK: Book title (the spine)

    @Test func setBookTitleRenamesTheBook() {
        var book = Self.book()
        EditMutations.setBookTitle(in: &book, "Easter 2026 at Camber Sands")
        #expect(book.title == "Easter 2026 at Camber Sands")
    }

    @Test func setBookTitleTrimsAndIgnoresBlankInput() {
        var book = Self.book()
        EditMutations.setBookTitle(in: &book, "  Camber Sands  ")
        #expect(book.title == "Camber Sands")
        EditMutations.setBookTitle(in: &book, "   ")
        #expect(book.title == "Camber Sands")
    }

    // MARK: Spine text (title + style, one commit)

    @Test func setSpineTextWritesTheTitleAndTheStyle() {
        var book = Self.book()
        let style = TextStyle(fontName: "Futura-Medium", pointSizeFactor: 0.05,
                              colorHex: "#FF0000", alignment: .center)
        EditMutations.setSpineText(in: &book,
                                   StyledText(string: "  Camber Sands  ", style: style))
        #expect(book.title == "Camber Sands")
        #expect(book.spineStyle == style)
    }

    @Test func setSpineTextKeepsTheOldTitleWhenTheStringIsBlank() {
        var book = Self.book()
        let original = book.title
        let style = TextStyle(pointSizeFactor: 0.07, colorHex: "#00FF00", alignment: .trailing)
        EditMutations.setSpineText(in: &book, StyledText(string: "   ", style: style))
        #expect(book.title == original)       // a book with no name prints nothing
        #expect(book.spineStyle == style)     // but restyling still lands
    }
}
