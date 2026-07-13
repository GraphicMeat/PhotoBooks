import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Captures the ten stable views consumed by the App Store template renderer.
/// Run only through `scripts/generate-store-screenshots.sh`, which supplies an
/// output directory and one Xcode test language/region per invocation.
final class ScreenshotTests: XCTestCase {
    private func writeFixtureImage(at url: URL, index: Int) throws {
        let width = index.isMultiple(of: 3) ? 900 : 700
        let height = index.isMultiple(of: 3) ? 600 : 900
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw NSError(domain: "screenshots", code: 1) }

        let palettes: [(CGFloat, CGFloat, CGFloat)] = [
            (0.80, 0.31, 0.21), (0.19, 0.50, 0.43), (0.20, 0.36, 0.66),
            (0.86, 0.60, 0.20), (0.51, 0.28, 0.62), (0.15, 0.57, 0.66)
        ]
        let color = palettes[index % palettes.count]
        let top = CGColor(srgbRed: min(color.0 + 0.18, 1), green: min(color.1 + 0.18, 1),
                          blue: min(color.2 + 0.18, 1), alpha: 1)
        let bottom = CGColor(srgbRed: color.0 * 0.55, green: color.1 * 0.55,
                             blue: color.2 * 0.55, alpha: 1)
        if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: width, y: height), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.28))
        context.fillEllipse(in: CGRect(x: width / 7, y: height / 5,
                                       width: width / 2, height: width / 2))
        context.setFillColor(CGColor(gray: 0.05, alpha: 0.16))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 5))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw NSError(domain: "screenshots", code: 2) }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "screenshots", code: 3)
        }
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "No window for \(name)")
        // Give SwiftUI animations, popovers, and async image decoding one beat
        // to settle before taking the deterministic window-only capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.7))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, atLeast count: Int,
                              timeout: TimeInterval = 15) {
        expectation(for: NSPredicate(format: "count >= %d", count), evaluatedWith: query)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    func testCaptureStoreViews() throws {
        // Prepare the permission-free photo set used by setup and the editor.
        let stagedFixture = URL(fileURLWithPath: "/private/tmp/PhotoBooksScreenshotFixture",
                                isDirectory: true)
        let stagedFiles = (try? FileManager.default.contentsOfDirectory(
            at: stagedFixture, includingPropertiesForKeys: nil)) ?? []
        let usesStagedPhotos = !stagedFiles.isEmpty
        let fixture = usesStagedPhotos ? stagedFixture : FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooksScreenshotFixture", isDirectory: true)
        if !usesStagedPhotos {
            try? FileManager.default.removeItem(at: fixture)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            for index in 0..<24 {
                try writeFixtureImage(
                    at: fixture.appendingPathComponent(String(format: "%02d.jpg", index)),
                    index: index)
            }
        }
        defer { if !usesStagedPhotos { try? FileManager.default.removeItem(at: fixture) } }

        // 1–2: the empty-document welcome and the first guided setup screen.
        let app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-create"].waitForExistence(timeout: 12))
        try capture("01-welcome", app: app)
        app.buttons["welcome-create"].click()
        XCTAssertTrue(app.buttons["source-folder"].waitForExistence(timeout: 8))
        try capture("02-choose-photos", app: app)
        app.terminate()

        // 3: deterministic setup review using the same real photo folder.
        app.launchArguments = [
            "-ScreenshotMode", "YES",
            "-ScreenshotSetupFixtureFolder", fixture.path,
            "-ScreenshotReview", "YES",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["curation-continue"].waitForExistence(timeout: 15))
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.95)).hover()
        try capture("03-refine-selection", app: app)
        app.terminate()

        // 4–10: relaunch into the deterministic fixture book.
        app.launchArguments = [
            "-ScreenshotMode", "YES", "-newBookFromFixtureFolder", fixture.path,
            "-ApplePersistenceIgnoreState", "YES",
            "-editor-canvas-background-mode", "white"
        ]
        app.launch()
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        waitForCount(thumbnails, atLeast: 4)

        thumbnails.element(boundBy: 2).click()
        let slots = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        waitForCount(slots, atLeast: 1)
        try capture("04-smart-layout", app: app)

        slots.element(boundBy: 0).click()
        XCTAssertTrue(app.descendants(matching: .any)["photo-actions-popover"]
            .waitForExistence(timeout: 6))
        try capture("05-photo-tools", app: app)

        app.typeKey(.escape, modifierFlags: [])
        slots.element(boundBy: 0).doubleClick()
        XCTAssertTrue(app.buttons["crop-editor-done"].waitForExistence(timeout: 6))
        try capture("06-crop", app: app)
        app.buttons["crop-editor-cancel"].click()

        XCTAssertTrue(app.buttons["tray-toggle"].waitForExistence(timeout: 6))
        app.buttons["tray-toggle"].click()
        XCTAssertTrue(app.descendants(matching: .any)["photo-tray"].waitForExistence(timeout: 6))
        try capture("07-photo-tray", app: app)
        app.buttons["tray-toggle"].click()

        thumbnails.element(boundBy: 0).click()
        try capture("08-cover", app: app)

        XCTAssertTrue(app.descendants(matching: .any)["toolbar-book-menu"]
            .waitForExistence(timeout: 6))
        app.descendants(matching: .any)["toolbar-book-menu"].click()
        let format = app.descendants(matching: .any)["toolbar-book-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 6))
        format.click()
        XCTAssertTrue(app.buttons["format-cancel"].waitForExistence(timeout: 6))
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).hover()
        try capture("09-format", app: app)
        app.buttons["format-cancel"].click()

        let exportMenu = app.descendants(matching: .any)["toolbar-export"]
        XCTAssertTrue(exportMenu.waitForExistence(timeout: 6))
        exportMenu.click()
        let digitalExport = app.descendants(matching: .any)["toolbar-export-digital"]
        XCTAssertTrue(digitalExport.waitForExistence(timeout: 6))
        digitalExport.click()
        XCTAssertTrue(app.buttons["preflight-continue"].waitForExistence(timeout: 8)
                      || app.descendants(matching: .any)["preflight-list"].exists)
        try capture("10-export", app: app)
    }
}
