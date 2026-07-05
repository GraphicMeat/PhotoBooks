import XCTest
@testable import PhotoBookCore

final class BackCoverModelTests: XCTestCase {

    private func sampleBackCoverPage() -> Page {
        Page(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
             role: .backCover,
             origin: .template(id: "backcover-hero"),
             photoSlots: [PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
                                    frame: .full,
                                    photoID: PhotoID(rawValue: "p1"),
                                    crop: .full, isLocked: false)],
             textSlots: [], isLocked: false)
    }

    func test_currentSchemaVersionIs4() {
        XCTAssertEqual(Book.currentSchemaVersion, 4)
    }

    func test_backCoverRoundTrips() throws {
        var book = Book(title: "T", presetID: "p", style: sampleStyle())
        book.backCover = sampleBackCoverPage()
        let data = try BookSerializer.encode(book)
        let decoded = try BookSerializer.decode(data)
        XCTAssertEqual(decoded.backCover, book.backCover)
        XCTAssertEqual(decoded.schemaVersion, 4)
    }

    func test_v3JSON_decodesBackCoverNil_andRestampsTo4() throws {
        let v3 = """
        {"schemaVersion":3,"title":"Old","presetID":"square-8","style":\(styleJSON()),
         "photoLibrary":[],"pages":[],"spreads":[]}
        """.data(using: .utf8)!
        let decoded = try BookSerializer.decode(v3)
        XCTAssertNil(decoded.backCover)
        XCTAssertEqual(decoded.schemaVersion, 4)
    }

    private func sampleStyle() -> BookStyle { BookStyle.standard }
    private func styleJSON() -> String {
        let data = try! JSONEncoder().encode(sampleStyle())
        return String(data: data, encoding: .utf8)!
    }
}
