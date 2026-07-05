import CoreGraphics
import Foundation
import PhotoBookCore

/// Which PDF the exporter produces. Pinned by the API contract.
public enum PDFTarget: Sendable {
    case blurbInterior
    case blurbCover
    case genericPrint(includeBleed: Bool)
    case digital
}

/// Pinned by the API contract.
public enum PDFExportError: Error {
    case preflightBlocked([PreflightIssue])
    case imageFetchFailed([PhotoID])     // resumable — retry list
    case cancelled
}

/// Geometry + page list for one export target, resolved up front so the
/// render loop is target-agnostic. All sizes in PDF points (72/inch).
struct ExportPlan {
    enum Job {
        case page(Page)
        case coverSheet
    }
    var mediaSize: CGSize
    var contentRect: CGRect          // top-left-origin; trim rect for bleed targets
    var jobs: [Job]
    var maxDPI: Double
    var uniquePhotoIDs: [PhotoID]    // every placed photo this export renders, sorted

    init(book: Book, preset: PrintPreset, target: PDFTarget) {
        let trimW = preset.trimSize.width * PDFExporter.pointsPerInch
        let trimH = preset.trimSize.height * PDFExporter.pointsPerInch
        let bleedPt = preset.bleed * PDFExporter.pointsPerInch
        let standardPages = book.pages.filter { $0.role == .standard }

        switch target {
        case .blurbInterior:
            // Interior: standard pages only (the cover is its own sheet),
            // media box = (trim + 2×bleed) × pointsPerInch, content offset by bleed.
            mediaSize = CGSize(width: trimW + 2 * bleedPt, height: trimH + 2 * bleedPt)
            contentRect = CGRect(x: bleedPt, y: bleedPt, width: trimW, height: trimH)
            jobs = standardPages.map { .page($0) }
            maxDPI = PDFExporter.printDPI
        case .blurbCover:
            // One sheet: back + spine + front, plus bleed all around.
            let spinePt = ExportPlan.spineWidthInches(preset: preset,
                                                      standardPageCount: standardPages.count) * PDFExporter.pointsPerInch
            mediaSize = CGSize(width: 2 * trimW + spinePt + 2 * bleedPt,
                               height: trimH + 2 * bleedPt)
            contentRect = CGRect(origin: .zero, size: mediaSize)   // unused for cover — front/spine/back panels computed locally in drawCoverSheet
            jobs = [.coverSheet]
            maxDPI = PDFExporter.printDPI
        case .genericPrint(let includeBleed):
            if includeBleed {
                mediaSize = CGSize(width: trimW + 2 * bleedPt, height: trimH + 2 * bleedPt)
                contentRect = CGRect(x: bleedPt, y: bleedPt, width: trimW, height: trimH)
            } else {
                mediaSize = CGSize(width: trimW, height: trimH)
                contentRect = CGRect(origin: .zero, size: mediaSize)
            }
            jobs = book.pages.map { .page($0) }    // all pages, cover first
            maxDPI = PDFExporter.printDPI
        case .digital:
            mediaSize = CGSize(width: trimW, height: trimH)
            contentRect = CGRect(origin: .zero, size: mediaSize)
            jobs = book.pages.map { .page($0) }    // all pages, cover first
            maxDPI = PDFExporter.digitalDPI
        }

        var ids = Set<PhotoID>()
        for job in jobs {
            switch job {
            case .page(let page):
                for slot in page.photoSlots { if let id = slot.photoID { ids.insert(id) } }
            case .coverSheet:
                if let cover = book.pages.first, cover.role == .cover {
                    for slot in cover.photoSlots { if let id = slot.photoID { ids.insert(id) } }
                }
                if let back = book.backCover {
                    for slot in back.photoSlots { if let id = slot.photoID { ids.insert(id) } }
                }
            }
        }
        uniquePhotoIDs = ids.sorted { $0.rawValue < $1.rawValue }
    }

    /// spine inches = spineBase + spinePerPage × standardPageCount (contract).
    static func spineWidthInches(preset: PrintPreset, standardPageCount: Int) -> Double {
        preset.spineBase + preset.spinePerPage * Double(standardPageCount)
    }
}

/// Pinned by the API contract.
public struct PDFExporter: Sendable {

    static let printDPI: Double = 300
    static let digitalDPI: Double = 144
    static let pointsPerInch: Double = 72

    public init() {}

    public func export(_ book: Book, preset: PrintPreset, target: PDFTarget,
                       imageStore: any ImageStore, to url: URL,
                       progress: @Sendable @escaping (Double) -> Void) async throws {
        // 1. Preflight gate (D8): never render placeholders into a print file.
        let blocking = Preflight.check(book, preset: preset).filter(\.isBlocking)
        guard blocking.isEmpty else { throw PDFExportError.preflightBlocked(blocking) }

        let plan = ExportPlan(book: book, preset: preset, target: target)

        // 2. Fetch pass, progress 0 → 0.5 (D2): fetch-and-discard every
        // unique photo to trigger downloads and collect failures BEFORE the
        // file exists. Pixels are dropped immediately — `_ =` keeps nothing.
        var failedIDs: [PhotoID] = []
        for (index, id) in plan.uniquePhotoIDs.enumerated() {
            if Task.isCancelled { throw PDFExportError.cancelled }
            do {
                _ = try await imageStore.fullImage(for: id)
            } catch is CancellationError {
                throw PDFExportError.cancelled
            } catch {
                failedIDs.append(id)
            }
            progress(0.5 * Double(index + 1) / Double(plan.uniquePhotoIDs.count))
        }
        if plan.uniquePhotoIDs.isEmpty { progress(0.5) }
        guard failedIDs.isEmpty else { throw PDFExportError.imageFetchFailed(failedIDs) }

        // 3. Render pass, progress 0.5 → 1.0, page by page.
        var mediaBox = CGRect(origin: .zero, size: plan.mediaSize)
        // Fixed metadata + an sRGB output intent (the spec's "sRGB profile
        // embedded"): every color and image in the file is authored in sRGB
        // (CGColor(srgbRed:…) fills, sRGB-tagged downsampled images), and
        // the intent declares that to print services.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let outputIntent: [CFString: Any] = [
            kCGPDFXOutputIntentSubtype: "GTS_PDFX",
            kCGPDFXOutputConditionIdentifier: "sRGB IEC61966-2.1",
            kCGPDFXInfo: "sRGB IEC61966-2.1",
            kCGPDFXDestinationOutputProfile: srgb,
        ]
        let auxiliaryInfo: [CFString: Any] = [
            kCGPDFContextCreator: "PhotoBooks",
            kCGPDFContextTitle: book.title,
            kCGPDFContextOutputIntent: outputIntent,
        ]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox,
                                      auxiliaryInfo as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let renderer = PDFPageRenderer(book: book, maxDPI: plan.maxDPI)
        var pageIsOpen = false
        do {
            for (index, job) in plan.jobs.enumerated() {
                if Task.isCancelled { throw PDFExportError.cancelled }
                context.beginPDFPage(nil)
                pageIsOpen = true
                switch job {
                case .page(let page):
                    try await renderer.draw(page: page, in: context,
                                            mediaSize: plan.mediaSize,
                                            contentRect: plan.contentRect,
                                            imageStore: imageStore)
                case .coverSheet:
                    try await drawCoverSheet(book: book, preset: preset, in: context,
                                             mediaSize: plan.mediaSize, imageStore: imageStore)
                }
                context.endPDFPage()
                pageIsOpen = false
                progress(0.5 + 0.5 * Double(index + 1) / Double(plan.jobs.count))
            }
            context.closePDF()
        } catch {
            // D10: close first (releases the file handle), then delete the
            // partial file, then rethrow — cancellation as `.cancelled`.
            if pageIsOpen { context.endPDFPage() }
            context.closePDF()
            try? FileManager.default.removeItem(at: url)
            if error is CancellationError { throw PDFExportError.cancelled }
            throw error
        }
    }

    // MARK: Cover sheet (blurbCover)

    /// One sheet, back–spine–front (left to right), everything + bleed:
    ///
    ///     sheetW = bleed + trimW + spine + trimW + bleed
    ///     back  panel: x ∈ [bleed,                bleed + trimW]
    ///     spine panel: x ∈ [bleed + trimW,        bleed + trimW + spine]
    ///     front panel: x ∈ [bleed + trimW + spine, sheetW − bleed]
    ///
    /// The front panel is the cover page rendered by `PDFPageRenderer`
    /// (which also fills the whole sheet with the book background — the back
    /// panel and bleed are exactly that fill). The spine carries the title,
    /// rotated to read top-to-bottom (D7).
    private func drawCoverSheet(book: Book, preset: PrintPreset, in context: CGContext,
                                mediaSize: CGSize, imageStore: any ImageStore) async throws {
        let trimW = preset.trimSize.width * Self.pointsPerInch
        let trimH = preset.trimSize.height * Self.pointsPerInch
        let bleedPt = preset.bleed * Self.pointsPerInch
        let standardCount = book.pages.count(where: { $0.role == .standard })
        let spinePt = ExportPlan.spineWidthInches(preset: preset,
                                                  standardPageCount: standardCount) * Self.pointsPerInch

        let backRect = CGRect(x: bleedPt, y: bleedPt, width: trimW, height: trimH)
        let spineRect = CGRect(x: bleedPt + trimW, y: bleedPt, width: spinePt, height: trimH)
        let frontRect = CGRect(x: bleedPt + trimW + spinePt, y: bleedPt,
                               width: trimW, height: trimH)

        let renderer = PDFPageRenderer(book: book, maxDPI: Self.printDPI)
        // Front first: its whole-media fill paints the bleed, spine, and back
        // area with the book background (the fallback back when there is no
        // back-cover photo).
        if let cover = book.pages.first, cover.role == .cover {
            try await renderer.draw(page: cover, in: context, mediaSize: mediaSize,
                                    contentRect: frontRect, imageStore: imageStore)
        } else {
            // D13: no cover page — still a valid sheet (background + spine).
            let bg = ColorHex.components(book.style.backgroundColorHex)
            context.setFillColor(CGColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: 1))
            context.fill(CGRect(origin: .zero, size: mediaSize))
        }
        // Back panel: fill scoped to the back rect so it never repaints the
        // already-drawn front. Absent back cover keeps the background fallback.
        if let back = book.backCover {
            try await renderer.draw(page: back, in: context, mediaSize: mediaSize,
                                    contentRect: backRect, imageStore: imageStore,
                                    backgroundFillRect: backRect)
        }
        drawSpineTitle(book.title, style: book.style, spineRect: spineRect,
                       mediaSize: mediaSize, in: context)
    }

    /// Vertical spine title. Under the global flip, `rotate(by: +π/2)` turns
    /// the local +x axis to point DOWN the sheet, so left-to-right text reads
    /// top-to-bottom — the US spine convention (D7). The rotated rect spans
    /// the spine's length; size = 60% of the spine width; color flips
    /// black/white against the background's relative luminance.
    private func drawSpineTitle(_ title: String, style: BookStyle, spineRect: CGRect,
                                mediaSize: CGSize, in context: CGContext) {
        guard !title.isEmpty, spineRect.width > 1 else { return }
        context.saveGState()
        context.translateBy(x: 0, y: mediaSize.height)   // the same global flip
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: spineRect.midX, y: spineRect.midY)
        context.rotate(by: .pi / 2)
        // In rotated-local coordinates the spine runs along x: a rect as wide
        // as the spine is TALL and as tall as the spine is WIDE, centered.
        let textRect = CGRect(x: -spineRect.height / 2, y: -spineRect.width / 2,
                              width: spineRect.height, height: spineRect.width)
        let styled = StyledText(
            string: title, fontName: "", pointSizeFactor: 0.6,
            colorHex: Self.contrastingTextColorHex(forBackground: style.backgroundColorHex),
            alignment: .center)
        // renderHeight = spine width in points → fontPoints(0.6, w) = 60% of it.
        PDFText.draw(styled, style: style, slotRect: textRect,
                     renderHeight: spineRect.width, in: context)
        context.restoreGState()
    }

    /// Black or white, whichever contrasts with `hex` (WCAG relative
    /// luminance with sRGB linearization; threshold 0.179 — the luminance at
    /// which black and white text have equal contrast ratio).
    static func contrastingTextColorHex(forBackground hex: String) -> String {
        let c = ColorHex.components(hex)
        func linearized(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearized(c.red)
                      + 0.7152 * linearized(c.green)
                      + 0.0722 * linearized(c.blue)
        return luminance > 0.179 ? "#000000" : "#FFFFFF"
    }
}
