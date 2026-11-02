import CoreGraphics
import Foundation
import PDFKit
import PhotoBookCore
import Testing
@testable import PhotoBookRender

@Suite struct SponsorPagePlanTests {
    private let preset = ExportFixtures.preset

    private func labels(_ book: Book, _ target: PDFTarget, sponsored: Bool = true) -> [String] {
        ExportPlan(book: book, preset: preset, target: target, sponsored: sponsored).jobs.map { job in
            switch job {
            case .page(let page): String(book.pages.firstIndex { $0.id == page.id } ?? -1)
            case .sponsor: "S"
            case .blank: "_"
            case .coverSheet: "sheet"
            }
        }
    }

    private func spreadEndingBook() -> Book {
        var book = ExportFixtures.book(standardCount: 4)
        let spread = UUID()
        book.pages[3].spreadID = spread
        book.pages[3].half = .left
        book.pages[4].spreadID = spread
        book.pages[4].half = .right
        return book
    }

    @Test func freeOfSponsorshipThePlanIsUnchanged() {
        #expect(labels(ExportFixtures.book(standardCount: 4), .digital, sponsored: false)
                == ["0", "1", "2", "3", "4"])
    }

    @Test func digitalGetsOneSponsorPageAfterTheCoverAndBeforeTheLastPage() {
        #expect(labels(ExportFixtures.book(standardCount: 4), .digital)
                == ["0", "S", "1", "2", "3", "S", "4"])
    }

    @Test func printPairsEachSponsorPageWithABlankSoFacingPagesStayFacing() {
        #expect(labels(ExportFixtures.book(standardCount: 4), .genericPrint(includeBleed: true))
                == ["0", "S", "_", "1", "2", "3", "_", "S", "4"])
    }

    @Test func blurbInteriorHasNoCoverSoItsFirstPageIsTheSponsorPage() {
        #expect(labels(ExportFixtures.book(standardCount: 4), .blurbInterior)
                == ["S", "_", "1", "2", "3", "_", "S", "4"])
    }

    @Test func aClosingSpreadIsNeverSplit() {
        #expect(labels(spreadEndingBook(), .digital) == ["0", "S", "1", "2", "S", "3", "4"])
        #expect(labels(spreadEndingBook(), .blurbInterior) == ["S", "_", "1", "2", "_", "S", "3", "4"])
    }

    @Test func booksTooShortForTwoSponsorPagesGetOne() {
        var coverOnly = ExportFixtures.book(standardCount: 1)
        coverOnly.pages.removeLast()
        #expect(labels(coverOnly, .digital) == ["0", "S"])
        #expect(labels(ExportFixtures.book(standardCount: 1), .digital) == ["0", "S", "1"])
        #expect(labels(ExportFixtures.book(standardCount: 1), .blurbInterior) == ["S", "_", "1"])
    }

    @Test func blurbCoverSpineGrowsWithTheAddedInteriorPages() {
        let book = ExportFixtures.book(standardCount: 20)
        let plain = ExportPlan(book: book, preset: preset, target: .blurbCover)
        let sponsored = ExportPlan(book: book, preset: preset, target: .blurbCover, sponsored: true)
        let added = Double(Sponsorship.printedPageCount) * preset.spinePerPage * PDFExporter.pointsPerInch
        #expect(abs(sponsored.mediaSize.width - plain.mediaSize.width - added) < 0.001)
    }

    @Test func printedPageCountMatchesWhatTheInteriorPlanAdds() {
        let book = ExportFixtures.book(standardCount: 20)
        let plain = ExportPlan(book: book, preset: preset, target: .blurbInterior)
        let sponsored = ExportPlan(book: book, preset: preset, target: .blurbInterior, sponsored: true)
        #expect(sponsored.jobs.count - plain.jobs.count == Sponsorship.printedPageCount)
    }

    @Test func preflightWarnsWhenSponsorPagesPushABookOverThePresetLimit() {
        var book = ExportFixtures.book(standardCount: 1)
        let extra = preset.maxPages - 2
        book.pages += (0..<extra).map { _ in Page(role: .standard, origin: .template(id: "hero-inset")) }
        #expect(Preflight.check(book, preset: preset).isEmpty)
        let issues = Preflight.check(book, preset: preset, sponsorPages: Sponsorship.printedPageCount)
        #expect(issues.map(\.kind) == [.pageCountOutOfRange(actual: preset.maxPages + 3,
                                                            min: preset.minPages,
                                                            max: preset.maxPages)])
    }

    @Test func preflightKeepsReportingTheBooksOwnCountWhenBelowTheMinimum() {
        let book = ExportFixtures.book(standardCount: preset.minPages - 1)
        let issues = Preflight.check(book, preset: preset, sponsorPages: Sponsorship.printedPageCount)
        #expect(issues.map(\.kind) == [.pageCountOutOfRange(actual: preset.minPages - 1,
                                                            min: preset.minPages,
                                                            max: preset.maxPages)])
    }
}

@Suite struct ExportedPDFLockTests {
    private func export(_ target: PDFTarget, sponsorship: Sponsorship?) async throws -> (URL, PDFDocument) {
        let book = ExportFixtures.book(standardCount: 20)
        let url = ExportFixtures.tempURL("lock")
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: target,
                                       imageStore: ExportFixtures.store(for: book), to: url,
                                       sponsorship: sponsorship) { _ in }
        return (url, try #require(PDFDocument(url: url)))
    }

    @Test(arguments: [PDFTarget.digital, .genericPrint(includeBleed: true), .blurbInterior, .blurbCover])
    func everyExportOpensFreelyButRefusesChanges(target: PDFTarget) async throws {
        for sponsorship in [nil, Sponsorship.standard] {
            let (url, document) = try await export(target, sponsorship: sponsorship)
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(document.isEncrypted)
            #expect(!document.isLocked, "must open without a password")
            #expect(!document.allowsDocumentChanges)
            #expect(!document.allowsDocumentAssembly, "assembly is what deletes pages")
            #expect(!document.allowsCommenting)
            #expect(document.allowsPrinting)
            #expect(document.allowsContentAccessibility)
            #expect(document.page(at: 0) != nil)
        }
    }
}

@Suite struct SponsorPageContentTests {
    private func sponsoredDigital(standardCount: Int = 4) async throws -> (URL, PDFDocument) {
        let book = ExportFixtures.book(standardCount: standardCount)
        let url = ExportFixtures.tempURL("sponsor")
        try await PDFExporter().export(book, preset: ExportFixtures.preset, target: .digital,
                                       imageStore: ExportFixtures.store(for: book), to: url,
                                       sponsorship: .standard) { _ in }
        return (url, try #require(PDFDocument(url: url)))
    }

    private func linkHosts(on page: PDFPage) -> Set<String> {
        Set(page.annotations.compactMap { $0.url?.host() })
    }

    @Test func sponsorPagesLinkToTheSponsorAndTheMaker() async throws {
        let (url, document) = try await sponsoredDigital()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(document.pageCount == 7)
        let expected: Set<String> = ["mailvaultapp.com", "graphicmeat.com"]
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(linkHosts(on: page) == ([1, 5].contains(index) ? expected : []), "page \(index)")
        }
    }

    @Test func printFilesCarryNoLinkAnnotations() async throws {
        let book = ExportFixtures.book(standardCount: 4)
        let url = ExportFixtures.tempURL("sponsor-print")
        defer { try? FileManager.default.removeItem(at: url) }
        try await PDFExporter().export(book, preset: ExportFixtures.preset,
                                       target: .genericPrint(includeBleed: true),
                                       imageStore: ExportFixtures.store(for: book), to: url,
                                       sponsorship: .standard) { _ in }
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 9)
        for index in 0..<document.pageCount {
            #expect(try #require(document.page(at: index)).annotations.isEmpty, "page \(index)")
        }
    }

    @Test func linksSitOnThePage() async throws {
        let (url, document) = try await sponsoredDigital()
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try #require(document.page(at: 1))
        let bounds = page.bounds(for: .mediaBox)
        #expect(page.annotations.count == 2)
        for annotation in page.annotations {
            #expect(bounds.contains(annotation.bounds))
            #expect(annotation.bounds.width > 20 && annotation.bounds.height > 5)
        }
    }

    @Test func sponsorPageCarriesItsCopy() async throws {
        let (url, document) = try await sponsoredDigital()
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try #require(document.page(at: 1)?.string)
        #expect(text.contains("mailvaultapp.com"))
        #expect(text.contains("sponsored by"))
    }

    /// Bottom-left-origin, opaque RGBA bytes of the page as drawn with bleed.
    private func renderedSponsorPage() -> (bytes: [UInt8], width: Int, height: Int) {
        let width = 600, height = 600
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        Sponsorship.standard.draw(in: context, mediaSize: CGSize(width: width, height: height),
                                  contentRect: CGRect(x: 10, y: 10, width: 580, height: 580),
                                  maxDPI: 144)
        return (bytes, width, height)
    }

    @Test func pageIsDarkEdgeToEdgeSoTheWhiteWordmarkReads() {
        let (bytes, width, height) = renderedSponsorPage()
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            let offset = (y * width + x) * 4
            #expect(bytes[offset] < 40 && bytes[offset + 1] < 40 && bytes[offset + 2] < 40,
                    "corner \(x),\(y) must be dark, bleed included")
        }
    }

    @Test func logosAndTextAreDrawn() {
        let (bytes, width, height) = renderedSponsorPage()
        var bright = 0, red = 0, blue = 0
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let (r, g, b) = (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
            if r > 220 && g > 220 && b > 220 { bright += 1 }   // "Mail", silver lettering, copy
            if r > 170 && g < 80 && b < 80 { red += 1 }        // GraphicMeat steak
            if b > 180 && r < 120 && g < 120 { blue += 1 }     // MailVault icon
        }
        #expect(bright > 300)
        #expect(red > 100)
        #expect(blue > 1000)
    }
}
