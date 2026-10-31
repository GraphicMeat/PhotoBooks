import UIKit
import XCTest

/// iPhone Duo (foldable) UI tests. They run on any iOS simulator; on the Duo
/// `scripts/duo/duo-smoke.sh` drives the hinge from the host.
///
/// Host handshake (only when env `DUO_HOST_SYNC=1`, i.e.
/// `TEST_RUNNER_DUO_HOST_SYNC=1 xcodebuild test …`): the test writes
/// `duo-sync/ready-<name>` into this runner's tmp directory, containing the
/// hinge poses the host should visit (capturing each display), and blocks
/// until the host writes `duo-sync/done-<name>`. Without the host every
/// checkpoint is a no-op, so the assertions still run on a plain simulator.
final class DuoSmokeUITests: XCTestCase {

    private var app: XCUIApplication!
    private let sync = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("duo-sync", isDirectory: true)
    private var hostSync: Bool { ProcessInfo.processInfo.environment["DUO_HOST_SYNC"] == "1" }
    /// Folder of fixture images on the host (the simulator can read host paths).
    private var fixtures: String {
        ProcessInfo.processInfo.environment["DUO_FIXTURES"] ?? ""
    }

    override func setUp() {
        continueAfterFailure = false
        // A runner container can outlive a run; stale done-* files would let
        // every checkpoint pass without the host.
        try? FileManager.default.removeItem(at: sync)
    }

    // MARK: Helpers

    /// Lets the host visit `poses` (capturing each) and waits until it has.
    private func checkpoint(_ name: String, poses: String = "closed half flat") {
        guard hostSync else { return }
        try? FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        let done = sync.appendingPathComponent("done-\(name)")
        try? poses.write(to: sync.appendingPathComponent("ready-\(name)"),
                         atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(240)
        while !FileManager.default.fileExists(atPath: done.path) {
            guard Date() < deadline else {
                XCTFail("Host never finished checkpoint \(name)")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitFor(_ identifier: String, timeout: TimeInterval = 20,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        if !found.waitForExistence(timeout: timeout) {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("\(identifier) did not appear", file: file, line: line)
        }
        return found
    }

    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(identifier, file: file, line: line).tap()
    }

    /// iOS `DocumentGroup` launches into the system document browser; create
    /// a new document from it (a relaunch may restore the last document
    /// instead, which the caller's own wait then finds).
    private func createDocumentFromBrowser(capture: Bool = false) {
        let create = app.buttons.matching(
            NSPredicate(format: "label ==[c] 'Create Document' OR identifier ==[c] 'Create Document'"))
            .firstMatch
        guard create.waitForExistence(timeout: 20) else {
            add(XCTAttachment(string: app.debugDescription))
            return
        }
        if capture { checkpoint("01-document-browser") }
        // The browser stays in the accessibility tree under the opened
        // document, so wait for document content rather than for the button
        // to vanish; retry once if the first tap landed while it settled.
        let content = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier IN {'welcome-create', 'source-photos', 'curation-use-all', 'toolbar-book-menu'}"))
            .firstMatch
        create.tap()
        if !content.waitForExistence(timeout: 15), create.isHittable {
            create.tap()
        }
    }

    private var isRegularLayout: Bool { element("page-thumbnail-0").exists }

    /// Regular-width editor chrome: one navigation bar holding one
    /// close-document button (not covered by Reorder), and no second
    /// file-name title row from the split view's own column bars.
    private func assertSingleDocumentBar(file: StaticString = #filePath, line: UInt = #line) {
        let closeButtons = app.buttons.matching(identifier: "BackButton")
        XCTAssertEqual(closeButtons.count, 1, "expected one close-document button", file: file, line: line)
        XCTAssertEqual(app.navigationBars.count, 1, "expected one navigation bar", file: file, line: line)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Untitled'")).firstMatch.exists,
                       "duplicate file-name title row", file: file, line: line)
        let close = closeButtons.firstMatch
        XCTAssertTrue(close.isHittable, "close-document button not tappable", file: file, line: line)
        let reorder = element("reorder-toggle")
        if reorder.exists {
            XCTAssertFalse(close.frame.intersects(reorder.frame),
                           "close-document button overlaps Reorder", file: file, line: line)
        }
        XCTAssertTrue(element("toolbar-export").isHittable,
                      "Export should be in the toolbar, not the overflow menu", file: file, line: line)
    }

    /// The export flow covers the editor; its toolbar must not stay usable.
    private func assertEditorToolbarInert(_ context: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        for id in ["tray-toggle", "toolbar-export", "reorder-toggle"] {
            let item = element(id)
            XCTAssertFalse(item.exists && item.isHittable,
                           "\(id) is still tappable during export (\(context))", file: file, line: line)
        }
    }

    // MARK: Tests

    /// Opens a generated fixture book and checks the editor shows its pages
    /// in whichever layout the current display gets.
    @MainActor
    func testNewBookFromFixtureFolderShowsPages() throws {
        try XCTSkipIf(fixtures.isEmpty, "Set TEST_RUNNER_DUO_FIXTURES to a folder of images")
        app = XCUIApplication()
        app.launchArguments = ["-newBookFromFixtureFolder", fixtures]
        app.launch()
        createDocumentFromBrowser()
        let pages = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'page-thumbnail-' OR identifier BEGINSWITH 'select-page-'"))
        expectation(for: NSPredicate(format: "count >= 3"), evaluatedWith: pages)
        waitForExpectations(timeout: 40)
    }

    /// Walks welcome → setup → editor → cover → export, pausing at each
    /// screen for the host to capture every hinge pose, then folds and
    /// unfolds with the editor open and checks the session survived.
    @MainActor
    func testDuoTourAndFoldContinuity() throws {
        try XCTSkipIf(fixtures.isEmpty, "Set TEST_RUNNER_DUO_FIXTURES to a folder of images")
        app = XCUIApplication()
        // Setup reads the fixture folder in place of the system pickers.
        app.launchArguments = ["-ScreenshotSetupFixtureFolder", fixtures]
        app.launch()
        createDocumentFromBrowser(capture: true)

        // The fixture lands straight on curation; walk back for source + welcome.
        _ = waitFor("curation-use-all", timeout: 40)
        checkpoint("04-setup-curation")
        tap("setup-back")
        _ = waitFor("source-photos")
        checkpoint("03-setup-source")
        tap("setup-back")
        _ = waitFor("welcome-create")
        checkpoint("02-welcome")

        // Forward through the whole setup flow to a generated book.
        tap("welcome-create")
        tap("curation-use-all")
        _ = waitFor("setup-shape-continue")
        tap("setup-shape-square")
        checkpoint("05-setup-shape")
        tap("setup-shape-continue")
        _ = waitFor("setup-format-continue")
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'preset-'")).firstMatch.tap()
        checkpoint("06-setup-format")
        tap("setup-format-continue")
        _ = waitFor("setup-create-book")
        checkpoint("07-setup-style")
        tap("setup-create-book")

        // Editor. The host leaves the hinge flat (inner display) after every
        // checkpoint, so the regular-width sidebar is on screen from here.
        _ = waitFor("toolbar-book-menu", timeout: 60)
        checkpoint("08-editor")
        XCTAssertTrue(waitFor("page-thumbnail-2").exists,
                      "Unfolded inner display should show the regular-width sidebar")
        XCTAssertTrue(element("page-thumbnail-0").isSelected,
                      "the editor should open on the cover whatever the pose")
        assertSingleDocumentBar()
        tap("page-thumbnail-2")
        checkpoint("09-editor-page")
        tap("page-thumbnail-0")
        _ = waitFor("cover-sheet")
        checkpoint("10-cover")

        // Fold continuity, part 1: the page selection survives fold → unfold
        // → fold → unfold (the scene moves between displays each time).
        tap("page-thumbnail-2")
        XCTAssertTrue(element("page-thumbnail-2").isSelected, "page 2 should be selected")

        checkpoint("11-fold-closed", poses: "closed")
        // Folded: the outer display is compact → the vertical page list.
        _ = waitFor("select-page-2")
        XCTAssertFalse(isRegularLayout, "Folded display should not show the sidebar")
        add(XCTAttachment(string: "folded select-page-2: label=\(element("select-page-2").label)"))

        checkpoint("12-unfold-flat", poses: "flat")
        _ = waitFor("page-thumbnail-2")
        XCTAssertTrue(element("page-thumbnail-2").isSelected,
                      "page 2 selection should survive fold → unfold")

        checkpoint("13-refold-closed", poses: "closed")
        _ = waitFor("select-page-2")
        XCTAssertFalse(isRegularLayout)
        checkpoint("14-restore-flat", poses: "flat")
        _ = waitFor("page-thumbnail-2")
        XCTAssertTrue(element("page-thumbnail-2").isSelected,
                      "page 2 selection should survive unfold → fold → unfold")

        // Part 2: the photo tray stays open across a fold (inspector on the
        // inner display, bottom sheet on the outer one).
        tap("tray-toggle")
        _ = waitFor("photo-tray")
        checkpoint("15-tray-fold", poses: "closed")
        XCTAssertTrue(waitFor("photo-tray").exists, "tray should stay open after folding")
        checkpoint("16-tray-unfold", poses: "flat")
        XCTAssertTrue(waitFor("photo-tray").exists, "tray should stay open after unfolding")
        // …as the inspector beside the editor, not the phone sheet over it.
        XCTAssertTrue(waitFor("tray-toggle", timeout: 5).isHittable,
                      "editor toolbar should not be covered after unfolding with the tray open")
        tap("tray-toggle")

        // Part 3: a full-screen page zoom (compact only) must not cover the
        // inner display's editor after unfolding.
        checkpoint("17-zoom-fold", poses: "closed")
        tap("zoom-page-0")
        _ = waitFor("zoom-close")
        checkpoint("18-zoom-unfold", poses: "flat")
        XCTAssertTrue(waitFor("page-thumbnail-2").isHittable,
                      "page zoom should give way to the split editor after unfolding")

        // Export flow, started on the inner display, then folded: the zoom
        // from part 3 must not come back over it.
        tap("toolbar-export")
        _ = waitFor("export-flow-overlay")
        assertEditorToolbarInert("inner display")
        checkpoint("19-export-folded", poses: "closed")
        XCTAssertTrue(waitFor("export-flow-overlay").exists, "export flow should survive folding")
        assertEditorToolbarInert("outer display")
        XCTAssertFalse(element("zoom-close").waitForExistence(timeout: 3),
                       "a page zoom from before the unfold should not reappear on fold")
        checkpoint("20-export", poses: "half flat")
        XCTAssertTrue(waitFor("export-flow-overlay").exists, "export flow should survive unfolding")
    }

    /// The regular-width editor (iPad, iPhone Duo inner display) as it appears
    /// in the store screenshots: one clean bar, a working sidebar toggle and
    /// the document's rename menu. On iPad it is checked in both orientations.
    @MainActor
    func testRegularEditorChrome() throws {
        try XCTSkipIf(fixtures.isEmpty, "Set TEST_RUNNER_DUO_FIXTURES to a folder of images")
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        app = XCUIApplication()
        app.launchArguments = ["-newBookFromFixtureFolder", fixtures]
        app.launch()
        createDocumentFromBrowser()
        _ = waitFor("page-thumbnail-0", timeout: 40)
        XCTAssertTrue(element("page-thumbnail-0").isSelected, "the editor should open on the cover")
        assertSingleDocumentBar()
        checkpoint(isPad ? "30-ipad-editor-landscape" : "30-duo-editor-inner", poses: isPad ? "shot" : "flat")

        if isPad {
            XCUIDevice.shared.orientation = .portrait
            _ = waitFor("page-thumbnail-0")
            assertSingleDocumentBar()
            checkpoint("31-ipad-editor-portrait", poses: "shot")
        } else {
            checkpoint("31-duo-editor-outer", poses: "closed")
            _ = waitFor("select-page-0")
            checkpoint("32-duo-editor-inner-again", poses: "flat")
            _ = waitFor("page-thumbnail-0")
        }

        // The sidebar toggle now lives in the document's bar.
        tap("sidebar-toggle")
        XCTAssertTrue(element("page-thumbnail-0").waitForNonExistence(timeout: 5), "sidebar should hide")
        tap("sidebar-toggle")
        XCTAssertTrue(waitFor("page-thumbnail-0", timeout: 5).exists, "sidebar should come back")

        // Rename still lives in the document title menu.
        app.navigationBars.buttons["Fixture Book"].firstMatch.tap()
        let rename = app.buttons.matching(NSPredicate(format: "label ==[c] 'Rename'")).firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "document title menu should offer Rename")
        checkpoint(isPad ? "33-ipad-title-menu" : "33-duo-title-menu", poses: isPad ? "shot" : "flat")
    }
}
