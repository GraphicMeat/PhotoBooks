import XCTest
@testable import PhotoBookCore

final class BackCoverEngineTests: XCTestCase {

    private func ref(_ id: String, importance: Double?, day: Int) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id),
                 source: .file(bookmark: Data(id.utf8)),
                 pixelWidth: 1000, pixelHeight: 800,
                 captureDate: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
                 importance: importance)
    }

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }
    private func engine() -> BookEngine { BookEngine() }
    private func style() -> BookStyle { BookStyle.standard }

    func test_backCoverPicksHighestImportanceExcludingFront() {
        let photos = [
            ref("p1", importance: 0.9, day: 1),   // front (earliest) — excluded
            ref("p2", importance: 0.2, day: 2),
            ref("p3", importance: 0.7, day: 3),   // highest of the rest
            ref("p4", importance: 0.5, day: 4),
        ]
        let book = engine().makeBook(title: "T", photos: photos, preset: preset,
                                     style: style(), seed: 42)
        XCTAssertEqual(book.backCover?.role, .backCover)
        XCTAssertEqual(book.backCover?.photoSlots.first?.photoID, PhotoID(rawValue: "p3"))
        XCTAssertTrue(book.backCover?.textSlots.isEmpty ?? false)
        XCTAssertEqual(book.backCover?.origin, .template(id: "backcover-hero"))
    }

    func test_backCoverTieBreaksToEarliest() {
        let photos = [
            ref("p1", importance: 0.9, day: 1),   // front
            ref("p2", importance: 0.6, day: 2),   // tie — earlier wins
            ref("p3", importance: 0.6, day: 3),   // tie — later
        ]
        let book = engine().makeBook(title: "T", photos: photos, preset: preset,
                                     style: style(), seed: 1)
        XCTAssertEqual(book.backCover?.photoSlots.first?.photoID, PhotoID(rawValue: "p2"))
    }

    func test_noBackCoverWithOnePhoto() {
        let book = engine().makeBook(title: "T", photos: [ref("only", importance: 0.5, day: 1)],
                                     preset: preset, style: style(), seed: 1)
        XCTAssertNil(book.backCover)
    }

    func test_backCoverPreservedAcrossRepaginateBook() {
        let photos = (1...8).map { ref("p\($0)", importance: Double($0) / 10.0, day: $0) }
        let book = engine().makeBook(title: "T", photos: photos, preset: preset,
                                     style: style(), seed: 7)
        XCTAssertNotNil(book.backCover)
        let reflowed = engine().repaginateBook(book, preset: preset, seed: 7)
        XCTAssertEqual(reflowed.backCover, book.backCover)
    }
}
