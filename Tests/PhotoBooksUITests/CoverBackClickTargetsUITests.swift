import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Regression for "clicking the left (back) cover page sometimes does not
/// select it": the spine's title subtree used to be laid out as a
/// sheet-height square centred on the spine, invisible thanks to `.clipped()`
/// but still hit-testable, and it sat above the back panel in z-order — so
/// every click on the back cover's right half died in the spine. The front
/// cover's full-bleed photo also overflows its slot (aspect-fill) and used to
/// swallow clicks on the strip of back cover it covers.
///
/// Every sampled point on the back cover must select the BACK cover's photo
/// (actions popover over the back panel, not the front one).
final class CoverBackClickTargetsUITests: XCTestCase {

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

    /// Six fixtures; the first (the front cover photo) is LANDSCAPE so that on
    /// the square fixture preset it aspect-fills wider than its slot — the
    /// overflow case this test guards.
    private func makeFixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooksCoverClickUITests-\(UUID().uuidString)",
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

    /// Real click at a point, routed through the window's coordinate space
    /// (`XCUIElement.click()` mis-targets inside the zoomable canvas).
    @MainActor
    private func click(_ app: XCUIApplication, at point: CGPoint) {
        let window = app.windows.firstMatch
        let wf = window.frame
        window.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - wf.minX) / wf.width,
            dy: (point.y - wf.minY) / wf.height)).click()
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
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        expectation(for: NSPredicate(format: "count >= 1"), evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        thumbnails.element(boundBy: 0).click()
        XCTAssertTrue(element(app, "cover-sheet").waitForExistence(timeout: 15),
                      "cover sheet should be visible")
        return app
    }

    /// Clicks `fraction` of the way across `slot`, expects the photo-actions
    /// popover to appear on `expectedSide` of the spine, then clears the
    /// selection with Escape so the next sample starts clean.
    @MainActor
    private func assertClickSelects(_ app: XCUIApplication, slot: XCUIElement,
                                    fx: CGFloat, fy: CGFloat, expectBack: Bool,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let spine = element(app, "cover-spine-edit").frame
        let f = slot.frame
        let point = CGPoint(x: f.minX + f.width * fx, y: f.minY + f.height * fy)
        click(app, at: point)
        let popover = element(app, "photo-actions-popover")
        let appeared = popover.waitForExistence(timeout: 3)
        XCTAssertTrue(appeared,
                      "click at (\(fx), \(fy)) of the \(expectBack ? "back" : "front") cover selected nothing",
                      file: file, line: line)
        if appeared {
            let midX = popover.frame.midX
            if expectBack {
                XCTAssertLessThan(midX, spine.minX,
                                  "click at (\(fx), \(fy)) selected the FRONT cover instead of the back",
                                  file: file, line: line)
            } else {
                XCTAssertGreaterThan(midX, spine.maxX,
                                     "click at (\(fx), \(fy)) selected the BACK cover instead of the front",
                                     file: file, line: line)
            }
        }
        app.typeKey(.escape, modifierFlags: [])
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: popover)
        waitForExpectations(timeout: 5)
    }

    /// The bug as reported: only part of the back cover took a click. Every
    /// sampled point — including the right half that used to be dead and the
    /// strip covered by the front photo's aspect-fill overflow — must select
    /// the back cover.
    @MainActor
    func testEveryPointOnTheBackCoverSelectsTheBackCover() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = launchOnCoverSpread(fixtures: folder)

        let back = element(app, "backcover-slot-photo-0")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "back cover slot missing")

        // Positive control first: the centre-left always worked.
        assertClickSelects(app, slot: back, fx: 0.25, fy: 0.5, expectBack: true)
        for fy: CGFloat in [0.1, 0.5, 0.9] {
            for fx: CGFloat in [0.6, 0.75, 0.9, 0.97] {
                assertClickSelects(app, slot: back, fx: fx, fy: fy, expectBack: true)
            }
        }
    }

    /// Guards the other side of the fix: the front cover keeps winning its own
    /// edge next to the spine (it is the later sibling, drawn on top).
    @MainActor
    func testFrontCoverEdgeNextToTheSpineSelectsTheFrontCover() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = launchOnCoverSpread(fixtures: folder)

        let front = element(app, "slot-photo-0")
        XCTAssertTrue(front.waitForExistence(timeout: 10), "front cover slot missing")
        assertClickSelects(app, slot: front, fx: 0.04, fy: 0.1, expectBack: false)
        assertClickSelects(app, slot: front, fx: 0.04, fy: 0.9, expectBack: false)
    }
}
