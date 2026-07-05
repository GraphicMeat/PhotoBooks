import Foundation
import PDFKit
import PhotoBookCore
import Synchronization
import Testing
@testable import PhotoBookRender

@Suite struct PDFExporterTests {

    private func export(_ book: Book, target: PDFTarget, name: String,
                        store: (any ImageStore)? = nil,
                        progress: ProgressRecorder = ProgressRecorder()) async throws -> URL {
        let url = ExportFixtures.tempURL(name)
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: target,
                                       imageStore: store ?? ExportFixtures.store(for: book),
                                       to: url) { progress.record($0) }
        return url
    }

    // MARK: digital

    @Test func digitalHasTrimBoxAndAllPages() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = try await export(book, target: .digital, name: "digital")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 21)                       // cover + 20
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 504) < 0.5)                     // 7 in × 72
        #expect(abs(box.height - 504) < 0.5)
    }

    @Test func progressIsMonotonicFrom0To1() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let recorder = ProgressRecorder()
        let url = try await export(book, target: .digital, name: "progress", progress: recorder)
        defer { try? FileManager.default.removeItem(at: url) }
        let values = recorder.values
        #expect(values == values.sorted())
        #expect(values.first ?? 1 <= 0.5)
        #expect(abs((values.last ?? 0) - 1.0) < 1e-9)
        // 21 unique photos (fetch) + 21 pages (render) = 42 callbacks.
        #expect(values.count == 42)
    }

    // MARK: error paths

    @Test func blockingPreflightIssueAborts() async throws {
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary[3].isMissing = true
        let url = ExportFixtures.tempURL("blocked")
        await #expect(throws: PDFExportError.self) {
            try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                           imageStore: ExportFixtures.store(for: book),
                                           to: url) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func fetchFailuresThrowTheRetryListBeforeAnyFileExists() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let store = FailingImageStore(base: ExportFixtures.store(for: book),
                                      failingIDs: [PhotoID(rawValue: "p7"), PhotoID(rawValue: "p3")])
        let url = ExportFixtures.tempURL("fetchfail")
        do {
            try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                           imageStore: store, to: url) { _ in }
            Issue.record("export must throw imageFetchFailed")
        } catch let PDFExportError.imageFetchFailed(ids) {
            #expect(ids == [PhotoID(rawValue: "p3"), PhotoID(rawValue: "p7")])  // sorted
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancellationDeletesThePartialFile() async throws {
        // The store hangs on the SECOND fetch of p3 (first = fetch pass,
        // second = render pass, page 3) — the export is parked mid-render
        // until the test cancels it. Deterministic: no timing assumptions.
        let book = ExportFixtures.book(standardCount: 20)
        let store = HangingImageStore(base: ExportFixtures.store(for: book),
                                      hangID: PhotoID(rawValue: "p3"), hangOnCall: 2)
        let url = ExportFixtures.tempURL("cancel")
        let recorder = ProgressRecorder()
        let task = Task {
            try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                           imageStore: store, to: url) { recorder.record($0) }
        }
        while (recorder.values.last ?? 0) <= 0.5 {              // render pass underway
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("export must throw cancelled")
        } catch let error as PDFExportError {
            guard case .cancelled = error else {
                Issue.record("expected .cancelled, got \(error)")
                return
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: blurbInterior + genericPrint

    @Test func interiorHasBleedBoxAndStandardPagesOnly() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = try await export(book, target: .blurbInterior, name: "interior")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 20)                       // cover skipped
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 522) < 0.5)                     // (7 + 0.25) × 72
        #expect(abs(box.height - 522) < 0.5)
    }

    @Test func genericWithoutBleedIsTrimSizeWithAllPages() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = try await export(book, target: .genericPrint(includeBleed: false), name: "generic")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 21)                       // cover included
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 504) < 0.5)
        #expect(abs(box.height - 504) < 0.5)
    }

    @Test func genericWithBleedGetsTheBleedBox() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = try await export(book, target: .genericPrint(includeBleed: true), name: "generic-bleed")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 21)
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 522) < 0.5)
        #expect(abs(box.height - 522) < 0.5)
    }

    // MARK: blurbCover

    @Test func spineWidthFormulaGolden() {
        // 0.25 + 0.002252 × 20 = 0.29504 in.
        let spine = ExportPlan.spineWidthInches(preset: ExportFixtures.preset,
                                                standardPageCount: 20)
        #expect(abs(spine - 0.29504) < 1e-12)
    }

    @Test func coverSheetIsOnePageAtComputedSize() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = try await export(book, target: .blurbCover, name: "cover")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        // Expected size computed IN-TEST from the preset constants (no magic
        // numbers): width = (2×trimW + spine(20) + 2×bleed) × 72.
        let preset = ExportFixtures.preset
        let spine = preset.spineBase + preset.spinePerPage * 20
        let expectedWidth = (2 * preset.trimSize.width + spine + 2 * preset.bleed) * 72
        let expectedHeight = (preset.trimSize.height + 2 * preset.bleed) * 72
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - expectedWidth) < 0.5)           // 1047.24288 pt
        #expect(abs(box.height - expectedHeight) < 0.5)         // 522 pt
    }

    @Test func spineTitleIsRotatedIntoTheSpineBand() async throws {
        // Rasterize the cover sheet and probe ink: the title must put dark
        // pixels inside the spine band (between the panels) and nowhere in
        // the back panel, and its ink bounding box must be TALLER than wide
        // — rotated text (D7). Glyph reading order is a manual check.
        let book = ExportFixtures.book(standardCount: 20, title: "Summer")
        let url = try await export(book, target: .blurbCover, name: "cover-spine")
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(CGPDFDocument(url as CFURL))
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        let bytesPerRow = context.bytesPerRow
        let data = context.data!.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        // Spine band x-range, from the same constants the exporter uses:
        // bleed(9) + trim(504) … + spine(21.24…) — probed 2 px inside.
        let preset = ExportFixtures.preset
        let bleedPt = preset.bleed * 72
        let trimPt = preset.trimSize.width * 72
        let spinePt = (preset.spineBase + preset.spinePerPage * 20) * 72
        let spineMinX = Int(bleedPt + trimPt) + 2
        let spineMaxX = Int(bleedPt + trimPt + spinePt) - 2

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<height {
            for x in (spineMinX - 60)...(spineMaxX + 60) {
                let offset = y * bytesPerRow + x * 4
                if data[offset] < 100 && data[offset + 1] < 100 && data[offset + 2] < 100 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        #expect(minX >= spineMinX, "spine ink must not bleed into the back panel")
        #expect(maxX <= spineMaxX, "spine ink must not bleed into the front panel")
        #expect(maxY - minY > maxX - minX, "spine title must be rotated (tall, not wide)")
    }

    @Test func coverWithoutCoverPageStillExportsOneValidSheet() async throws {
        var book = ExportFixtures.book(standardCount: 20)
        book.pages.removeFirst()                                // drop the cover (D13)
        let url = try await export(book, target: .blurbCover, name: "cover-defensive")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
    }
}

/// Hangs (cancellably) on the Nth `fullImage` call for one ID; everything
/// else resolves like the base store. Drives the deterministic cancellation
/// test: the export parks itself mid-render until the test cancels.
final class HangingImageStore: ImageStore {
    private let base: StubImageStore
    private let hangID: PhotoID
    private let hangOnCall: Int
    private let calls = Mutex<Int>(0)

    init(base: StubImageStore, hangID: PhotoID, hangOnCall: Int) {
        self.base = base
        self.hangID = hangID
        self.hangOnCall = hangOnCall
    }

    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
        try await fullImage(for: id)
    }

    func fullImage(for id: PhotoID) async throws -> CGImage {
        if id == hangID {
            let count = calls.withLock { $0 += 1; return $0 }
            if count >= hangOnCall {
                try await Task.sleep(for: .seconds(3600))       // throws on cancel
            }
        }
        return try await base.fullImage(for: id)
    }
}
