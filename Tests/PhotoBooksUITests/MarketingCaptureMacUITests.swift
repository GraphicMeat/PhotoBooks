import CoreGraphics
import XCTest

/// App Store marketing captures on macOS: a 1440 x 900 pt light-mode window
/// (2880 x 1800 px on a 2x display). Stills are kept XCTAttachments named by
/// shot id. Beats are cut by `scripts/marketing/capture.sh` (device "mac") from
/// one screen recording around `test3RecordBeats`, which leaves a timeline of
/// wall-clock marks (see `cut-mac-beats.py`).
///
/// Env: MARKETING_PHOTOS (prepared photos in a folder the Debug app may read,
/// e.g. /private/tmp/...), MARKETING_EXPORT (an empty folder for the PDF),
/// MARKETING_PICKS (as the iOS class), MARKETING_BEAT_FOLDER (the photo folder
/// picked on camera; its name becomes the book title), MARKETING_BEAT_EXPORT
/// (an empty folder for the on-camera export).
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

    // MARK: Recorded beats

    private var timeline: [String] = []

    private func mark(_ event: String) {
        timeline.append(String(format: "%.3f ", Date().timeIntervalSince1970) + event)
    }

    /// The pointer's position, in the same top-left screen points as XCUI frames.
    private var pointer: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func placePointer(_ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(point)
    }

    /// An eased, unhurried pointer move (XCUI clicks jump there instantly).
    private func glide(to target: CGPoint) {
        let start = pointer
        let distance = hypot(target.x - start.x, target.y - start.y)
        let seconds = min(1.4, max(0.5, 0.4 + Double(distance) / 800))
        let began = Date()
        while true {
            let progress = min(1, Date().timeIntervalSince(began) / seconds)
            let eased = CGFloat(progress * progress * (3 - 2 * progress))
            placePointer(CGPoint(x: start.x + (target.x - start.x) * eased,
                                 y: start.y + (target.y - start.y) * eased))
            if progress >= 1 { break }
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
    }

    /// A warp moves the pointer without an event, so hover effects and the
    /// cursor's shape (still the resize arrows after sizing the window) only
    /// catch up with an XCUI hover at the end.
    @MainActor
    private func glide(to found: XCUIElement) {
        let frame = found.frame
        glide(to: CGPoint(x: frame.midX, y: frame.midY))
        found.hover()
    }

    /// Moves to a spot in the window, given as fractions of its size.
    @MainActor
    private func park(_ x: CGFloat, _ y: CGFloat) {
        let window = app.windows.firstMatch
        let frame = window.frame
        glide(to: CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y))
        window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).hover()
    }

    /// Moves to the element, waits, clicks it, waits: what a viewer can follow.
    @MainActor
    @discardableResult
    private func act(_ identifier: String, before: TimeInterval = 0.7, after: TimeInterval = 1.0,
                     timeout: TimeInterval = 30) -> Bool {
        let found = element(identifier)
        guard found.waitForExistence(timeout: timeout) else {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("\(identifier) did not appear")
            return false
        }
        glide(to: found)
        pause(before)
        mark("act click \(identifier)")
        found.click()
        pause(after)
        return true
    }

    /// App Store rule: no other marketplace's name on camera.
    @MainActor
    private func logBlurb(_ moment: String) {
        let window = app.windows.firstMatch.frame
        let texts = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Blurb'"))
        for index in 0..<min(texts.count, 10) {
            let text = texts.element(boundBy: index)
            if text.exists, text.frame.intersects(window), !text.frame.isEmpty {
                mark("blurb \(moment): \(text.label)")
            }
        }
    }

    @MainActor
    private func beatIn(_ name: String) {
        let window = app.windows.firstMatch
        if abs(window.frame.width - 1440) >= 1 || abs(window.frame.height - 900) >= 1 { sizeWindow() }
        let frame = window.frame
        mark("in \(name) \(frame.minX) \(frame.minY) \(frame.width) \(frame.height)")
        pause(1.2)
    }

    @MainActor
    private func beatOut(_ name: String) {
        mark("out \(name)")
    }

    /// Goes to a folder in the open or save panel (out of process, bridged into
    /// the app's tree) by typing its path.
    @MainActor
    private func goToFolder(_ path: String) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        pause(1.0)
        app.typeText(path)
        pause(1.0)
        app.typeKey(.return, modifierFlags: [])
        pause(1.8)
    }

    /// Clicks the open or save panel's default button; Return if it stays up.
    @MainActor
    private func confirmPanel() {
        let button = app.buttons["OKButton"]
        guard button.waitForExistence(timeout: 5) else {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("no panel button")
            return
        }
        glide(to: button)
        pause(0.7)
        mark("act click panel button")
        button.click()
        if !button.waitForNonExistence(timeout: 3) {
            mark("act return key in panel")
            app.typeKey(.return, modifierFlags: [])
        }
    }

    @MainActor
    func test3RecordBeats() throws {
        let folder = env["MARKETING_BEAT_FOLDER"] ?? ""
        try XCTSkipIf(folder.isEmpty, "needs MARKETING_BEAT_FOLDER")
        defer {
            let attachment = XCTAttachment(string: timeline.joined(separator: "\n") + "\n")
            attachment.name = "beat-timeline.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
            app?.terminate()
        }
        let screen = CGDisplayBounds(CGMainDisplayID())
        mark("screen \(screen.width) \(screen.height)")

        // Sync marks on a still desktop: the recording's first frame after
        // each gap is this pointer jump.
        for x in [40.0, 80.0] {
            placePointer(CGPoint(x: x - 20, y: 500))
            pause(3)
            mark("sync")
            placePointer(CGPoint(x: x, y: 500))
            pause(0.5)
        }

        launch(["-ScreenshotMode", "NO"])
        guard element("welcome-create").waitForExistence(timeout: 30) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("no welcome screen"); return
        }
        park(0.72, 0.8)
        pause(2)

        // Beat 1: from the welcome screen through the photo folder, the
        // curation review and the book's shape. The size step that follows
        // lists a Blurb preset in every shape, so it stays off camera.
        beatIn("beat-01-pick")
        logBlurb("welcome")
        guard act("welcome-create") else { return }
        guard element("source-folder").waitForExistence(timeout: 15) else { XCTFail("no source step"); return }
        logBlurb("source")
        guard act("source-folder", after: 1.6) else { return }
        // Going to the folder is cut: the sheet opens on the last typed path,
        // a temporary one.
        mark("skip-start")
        goToFolder(folder)
        mark("skip-end")
        pause(0.8)
        confirmPanel()
        guard act("curation-select-best", before: 1.4, after: 0.4, timeout: 60) else { return }
        logBlurb("curation")
        guard element("curation-continue").waitForExistence(timeout: 240) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("curation never finished"); return
        }
        mark("act analysis finished")
        pause(3.0)
        logBlurb("review")
        guard act("curation-continue", before: 1.2) else { return }
        guard element("setup-shape-portrait").waitForExistence(timeout: 15) else { XCTFail("no shape step"); return }
        logBlurb("shape")
        guard act("setup-shape-portrait", after: 1.4) else { return }
        let shapeContinue = element("setup-shape-continue")
        glide(to: shapeContinue)
        pause(1.0)
        beatOut("beat-01-pick")
        shapeContinue.click()

        // Off camera: the size step, Continue to the style step.
        click("preset-magazine-premium")
        pause(0.4)
        click("setup-format-continue")
        guard element("setup-create-book").waitForExistence(timeout: 15) else { XCTFail("no style step"); return }
        pause(1.0)

        // Beat 2: the book builds itself, then a slow look through it.
        beatIn("beat-02-build")
        logBlurb("style")
        guard act("setup-create-book", after: 0.2) else { return }
        guard element("page-thumbnail-0").waitForExistence(timeout: 180) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("editor never opened"); return
        }
        mark("act editor appeared")
        pause(4)
        logBlurb("editor")
        for page in [1, 3, 5, 7] where element("page-thumbnail-\(page)").exists {
            guard act("page-thumbnail-\(page)", before: 0.7, after: 2.4) else { return }
        }
        beatOut("beat-02-build")

        // Beat 3: click a photo, make it the key photo, the page reflows.
        selectPage(pick("beat-emphasize", default: 3))
        pause(1.5)
        beatIn("beat-03-emphasize")
        emphasizeAPhoto()
        pause(1.5)
        beatOut("beat-03-emphasize")
        app.typeKey(.escape, modifierFlags: [])
        pause(0.6)

        // Beat 4: the wraparound cover.
        beatIn("beat-04-cover")
        guard act("page-thumbnail-0", after: 1.5) else { return }
        logBlurb("cover")
        park(0.6, 0.5)
        pause(2.5)
        beatOut("beat-04-cover")

        // Beat 5a: the book check. The export-type step that follows names
        // Blurb, so it stays off camera, as on iOS.
        beatIn("beat-05a-check")
        guard act("toolbar-export", after: 0.2) else { return }
        guard element("preflight-continue").waitForExistence(timeout: 30) else { XCTFail("no preflight"); return }
        logBlurb("preflight")
        pause(2.0)
        let preflightContinue = element("preflight-continue")
        glide(to: preflightContinue)
        pause(0.6)   // before its tooltip
        beatOut("beat-05a-check")
        preflightContinue.click()
        click("export-type-digital")
        click("export-single-file")
        park(0.88, 0.7)   // off the Cancel button that takes Export's place

        // Beat 5: rendering, the save panel, the finished preview. Going to
        // the folder is cut here too.
        beatIn("beat-05-export")
        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: 60) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("no save sheet"); return
        }
        pause(1.2)
        if let exportFolder = env["MARKETING_BEAT_EXPORT"] {
            mark("skip-start")
            goToFolder(exportFolder)
            mark("skip-end")
        }
        pause(0.8)
        confirmPanel()
        guard element("export-next").waitForExistence(timeout: 120) else {
            add(XCTAttachment(string: app.debugDescription)); XCTFail("export never finished"); return
        }
        mark("act finished preview")
        logBlurb("finished")
        pause(6)
        beatOut("beat-05-export")
    }

    /// Clicks a photo near the middle of the page and presses Make key until it
    /// can grow no further. Only that last press reflows: a photo leaves its
    /// page's packing once its weight reaches the page maximum (6, from 1 in
    /// steps of 2 unless the book was made with Emphasize standouts).
    @MainActor
    private func emphasizeAPhoto() {
        let slots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        let window = app.windows.firstMatch.frame
        var candidates: [(slot: XCUIElement, score: CGFloat)] = []
        for index in 0..<min(slots.count, 20) {
            let slot = slots.element(boundBy: index)
            guard slot.exists, slot.isHittable else { continue }
            let frame = slot.frame
            guard frame.minX > window.minX + 240, frame.minY > window.minY + 110 else { continue }
            candidates.append((slot, abs(frame.midX - window.midX) + sqrt(frame.width * frame.height) * 0.3))
        }
        for candidate in candidates.sorted(by: { $0.score < $1.score }).prefix(5) {
            glide(to: candidate.slot)
            pause(0.9)
            mark("act click photo")
            candidate.slot.click()
            pause(1.2)
            let key = element("photo-action-key")
            if key.waitForExistence(timeout: 3), key.isEnabled {
                var presses = 0
                while presses < 4, key.exists, key.isEnabled {
                    glide(to: key)
                    pause(0.6)
                    presses += 1
                    mark("act click key photo (press \(presses))")
                    key.click()
                    pause(1.4)
                }
                mark("act key photo pressed \(presses) times")
                pause(1.5)
                return
            }
            candidate.slot.click()   // deselect, try another
            pause(0.5)
        }
        add(XCTAttachment(string: app.debugDescription))
        XCTFail("no photo could become the key photo")
    }
}
