import CoreGraphics
import Foundation
import PDFKit
import PhotoBookCore
import PhotoBookRender
import Testing
@testable import ModelLayer

private struct NoPhotosStore: ImageStore {
    struct Unexpected: Error {}
    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage { throw Unexpected() }
    func fullImage(for id: PhotoID) async throws -> CGImage { throw Unexpected() }
}

@MainActor
@Suite struct ExportSupportFlowTests {
    private final class Supporter { var value = false }

    private func book(standardCount: Int = 20) -> Book {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.pages = [Page(role: .cover, origin: .template(id: "cover-hero"))]
        book.pages += (0..<standardCount).map { _ in Page(role: .standard, origin: .template(id: "hero-inset")) }
        return book
    }

    private func model(_ supporter: Supporter, book: Book? = nil) -> ExportModel {
        ExportModel(document: BookDocument(book: book ?? self.book()), imageStore: NoPhotosStore(),
                    isSupporter: { supporter.value })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    private func exportSingleFile(_ model: ExportModel) async throws -> PDFDocument {
        model.exportSingleFileToTemporary()
        try await waitUntil { model.renderedDocument != nil }
        let rendered = try #require(model.renderedDocument)
        return try #require(PDFDocument(data: rendered.data))
    }

    @Test func freeUsersSeeTheSupportStepBeforeChoosingAnExport() {
        let model = model(Supporter())
        model.begin()
        #expect(model.showsSupportStep)
        model.continueFromPreflight()
        #expect(model.phase == .support)
        model.continueFromSupport()
        #expect(model.phase == .choosingDestination)
    }

    @Test func supportersSkipTheSupportStep() {
        let supporter = Supporter()
        supporter.value = true
        let model = model(supporter)
        model.begin()
        #expect(!model.showsSupportStep)
        model.continueFromPreflight()
        #expect(model.phase == .choosingDestination)
    }

    @Test func continueFromSupportOnlyWorksOnTheSupportStep() {
        let model = model(Supporter())
        model.begin()
        model.continueFromSupport()
        #expect(model.phase == .preflight)
    }

    @Test func freeExportCarriesSponsorPages() async throws {
        let model = model(Supporter())
        model.begin()
        let document = try await exportSingleFile(model)
        #expect(document.pageCount == 21 + 2)
        #expect(!document.allowsDocumentChanges)
    }

    @Test func donatingOnTheSupportStepRemovesThemFromTheVeryNextExport() async throws {
        let supporter = Supporter()
        let model = model(supporter)
        model.begin()
        model.continueFromPreflight()
        supporter.value = true
        model.continueFromSupport()
        let document = try await exportSingleFile(model)
        #expect(document.pageCount == 21)
        #expect(!document.allowsDocumentChanges, "donors' PDFs stay locked too")
    }

    @Test func blurbPairIsSponsoredAndItsSpineCountsTheAddedPages() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportSupportFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func coverWidth(for supporter: Supporter) async throws -> (interior: Int, cover: CGFloat) {
            let model = model(supporter)
            model.begin(.blurb)
            model.exportBlurbPair(into: folder)
            try await waitUntil {
                if case .finished = model.phase { return true }
                return false
            }
            guard case .finished(let urls) = model.phase else { throw CocoaError(.fileReadUnknown) }
            let interior = try #require(PDFDocument(url: urls[0]))
            let cover = try #require(PDFDocument(url: urls[1])?.page(at: 0))
            return (interior.pageCount, cover.bounds(for: .mediaBox).width)
        }

        let free = try await coverWidth(for: Supporter())
        let donor = Supporter()
        donor.value = true
        let paid = try await coverWidth(for: donor)
        #expect(free.interior == 20 + Sponsorship.printedPageCount)
        #expect(paid.interior == 20)
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let added = CGFloat(Double(Sponsorship.printedPageCount) * preset.spinePerPage * 72)
        #expect(abs(free.cover - paid.cover - added) < 0.5)
    }

    @Test func preflightOnlyCountsSponsorPagesForFreeUsers() {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let full = book(standardCount: preset.maxPages - 1)
        let free = model(Supporter(), book: full)
        free.begin()
        #expect(!free.issues.isEmpty)
        let donor = Supporter()
        donor.value = true
        let paid = model(donor, book: full)
        paid.begin()
        #expect(paid.issues.isEmpty)
    }
}
