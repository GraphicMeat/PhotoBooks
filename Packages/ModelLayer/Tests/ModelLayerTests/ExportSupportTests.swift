import AppSupport
import EditCore
import Foundation
import PhotoBookCore
import PhotoBookRender
import Testing
@testable import ModelLayer

@MainActor
@Suite struct DebouncerTests {

    @Test func burstCoalescesIntoOneTrailingRun() async throws {
        let debouncer = Debouncer(interval: .milliseconds(40))
        var runs = 0
        for _ in 0..<5 {
            debouncer.schedule { runs += 1 }
        }
        #expect(runs == 0)                       // nothing fires inside the burst
        try await Task.sleep(for: .milliseconds(200))
        #expect(runs == 1)                       // exactly the LAST call ran
    }

    @Test func cancelPreventsTheScheduledRun() async throws {
        let debouncer = Debouncer(interval: .milliseconds(40))
        var runs = 0
        debouncer.schedule { runs += 1 }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(runs == 0)
    }
}

@Suite struct ExportSupportTests {

    // MARK: ExportFilenames

    @Test func blurbPairFilenamesFollowTheConvention() {
        #expect(ExportFilenames.interior(title: "Summer 2026") == "Summer 2026-interior.pdf")
        #expect(ExportFilenames.cover(title: "Summer 2026") == "Summer 2026-cover.pdf")
        #expect(ExportFilenames.single(title: "Summer 2026") == "Summer 2026.pdf")
    }

    @Test func titlesAreSanitizedForTheFilesystem() {
        #expect(ExportFilenames.sanitized(title: "A/B: C\\D") == "A-B- C-D")
        #expect(ExportFilenames.sanitized(title: "   ") == "Photo Book")
    }

    // MARK: ExportPadding

    @Test func padToMinimumAppendsExactlyTheMissingBlankPages() {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.pages = [Page(role: .cover, origin: .template(id: "cover-hero"))]
        book.pages += (0..<12).map { _ in Page(role: .standard, origin: .template(id: "hero-inset")) }
        ExportPadding.padToMinimum(in: &book, preset: preset)
        #expect(book.pages.count(where: { $0.role == .standard }) == 20)   // 12 + 8 blanks
        #expect(book.pages.count == 21)
        let blank = book.pages.last!
        #expect(blank.photoSlots.isEmpty && blank.textSlots.isEmpty)
    }

    @Test func padToMinimumIsANoOpAtOrAboveMinimum() {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.pages = (0..<25).map { _ in Page(role: .standard, origin: .template(id: "hero-inset")) }
        let before = book
        ExportPadding.padToMinimum(in: &book, preset: preset)
        #expect(book == before)
    }
}

@Suite struct PreflightSummaryTests {
    // PreflightIssue has no public initializer (the contract pins only the
    // type's vars), so every fixture issue comes from the REAL
    // `Preflight.check` over a crafted book — which also pins the
    // summary's behavior to actual preflight output.

    private let preset = PresetLibrary.preset(id: "blurb-small-square")!

    /// Cover + 20 standard pages; page 7 places the one library photo
    /// (300×300 px in a half-size slot → 85 DPI low-res warning).
    private func bookWithLowResPhotoOnPage7() -> Book {
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.photoLibrary = [PhotoRef(id: PhotoID(rawValue: "low"),
                                      source: .file(bookmark: Data()),
                                      pixelWidth: 300, pixelHeight: 300)]
        book.pages = [Page(role: .cover, origin: .template(id: "cover-hero"))]
        book.pages += (1...20).map { n in
            Page(role: .standard, origin: .template(id: "hero-inset"),
                 photoSlots: n == 7
                     ? [PhotoSlot(frame: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                  photoID: PhotoID(rawValue: "low"))]
                     : [])
        }
        return book
    }

    @Test func blockingStateReflectsAnyBlockingIssue() {
        var book = bookWithLowResPhotoOnPage7()
        let warningOnly = PreflightSummary(issues: Preflight.check(book, preset: preset))
        #expect(!warningOnly.issues.isEmpty)
        #expect(!warningOnly.hasBlockingIssues)

        book.photoLibrary[0].isMissing = true            // upgrade to blocking
        let blocked = PreflightSummary(issues: Preflight.check(book, preset: preset))
        #expect(blocked.hasBlockingIssues)
    }

    @Test func lowResPhotoBadgesItsPage() {
        // The badge-computation requirement: a book with a low-res photo
        // marks that PAGE in pageIndexesWithWarnings.
        let summary = PreflightSummary(
            issues: Preflight.check(bookWithLowResPhotoOnPage7(), preset: preset))
        #expect(summary.pageIndexesWithWarnings == [7])
    }

    @Test func blockingAndBookLevelIssuesNeverBadge() {
        // Missing photo (blocking, page 7) + page count (book-level, no
        // page index): neither contributes a badge — blocking issues go
        // through Plan 5's banner, book-level issues have no page.
        var book = bookWithLowResPhotoOnPage7()
        book.photoLibrary[0].isMissing = true
        book.pages.removeLast()                          // 19 standard → count issue
        let summary = PreflightSummary(issues: Preflight.check(book, preset: preset))
        #expect(summary.issues.count == 2)
        #expect(summary.pageIndexesWithWarnings.isEmpty)
    }
}
