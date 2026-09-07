import CoreGraphics
import ImageIO
import StoreKitTest
import UniformTypeIdentifiers
import XCTest

/// macOS smoke test for the one path a human can't check twice: exporting a
/// Digital PDF, then buying a tip on the thank-you screen. StoreKitTest fakes
/// the store, so the purchase actually completes and lands a transaction.
final class TipJarSmokeTests: XCTestCase {

    /// Held for the whole test: deallocating the session tears down the fake
    /// store the app under test is talking to.
    private var session: SKTestSession!
    private var folders: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(
            Bundle(for: TipJarSmokeTests.self).url(forResource: "PhotoBooks", withExtension: "storekit"),
            "PhotoBooks.storekit is not bundled in the UITest target")
        session = try SKTestSession(contentsOf: url)
        // Reset FIRST: resetToDefaultState() also resets disableDialogs, and
        // with dialogs on the purchase stalls behind Xcode's confirm sheet.
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true          // purchase without the confirm sheet
    }

    override func tearDown() {
        session = nil
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    /// Same CGContext → CGImageDestination fixture generator the other UITests
    /// inline (UITest bundles do not link the test-support packages).
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

    /// The runner is sandboxed and read-only everywhere but its own container,
    /// so folders live in its temporary directory (under /private/var/folders,
    /// which the Debug app's entitlements let it read).
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooksTipJar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    @MainActor
    func testExportThenTipCompletesPurchase() throws {
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
        let exportFolder = try makeFolder()

        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", photos.path,
            "-ApplePersistenceIgnoreState", "YES",
            "-photobooks.hideDonationRequests", "NO",
            // Aims the save panel at a throwaway folder so the PDF lands
            // somewhere we can delete.
            "-NSNavLastRootDirectory", exportFolder.path
        ]
        app.launch()

        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "No document window appeared")
        // The book has to be laid out before export has anything to render.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 3"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 20)

        // File → Export Digital PDF… (Unicode ellipsis, so match by prefix).
        app.menuBars.menuBarItems["File"].click()
        let exportItem = app.menuBars.menuItems
            .matching(NSPredicate(format: "title BEGINSWITH 'Export Digital'")).firstMatch
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5), "No Export Digital PDF menu item")
        exportItem.click()

        let cont = app.buttons["preflight-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Preflight step never appeared")
        cont.click()

        let exportButton = app.buttons["export-single-file"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10), "Destination step never appeared")
        exportButton.click()

        try saveInPanel(at: exportFolder.appendingPathComponent("tip-jar-smoke.pdf"))

        XCTAssertTrue(app.buttons["export-open-file"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["export-share"].exists)
        XCTAssertFalse(app.windows["Export — PhotoBooks"].exists,
                       "Thank-you content should stay inside the main window")
        // Two frames a few seconds apart: the page-flip preview should have
        // turned a page in between. Kept as attachments for eyeballing.
        attachScreenshot(named: "thank-you-sheet")
        sleep(3)
        attachScreenshot(named: "thank-you-sheet-3s-later")

        // Done is available only after advancing through all four steps.
        for _ in 0..<3 {
            XCTAssertFalse(app.buttons["export-done"].exists)
            let next = app.buttons["export-next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.click()
        }
        XCTAssertTrue(app.buttons["export-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export-next"].exists)
        // A previous run may have persisted support. Explicitly opt in again.
        let donateAgain = app.buttons["export-donate-again"]
        if donateAgain.waitForExistence(timeout: 2) { donateAgain.click() }
        // Thank-you step: the tip jar loaded the SKTestSession's products.
        let coffee = app.buttons["export-tip-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 15),
                      "export-tip-coffee never appeared — tip jar products did not load")
        let described = ([coffee.label, coffee.value as? String ?? ""]
                         + coffee.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
        XCTAssertTrue(described.contains("Espresso"), "Coffee tip button did not mention Espresso: \(described)")
        XCTAssertTrue(described.contains("1.99"), "Coffee tip button did not show the price: \(described)")
        for tier in ["burger", "steak", "bbq", "brisket", "feast"] {
            XCTAssertTrue(app.buttons["export-tip-\(tier)"].exists, "Missing tip button for \(tier)")
        }

        coffee.click()

        // macOS SwiftUI text lands in the AX value, not the label.
        let thanks = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Thank you for your support!' OR value CONTAINS 'Thank you for your support!'")).firstMatch
        XCTAssertTrue(thanks.waitForExistence(timeout: 15), "Thank-you confirmation never appeared")
        XCTAssertFalse(coffee.exists)
        XCTAssertTrue(donateAgain.exists)
        attachScreenshot(named: "thank-you-after-tip")
        donateAgain.click()
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        coffee.click()
        XCTAssertTrue(thanks.waitForExistence(timeout: 15))

        let transactions = session.allTransactions()
        XCTAssertEqual(transactions.count, 2, "Expected both initial and repeat tip transactions")
        XCTAssertEqual(transactions.first?.productIdentifier, "com.graphicMeat.PhotoBooks.tip.coffee")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The sandboxed save panel is a remote view, but it is bridged into the
    /// app's own accessibility tree (a proxy for the panel XPC service throws
    /// when that process is not separately visible). ⇧⌘G jumps the panel to
    /// the throwaway folder, then the name field gets the filename.
    @MainActor
    private func saveInPanel(at url: URL) throws {
        let app = XCUIApplication()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Save panel filename field never appeared")
        field.click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        sleep(1)
        app.typeText(url.deletingLastPathComponent().path)
        app.typeKey(.return, modifierFlags: [])
        sleep(2)
        let name = app.textFields.firstMatch
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText(url.deletingPathExtension().lastPathComponent)
        name.typeKey(.return, modifierFlags: [])
    }
}
