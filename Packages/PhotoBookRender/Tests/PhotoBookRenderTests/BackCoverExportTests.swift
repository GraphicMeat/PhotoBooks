import XCTest
import PhotoBookCore
@testable import PhotoBookRender

final class BackCoverExportTests: XCTestCase {

    private func photo(_ id: String) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data(id.utf8)),
                 pixelWidth: 1000, pixelHeight: 800)
    }

    func test_coverSheetPlanFetchesBackCoverPhoto() {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.photoLibrary = [photo("front"), photo("back")]
        book.pages = [Page(id: UUID(), role: .cover, origin: .template(id: "cover-hero"),
                           photoSlots: [PhotoSlot(id: UUID(), frame: .full,
                                                  photoID: PhotoID(rawValue: "front"),
                                                  crop: .full, isLocked: false)],
                           textSlots: [], isLocked: false)]
        book.backCover = Page(id: UUID(), role: .backCover, origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: UUID(), frame: .full,
                                                     photoID: PhotoID(rawValue: "back"),
                                                     crop: .full, isLocked: false)],
                              textSlots: [], isLocked: false)

        let plan = ExportPlan(book: book, preset: preset, target: .blurbCover)
        XCTAssertTrue(plan.uniquePhotoIDs.contains(PhotoID(rawValue: "back")),
                      "back-cover photo must be in the fetch set")
        XCTAssertTrue(plan.uniquePhotoIDs.contains(PhotoID(rawValue: "front")))
    }

    /// Rasterize the exported cover sheet and probe pixels: the back-cover
    /// photo must land in the BACK panel, AND drawing the back must NOT erase
    /// the FRONT panel — the core correctness property of the scoped
    /// `backgroundFillRect` fill in `drawCoverSheet`. Front = pure red, back =
    /// pure blue (both ≠ white background); each is a full-bleed cover photo.
    func test_coverSheetBackPhotoShowsAndFrontNotErased() async throws {
        let preset = ExportFixtures.preset
        // Reuse the standard fixture (cover + 20 pages → spine has width). Its
        // cover already carries a full-bleed `.full` photo slot for p0.
        var book = ExportFixtures.book(standardCount: 20)
        // Back cover: a full-bleed photo slot holding a distinct photo id.
        book.photoLibrary.append(photo("back"))
        book.backCover = Page(id: UUID(), role: .backCover, origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: UUID(), frame: .full,
                                                     photoID: PhotoID(rawValue: "back"),
                                                     crop: .full, isLocked: false)],
                              textSlots: [], isLocked: false)
        // Custom store: front cover photo (p0) = pure RED, back photo = pure BLUE.
        let store = StubImageStore(images: [
            PhotoID(rawValue: "p0"): ExportFixtures.solidImage(width: 1600, height: 1600,
                                                               red: 1, green: 0, blue: 0),
            PhotoID(rawValue: "back"): ExportFixtures.solidImage(width: 1000, height: 800,
                                                                 red: 0, green: 0, blue: 1),
        ])

        let url = ExportFixtures.tempURL("cover-panels")
        try await PDFExporter().export(book, preset: preset, target: .blurbCover,
                                       imageStore: store, to: url) { _ in }
        defer { try? FileManager.default.removeItem(at: url) }

        // Rasterize the single cover sheet page (same path as the spine probe).
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))   // white bg
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        let bytesPerRow = context.bytesPerRow
        let data = context.data!.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        // Panel x-geometry from the exporter's constants: back ∈ [bleed, bleed+trimW],
        // spine next, front ∈ [bleed+trimW+spine, …]. (Same flip-agnostic sampling as
        // the spine probe: a solid full-bleed photo is symmetric top↔bottom.)
        let bleedPt = preset.bleed * 72
        let trimPt = preset.trimSize.width * 72
        let spinePt = (preset.spineBase + preset.spinePerPage * 20) * 72
        let midY = height / 2
        let backCenterX = Int(bleedPt + trimPt / 2)
        let frontCenterX = Int(bleedPt + trimPt + spinePt + trimPt / 2)

        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let offset = y * bytesPerRow + x * 4
            return (data[offset], data[offset + 1], data[offset + 2])
        }

        // BACK panel center → the back photo (blue) is visible.
        let back = pixel(x: backCenterX, y: midY)
        XCTAssertTrue(back.b > 180 && back.r < 90 && back.g < 90,
                      "back panel must show the back photo (blue) — got \(back)")

        // FRONT panel center → still the front photo (red), NOT erased by the back draw.
        let front = pixel(x: frontCenterX, y: midY)
        XCTAssertTrue(front.r > 180 && front.g < 90 && front.b < 90,
                      "front panel must still be the front photo (red), not erased — got \(front)")
    }
}
