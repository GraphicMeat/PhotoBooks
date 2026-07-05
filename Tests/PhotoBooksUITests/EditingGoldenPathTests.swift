import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// macOS golden-path edit test: fixture book → swap two photo slots →
/// apply a template alternative → caption the cover text slot → reshuffle
/// the book → undo ×4 → app stable, page structure unchanged.
final class EditingGoldenPathTests: XCTestCase {

    /// Same fixture-image generator as Plan 4's NewBookSmokeTests (inlined:
    /// UITest bundles do not link test-support packages).
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
    func testEditLoopSurvivesFullUndo() throws {
        // 1. Six fixture images in a unique /tmp folder (readable by the
        //    Debug build's temporary sandbox exception — Plan 4 D6).
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("PhotoBooksEditUITests-\(UUID().uuidString)", isDirectory: true)
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

        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 3"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        let initialThumbnailCount = thumbnails.count

        // 3. SWAP: select the first interior page, click two photo slots.
        thumbnails.element(boundBy: 1).click()
        let photoSlots = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: photoSlots)
        waitForExpectations(timeout: 10)
        photoSlots.element(boundBy: 0).click()
        photoSlots.element(boundBy: 1).click()

        // 4. TEMPLATE SWITCH: apply any second item from the grouped strip.
        // Strip items are now identified as 'template-strip-<count>-<index>'.
        let stripItems = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'template-strip-'"))
        expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: stripItems)
        waitForExpectations(timeout: 10)
        stripItems.element(boundBy: 1).click()

        // 5. TEXT: caption the cover's text slot.
        thumbnails.element(boundBy: 0).click()
        let textSlots = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'slot-text-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: textSlots)
        waitForExpectations(timeout: 10)
        textSlots.element(boundBy: 0).doubleClick()
        // The caption field is a TextField; the vertical-axis variant can
        // expose as a text view — accept either.
        var field = app.textFields["text-editor-field"]
        if !field.waitForExistence(timeout: 5) {
            field = app.textViews["text-editor-field"]
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Text editor did not open")
        field.click()
        field.typeText("My Summer")
        app.buttons["text-editor-done"].click()

        // 6. RESHUFFLE BOOK.
        XCTAssertTrue(app.buttons["toolbar-reshuffle-book"].waitForExistence(timeout: 5))
        app.buttons["toolbar-reshuffle-book"].click()

        // 7. UNDO ×4 (reshuffle, text, template switch, swap).
        for _ in 0..<4 {
            app.typeKey("z", modifierFlags: .command)
        }

        // 8. App stable, page structure unchanged.
        XCTAssertTrue(app.windows.firstMatch.exists, "Window vanished after undo chain")
        XCTAssertEqual(thumbnails.count, initialThumbnailCount,
                       "Page count changed across the edit + undo loop")
    }
}
