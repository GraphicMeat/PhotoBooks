import XCTest

/// App Store marketing stills on macOS: a 1440 x 900 pt light-mode window
/// (2880 x 1800 px on a 2x display), saved as kept XCTAttachments named by
/// shot id. `scripts/marketing/capture.sh` (device "mac") exports them.
///
/// Env: MARKETING_PHOTOS (prepared photos in a folder the Debug app may read,
/// e.g. /private/tmp/...), MARKETING_EXPORT (an empty folder for the PDF),
/// MARKETING_PICKS (as the iOS class).
final class MarketingCaptureMacUITests: XCTestCase {

    static var title: String { ProcessInfo.processInfo.environment["MARKETING_TITLE"] ?? "Summer by the Sea" }
    static var language: String { ProcessInfo.processInfo.environment["MARKETING_LANGUAGE"] ?? "en" }
    static var region: String { ProcessInfo.processInfo.environment["MARKETING_REGION"] ?? "en_US" }
    private var app: XCUIApplication!
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var photos: String { env["MARKETING_PHOTOS"] ?? "" }

    private func pick(_ key: String, default value: Int) -> Int {
        for pair in (env["MARKETING_PICKS"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, parts[0] == key, let number = Int(parts[1]) { return number }
        }
        return value
    }

    override func setUp() {
        continueAfterFailure = true
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    @discardableResult
    private func click(_ identifier: String, timeout: TimeInterval = 20) -> Bool {
        let found = element(identifier)
        guard found.waitForExistence(timeout: timeout) else {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("\(identifier) did not appear")
            return false
        }
        found.click()
        return true
    }

    @MainActor
    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments + [
            "-ScreenshotBookTitle", Self.title,
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleInterfaceStyle", "Light",
            "-AppleLanguages", "(\(Self.language))", "-AppleLocale", Self.region,
            "-editor-canvas-background-mode", "white"
        ]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "no document window")
        sizeWindow()
    }

    /// Moves the document window near the top-left and drags its corner
    /// until the frame is exactly 1440 x 900 points.
    @MainActor
    private func sizeWindow() {
        let window = app.windows.firstMatch
        for _ in 0..<4 {
            let frame = window.frame
            if abs(frame.width - 1440) < 1, abs(frame.height - 900) < 1, frame.minY < 120 { return }
            let origin = window.coordinate(withNormalizedOffset: .zero)
            if frame.minY > 60 || frame.minX > 60 || frame.maxX > 1900 {
                let grab = origin.withOffset(CGVector(dx: frame.width / 2, dy: 10))
                grab.click(forDuration: 0.2, thenDragTo: grab.withOffset(
                    CGVector(dx: 60 - frame.minX, dy: 50 - frame.minY)))
                pause(0.5)
                continue
            }
            let corner = origin.withOffset(CGVector(dx: frame.width - 2, dy: frame.height - 2))
            corner.click(forDuration: 0.2, thenDragTo: corner.withOffset(
                CGVector(dx: 1440 - frame.width, dy: 900 - frame.height)))
            pause(0.6)
        }
        let frame = window.frame
        add(XCTAttachment(string: "window frame \(frame)"))
    }

    @MainActor
    private func shot(_ name: String, settle: TimeInterval = 1.5) {
        // Park the pointer in a corner: preset and shape cards play a
        // page-turn animation while hovered.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.5)).hover()
        pause(settle + 1.5)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Setup stills

    @MainActor
    func test1SetupStills() throws {
        try XCTSkipIf(photos.isEmpty, "needs MARKETING_PHOTOS")
        launch(["-ScreenshotSetupFixtureFolder", photos, "-ScreenshotReview", "YES"])
        guard element("curation-continue").waitForExistence(timeout: 40) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("no curation review"); return
        }
        shot("04-curate", settle: 3)
        click("curation-continue")
        click("setup-shape-portrait")
        shot("08-format-shape")
        click("setup-shape-continue")
        click("preset-trade-6x9")
        shot("08-format")
        for _ in 0..<6 where !element("welcome-create").exists {
            let back = element("setup-back")
            guard back.waitForExistence(timeout: 5) else { break }
            back.click()
            pause(0.8)
        }
        if element("welcome-create").waitForExistence(timeout: 10) { shot("09-private") }
        app.terminate()
    }

    // MARK: Editor stills

    @MainActor
    private func selectPage(_ index: Int) {
        let thumbnail = element("page-thumbnail-\(index)")
        if thumbnail.waitForExistence(timeout: 5) {
            thumbnail.click()
        } else {
            XCTFail("no page-thumbnail-\(index)")
        }
    }

    @MainActor
    func test2EditorStills() throws {
        try XCTSkipIf(photos.isEmpty, "needs MARKETING_PHOTOS")
        launch(["-newBookFromFixtureFolder", photos, "-ScreenshotMode", "NO"])
        guard element("page-thumbnail-0").waitForExistence(timeout: 40) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("no editor"); return
        }
        pause(4)
        selectPage(0)
        shot("07-cover", settle: 2)
        selectPage(pick("hero", default: 1))
        shot("10-hero", settle: 2)
        selectPage(pick("designed", default: 5))
        shot("02-designed", settle: 2)

        selectPage(pick("emphasize", default: 7))
        pause(1)
        let slots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        for index in 0..<min(slots.count, 8) {
            let slot = slots.element(boundBy: index)
            guard slot.exists, slot.isHittable else { continue }
            slot.click()
            pause(0.8)
            let key = element("photo-action-key")
            if key.waitForExistence(timeout: 3), key.isEnabled {
                key.click()
                shot("05-emphasize", settle: 1.5)
                break
            }
            slot.click()
        }

        let spread = pick("spread", default: 9)
        selectPage(spread)
        pause(1)
        let pageMenu = app.toolbars.descendants(matching: .any).matching(NSPredicate(format: "label == 'Page'")).firstMatch
        if pageMenu.waitForExistence(timeout: 5) {
            pageMenu.click()
            let merge = app.menuItems["Merge Facing Pages"]
            if merge.waitForExistence(timeout: 3), merge.isEnabled {
                merge.click()
                pause(1.5)
                for template in ["spread-split-two-thirds", "spread-split-two-thirds-3", "spread-panorama-band-3",
                                 "spread-hero-strip", "spread-center-columns-3", "spread-center-columns-5"] {
                    let option = element("spread-template-strip-\(template)")
                    if option.exists, option.isHittable { option.click(); break }
                }
                shot("06-spreads", settle: 2)
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
        }

        // Export to the finished preview; the save panel goes to MARKETING_EXPORT.
        click("toolbar-export")
        guard element("preflight-continue").waitForExistence(timeout: 20) else { return }
        click("preflight-continue")
        click("export-type-digital")
        click("export-single-file")
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 30), let folder = env["MARKETING_EXPORT"] {
            pause(1)
            app.typeKey("g", modifierFlags: [.command, .shift])
            pause(1)
            app.typeText(folder + "\n")
            pause(1.5)
            app.typeKey(.return, modifierFlags: [])
        }
        if element("export-next").waitForExistence(timeout: 60) {
            let motion = element("export-background-motion")
            if motion.exists { motion.click() }
            shot("03-export", settle: 5)
        } else {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("export never finished")
        }
        app.terminate()
    }
}
