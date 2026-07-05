import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// macOS UI test for the in-app cover sheet: fixture book → the cover page is
/// selected by default → assert the three-panel cover sheet (back cover |
/// spine | front) and its spine title are on screen.
final class CoverSheetUITests: XCTestCase {

    /// Same fixture-image generator as the other UITests (inlined: UITest
    /// bundles do not link test-support packages).
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
    func testSelectingCoverShowsCoverSheetWithSpineTitle() throws {
        // 1. Six fixture images in a unique /tmp folder (readable by the
        //    Debug build's temporary sandbox exception).
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("PhotoBooksCoverUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.3, 0.9),
            (0.9, 0.7, 0.1), (0.6, 0.2, 0.7), (0.1, 0.7, 0.7)
        ]
        for (index, color) in colors.enumerated() {
            let landscape = index.isMultiple(of: 2)
            try writeFixtureImage(
                at: folder.appendingPathComponent("fixture-\(index).png"),
                width: landscape ? 320 : 240,
                height: landscape ? 240 : 320,
                red: color.0, green: color.1, blue: color.2)
        }

        // 2. Launch on the fixture book.
        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", folder.path,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "No document window appeared")

        // 3. Ensure the cover page (pages[0]) is selected — it is by default,
        //    but click its thumbnail to be explicit.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        thumbnails.element(boundBy: 0).click()

        // 4. The cover sheet and its spine title appear.
        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cover-sheet'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "cover sheet should be visible")

        let spineTitle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cover-spine-title'")).firstMatch
        XCTAssertTrue(spineTitle.waitForExistence(timeout: 5),
                      "spine title should be visible on the cover sheet")
    }
}
