import CoreGraphics
import Foundation
import PDFKit
import PhotoBookCore
import Testing
@testable import PhotoBookRender

/// CGPDF-level inspection: embedded image resolution and export determinism.
@Suite struct PDFInspectionTests {

    /// Pixel widths of every image XObject on a page (via the page's
    /// Resources → XObject dictionary).
    private func embeddedImageWidths(in document: CGPDFDocument, pageNumber: Int) -> [Int] {
        guard let page = document.page(at: pageNumber),
              let pageDictionary = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources),
              let resources else { return [] }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
              let xObjects else { return [] }

        final class Box { var widths: [Int] = [] }
        let box = Box()
        CGPDFDictionaryApplyBlock(xObjects, { _, object, info in
            let box = Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDictionary = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return true }
            var width: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(streamDictionary, "Width", &width) {
                box.widths.append(width)
            }
            return true
        }, Unmanaged.passUnretained(box).toOpaque())
        return box.widths
    }

    @Test func interiorEmbedsAtMost300DPIImages() async throws {
        // Fixture geometry: every interior photo is placed 3.5 × 3.5 in
        // (0.5 slot × 7 in trim, square full-crop photo → drawn rect = slot
        // rect), so a 1600 px source must be downsampled to ≤ ceil(3.5×300)
        // = 1050 px → ≤ 300 DPI (310 with slack for the ceil).
        let book = ExportFixtures.book(standardCount: 20)
        let url = ExportFixtures.tempURL("dpi")
        defer { try? FileManager.default.removeItem(at: url) }
        try await PDFExporter().export(book, preset: ExportFixtures.preset,
                                       target: .blurbInterior,
                                       imageStore: ExportFixtures.store(for: book),
                                       to: url) { _ in }
        let document = try #require(CGPDFDocument(url as CFURL))
        var inspected = 0
        for pageNumber in 1...document.numberOfPages {
            for width in embeddedImageWidths(in: document, pageNumber: pageNumber) {
                let dpi = Double(width) / 3.5
                #expect(dpi <= 310, "page \(pageNumber): \(width) px over 3.5 in = \(dpi) DPI")
                #expect(dpi > 250, "unexpectedly soft: \(dpi) DPI")   // sanity floor
                inspected += 1
            }
        }
        #expect(inspected == 20, "every interior page embeds exactly one photo")
    }

    @Test func digitalEmbedsAtMost144DPIImages() async throws {
        let book = ExportFixtures.book(standardCount: 20)
        let url = ExportFixtures.tempURL("dpi-digital")
        defer { try? FileManager.default.removeItem(at: url) }
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                       imageStore: ExportFixtures.store(for: book),
                                       to: url) { _ in }
        let document = try #require(CGPDFDocument(url as CFURL))
        // Page 1 is the cover (full-bleed 7 in photo): ≤ ceil(7×144) = 1008 px.
        // Pages 2+ are the 3.5 in placements: ≤ ceil(3.5×144) = 504 px.
        for pageNumber in 2...document.numberOfPages {
            for width in embeddedImageWidths(in: document, pageNumber: pageNumber) {
                #expect(Double(width) / 3.5 <= 150)
            }
        }
    }

    @Test func exportingTwiceIsStructurallyIdentical() async throws {
        // Byte-equality is NOT achievable through public CGPDFContext API
        // (verified — D6): Quartz writes a trailer `/ID [ <hash> <hash> ]`
        // that differs every run, second-resolution /CreationDate//ModDate,
        // and a /Producer string embedding the OS build, and CGPDFContext.h
        // exposes no auxiliaryInfo key to pin any of them. What IS stable —
        // and asserted here: equal file sizes (the variable fields are
        // fixed-width), equal page count, every media box equal, equal
        // per-page embedded-image counts, and the pinned metadata.
        let book = ExportFixtures.book(standardCount: 20)
        let store = ExportFixtures.store(for: book)
        let urlA = ExportFixtures.tempURL("det-a")
        let urlB = ExportFixtures.tempURL("det-b")
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                       imageStore: store, to: urlA) { _ in }
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                       imageStore: store, to: urlB) { _ in }

        let dataA = try Data(contentsOf: urlA)
        let dataB = try Data(contentsOf: urlB)
        #expect(dataA.count == dataB.count)

        let docA = try #require(PDFDocument(url: urlA))
        let docB = try #require(PDFDocument(url: urlB))
        #expect(docA.pageCount == docB.pageCount)
        for index in 0..<docA.pageCount {
            let boxA = try #require(docA.page(at: index)).bounds(for: .mediaBox)
            let boxB = try #require(docB.page(at: index)).bounds(for: .mediaBox)
            #expect(boxA == boxB)
        }
        let cgA = try #require(CGPDFDocument(urlA as CFURL))
        let cgB = try #require(CGPDFDocument(urlB as CFURL))
        for pageNumber in 1...cgA.numberOfPages {
            #expect(embeddedImageWidths(in: cgA, pageNumber: pageNumber)
                 == embeddedImageWidths(in: cgB, pageNumber: pageNumber))
        }

        // Pinned metadata + the sRGB output intent actually land in the file.
        let attributes = try #require(docA.documentAttributes)
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "PhotoBooks")
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Fixture")
        let raw = String(decoding: dataA, as: UTF8.self)
        #expect(raw.contains("/OutputIntents"))
        #expect(raw.contains("/DestOutputProfile"))
    }
}
