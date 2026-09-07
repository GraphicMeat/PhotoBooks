import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// End-to-end cover-sheet editing (issue #5): the back cover photo takes
/// selection and shows the photo-actions popover, and the spine opens the
/// book-title editor so the title no longer has to be changed by hand-editing
/// `book.json`.
final class BackCoverAndSpineUITests: XCTestCase {

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

    /// Six fixture photos in a fresh folder. `temporaryDirectory` (not /tmp):
    /// the Xcode 26 UITest runner is sandboxed read-only outside it.
    private func makeFixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooksBackCoverUITests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
        return folder
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// Clicks an element's centre through a WINDOW-relative coordinate.
    /// `XCUIElement.click()` mis-targets inside the editor's zoomable canvas
    /// (the enclosing scroll view reports a shifted accessibility frame), so
    /// every canvas interaction here goes through the window's coordinate
    /// space instead.
    @MainActor
    private func clickCentre(_ app: XCUIApplication, _ element: XCUIElement) {
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let frame = element.frame
        window.coordinate(withNormalizedOffset: CGVector(
            dx: (frame.midX - windowFrame.minX) / windowFrame.width,
            dy: (frame.midY - windowFrame.minY) / windowFrame.height)).click()
    }

    @MainActor
    private func launchOnCoverSpread(fixtures: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", fixtures.path,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "No document window appeared")

        // The cover page is selected by default; click its thumbnail to be sure.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        thumbnails.element(boundBy: 0).click()

        XCTAssertTrue(element(app, "cover-sheet").waitForExistence(timeout: 15),
                      "cover sheet should be visible")
        return app
    }

    /// The bug as reported: clicking the rear cover photo produced neither the
    /// selection ring nor the crop/swap/lock popover.
    @MainActor
    func testBackCoverPhotoIsSelectableAndShowsTheActionsPopover() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = launchOnCoverSpread(fixtures: folder)

        let backSlot = element(app, "backcover-slot-photo-0")
        XCTAssertTrue(backSlot.waitForExistence(timeout: 10),
                      "back cover photo slot should be on the cover sheet")
        clickCentre(app, backSlot)

        let popover = element(app, "photo-actions-popover")
        XCTAssertTrue(popover.waitForExistence(timeout: 5),
                      "Photo actions popover did not appear for the back cover photo")

        // Replace works from the back cover: it arms replace mode + the snackbar.
        let replaceButton = element(app, "photo-action-replace")
        XCTAssertTrue(replaceButton.waitForExistence(timeout: 5), "Replace action missing")
        replaceButton.click()

        let snackbar = element(app, "snackbar")
        XCTAssertTrue(snackbar.waitForExistence(timeout: 5),
                      "Replace mode did not start from the back cover")

        let snackbarAction = element(app, "snackbar-action")
        XCTAssertTrue(snackbarAction.waitForExistence(timeout: 5), "Snackbar action missing")
        snackbarAction.click()
        XCTAssertTrue(app.windows.firstMatch.exists, "Window vanished after back-cover replace")
    }

    /// The second half of the report: the spine title was not editable in the
    /// UI at all. Clicking it opens the FULL text editor — the same font /
    /// size / color / alignment bar every caption gets — and the new title
    /// lands on the spine.
    @MainActor
    func testSpineOpensTheTitleEditorAndRenamesTheBook() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = launchOnCoverSpread(fixtures: folder)

        let spine = element(app, "cover-spine-edit")
        XCTAssertTrue(spine.waitForExistence(timeout: 10), "spine should be clickable")
        clickCentre(app, spine)

        let field = element(app, "text-editor-field")
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "The text editor did not open from the spine")
        // The whole style bar is there: the spine is a styled text run, not a
        // plain-string rename alert.
        for control in ["text-editor-font", "text-editor-size",
                        "text-editor-color", "text-editor-alignment"] {
            XCTAssertTrue(element(app, control).waitForExistence(timeout: 5),
                          "\(control) missing — the spine is not using the full text editor")
        }

        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Easter 2026 at Camber Sands")

        let done = element(app, "text-editor-done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done button missing from the text editor")
        done.click()

        // The spine now prints the new title.
        let spineTitle = element(app, "cover-spine-title")
        XCTAssertTrue(spineTitle.waitForExistence(timeout: 5), "spine title vanished")
        let renamed = NSPredicate(format: "value == %@", "Easter 2026 at Camber Sands")
        expectation(for: renamed, evaluatedWith: spineTitle)
        waitForExpectations(timeout: 10)
    }
}
