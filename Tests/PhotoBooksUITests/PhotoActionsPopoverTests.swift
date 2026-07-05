import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// macOS UI test for the selected-photo action popover and the replace-mode
/// snackbar: fixture book → select a photo slot → the action popover appears →
/// tap "Replace" → the snackbar appears → tap its Cancel action → snackbar
/// dismisses and the app stays stable.
final class PhotoActionsPopoverTests: XCTestCase {

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
    func testSelectingPhotoShowsPopoverAndReplaceShowsSnackbar() throws {
        // 1. Six fixture images in a unique /tmp folder.
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("PhotoBooksPopoverUITests-\(UUID().uuidString)", isDirectory: true)
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

        // 3. Select an interior page with photos.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 3"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        thumbnails.element(boundBy: 1).click()

        // 4. Select the first photo slot → the action popover appears.
        let photoSlots = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: photoSlots)
        waitForExpectations(timeout: 10)
        photoSlots.element(boundBy: 0).click()

        // The Replace action button is inside the popover; assert it appears.
        let replaceButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photo-action-replace'")).firstMatch
        XCTAssertTrue(replaceButton.waitForExistence(timeout: 5),
                      "Photo action popover did not appear on selection")

        // 5. Tap Replace → the replace-mode snackbar appears.
        replaceButton.click()
        let snackbar = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'snackbar'")).firstMatch
        XCTAssertTrue(snackbar.waitForExistence(timeout: 5),
                      "Snackbar did not appear after entering replace mode")

        // 6. Tap the snackbar's Cancel action → it dismisses.
        let snackbarAction = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'snackbar-action'")).firstMatch
        XCTAssertTrue(snackbarAction.waitForExistence(timeout: 5),
                      "Snackbar action button missing")
        snackbarAction.click()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: snackbar)
        waitForExpectations(timeout: 5)

        // 7. App stays stable.
        XCTAssertTrue(app.windows.firstMatch.exists, "Window vanished after replace/cancel")
    }
}
