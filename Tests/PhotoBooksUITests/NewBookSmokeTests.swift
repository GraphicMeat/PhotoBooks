import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// macOS smoke test: launch with `-newBookFromFixtureFolder <path>` pointing
/// at six runtime-generated images, force a new document, and assert the
/// sidebar shows at least three page thumbnails (cover + interior pages).
final class NewBookSmokeTests: XCTestCase {

    /// Generates one solid-color PNG (same CGContext → CGImageDestination
    /// pattern as PhotoBookImport's FixtureFactory; inlined because UITest
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

    @MainActor
    func testNewBookFromFixtureFolderShowsSidebarThumbnails() throws {
        // 1. Six fixture images in a unique /tmp folder (readable by the
        //    Debug build's temporary sandbox exception).
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("PhotoBooksUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.3, 0.9),
            (0.9, 0.7, 0.1), (0.6, 0.2, 0.7), (0.1, 0.7, 0.7)
        ]
        for (index, color) in colors.enumerated() {
            // Mixed orientations so the engine exercises real layouts.
            let landscape = index.isMultiple(of: 2)
            try writeFixtureImage(
                at: folder.appendingPathComponent("fixture-\(index).png"),
                width: landscape ? 320 : 240,
                height: landscape ? 240 : 320,
                red: color.0, green: color.1, blue: color.2)
        }

        // 2. Launch with the DEBUG fixture argument; ignore window restoration.
        let app = XCUIApplication()
        app.launchArguments = [
            "-newBookFromFixtureFolder", folder.path,
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        // 3. macOS opens an untitled document on launch; if restoration ate
        //    it, force one with File → New (⌘N).
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "No document window appeared")

        // 4. The browser sidebar shows numbered page thumbnails. 6 photos →
        //    cover + at least 2 interior pages.
        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-thumbnail-'"))
        let appeared = NSPredicate(format: "count >= 3")
        expectation(for: appeared, evaluatedWith: thumbnails)
        waitForExpectations(timeout: 15)
        XCTAssertGreaterThanOrEqual(thumbnails.count, 3,
                                    "Expected at least 3 page thumbnails (cover + interior)")
    }
}
