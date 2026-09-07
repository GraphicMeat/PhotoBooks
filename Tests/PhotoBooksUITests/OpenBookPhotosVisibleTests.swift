import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// End-to-end guard for "photos are placeholders until you switch pages".
///
/// A slot's thumbnail load is keyed on (photo id, bucketed pixel size). When
/// the editor canvas resizes — which it does while a freshly opened book
/// settles, and whenever the zoom changes — SwiftUI cancels the in-flight
/// load. Cancellation used to be latched as a permanent failure, so the slot
/// drew the missing-photo placeholder until its key changed again.
///
/// Real loads finish in a few milliseconds, so the cancellation window is far
/// too narrow to hit by timing; `-slowThumbnailsMs` (DEBUG-only) widens it and
/// makes this deterministic. The zoom churn then re-keys every visible slot
/// mid-load — and once the canvas settles, no slot may claim a missing photo,
/// because none of these photos is missing.
final class OpenBookPhotosVisibleTests: XCTestCase {

    /// The placeholder's accessibility LABEL, not its identifier: an
    /// ancestor's identifier (`cover-sheet`, `page-thumbnail-N`) propagates
    /// down onto every leaf and overwrites inner ones, so an identifier set
    /// on the placeholder can never be matched.
    ///
    /// Label only — a `value CONTAINS` clause crashes the app under test,
    /// because some elements (scroll bars) expose a numeric `value` and
    /// XCTest's query processor throws while evaluating the comparison.
    private static func missingPhotoPredicate() -> NSPredicate {
        NSPredicate(format: "label == 'Missing photo'")
    }

    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
        super.tearDown()
    }

    /// The runner is sandboxed and read-only outside its own container, so
    /// fixtures live in its temporary directory (under /private/var/folders,
    /// which the Debug app's entitlements let it read).
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooksOpenBook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    private func writeFixtureImage(at url: URL, width: Int, height: Int,
                                   red: CGFloat, green: CGFloat, blue: CGFloat) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw NSError(domain: "fixtures", code: 1) }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw NSError(domain: "fixtures", code: 2) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "fixtures", code: 3)
        }
    }

    @MainActor
    func testOpenedBookShowsNoMissingPhotoPlaceholders() throws {
        let photos = try makeFolder()
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.3, 0.9),
            (0.9, 0.7, 0.1), (0.6, 0.2, 0.7), (0.1, 0.7, 0.7)
        ]
        for (index, color) in colors.enumerated() {
            let landscape = index.isMultiple(of: 2)
            try writeFixtureImage(
                at: photos.appendingPathComponent("fixture-\(index).png"),
                width: landscape ? 320 : 240,
                height: landscape ? 240 : 320,
                red: color.0, green: color.1, blue: color.2)
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", photos.path,
            // Holds every uncached thumbnail long enough that the zoom churn
            // below lands on loads that are genuinely still in flight.
            "-slowThumbnailsMs", "900",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "No document window appeared")

        // The book has to be laid out before any slot exists.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 60)
        thumbnails.element(boundBy: 0).click()

        // The cover spread opens first, and its back-cover panel carries no
        // editing chrome — so its slots stay in the accessibility tree where
        // this test can read them.
        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cover-sheet'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30),
                      "cover sheet never appeared — the assertion below would be vacuous")

        // Churn the canvas size while those slow loads are in flight: every
        // change re-keys every visible slot and cancels the old load.
        let zoomOut = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'canvas-zoom-out'")).firstMatch
        let zoomIn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'canvas-zoom-in'")).firstMatch
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 10), "no zoom-out control")
        XCTAssertTrue(zoomIn.exists, "no zoom-in control")
        for _ in 0..<4 {
            zoomOut.click()
            zoomIn.click()
        }

        // Settle, then assert. Cancellation is not failure: once the canvas
        // stops moving, every slot must resolve to its photo.
        let placeholders = app.descendants(matching: .any)
            .matching(Self.missingPhotoPredicate())
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"), object: placeholders)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 30), .completed,
                       "\(placeholders.count) slot(s) still show the missing-photo placeholder "
                       + "after the canvas settled, though every fixture photo is on disk")
    }

    /// Positive control for the assertion above: when the photos really ARE
    /// gone, the placeholder must be findable. Without this, a query that
    /// silently matches nothing would make `testOpenedBook...` pass forever.
    @MainActor
    func testMissingPhotosDoShowThePlaceholder() throws {
        let photos = try makeFolder()
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.3, 0.9),
            (0.9, 0.7, 0.1), (0.6, 0.2, 0.7), (0.1, 0.7, 0.7)
        ]
        for (index, color) in colors.enumerated() {
            let landscape = index.isMultiple(of: 2)
            try writeFixtureImage(
                at: photos.appendingPathComponent("fixture-\(index).png"),
                width: landscape ? 320 : 240,
                height: landscape ? 240 : 320,
                red: color.0, green: color.1, blue: color.2)
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", photos.path,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "No document window appeared")

        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 60)
        thumbnails.element(boundBy: 0).click()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cover-sheet'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "cover sheet never appeared")

        // Pull the files out from under the book, then zoom until the cover
        // sheet asks for a thumbnail bucket it has never decoded — a
        // guaranteed cache miss whose load must hit the (now deleted) files.
        // Stay on the cover: its BACK panel is the only photo surface with no
        // editing chrome, and `SlotEditingModifier`'s `.accessibilityElement()`
        // hides the placeholder inside every slot that has chrome.
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
        let zoomIn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'canvas-zoom-in'")).firstMatch
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10), "no zoom-in control")
        for _ in 0..<4 { zoomIn.click() }

        let placeholders = app.descendants(matching: .any)
            .matching(Self.missingPhotoPredicate())
        let appeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"), object: placeholders)
        if XCTWaiter().wait(for: [appeared], timeout: 30) != .completed {
            print("A11Y-TREE-BEGIN\n\(app.debugDescription)\nA11Y-TREE-END")
            XCTFail("deleted photos showed no missing-photo placeholder — the query is blind, "
                    + "so the no-placeholder assertion in the other test proves nothing")
        }
    }
}
