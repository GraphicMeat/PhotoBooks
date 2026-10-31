import Photos
import UIKit
import XCTest

/// App Store marketing captures: real screens of a "Summer by the Sea" book,
/// stills plus the app-preview beats. Driven by `scripts/marketing/capture.sh`
/// on the Mac mini, which owns every screenshot, recording and hinge move.
///
/// Host handshake (env `MARKETING_HOST_SYNC=1`): the test writes
/// `marketing-sync/ready-<name>` into this runner's tmp directory with a list
/// of host commands (`shot`, `rec:<beat>`, `recouter:`/`recinner:<beat>`,
/// `stop`, `closed`/`flat`, `hinge:<deg>`, `wait:<s>`, `cleardocs`) and
/// blocks until the host
/// writes `done-<name>`. `shot` saves `<device>/<name>.png`. Without the host
/// every checkpoint is a no-op. Tree dumps for failed steps land in
/// `marketing-dumps/`, which the host copies out.
///
/// Env: MARKETING_PHOTOS (host folder of the prepared photos),
/// MARKETING_BEATS=1 (record beats 01-05 after the picker still),
/// MARKETING_UNFOLD=1 (iPhone Duo unfold recording), MARKETING_SURVEY=1
/// (capture every spread to choose from), MARKETING_PICKS
/// ("designed=5,spread=9,emphasize=7,hero=1": page indexes of the fixture book).
final class MarketingCaptureUITests: XCTestCase {

    /// The album and book title, localized by the host (MARKETING_TITLE).
    static var title: String { ProcessInfo.processInfo.environment["MARKETING_TITLE"] ?? "Summer by the Sea" }
    /// App language and region (MARKETING_LANGUAGE / MARKETING_REGION).
    static var language: String { ProcessInfo.processInfo.environment["MARKETING_LANGUAGE"] ?? "en" }
    static var region: String { ProcessInfo.processInfo.environment["MARKETING_REGION"] ?? "en_US" }

    /// The app's own labels the test matches by text (compact toolbars drop
    /// identifiers), in each capture language.
    private static let labels: [String: [String: String]] = [
        "Page": ["de": "Seite", "fr": "Page", "es": "Página", "it": "Pagina", "ja": "ページ",
                 "ko": "페이지", "zh-Hans": "页面", "pt-BR": "Página"],
        "Book": ["de": "Buch", "fr": "Livre", "es": "Libro", "it": "Libro", "ja": "ブック",
                 "ko": "포토북", "zh-Hans": "相册", "pt-BR": "Livro"],
        "Export": ["de": "Exportieren", "fr": "Exporter", "es": "Exportar", "it": "Esporta", "ja": "書き出す",
                   "ko": "내보내기", "zh-Hans": "导出", "pt-BR": "Exportar"],
        "Merge Facing Pages": ["de": "Gegenüberliegende Seiten zusammenführen",
                               "fr": "Fusionner les pages en vis-à-vis", "es": "Combinar páginas enfrentadas",
                               "it": "Unisci le pagine affiancate", "ja": "見開きのページを結合",
                               "ko": "마주보는 페이지 병합", "zh-Hans": "合并相邻页面", "pt-BR": "Mesclar páginas opostas"],
        "Rename Book…": ["de": "Buch umbenennen…", "fr": "Renommer le livre…", "es": "Renombrar libro…",
                         "it": "Rinomina libro…", "ja": "ブックの名前を変更…", "ko": "책 이름 변경…",
                         "zh-Hans": "重命名图书…", "pt-BR": "Renomear livro…"],
        // System document browser.
        "Create Document": ["de": "Dokument erstellen", "fr": "Créer un document", "es": "Crear documento",
                            "it": "Crea documento", "ja": "書類を作成", "ko": "문서 생성",
                            "zh-Hans": "创建文稿", "pt-BR": "Criar Documento"],
        "Replace": ["de": "Ersetzen", "fr": "Remplacer", "es": "Reemplazar", "it": "Sostituisci",
                    "ja": "置き換える", "ko": "대치", "zh-Hans": "替换", "pt-BR": "Substituir"]
    ]

    /// `english` in the capture language (falls back to English).
    static func tr(_ english: String) -> String { labels[english]?[language] ?? english }

    private var app: XCUIApplication!
    private let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    private var sync: URL { tmp.appendingPathComponent("marketing-sync", isDirectory: true) }
    private var dumps: URL { tmp.appendingPathComponent("marketing-dumps", isDirectory: true) }
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var hostSync: Bool { env["MARKETING_HOST_SYNC"] == "1" }
    private var photos: String { env["MARKETING_PHOTOS"] ?? "" }
    private var recordBeats: Bool { env["MARKETING_BEATS"] == "1" }
    private var survey: Bool { env["MARKETING_SURVEY"] == "1" }

    @MainActor
    private func pick(_ key: String, default value: Int) -> Int {
        for pair in (env["MARKETING_PICKS"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, parts[0] == key, let number = Int(parts[1]) { return number }
        }
        return value
    }

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.removeItem(at: sync)
        try? FileManager.default.createDirectory(at: dumps, withIntermediateDirectories: true)
    }

    /// A document left open is restored on the next launch.
    @MainActor
    private func closeDocument() {
        if let app, app.state == .runningForeground {
            let close = app.buttons["BackButton"]
            if close.exists, close.isHittable { close.tap(); pause(1) }
        }
    }

    // MARK: Host handshake

    @MainActor
    @discardableResult
    private func host(_ name: String, _ commands: String) -> Bool {
        guard hostSync else { return true }
        try? FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        let done = sync.appendingPathComponent("done-\(name)")
        try? commands.write(to: sync.appendingPathComponent("ready-\(name)"), atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(300)
        while !FileManager.default.fileExists(atPath: done.path) {
            guard Date() < deadline else {
                XCTFail("Host never finished \(name)")
                return false
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return true
    }

    /// Captures the current screen as `<device>/<name>.png` once it settles.
    @MainActor
    private func shot(_ name: String, settle: TimeInterval = 1.2) {
        pause(settle)
        host(name, "shot")
        checkNoBlurb(name)
    }

    /// App Store rule: no other marketplace's name on screen. Logs any
    /// on-screen "Blurb" text (preset names, export targets) per capture.
    @MainActor
    private func checkNoBlurb(_ name: String) {
        guard let app else { return }
        let window = app.windows.firstMatch.frame
        let texts = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Blurb'"))
        var seen: [String] = []
        for index in 0..<min(texts.count, 30) {
            let text = texts.element(boundBy: index)
            if text.exists, text.frame.intersects(window), !text.frame.isEmpty { seen.append(text.label) }
        }
        guard !seen.isEmpty else { return }
        let line = "\(name): \(seen.joined(separator: " | "))\n"
        let file = dumps.appendingPathComponent("blurb-visible.txt")
        let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? (previous + line).write(to: file, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func dump(_ name: String) {
        let text = app?.debugDescription ?? "no app"
        try? text.write(to: dumps.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        add(XCTAttachment(string: text))
    }

    // MARK: Element helpers

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func anyElement(_ identifiers: [String]) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", identifiers)).firstMatch
    }

    @MainActor
    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 20,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement? {
        let found = element(identifier)
        guard found.waitForExistence(timeout: timeout) else {
            dump("missing-\(identifier)")
            XCTFail("\(identifier) did not appear", file: file, line: line)
            return nil
        }
        return found
    }

    @MainActor
    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 20,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let found = waitFor(identifier, timeout: timeout, file: file, line: line) else { return false }
        found.tap()
        return true
    }

    @MainActor
    private func firstHittable(_ query: XCUIElementQuery, where accept: (XCUIElement) -> Bool = { _ in true })
        -> XCUIElement? {
        for index in 0..<min(query.count, 60) {
            let candidate = query.element(boundBy: index)
            if candidate.exists, candidate.isHittable, accept(candidate) { return candidate }
        }
        return nil
    }

    /// A hittable button (or menu item / cell) with one of these labels.
    @MainActor
    private func labeled(_ labels: [String], timeout: TimeInterval = 8) -> XCUIElement? {
        let predicate = NSPredicate(format: "label IN %@", labels)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in [app.buttons, app.menuItems, app.cells, app.staticTexts] {
                if let hit = firstHittable(query.matching(predicate)) { return hit }
            }
            pause(0.4)
        } while Date() < deadline
        return nil
    }

    @MainActor
    private var isRegular: Bool { element("page-thumbnail-0").exists }

    @MainActor
    private func launch(_ arguments: [String]) {
        XCUIDevice.shared.orientation = .portrait   // iPad captures are portrait
        app = XCUIApplication()
        app.launchArguments = arguments + [
            "-AppleLanguages", "(\(Self.language))", "-AppleLocale", Self.region,
            "-editor-canvas-background-mode", "white"
        ]
        app.launch()
    }

    /// Opens a NEW document from the iOS document browser, closing any
    /// document the relaunch restored first, then waits for `identifiers`.
    @MainActor
    @discardableResult
    private func openNewDocument(waitingFor identifiers: [String], timeout: TimeInterval = 40) -> Bool {
        let names = ["Create Document", Self.tr("Create Document")]
        let named = app.buttons.matching(
            NSPredicate(format: "label IN %@ OR identifier ==[c] 'Create Document'", names)).firstMatch
        // In any language the browser's primary action is its second button
        // (after Back), should the localized name differ from the table.
        let restored = anyElement(["toolbar-book-menu", "welcome-create", "curation-use-all",
                                   "curation-continue", "source-photos", "select-page-0", "page-thumbnail-0"])
        var create: XCUIElement { named.exists || restored.exists ? named : app.buttons.element(boundBy: 1) }
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if create.exists, create.isHittable { break }
            if restored.exists {
                let close = app.buttons["BackButton"]
                if close.exists, close.isHittable { close.tap(); pause(1.5); continue }
            }
            pause(0.5)
        }
        guard create.exists, create.isHittable else {
            dump("no-document-browser")
            XCTFail("document browser never offered Create Document")
            return false
        }
        create.tap()
        let target = anyElement(identifiers)
        if !target.waitForExistence(timeout: 15), create.exists, create.isHittable { create.tap() }
        guard target.waitForExistence(timeout: timeout) else {
            dump("new-document-\(identifiers.first ?? "")")
            XCTFail("new document never showed \(identifiers)")
            return false
        }
        return true
    }

    // MARK: Scrolling

    /// A slow drag that scrolls without flinging. It starts in the left
    /// margin: on a photo it could move the photo, and on the right edge it
    /// grabs the scroll indicator, which scrubs the list the other way.
    @MainActor
    private func drag(by deltaY: CGFloat, velocity: XCUIGestureVelocity = .slow, hold: TimeInterval = 0.3,
                      x: CGFloat? = nil) {
        let frame = app.windows.firstMatch.frame
        let x = x ?? 10
        let startY = deltaY < 0 ? frame.height * 0.72 : frame.height * 0.30
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x, dy: startY))
        let end = origin.withOffset(CGVector(dx: x, dy: startY + deltaY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: hold)
    }

    @MainActor
    private var contentTop: CGFloat {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.frame.maxY : 100
    }

    /// Compact layout: scrolls the page list so page `index` starts just
    /// under the navigation bar.
    @MainActor
    private func scrollCompact(toPage index: Int) {
        for _ in 0..<40 {
            if index == 0 {
                let cover = element("cover-sheet")
                if cover.exists, cover.frame.minY > contentTop { return }
                drag(by: 600)
                continue
            }
            let anchor = element("select-page-\(index - 1)")
            if anchor.exists, !anchor.frame.isEmpty {
                let delta = anchor.frame.maxY + 8 - contentTop
                if abs(delta) < 14 { return }
                drag(by: -max(-600, min(600, delta)))
            } else {
                // Lazily rendered: page index above or below the window?
                let rendered = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'select-page-'"))
                let first = rendered.count > 0 ? rendered.element(boundBy: 0).identifier : "select-page-0"
                let visible = Int(first.dropFirst("select-page-".count)) ?? 0
                drag(by: visible < index ? -600 : 600)
            }
        }
    }

    /// Regular layout: selects page `index` in the sidebar.
    @MainActor
    @discardableResult
    private func selectThumbnail(_ index: Int) -> Bool {
        let thumbnail = element("page-thumbnail-\(index)")
        // The iPhone Duo's inner display collapses the sidebar after a pick.
        if !element("page-thumbnail-0").exists, element("sidebar-toggle").exists {
            element("sidebar-toggle").tap()
            _ = element("page-thumbnail-0").waitForExistence(timeout: 3)
        }
        let list = app.collectionViews.containing(NSPredicate(
            format: "identifier BEGINSWITH 'page-thumbnail-'")).firstMatch
        for _ in 0..<8 where !(thumbnail.exists && thumbnail.isHittable) {
            guard list.exists else { break }
            // Down the list when the target lies below what is rendered.
            let rendered = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'page-thumbnail-'"))
            let last = rendered.count > 0 ? rendered.element(boundBy: rendered.count - 1).identifier : ""
            let lastIndex = Int(last.dropFirst("page-thumbnail-".count)) ?? 0
            // Rendered rows run past the visible ones, so go by position.
            let below = thumbnail.exists ? thumbnail.frame.midY > list.frame.midY : lastIndex < index
            if below { list.swipeUp(velocity: .slow) } else { list.swipeDown(velocity: .slow) }
            pause(0.6)
        }
        guard thumbnail.exists else {
            dump("no-thumbnail-\(index)")
            return false
        }
        thumbnail.tap()
        return true
    }

    @MainActor
    private func showPage(_ index: Int) {
        if isRegular { selectThumbnail(index) } else { scrollCompact(toPage: index) }
    }

    // MARK: Toolbar

    /// Taps a toolbar control, through the overflow menu on compact widths
    /// (which drops identifiers, so menu rows go by label).
    @MainActor
    @discardableResult
    private func tapToolbar(_ identifier: String, label: String) -> Bool {
        let direct = element(identifier)
        if direct.exists, direct.isHittable { direct.tap(); return true }
        let byLabel = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if byLabel.exists, byLabel.isHittable { byLabel.tap(); return true }
        let overflow = app.buttons.matching(NSPredicate(
            format: "identifier ENDSWITH 'OverflowBarButtonItem'")).firstMatch
        guard overflow.exists else {
            dump("no-toolbar-\(identifier)")
            return false
        }
        overflow.tap()
        guard let row = labeled([label]) else {
            dump("no-overflow-\(identifier)")
            return false
        }
        row.tap()
        return true
    }

    /// Opens the Page menu and picks `item`.
    @MainActor
    @discardableResult
    private func pageMenu(_ item: String) -> Bool {
        guard tapToolbar("toolbar-page-menu", label: Self.tr("Page")), let row = labeled([item, Self.tr(item)]) else {
            dump("page-menu-\(item)")
            return false
        }
        guard row.isEnabled else {
            // A tap outside an open menu only dismisses it.
            for _ in 0..<3 where row.exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
                pause(0.8)
            }
            return false
        }
        row.tap()
        return true
    }

    // MARK: 1. Photos library album (runner-side PhotoKit, no app code)

    /// Gathers the photos the host added with `simctl addmedia` (dated July
    /// 2026 by prepare-photos.swift) into a "Summer by the Sea" album.
    @MainActor
    func test1PhotosAlbum() throws {
        try XCTSkipUnless(hostSync, "host-driven")
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        try? "runner photos status: \(status.rawValue)\n".write(
            to: dumps.appendingPathComponent("album-status.txt"), atomically: true, encoding: .utf8)
        guard status == .authorized else {
            XCTFail("runner has no Photos access (status \(status.rawValue))")
            return
        }
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var existing: PHAssetCollection?
        albums.enumerateObjects { album, _, _ in
            if album.localizedTitle == Self.title { existing = album }
        }
        if let existing, PHAsset.fetchAssets(in: existing, options: nil).count >= 24 { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let all = PHAsset.fetchAssets(with: .image, options: options)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        var story: [PHAsset] = []
        all.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate, date >= start, date < end { story.append(asset) }
        }
        try? "story assets: \(story.count) of \(all.count)\n".write(
            to: dumps.appendingPathComponent("album-assets.txt"), atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(story.count, 24, "addmedia photos not found in the library")
        try PHPhotoLibrary.shared().performChangesAndWait {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.title)
            request.addAssets(story as NSArray)
        }
    }

    // MARK: Document + editor chrome

    /// Renames the open document (the iOS bar shows its file name, "Untitled
    /// N", outside the editor) to the book title.
    @MainActor
    private func renameDocument() {
        guard env["MARKETING_RENAME"] == "1" else { return }   // unreliable: off by default
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Untitled'")).firstMatch
        guard title.waitForExistence(timeout: 5) else {
            dump("rename-no-title")
            return
        }
        title.tap()
        guard let rename = labeled(["Rename"], timeout: 5) else {
            dump("rename-no-menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        rename.tap()
        // The title turns into a selected, focused field (with the keyboard
        // up) that the query tree does not expose; type into the focus.
        pause(1.5)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        app.typeText(Self.title + "\n")
        pause(1.5)
        if !app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.title))
            .firstMatch.exists {
            dump("rename-result")
        }
    }

    /// Closes the photo tray if it is showing (it opens on its own on the
    /// iPhone Duo's inner display).
    @MainActor
    private func closeTray() {
        if element("photo-tray").exists, element("tray-toggle").exists, element("tray-toggle").isHittable {
            element("tray-toggle").tap()
            pause(1.0)
        }
    }

    /// Regular layout: shows or hides the page sidebar.
    @MainActor
    private func setSidebar(visible: Bool) {
        guard isRegular || element("sidebar-toggle").exists else { return }
        if element("page-thumbnail-0").exists != visible, element("sidebar-toggle").exists {
            element("sidebar-toggle").tap()
            pause(1.0)
        }
    }

    /// The iPhone Duo's inner display can bring the sidebar up as an overlay
    /// that dims the page behind it; hide it then (the page shows larger).
    @MainActor
    private func avoidSidebarOverlay() {
        let thumb = element("page-thumbnail-0")
        let detail = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'cover-sheet' OR identifier BEGINSWITH 'slot-photo-'")).firstMatch
        guard element("sidebar-toggle").exists, thumb.exists, detail.exists else { return }
        if detail.frame.minX < thumb.frame.maxX - 4 { setSidebar(visible: false) }
    }

    /// Compact layout: selects page `index` (its check mark) so the Page
    /// menu acts on it.
    @MainActor
    private func selectPage(_ index: Int) {
        if isRegular {
            selectThumbnail(index)
        } else {
            scrollCompact(toPage: index)
            let select = element("select-page-\(index)")
            if select.exists, select.isHittable { select.tap() }
        }
        pause(0.6)
    }

    // MARK: 2. Picker still + app-preview beats (real Photos flow)

    @MainActor
    func test2PickAndBeats() throws {
        try XCTSkipUnless(hostSync, "host-driven")
        defer { closeDocument() }
        host("clear-documents", "cleardocs")
        launch([])
        guard openNewDocument(waitingFor: ["welcome-create"]) else { return }
        renameDocument()
        pause(1.5)
        if recordBeats { host("beat-01-start", "rec:beat-01-pick"); pause(1.2) }

        tap("welcome-create")
        guard waitFor("source-photos") != nil else { return }
        pause(1.0)
        tap("source-photos")

        // The system picker runs out of process; go by labels.
        // Collections, in any language: the second segment of the phone
        // picker's Photos | Collections switch, or the iPad sidebar's
        // "collections" row.
        let segments = app.segmentedControls.firstMatch
        let sidebarRow = app.cells.matching(identifier: "collections").firstMatch
        let pickerShown = Date().addingTimeInterval(20)
        while Date() < pickerShown, !segments.exists, !sidebarRow.exists { pause(0.5) }
        let collections: XCUIElement? = segments.exists && segments.buttons.count >= 2
            ? segments.buttons.element(boundBy: 1)
            : sidebarRow.exists ? sidebarRow : labeled(["Collections", "Albums"], timeout: 5)
        guard let collections else {
            dump("picker-open")
            XCTFail("Photos picker never showed Collections")
            return
        }
        pause(1.2)
        collections.tap()
        pause(1.5)
        let album = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Self.title)).firstMatch
        guard album.waitForExistence(timeout: 10) else {
            dump("picker-collections")
            XCTFail("album not listed")
            return
        }
        shot("01-pick", settle: 1.5)
        guard recordBeats else { return }
        album.tap()
        pause(1.6)

        // Select the album's photos at an unhurried tapping pace: the first
        // screen, then one slow scroll for more.
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        let isRegularPicker = app.windows.firstMatch.frame.width > 600
        var picked = 0
        for pass in 0..<2 {
            for index in 0..<min(cells.count, 60) where picked < 26 {
                let cell = cells.element(boundBy: index)
                // Not under the floating "Show Selected" button either.
                guard cell.exists, cell.isHittable, !cell.isSelected,
                      cell.frame.minY > contentTop,
                      cell.frame.maxY < app.windows.firstMatch.frame.height - 110 else { continue }
                cell.tap()
                picked += 1
                pause(0.3)
            }
            // Wide pickers show plenty at once; their scroll gesture can also
            // land on the floating "Show Selected" button.
            if pass == 0, !isRegularPicker {
                drag(by: -320, velocity: XCUIGestureVelocity(400), hold: 0.3,
                     x: app.windows.firstMatch.frame.midX)
                pause(0.8)
            }
        }
        if picked == 0 {
            dump("picker-no-cells")
            XCTFail("no picker photo cells")
            return
        }
        pause(0.8)
        // The confirm check mark (identifier "Add"); in the regular-width
        // popover it can report not hittable, so tap its centre.
        let add = app.buttons.matching(identifier: "Add").firstMatch
        if !add.waitForExistence(timeout: 3) {
            // A stray tap opened the selection review; its Done returns.
            let done = app.buttons.matching(NSPredicate(format: "label == 'Done' AND identifier == ''")).firstMatch
            if done.exists { done.tap(); pause(1.0) }
        }
        guard add.waitForExistence(timeout: 5) else {
            dump("picker-no-add")
            XCTFail("no picker confirm button")
            return
        }
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(2.0)
        host("beat-01-stop", "stop")

        // Setup: keep every photo, a portrait magazine-size book (the style
        // step's summary names the preset, so never a Blurb one on camera).
        guard tap("curation-use-all", timeout: 30) else { return }
        guard waitFor("setup-shape-continue") != nil else { return }
        tap("setup-shape-portrait")
        tap("setup-shape-continue")
        guard waitFor("setup-format-continue") != nil else { return }
        let magazine = element("preset-magazine-premium")
        for _ in 0..<6 where !(magazine.exists && magazine.isHittable) {
            drag(by: -250, x: app.windows.firstMatch.frame.midX)
        }
        tap("preset-magazine-premium")
        tap("setup-format-continue")
        guard waitFor("setup-create-book") != nil else { return }
        pause(1.0)

        // Beat 2: the book builds itself, then a slow look through it.
        host("beat-02-start", "rec:beat-02-build")
        pause(1.2)
        tap("setup-create-book")
        guard anyElement(["select-page-0", "page-thumbnail-0"]).waitForExistence(timeout: 90) else {
            dump("beat-02-no-editor")
            XCTFail("editor never opened")
            return
        }
        closeTray()
        pause(5.0)   // Photos thumbnails arrive
        if isRegular {
            // A small book has few pages; stop at the last one.
            for page in [1, 3, 5, 7] where element("page-thumbnail-\(page)").exists {
                selectThumbnail(page)
                pause(2.6)
            }
        } else {
            for _ in 0..<4 {
                drag(by: -380, velocity: XCUIGestureVelocity(250), hold: 0.4)
                pause(2.0)
            }
        }
        pause(1.0)
        host("beat-02-stop", "stop")

        // Beat 3: tap a photo, make it the key photo, the page reflows.
        showPage(isRegular ? 3 : 2)
        pause(1.0)
        host("beat-03-start", "rec:beat-03-emphasize")
        pause(1.2)
        emphasizeAPhoto(recording: true)
        pause(1.5)
        host("beat-03-stop", "stop")
        deselectPhoto()

        // Beat 4: the cover gets its title.
        showPage(0)
        pause(1.0)
        host("beat-04-start", "rec:beat-04-cover")
        pause(1.2)
        typeCoverTitle()
        pause(2.0)
        host("beat-04-stop", "stop")
        renameBook()   // off camera: the bar and spine follow the cover

        // Beat 5: export to the finished preview. The export-type step lists
        // a Blurb target, so it is cut: 05a ends on the book check, 05 picks
        // up once Digital PDF is rendering.
        exportToFinishedPreview(recording: true)
        pause(4.0)
        host("beat-05-stop", "stop")
    }

    /// Selects a photo on the visible page (a mid-size one away from the
    /// edges, so the actions bar fits), and makes it the key photo twice so
    /// the reflow reads; returns false when no photo could grow.
    @MainActor
    @discardableResult
    private func emphasizeAPhoto(recording: Bool) -> Bool {
        let slots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        let window = app.windows.firstMatch.frame
        let top = contentTop
        var candidates: [XCUIElement] = []
        for index in 0..<min(slots.count, 40) {
            let slot = slots.element(boundBy: index)
            guard slot.exists, slot.isHittable else { continue }
            let frame = slot.frame
            guard frame.minY > top + 60, frame.maxY < window.height - 40 else { continue }
            candidates.append(slot)
        }
        // Nearest the middle first (the actions bar centres on the photo),
        // smaller before larger: growing a small one shows the reflow best.
        let midX = window.midX
        candidates.sort {
            let a = abs($0.frame.midX - midX) + sqrt($0.frame.width * $0.frame.height) * 0.3
            let b = abs($1.frame.midX - midX) + sqrt($1.frame.width * $1.frame.height) * 0.3
            return a < b
        }
        for slot in candidates.prefix(5) {
            slot.tap()
            pause(recording ? 1.5 : 0.8)
            let key = element("photo-action-key")
            if key.waitForExistence(timeout: 4), key.isEnabled {
                key.tap()
                pause(recording ? 1.6 : 1.0)
                if key.exists, key.isEnabled {
                    key.tap()
                    pause(recording ? 2.2 : 1.5)
                }
                return true
            }
            slot.tap()   // deselect, try another
            pause(0.5)
        }
        dump("emphasize-none")
        return false
    }

    /// Clears the photo selection (tapping a selected photo toggles it off).
    @MainActor
    private func deselectPhoto() {
        guard element("photo-actions-popover").exists else { return }
        let selected = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'slot-photo-' AND selected == YES")).firstMatch
        if selected.exists, selected.isHittable { selected.tap(); pause(0.6) }
    }

    /// Clears a text field and types `text` one letter at a time.
    @MainActor
    private func retype(_ field: XCUIElement, _ text: String) {
        // Tap past the end of the text so the caret lands after it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        pause(0.4)
        let current = (field.value as? String) ?? ""
        for _ in 0..<(current.count + 1) {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            Thread.sleep(forTimeInterval: 0.06)
        }
        pause(0.5)
        for character in text {
            field.typeText(String(character))
            Thread.sleep(forTimeInterval: 0.11)
        }
    }

    /// Opens the front-cover title and types the book title.
    @MainActor
    private func typeCoverTitle() {
        let texts = app.descendants(matching: .any).matching(identifier: "slot-text-0")
        guard let title = firstHittable(texts) else {
            dump("cover-no-title-slot")
            XCTFail("cover title slot not found")
            return
        }
        title.doubleTap()
        guard let field = waitFor("text-editor-field", timeout: 8) else { return }
        pause(1.0)
        retype(field, Self.title)
        pause(1.2)
        tap("text-editor-done")
    }

    /// Book → Rename Book… (the spine and the editor's title).
    @MainActor
    private func renameBook() {
        guard tapToolbar("toolbar-book-menu", label: Self.tr("Book")),
              let rename = labeled([Self.tr("Rename Book…")]) else {
            dump("rename-book")
            return
        }
        rename.tap()
        guard let field = waitFor("text-editor-field", timeout: 8) else { return }
        retype(field, Self.title)
        tap("text-editor-done")
        pause(1.0)
    }

    /// Export: check → Digital PDF → save → the finished-book preview.
    /// While recording, the export-type step (which names Blurb) stays off camera.
    @MainActor
    @discardableResult
    private func exportToFinishedPreview(recording: Bool) -> Bool {
        if recording { host("beat-05a-start", "rec:beat-05a-check"); pause(1.2) }
        guard tapToolbar("toolbar-export", label: Self.tr("Export")) else { return false }
        guard waitFor("preflight-continue") != nil else { return false }
        pause(recording ? 2.5 : 1.0)
        if recording { host("beat-05a-stop", "stop") }
        tap("preflight-continue")
        guard waitFor("export-type-digital") != nil else { return false }
        tap("export-type-digital")
        pause(0.4)
        tap("export-single-file")
        if recording { host("beat-05-start", "rec:beat-05-export") }
        // System save sheet (out of process).
        let save = app.buttons["DOCPicker.actionButton"]
        if !save.waitForExistence(timeout: 60) {
            dump("save-sheet")
            XCTFail("save sheet never appeared")
            return false
        }
        pause(recording ? 1.5 : 1.0)
        // The first tap can land while the sheet is still settling.
        // An earlier export of the same title asks to replace it; its
        // first button is Replace in every language.
        let replace = app.alerts.firstMatch.buttons.element(boundBy: 0)
        for _ in 0..<3 where save.exists {
            if save.isHittable { save.tap() }
            if replace.waitForExistence(timeout: 3) { replace.tap() }
            if save.waitForNonExistence(timeout: 5) { break }
        }
        guard waitFor("export-next", timeout: 60) != nil else { return false }
        return true
    }

    // MARK: 3. Setup stills (DEBUG fixture-folder path)

    @MainActor
    func test3SetupStills() throws {
        try XCTSkipUnless(hostSync && !photos.isEmpty, "host-driven, needs MARKETING_PHOTOS")
        defer { closeDocument() }
        host("clear-documents", "cleardocs")
        launch(["-ScreenshotSetupFixtureFolder", photos, "-ScreenshotReview", "YES",
                "-ScreenshotBookTitle", Self.title])
        guard openNewDocument(waitingFor: ["curation-continue", "curation-use-all"]) else { return }
        guard waitFor("curation-continue", timeout: 40) != nil else { return }
        renameDocument()
        shot("04-curate", settle: 3.0)

        tap("curation-continue")
        guard waitFor("setup-shape-continue") != nil else { return }
        tap("setup-shape-portrait")
        // Blurb-free alternative for 08 (shapes, no preset names).
        shot("08-format-shape", settle: 1.2)
        tap("setup-shape-continue")
        guard waitFor("setup-format-continue") != nil else { return }
        positionFormatGrid()
        shot("08-format", settle: 1.5)

        // Back to the welcome screen.
        for _ in 0..<6 where !element("welcome-create").exists {
            let back = element("setup-back")
            guard back.waitForExistence(timeout: 5) else { break }
            back.tap()
            pause(0.8)
        }
        guard waitFor("welcome-create") != nil else { return }
        shot("09-private", settle: 1.5)
    }

    /// Book size step, portrait: selects Trade 6x9 and scrolls the first
    /// card (Blurb 8x10) out of view wherever the grid scrolls that far.
    @MainActor
    private func positionFormatGrid() {
        let midX = app.windows.firstMatch.frame.midX
        let trade = element("preset-trade-6x9")
        for _ in 0..<6 where !(trade.exists && trade.isHittable) { drag(by: -250, x: midX) }
        guard trade.exists else { dump("format-no-trade"); return }
        trade.tap()
        pause(0.6)
        let blurb = element("preset-blurb-standard-portrait")
        for _ in 0..<6 where !(blurb.exists && blurb.isHittable) { drag(by: 250, x: midX) }
        guard blurb.exists else { return }
        // Shift by one row: to the first card below the Blurb card's row.
        let others = ["preset-generic-a4-portrait", "preset-trade-5x8", "preset-trade-6x9", "preset-magazine-premium"]
            .map(element).filter { $0.exists && $0.frame.minY > blurb.frame.minY + 10 }
        guard let next = others.min(by: { $0.frame.minY < $1.frame.minY }) else { return }
        let shift = next.frame.minY - blurb.frame.minY
        drag(by: -(shift + 4), x: midX)
        pause(0.5)
    }

    // MARK: 4. Editor stills (DEBUG deterministic fixture book)

    @MainActor
    func test4EditorStills() throws {
        try XCTSkipUnless(hostSync && !photos.isEmpty, "host-driven, needs MARKETING_PHOTOS")
        defer { closeDocument() }
        host("clear-documents", "cleardocs")
        launch(["-newBookFromFixtureFolder", photos, "-ScreenshotMode", "YES",
                "-ScreenshotBookTitle", Self.title])
        guard openNewDocument(waitingFor: ["select-page-0", "page-thumbnail-0"]) else { return }
        closeTray()
        pause(4.0)   // thumbnails decode
        let regular = isRegular

        // The editor opens on the cover.
        if regular { avoidSidebarOverlay() }
        shot("07-cover", settle: 1.5)

        showPage(pick("hero", default: 1))
        setSidebar(visible: true)
        if regular { avoidSidebarOverlay() }
        shot("10-hero", settle: 2.0)

        if survey {
            var index = 1
            while index < 60 {
                if regular { guard selectThumbnail(index) else { break } } else {
                    scrollCompact(toPage: index)
                    guard element("select-page-\(index)").exists else { break }
                }
                shot(String(format: "survey-%02d", index), settle: 1.5)
                index += 2
            }
        }

        showPage(pick("designed", default: 5))
        if regular { setSidebar(visible: false) }   // the spread, as large as it gets
        shot("02-designed", settle: 2.0)
        if regular { setSidebar(visible: true) }

        // Emphasize a photo; keep the actions bar up for the still.
        showPage(pick("emphasize", default: 7))
        pause(1.0)
        if emphasizeAPhoto(recording: false) { shot("05-emphasize", settle: 1.0) }
        deselectPhoto()

        // One photo across the gutter: thin the facing pair out to a photo
        // a page (the rest flow on), merge it and pick a template whose
        // first photo spans two thirds of the spread.
        let left = pick("spread", default: 9)
        let center = thinPair(left: left)
        // Select the left page through one of its photos (reliable on every
        // layout), then let go of the photo; the page stays selected.
        if let slot = focusPage(left, center: center) { slot.tap(); pause(0.6) }
        if pageMenu("Merge Facing Pages") {
            pause(1.5)
            for template in ["spread-split-two-thirds", "spread-panorama", "spread-split-two-thirds-3",
                             "spread-panorama-band-3", "spread-hero-strip"] {
                let option = element("spread-template-strip-\(template)")
                if option.exists, option.isHittable { option.tap(); break }
            }
            pause(1.5)
            if regular { setSidebar(visible: false) } else { scrollCompact(toPage: left) }
            shot("06-spreads", settle: 1.5)
            if regular { setSidebar(visible: true) }
        }

        // Export through to the finished-book preview.
        if exportToFinishedPreview(recording: false) {
            pause(1.0)
            let motion = element("export-background-motion")
            if motion.exists, motion.isHittable { motion.tap() }
            shot("03-export", settle: 5.0)
        }
    }

    /// Photo slots of page `page`: on compact widths those between its
    /// neighbours' captions; on regular widths the left or right half of the
    /// spread on screen (split at `center`).
    @MainActor
    private func slots(onPage page: Int, center: CGFloat?) -> [XCUIElement] {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'slot-photo-'"))
        var found: [XCUIElement] = []
        let window = app.windows.firstMatch.frame
        var top = contentTop, bottom = window.height
        if center == nil {
            let above = element("select-page-\(page - 1)"), below = element("select-page-\(page)")
            if above.exists { top = max(top, above.frame.maxY) }
            if below.exists { bottom = min(bottom, below.frame.minY) }
        }
        for index in 0..<min(query.count, 60) {
            let slot = query.element(boundBy: index)
            guard slot.exists, slot.isHittable else { continue }
            let frame = slot.frame
            if let center {
                guard (frame.midX < center) == (page % 2 == 1) else { continue }
            } else {
                guard frame.midY > top, frame.midY < bottom else { continue }
            }
            found.append(slot)
        }
        return found
    }

    /// Selects a photo on page `page` (which selects the page) and returns it.
    @MainActor
    @discardableResult
    private func focusPage(_ page: Int, center: CGFloat?) -> XCUIElement? {
        if center == nil { scrollCompact(toPage: page) }
        guard let slot = slots(onPage: page, center: center).first else { return nil }
        slot.tap()
        pause(0.7)
        // Tapping the photo that was already selected lets go of it instead.
        if !element("photo-actions-popover").exists { slot.tap(); pause(0.7) }
        return slot
    }

    /// Leaves one photo on each page of the facing pair `left`/`left + 1`
    /// with the actions bar's "Fewer" (the extra photos flow to later
    /// pages). Returns the spread's centre line on regular widths.
    @MainActor
    private func thinPair(left: Int) -> CGFloat? {
        let regular = isRegular
        var center: CGFloat?
        if regular {
            selectThumbnail(left)
            pause(1.0)
            let all = slots(onPage: 1, center: .greatestFiniteMagnitude) + slots(onPage: 2, center: -1)
            guard let minX = all.map({ $0.frame.minX }).min(), let maxX = all.map({ $0.frame.maxX }).max() else { return nil }
            center = (minX + maxX) / 2
        }
        // Bounded: on the iPhone Duo's inner display this can stall.
        let giveUp = Date().addingTimeInterval(150)
        for _ in 0..<16 where Date() < giveUp {
            var page: Int?
            for candidate in [left + 1, left] {
                if !regular { scrollCompact(toPage: candidate) }
                if slots(onPage: candidate, center: center).count > 1 { page = candidate; break }
            }
            guard let page, focusPage(page, center: center) != nil else { break }
            let fewer = element("photo-action-smaller")
            guard fewer.waitForExistence(timeout: 3), fewer.isEnabled else {
                dump("thin-no-fewer")
                deselectPhoto()
                break
            }
            fewer.tap()
            pause(1.0)
        }
        return center
    }

    // MARK: 5. iPhone Duo unfold

    /// The simulator records one display at a time: the outer display with
    /// the editor open, then the inner display from just before it lights
    /// up through the unfold.
    @MainActor
    func test5Unfold() throws {
        try XCTSkipUnless(hostSync && env["MARKETING_UNFOLD"] == "1" && !photos.isEmpty, "Duo only")
        defer { closeDocument() }
        host("clear-documents", "cleardocs")
        host("unfold-fold", "closed")
        launch(["-newBookFromFixtureFolder", photos, "-ScreenshotMode", "YES",
                "-ScreenshotBookTitle", Self.title])
        guard openNewDocument(waitingFor: ["select-page-0", "page-thumbnail-0"]) else { return }
        pause(4.0)
        host("unfold-outer", "recouter:beat-unfold")
        pause(1.2)
        drag(by: -260, velocity: XCUIGestureVelocity(180), hold: 0.5)
        pause(1.5)
        host("unfold-inner",
             "stop recinner:beat-unfold wait:0.5 hinge:30 wait:0.25 hinge:60 wait:0.25 hinge:90 "
             + "wait:0.25 hinge:120 wait:0.25 hinge:150 wait:0.25 flat wait:4 stop")
        XCTAssertTrue(element("page-thumbnail-0").waitForExistence(timeout: 10),
                      "the unfolded inner display should show the sidebar")
    }
}
