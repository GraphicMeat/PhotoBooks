import Foundation
import PhotoBookCore
import Testing
@testable import EditCore

@Suite struct EditMutationsTests {

    // MARK: Fixture
    // Square 7×7 preset. Cover (1 photo, 1 text) + page 1 (2 photos) +
    // page 2 (1 photo + 1 empty slot, 1 text). Library: 5 photos (p5 unplaced).

    static let pageSize = SizeInches(width: 7, height: 7)

    static func uuid(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)")!
    }

    static let coverPageID = uuid("A0"), page1ID = uuid("A1"), page2ID = uuid("A2")
    static let coverSlotID = uuid("B0"), slot1aID = uuid("B1"), slot1bID = uuid("B2")
    static let slot2aID = uuid("B3"), emptySlotID = uuid("B4")
    static let coverTextID = uuid("C0"), page2TextID = uuid("C1")

    static func photo(_ name: String, width: Int, height: Int) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: name), source: .file(bookmark: Data([0x01])),
                 pixelWidth: width, pixelHeight: height)
    }

    static func fixtureBook() -> Book {
        var book = Book(title: "Edit Fixture", presetID: "blurb-small-square", style: .standard)
        book.photoLibrary = [
            photo("p1", width: 1500, height: 1000),   // aspect 1.5
            photo("p2", width: 1000, height: 1000),   // aspect 1.0
            photo("p3", width: 1000, height: 2000),   // aspect 0.5
            photo("p4", width: 1200, height: 800),    // aspect 1.5
            photo("p5", width: 800, height: 800)      // aspect 1.0 — unplaced
        ]
        book.pages = [
            Page(id: coverPageID, role: .cover, origin: .template(id: "cover-hero"),
                 photoSlots: [PhotoSlot(id: coverSlotID, frame: .full,
                                        photoID: PhotoID(rawValue: "p1"))],
                 textSlots: [TextSlot(id: coverTextID,
                                      frame: NormRect(x: 0.08, y: 0.40, width: 0.84, height: 0.20),
                                      text: StyledText(string: "Edit Fixture", fontName: "",
                                                       pointSizeFactor: 0.07,
                                                       colorHex: "#FFFFFF", alignment: .center))]),
            Page(id: page1ID, origin: .template(id: "two-up"),
                 photoSlots: [
                     PhotoSlot(id: slot1aID,
                               frame: NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9),
                               photoID: PhotoID(rawValue: "p2")),
                     PhotoSlot(id: slot1bID,
                               frame: NormRect(x: 0.525, y: 0.05, width: 0.425, height: 0.9),
                               photoID: PhotoID(rawValue: "p3"))
                 ]),
            Page(id: page2ID, origin: .template(id: "two-up"),
                 photoSlots: [
                     PhotoSlot(id: slot2aID,
                               frame: NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9),
                               photoID: PhotoID(rawValue: "p4")),
                     PhotoSlot(id: emptySlotID,
                               frame: NormRect(x: 0.525, y: 0.05, width: 0.425, height: 0.9))
                 ],
                 textSlots: [TextSlot(id: page2TextID,
                                      frame: NormRect(x: 0.05, y: 0.9, width: 0.9, height: 0.08),
                                      text: StyledText(string: "", pointSizeFactor: 0.04))])
        ]
        return book
    }

    // MARK: Swap

    @Test func swapAcrossPagesExchangesPhotosRecropsAndLocksBoth() {
        var book = Self.fixtureBook()
        EditMutations.swapPhotos(in: &book, slotA: Self.slot1aID, slotB: Self.slot2aID,
                                 pageSize: Self.pageSize)
        let slotA = book.pages[1].photoSlots[0]
        let slotB = book.pages[2].photoSlots[0]
        // Photos exchanged: p2 ↔ p4.
        #expect(slotA.photoID == PhotoID(rawValue: "p4"))
        #expect(slotB.photoID == PhotoID(rawValue: "p2"))
        // Both locked.
        #expect(slotA.isLocked && slotB.isLocked)
        // Crops are the centered aspect-fill crops for the NEW occupants.
        // Slot frame 0.425×0.9 on 7×7 → true slot aspect = 0.425/0.9 ≈ 0.4722.
        let slotAspect = (0.425 / 0.9)
        #expect(slotA.crop == defaultCrop(photoAspect: 1.5, slotAspect: slotAspect))  // p4
        #expect(slotB.crop == defaultCrop(photoAspect: 1.0, slotAspect: slotAspect))  // p2
        // IDs and frames untouched.
        #expect(slotA.id == Self.slot1aID && slotB.id == Self.slot2aID)
    }

    @Test func swapIntoEmptySlotMovesThePhoto() {
        var book = Self.fixtureBook()
        EditMutations.swapPhotos(in: &book, slotA: Self.slot2aID, slotB: Self.emptySlotID,
                                 pageSize: Self.pageSize)
        #expect(book.pages[2].photoSlots[0].photoID == nil)
        #expect(book.pages[2].photoSlots[0].crop == .full)
        #expect(book.pages[2].photoSlots[1].photoID == PhotoID(rawValue: "p4"))
        // Source slot is now empty → must NOT be locked (eligible for reshuffle).
        #expect(!book.pages[2].photoSlots[0].isLocked)
        // Destination slot received the photo → locked.
        #expect(book.pages[2].photoSlots[1].isLocked)
    }

    @Test func swapWithUnknownSlotIsANoOp() {
        var book = Self.fixtureBook()
        let before = book
        EditMutations.swapPhotos(in: &book, slotA: Self.slot1aID, slotB: UUID(),
                                 pageSize: Self.pageSize)
        #expect(book == before)
        EditMutations.swapPhotos(in: &book, slotA: Self.slot1aID, slotB: Self.slot1aID,
                                 pageSize: Self.pageSize)
        #expect(book == before)
    }

    // MARK: Tray

    @Test func unplacedPhotoIDsAreLibraryMinusPlacedInLibraryOrder() {
        let book = Self.fixtureBook()
        #expect(EditMutations.unplacedPhotoIDs(in: book) == [PhotoID(rawValue: "p5")])
        var emptier = book
        emptier.pages[1].photoSlots[0].photoID = nil
        // p2 unplaced now; library order (p2 before p5) preserved.
        #expect(EditMutations.unplacedPhotoIDs(in: emptier)
                == [PhotoID(rawValue: "p2"), PhotoID(rawValue: "p5")])
    }

    @Test func assignIntoEmptySlotPlacesCropsAndLocks() {
        var book = Self.fixtureBook()
        EditMutations.assignPhoto(in: &book, photoID: PhotoID(rawValue: "p5"),
                                  toSlot: Self.emptySlotID, pageSize: Self.pageSize)
        let slot = book.pages[2].photoSlots[1]
        #expect(slot.photoID == PhotoID(rawValue: "p5"))
        #expect(slot.isLocked)
        #expect(slot.crop == defaultCrop(photoAspect: 1.0, slotAspect: 0.425 / 0.9))
        #expect(EditMutations.unplacedPhotoIDs(in: book).isEmpty)
    }

    @Test func assignIntoOccupiedSlotReplacesAndFreesOldPhoto() {
        var book = Self.fixtureBook()
        EditMutations.assignPhoto(in: &book, photoID: PhotoID(rawValue: "p5"),
                                  toSlot: Self.slot1aID, pageSize: Self.pageSize)
        #expect(book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p5"))
        // The replaced p2 is simply unplaced now.
        #expect(EditMutations.unplacedPhotoIDs(in: book) == [PhotoID(rawValue: "p2")])
    }

    @Test func assignUnknownPhotoIsANoOp() {
        var book = Self.fixtureBook()
        let before = book
        EditMutations.assignPhoto(in: &book, photoID: PhotoID(rawValue: "nope"),
                                  toSlot: Self.slot1aID, pageSize: Self.pageSize)
        #expect(book == before)
    }

    @Test func removePhotoEmptiesSlotAndClearsLock() {
        var book = Self.fixtureBook()
        book.pages[1].photoSlots[0].isLocked = true
        EditMutations.removePhoto(in: &book, fromSlot: Self.slot1aID)
        let slot = book.pages[1].photoSlots[0]
        #expect(slot.photoID == nil)
        #expect(slot.crop == .full)
        #expect(!slot.isLocked)
        #expect(slot.frame == NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9))
        #expect(EditMutations.unplacedPhotoIDs(in: book).contains(PhotoID(rawValue: "p2")))
    }

    @Test func removeFromEmptySlotIsANoOp() {
        var book = Self.fixtureBook()
        let before = book
        EditMutations.removePhoto(in: &book, fromSlot: Self.emptySlotID)
        #expect(book == before)
    }

    // MARK: Crop / text commits

    @Test func setCropCommitsAndLocks() {
        var book = Self.fixtureBook()
        let crop = NormRect(x: 0.1, y: 0, width: 0.5, height: 0.75)
        EditMutations.setCrop(in: &book, slotID: Self.slot1aID, crop: crop)
        #expect(book.pages[1].photoSlots[0].crop == crop)
        #expect(book.pages[1].photoSlots[0].isLocked)
    }

    @Test func setTextCommitsAndLocks() {
        var book = Self.fixtureBook()
        let text = StyledText(string: "Summer", fontName: "Helvetica-Bold",
                              pointSizeFactor: 0.05, colorHex: "#22CC88", alignment: .trailing)
        EditMutations.setText(in: &book, slotID: Self.page2TextID, text: text)
        #expect(book.pages[2].textSlots[0].text == text)
        #expect(book.pages[2].textSlots[0].isLocked)
    }

    // MARK: Page lock

    @Test func togglePageLockFlips() {
        var book = Self.fixtureBook()
        EditMutations.togglePageLock(in: &book, pageID: Self.page1ID)
        #expect(book.pages[1].isLocked)
        EditMutations.togglePageLock(in: &book, pageID: Self.page1ID)
        #expect(!book.pages[1].isLocked)
    }

    // MARK: applyAlternative

    @Test func applyAlternativeReflowsPhotosInOrderAndSetsOrigin() {
        var book = Self.fixtureBook()
        let candidate = LayoutCandidate(
            origin: .template(id: "stacked"),
            photoSlotFrames: [NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.42),
                              NormRect(x: 0.05, y: 0.53, width: 0.9, height: 0.42)],
            textSlotFrames: [])
        EditMutations.applyAlternative(in: &book, candidate: candidate,
                                       pageID: Self.page1ID, pageSize: Self.pageSize)
        let page = book.pages[1]
        #expect(page.origin == .template(id: "stacked"))
        #expect(page.photoSlots.count == 2)
        #expect(page.photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(page.photoSlots[1].photoID == PhotoID(rawValue: "p3"))
        #expect(page.photoSlots[0].frame == NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.42))
        // Crops recomputed for the new frames (true aspect 0.9/0.42 on square page).
        #expect(page.photoSlots[0].crop == defaultCrop(photoAspect: 1.0, slotAspect: 0.9 / 0.42))
        #expect(page.photoSlots[1].crop == defaultCrop(photoAspect: 0.5, slotAspect: 0.9 / 0.42))
        // Page identity survives.
        #expect(page.id == Self.page1ID)
    }

    @Test func applyAlternativeWithFewerFramesDropsExtraPhotosToTray() {
        var book = Self.fixtureBook()
        let candidate = LayoutCandidate(origin: .template(id: "hero"),
                                        photoSlotFrames: [NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)],
                                        textSlotFrames: [])
        EditMutations.applyAlternative(in: &book, candidate: candidate,
                                       pageID: Self.page1ID, pageSize: Self.pageSize)
        #expect(book.pages[1].photoSlots.count == 1)
        #expect(book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        // p3 fell out → unplaced (library order: p3 before p5).
        #expect(EditMutations.unplacedPhotoIDs(in: book)
                == [PhotoID(rawValue: "p3"), PhotoID(rawValue: "p5")])
    }

    @Test func applyAlternativeWithMoreFramesLeavesEmptySlots() {
        var book = Self.fixtureBook()
        let candidate = LayoutCandidate(
            origin: .generated(GeneratedLayoutParams(seed: 9, boxes: [])),
            photoSlotFrames: [NormRect(x: 0, y: 0, width: 0.5, height: 0.5),
                              NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                              NormRect(x: 0, y: 0.5, width: 1, height: 0.5)],
            textSlotFrames: [])
        EditMutations.applyAlternative(in: &book, candidate: candidate,
                                       pageID: Self.page1ID, pageSize: Self.pageSize)
        let page = book.pages[1]
        #expect(page.photoSlots.count == 3)
        #expect(page.photoSlots[0].photoID == PhotoID(rawValue: "p2"))
        #expect(page.photoSlots[1].photoID == PhotoID(rawValue: "p3"))
        #expect(page.photoSlots[2].photoID == nil)
        #expect(page.photoSlots[2].crop == .full)
        #expect(!page.photoSlots[2].isLocked)
    }

    @Test func applyAlternativeCarriesLocksInSlotOrder() {
        var book = Self.fixtureBook()
        book.pages[1].photoSlots[1].isLocked = true   // p3 locked
        let candidate = LayoutCandidate(
            origin: .template(id: "stacked"),
            photoSlotFrames: [NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.42),
                              NormRect(x: 0.05, y: 0.53, width: 0.9, height: 0.42)],
            textSlotFrames: [])
        EditMutations.applyAlternative(in: &book, candidate: candidate,
                                       pageID: Self.page1ID, pageSize: Self.pageSize)
        // The lock follows p3 into its NEW slot; p2's slot stays unlocked.
        #expect(!book.pages[1].photoSlots[0].isLocked)
        #expect(book.pages[1].photoSlots[1].isLocked)
        #expect(book.pages[1].photoSlots[1].photoID == PhotoID(rawValue: "p3"))
    }

    @Test func applyAlternativeCarriesTextAndAddsEmptyZones() {
        var book = Self.fixtureBook()
        book.pages[2].textSlots[0].text.string = "Keep me"
        let candidate = LayoutCandidate(
            origin: .template(id: "two-text"),
            photoSlotFrames: [NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.6)],
            textSlotFrames: [NormRect(x: 0.05, y: 0.7, width: 0.9, height: 0.1),
                             NormRect(x: 0.05, y: 0.82, width: 0.9, height: 0.1)])
        EditMutations.applyAlternative(in: &book, candidate: candidate,
                                       pageID: Self.page2ID, pageSize: Self.pageSize)
        let page = book.pages[2]
        #expect(page.textSlots.count == 2)
        #expect(page.textSlots[0].text.string == "Keep me")
        #expect(page.textSlots[1].text.string == "")
        #expect(page.textSlots[1].text.pointSizeFactor == 0.04)
    }

    // MARK: movePages (cover pinned)

    private func pageIDs(_ book: Book) -> [UUID] { book.pages.map(\.id) }

    @Test func movePagesNeverMovesTheCover() {
        // Standard pages [A1, A2]; move offset 1 → 0: pages become
        // [cover, A2, A1] — cover pinned at index 0.
        var book = Self.fixtureBook()
        EditMutations.movePages(in: &book, fromStandardOffsets: IndexSet([1]), toStandardOffset: 0)
        #expect(pageIDs(book) == [Self.coverPageID, Self.page2ID, Self.page1ID])
        #expect(book.pages[0].role == .cover)
    }

    @Test func movePagesMatchesOnMoveSemanticsGoldenCases() {
        // 4 standard pages A B C D after the cover.
        func makeBook() -> (Book, [UUID]) {
            var book = Self.fixtureBook()
            let extra = [Page(id: Self.uuid("D3"), origin: .template(id: "hero")),
                         Page(id: Self.uuid("D4"), origin: .template(id: "hero"))]
            book.pages.append(contentsOf: extra)
            return (book, [Self.page1ID, Self.page2ID, Self.uuid("D3"), Self.uuid("D4")])
        }
        // Case 1: move first standard page to offset 2 → [B, A, C, D]
        var (book1, abcd) = makeBook()
        EditMutations.movePages(in: &book1, fromStandardOffsets: IndexSet([0]), toStandardOffset: 2)
        #expect(pageIDs(book1) == [Self.coverPageID, abcd[1], abcd[0], abcd[2], abcd[3]])
        // Case 2: move last standard page (offset 3, "page 4") before the
        // first ("page 1") → [D, A, B, C]
        var (book2, _) = makeBook()
        EditMutations.movePages(in: &book2, fromStandardOffsets: IndexSet([3]), toStandardOffset: 0)
        #expect(pageIDs(book2) == [Self.coverPageID, abcd[3], abcd[0], abcd[1], abcd[2]])
        // Case 3: multi-select [0, 2] to end (offset 4) → [B, D, A, C]
        var (book3, _) = makeBook()
        EditMutations.movePages(in: &book3, fromStandardOffsets: IndexSet([0, 2]), toStandardOffset: 4)
        #expect(pageIDs(book3) == [Self.coverPageID, abcd[1], abcd[3], abcd[0], abcd[2]])
    }

    @Test func movePagesOutOfRangeIsANoOp() {
        var book = Self.fixtureBook()
        let before = book
        EditMutations.movePages(in: &book, fromStandardOffsets: IndexSet([9]), toStandardOffset: 0)
        #expect(book == before)
        EditMutations.movePages(in: &book, fromStandardOffsets: IndexSet([0]), toStandardOffset: 99)
        #expect(book == before)
    }

    // MARK: Missing / relink

    @Test func markMissingFlagsOnlyListedRefs() {
        var book = Self.fixtureBook()
        EditMutations.markMissing(in: &book, photoIDs: [PhotoID(rawValue: "p2"),
                                                        PhotoID(rawValue: "p4")])
        #expect(book.photoLibrary.map(\.isMissing) == [false, true, false, true, false])
    }

    @Test func relinkKeepsIdentityAndClearsMissing() {
        var book = Self.fixtureBook()
        EditMutations.markMissing(in: &book, photoIDs: [PhotoID(rawValue: "p2")])
        // MetadataReader mints a path-derived ID for the new file — the
        // mutation must KEEP p2 so slots stay valid (D8).
        let fresh = PhotoRef(id: PhotoID(rawValue: "new-path-hash"),
                             source: .file(bookmark: Data([0xAB, 0xCD])),
                             pixelWidth: 2000, pixelHeight: 1000)
        EditMutations.relinkPhoto(in: &book, photoID: PhotoID(rawValue: "p2"), with: fresh)
        let ref = book.photoLibrary[1]
        #expect(ref.id == PhotoID(rawValue: "p2"))
        #expect(ref.source == .file(bookmark: Data([0xAB, 0xCD])))
        #expect(ref.pixelWidth == 2000)
        #expect(!ref.isMissing)
        // Slots still resolve.
        #expect(book.pages[1].photoSlots[0].photoID == PhotoID(rawValue: "p2"))
    }

    @Test func relinkUnknownIDIsANoOp() {
        var book = Self.fixtureBook()
        let before = book
        EditMutations.relinkPhoto(in: &book, photoID: PhotoID(rawValue: "nope"),
                                  with: Self.photo("x", width: 10, height: 10))
        #expect(book == before)
    }

    // MARK: Background color

    @Test func setPageBackgroundStoresAndClears() {
        var book = EditMutationsTests.fixtureBook()
        EditMutations.setPageBackground(in: &book, pageID: EditMutationsTests.page1ID, hex: "#FF0000")
        #expect(book.pages.first { $0.id == EditMutationsTests.page1ID }?.backgroundColorHex == "#FF0000")
        EditMutations.setPageBackground(in: &book, pageID: EditMutationsTests.page1ID, hex: nil)
        #expect(book.pages.first { $0.id == EditMutationsTests.page1ID }?.backgroundColorHex == nil)
    }

    @Test func setBookBackgroundStoresHex() {
        var book = EditMutationsTests.fixtureBook()
        EditMutations.setBookBackground(in: &book, hex: "#00FF00")
        #expect(book.style.backgroundColorHex == "#00FF00")
    }

    // MARK: Remove-from-book cleanup

    @Test func removePhotoFromBookClearsSlotsAndDropsLibraryRef() {
        var book = EditMutationsTests.fixtureBook()
        book.pages[1].photoSlots[0].isLocked = true   // lock must clear with the photo
        EditMutations.removePhotoFromBook(in: &book, photoID: PhotoID(rawValue: "p2"))
        let slot = book.pages[1].photoSlots[0]
        #expect(slot.photoID == nil)
        #expect(slot.crop == .full)
        #expect(!slot.isLocked)
        #expect(!book.photoLibrary.contains { $0.id == PhotoID(rawValue: "p2") })
        // Other slots untouched.
        #expect(book.pages[1].photoSlots[1].photoID == PhotoID(rawValue: "p3"))
    }

    @Test func removePhotoFromBookUnknownIDIsANoOp() {
        var book = EditMutationsTests.fixtureBook()
        let before = book
        EditMutations.removePhotoFromBook(in: &book, photoID: PhotoID(rawValue: "ghost"))
        #expect(book == before)
    }

    /// The back cover is a photo surface OUTSIDE `book.pages[]`: removing its
    /// photo must clear that slot too (same as a page slot), or it dangles.
    @Test func removePhotoFromBookClearsBackCoverSlot() {
        var book = EditMutationsTests.fixtureBook()
        book.photoLibrary.append(Self.photo("pback", width: 1000, height: 800))
        book.backCover = Page(id: Self.uuid("D0"), role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: Self.uuid("D1"), frame: .full,
                                                     photoID: PhotoID(rawValue: "pback"),
                                                     crop: NormRect(x: 0.1, y: 0.1,
                                                                    width: 0.8, height: 0.8),
                                                     isLocked: true)],
                              textSlots: [], isLocked: false)
        EditMutations.removePhotoFromBook(in: &book, photoID: PhotoID(rawValue: "pback"))
        let slot = book.backCover?.photoSlots.first
        #expect(slot?.photoID == nil)
        #expect(slot?.crop == .full)
        #expect(slot?.isLocked == false)
        #expect(!book.photoLibrary.contains { $0.id == PhotoID(rawValue: "pback") })
    }
}
