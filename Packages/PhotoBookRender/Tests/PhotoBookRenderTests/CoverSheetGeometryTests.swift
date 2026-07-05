import XCTest
import CoreGraphics
import PhotoBookCore
@testable import PhotoBookRender

final class CoverSheetGeometryTests: XCTestCase {

    func test_panelsAreContiguousAndTrimHeightMatches() {
        let trim = SizeInches(width: 10, height: 8)   // aspect 1.25
        let layout = CoverSheetGeometry.layout(available: CGSize(width: 1000, height: 400),
                                               trimSize: trim, spineInches: 0.5)
        XCTAssertEqual(layout.back.minX, 0, accuracy: 0.001)
        XCTAssertEqual(layout.spine.minX, layout.back.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.front.minX, layout.spine.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.back.height, layout.front.height, accuracy: 0.001)
        XCTAssertEqual(layout.back.width, layout.front.width, accuracy: 0.001)
        // Spine-to-trim width ratio == spineInches / trimWidthInches (H cancels).
        XCTAssertEqual(layout.spine.width / layout.back.width, 0.5 / 10.0, accuracy: 0.0001)
        XCTAssertEqual(layout.size.width, 2 * layout.back.width + layout.spine.width, accuracy: 0.001)
        XCTAssertEqual(layout.size.height, layout.back.height, accuracy: 0.001)
    }

    func test_fitsWithinAvailableSize() {
        let trim = SizeInches(width: 8, height: 8)
        let layout = CoverSheetGeometry.layout(available: CGSize(width: 300, height: 900),
                                               trimSize: trim, spineInches: 0.4)
        XCTAssertLessThanOrEqual(layout.size.width, 300 + 0.001)
        XCTAssertLessThanOrEqual(layout.size.height, 900 + 0.001)
    }
}
