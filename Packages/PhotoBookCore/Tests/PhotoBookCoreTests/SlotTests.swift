import Foundation
import Testing
import PhotoBookCore

@Suite struct SlotTests {

    @Test func photoSlotCodableRoundTrip() throws {
        let original = PhotoSlot(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            frame: NormRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            photoID: PhotoID(rawValue: "p1"),
            crop: NormRect(x: 0, y: 0.25, width: 1, height: 0.5),
            isLocked: true
        )
        let decoded = try JSONDecoder().decode(PhotoSlot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func emptyPhotoSlotRoundTripsNilPhotoID() throws {
        let original = PhotoSlot(frame: .full)
        #expect(original.photoID == nil)
        #expect(original.crop == .full)
        #expect(original.isLocked == false)
        let decoded = try JSONDecoder().decode(PhotoSlot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.photoID == nil)
    }

    @Test func textAlignmentRawValues() {
        #expect(TextAlignment.leading.rawValue == "leading")
        #expect(TextAlignment.center.rawValue == "center")
        #expect(TextAlignment.trailing.rawValue == "trailing")
    }

    @Test func styledTextCodableRoundTrip() throws {
        let original = StyledText(string: "Hello", fontName: "HelveticaNeue-Bold",
                                  pointSizeFactor: 0.04, colorHex: "#FF8800", alignment: .center)
        let decoded = try JSONDecoder().decode(StyledText.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func styledTextDefaults() {
        let text = StyledText(string: "Caption", pointSizeFactor: 0.03)
        #expect(text.fontName == "")           // "" = style default font
        #expect(text.colorHex == "#000000")
        #expect(text.alignment == .leading)
    }

    @Test func textSlotCodableRoundTrip() throws {
        let original = TextSlot(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            frame: NormRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            text: StyledText(string: "Chapter One", fontName: "", pointSizeFactor: 0.05,
                             colorHex: "#222222", alignment: .center),
            isLocked: false
        )
        let decoded = try JSONDecoder().decode(TextSlot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
