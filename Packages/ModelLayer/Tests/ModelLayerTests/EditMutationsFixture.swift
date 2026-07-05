import Foundation
import PhotoBookCore

/// Shared edit fixture for ModelLayer tests, mirroring the canonical fixture
/// that lives in `EditCoreTests.EditMutationsTests`. SPM test targets cannot
/// import each other's test code, so the fixture's pure static helpers are
/// re-declared here as a plain namespace (no `@Suite` — adds no test cases).
/// Kept byte-for-byte in sync with the EditCore copy so model tests assert on
/// exactly the same book.
enum EditMutationsTests {

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
}
