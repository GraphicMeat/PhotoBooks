import CoreGraphics
import Foundation
import PhotoBookCore
import Testing
@testable import PhotoBookRender

/// Renders pages into a BITMAP context (PDFPageRenderer draws into any
/// CGContext) and probes pixels — orientation and placement are verified
/// without parsing PDF content streams. The global flip means memory row 0
/// is the page's visual top, so probe coordinates are plain top-left coords.
@Suite struct PDFPageRendererTests {

    // MARK: bitmap harness

    private func renderToBitmap(page: Page, book: Book, size: Int = 504,
                                store: any ImageStore) async throws -> (data: [UInt8], bytesPerRow: Int) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let renderer = PDFPageRenderer(book: book, maxDPI: 300)
        try await renderer.draw(page: page, in: context,
                                mediaSize: CGSize(width: size, height: size),
                                contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                                imageStore: store)
        let count = context.bytesPerRow * size
        let buffer = context.data!.bindMemory(to: UInt8.self, capacity: count)
        return (Array(UnsafeBufferPointer(start: buffer, count: count)), context.bytesPerRow)
    }

    private func pixel(_ bitmap: (data: [UInt8], bytesPerRow: Int), x: Int, yTop: Int)
        -> (r: UInt8, g: UInt8, b: UInt8) {
        let offset = yTop * bitmap.bytesPerRow + x * 4
        return (bitmap.data[offset], bitmap.data[offset + 1], bitmap.data[offset + 2])
    }

    // MARK: downsampler formulas (golden values)

    @Test func maxPixelSizeFormula() {
        // 252 × 252 pt = 3.5 × 3.5 in → 300 DPI: ceil(3.5 × 300) = 1050.
        #expect(PDFDownsampler.maxPixelSize(drawnPointSize: CGSize(width: 252, height: 252),
                                            maxDPI: 300) == 1050)
        // Digital 144 DPI: ceil(3.5 × 144) = 504.
        #expect(PDFDownsampler.maxPixelSize(drawnPointSize: CGSize(width: 252, height: 252),
                                            maxDPI: 144) == 504)
        // Longest side wins: 504 × 252 pt at 300 → ceil(7 × 300) = 2100.
        #expect(PDFDownsampler.maxPixelSize(drawnPointSize: CGSize(width: 504, height: 252),
                                            maxDPI: 300) == 2100)
    }

    @Test func downsampleCapsLongestSideAndKeepsAspect() {
        let image = ExportFixtures.solidImage(width: 1600, height: 800)
        let result = PDFDownsampler.downsample(image, maxPixelSize: 400)
        #expect(result.width == 400)
        #expect(result.height == 200)
    }

    @Test func downsampleNeverUpsamples() {
        let image = ExportFixtures.solidImage(width: 800, height: 800)
        let result = PDFDownsampler.downsample(image, maxPixelSize: 1050)
        #expect(result.width == 800)
        #expect(result.height == 800)
    }

    // MARK: placement + background (pixel probes)

    @Test func photoLandsOnSlotRectOverBackground() async throws {
        // Fixture page: 0.5×0.5 slot centered on a white page → at 504 px the
        // slot is (126,126,252,252). Center = photo red; outside = white.
        let book = ExportFixtures.book(standardCount: 20)
        let bitmap = try await renderToBitmap(page: book.pages[1], book: book,
                                              store: ExportFixtures.store(for: book))
        let inside = pixel(bitmap, x: 252, yTop: 252)
        #expect(inside.r > 180 && inside.g < 90 && inside.b < 90)     // ~(204, 51, 51)
        let outside = pixel(bitmap, x: 60, yTop: 60)
        #expect(outside.r > 240 && outside.g > 240 && outside.b > 240) // white
        // Just outside the slot's left edge: still background.
        let leftOfSlot = pixel(bitmap, x: 120, yTop: 252)
        #expect(leftOfSlot.r > 240 && leftOfSlot.g > 240 && leftOfSlot.b > 240)
    }

    @Test func photoIsNotMirroredVertically() async throws {
        // Two-tone photo: TOP half green, BOTTOM half blue. After the global
        // flip + the local counter-flip the slot must show green on top —
        // a missing counter-flip would show blue (D4).
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary[1] = ExportFixtures.photoRef(1, pixelWidth: 400, pixelHeight: 400)
        let store = StubImageStore(images: [
            PhotoID(rawValue: "p1"): Self.twoToneImage(width: 400, height: 400)
        ])
        let bitmap = try await renderToBitmap(page: book.pages[1], book: book, store: store)
        let upper = pixel(bitmap, x: 252, yTop: 140)    // inside slot, upper area
        #expect(upper.g > 150 && upper.b < 90, "slot top must be GREEN (image top)")
        let lower = pixel(bitmap, x: 252, yTop: 364)    // inside slot, lower area
        #expect(lower.b > 150 && lower.g < 90, "slot bottom must be BLUE (image bottom)")
    }

    @Test func textGlyphsAreNotMirroredVertically() async throws {
        // Orientation probe: a period's ink sits on the BASELINE — the
        // bottom of its line box. Mirrored glyphs would put the ink near the
        // top of the slot. Assert the ink's average row is below the slot's
        // vertical midline.
        var book = ExportFixtures.book(standardCount: 20)
        book.pages[1].photoSlots = []
        book.pages[1].textSlots = [TextSlot(
            id: ExportFixtures.uuid(3000),
            frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1),   // (50.4, 50.4, 403.2, 50.4)
            text: StyledText(string: ".", fontName: "", pointSizeFactor: 0.05,
                             colorHex: "#000000", alignment: .center),
            isLocked: false)]
        let bitmap = try await renderToBitmap(page: book.pages[1], book: book,
                                              store: ExportFixtures.store(for: book))
        var inkRows: [Int] = []
        for yTop in 50...101 {
            for x in 50...453 where pixel(bitmap, x: x, yTop: yTop).r < 100 {
                inkRows.append(yTop)
                break
            }
        }
        #expect(!inkRows.isEmpty, "the period must render ink inside the slot")
        let averageRow = Double(inkRows.reduce(0, +)) / Double(inkRows.count)
        #expect(averageRow > 75.6, "period ink must sit near the baseline (lower half), not mirrored to the top")
    }

    @Test func emptySlotDrawsTheScreenGrayWell() async throws {
        var book = ExportFixtures.book(standardCount: 20)
        book.pages[1].photoSlots[0].photoID = nil
        let bitmap = try await renderToBitmap(page: book.pages[1], book: book,
                                              store: ExportFixtures.store(for: book))
        let inside = pixel(bitmap, x: 252, yTop: 252)
        #expect(inside.r > 200 && inside.r < 230)       // 0.85 gray ≈ 217
        #expect(inside.r == inside.g && inside.g == inside.b)
    }

    // MARK: spine color

    @Test func contrastingTextColorGoldens() {
        #expect(PDFExporter.contrastingTextColorHex(forBackground: "#FFFFFF") == "#000000")
        #expect(PDFExporter.contrastingTextColorHex(forBackground: "#102040") == "#FFFFFF")
        #expect(PDFExporter.contrastingTextColorHex(forBackground: "#FFD60A") == "#000000")
    }

    // MARK: helpers

    static func twoToneImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext drawing coords: y = 0 is the image's BOTTOM.
        context.setFillColor(CGColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))  // top half green
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))           // bottom half blue
        return context.makeImage()!
    }
}
