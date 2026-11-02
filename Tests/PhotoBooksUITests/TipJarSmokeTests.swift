import CoreGraphics
import ImageIO
import StoreKitTest
import UniformTypeIdentifiers
import XCTest

/// macOS smoke test for the one path a human can't check twice: a free export
/// carries sponsor pages, a tip on the step before export removes them.
/// StoreKitTest fakes the store, so the purchase actually completes and lands
/// a transaction.
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
    func testTipBeforeExportRemovesSponsorPages() throws {
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
            "-resetSupporterStatus", "YES",
            // Menu titles and copy are matched in English, whatever the host's language.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
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

        // A free export: the support step explains itself, then is passed by.
        openExportFlow(app)
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
        attachScreenshot(named: "support-step")
        app.buttons["export-support-continue"].click()

        let freeURL = exportFolder.appendingPathComponent("free.pdf")
        try exportAndFinish(app, to: freeURL)
        let free = try XCTUnwrap(CGPDFDocument(freeURL as CFURL))
        XCTAssertTrue(free.isEncrypted, "Exports must be locked against changes")
        XCTAssertTrue(free.isUnlocked, "Exports must open without a password")
        attachPage(2, of: free, named: "sponsor-page")

        // Tip on the next run: the same export comes out without the pages.
        openExportFlow(app)
        XCTAssertTrue(coffee.waitForExistence(timeout: 15))
        coffee.click()
        let thanks = app.descendants(matching: .any)["export-supporter-thanks"]
        XCTAssertTrue(thanks.waitForExistence(timeout: 15), "Thank-you confirmation never appeared")
        XCTAssertFalse(coffee.exists)
        attachScreenshot(named: "support-step-after-tip")
        app.buttons["export-support-continue"].click()

        let paidURL = exportFolder.appendingPathComponent("paid.pdf")
        try exportAndFinish(app, to: paidURL)
        let paid = try XCTUnwrap(CGPDFDocument(paidURL as CFURL))
        XCTAssertEqual(free.numberOfPages, paid.numberOfPages + 2, "Digital export adds exactly two sponsor pages")
        XCTAssertTrue(paid.isEncrypted, "Donors' exports stay locked too")

        // From now on the support step never appears.
        openExportFlow(app)
        XCTAssertTrue(app.buttons["export-single-file"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["export-support-continue"].exists)

        let transactions = session.allTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.productIdentifier, "com.graphicMeat.PhotoBooks.tip.coffee")
    }

    /// File → Export… (Unicode ellipsis, so match by prefix), past preflight.
    /// Digital PDF is the default selection.
    @MainActor
    private func openExportFlow(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["File"].click()
        let exportItem = app.menuBars.menuItems
            .matching(NSPredicate(format: "title BEGINSWITH 'Export'")).firstMatch
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5), "No Export menu item")
        exportItem.click()

        let cont = app.buttons["preflight-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Preflight step never appeared")
        cont.click()
    }

    /// Destination step → save panel → through the three thank-you steps.
    @MainActor
    private func exportAndFinish(_ app: XCUIApplication, to url: URL) throws {
        let exportButton = app.buttons["export-single-file"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10), "Destination step never appeared")
        exportButton.click()

        try saveInPanel(at: url)

        XCTAssertTrue(app.buttons["export-open-file"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["export-share"].exists)
        XCTAssertFalse(app.windows["Export — PhotoBooks"].exists,
                       "Thank-you content should stay inside the main window")
        attachScreenshot(named: "thank-you-\(url.lastPathComponent)")

        for _ in 0..<2 {
            XCTAssertFalse(app.buttons["export-done"].exists)
            let next = app.buttons["export-next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.click()
        }
        let done = app.buttons["export-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export-next"].exists)
        done.click()
    }

    /// The page as exported, for eyeballing.
    private func attachPage(_ number: Int, of document: CGPDFDocument, named name: String) {
        guard let page = document.page(at: number),
              let context = CGContext(data: nil, width: 1000, height: 1000, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let box = page.getBoxRect(.mediaBox)
        context.scaleBy(x: 1000 / box.width, y: 1000 / box.height)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return }
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
