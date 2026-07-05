import Foundation
import PhotoBookCore
import Testing
@testable import PhotoBookRender

@Suite struct PreflightTests {

    // MARK: fixture guard — geometry goldens in Tasks 5–9 assume these numbers

    @Test func fixturePresetMatchesBlurbSmallSquareData() {
        let preset = ExportFixtures.preset
        #expect(preset.trimSize == SizeInches(width: 7, height: 7))
        #expect(preset.bleed == 0.125)
        #expect(preset.safeMargin == 0.25)
        #expect(preset.minPages == 20)
        #expect(preset.maxPages == 240)
        #expect(preset.spineBase == 0.25)
        #expect(preset.spinePerPage == 0.002252)
    }

    @Test func cleanBookHasNoIssues() {
        let issues = Preflight.check(ExportFixtures.book(standardCount: 20),
                                     preset: ExportFixtures.preset)
        #expect(issues.isEmpty)
    }

    // MARK: missingPhoto — the only BLOCKING kind

    @Test func missingLibraryEntryBlocks() {
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary[3].isMissing = true        // p3, placed on pages[3]
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        let missing = issues.filter { if case .missingPhoto = $0.kind { true } else { false } }
        #expect(missing.count == 1)
        #expect(missing.first?.kind == .missingPhoto(PhotoID(rawValue: "p3")))
        #expect(missing.first?.pageIndex == 3)
        #expect(missing.first?.isBlocking == true)
    }

    @Test func danglingPhotoIDBlocks() {
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary.removeAll { $0.id == PhotoID(rawValue: "p5") }
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        let missing = issues.filter(\.isBlocking)
        #expect(missing.count == 1)
        #expect(missing.first?.kind == .missingPhoto(PhotoID(rawValue: "p5")))
        #expect(missing.first?.pageIndex == 5)
    }

    // MARK: back cover — a photo surface OUTSIDE book.pages[]

    /// A missing back-cover photo must block export just like a page photo.
    /// The back cover isn't in `pages[]`, so its issue carries `pageIndex == nil`.
    @Test func missingBackCoverPhotoBlocks() {
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary.append(ExportFixtures.photoRef(999, isMissing: true))
        book.backCover = Page(id: ExportFixtures.uuid(9000), role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: ExportFixtures.uuid(9001), frame: .full,
                                                     photoID: PhotoID(rawValue: "p999"),
                                                     crop: .full, isLocked: false)],
                              textSlots: [], isLocked: false)
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        let missing = issues.filter { if case .missingPhoto = $0.kind { true } else { false } }
        #expect(missing.count == 1)
        #expect(missing.first?.kind == .missingPhoto(PhotoID(rawValue: "p999")))
        #expect(missing.first?.pageIndex == nil)
        #expect(missing.first?.isBlocking == true)
    }

    /// A dangling back-cover photo id (no library entry) blocks too.
    @Test func danglingBackCoverPhotoIDBlocks() {
        var book = ExportFixtures.book(standardCount: 20)
        book.backCover = Page(id: ExportFixtures.uuid(9000), role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: ExportFixtures.uuid(9001), frame: .full,
                                                     photoID: PhotoID(rawValue: "ghost"),
                                                     crop: .full, isLocked: false)],
                              textSlots: [], isLocked: false)
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        let blocking = issues.filter(\.isBlocking)
        #expect(blocking.count == 1)
        #expect(blocking.first?.kind == .missingPhoto(PhotoID(rawValue: "ghost")))
        #expect(blocking.first?.pageIndex == nil)
    }

    /// A back cover with a healthy photo produces no issue.
    @Test func healthyBackCoverHasNoIssue() {
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary.append(ExportFixtures.photoRef(999))
        book.backCover = Page(id: ExportFixtures.uuid(9000), role: .backCover,
                              origin: .template(id: "backcover-hero"),
                              photoSlots: [PhotoSlot(id: ExportFixtures.uuid(9001), frame: .full,
                                                     photoID: PhotoID(rawValue: "p999"),
                                                     crop: .full, isLocked: false)],
                              textSlots: [], isLocked: false)
        #expect(Preflight.check(book, preset: ExportFixtures.preset).isEmpty)
    }

    // MARK: pageCountOutOfRange — cover excluded

    @Test func pageCountCountsStandardPagesOnly() {
        // Cover + 19 standard = 20 pages total, but only the 19 STANDARD
        // pages count (the cover is its own physical product): below min 20.
        let book = ExportFixtures.book(standardCount: 19)
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        #expect(issues.count == 1)
        #expect(issues.first?.kind == .pageCountOutOfRange(actual: 19, min: 20, max: 240))
        #expect(issues.first?.pageIndex == nil)
        #expect(issues.first?.isBlocking == false)
    }

    @Test func pageCountAtMinimumIsFine() {
        let issues = Preflight.check(ExportFixtures.book(standardCount: 20),
                                     preset: ExportFixtures.preset)
        #expect(!issues.contains { if case .pageCountOutOfRange = $0.kind { true } else { false } })
    }

    // MARK: lowResolution — golden DPI values (formula in Preflight.effectiveDPI)

    @Test func effectiveDPIGoldenHighRes() {
        // 4000×3000, full crop, 0.5×0.5 slot on a 10×8 in page:
        // placed = 5.0 × 4.0 in → DPI = min(4000/5, 3000/4) = min(800, 750) = 750.
        let ref = ExportFixtures.photoRef(1, pixelWidth: 4000, pixelHeight: 3000)
        let slot = PhotoSlot(id: ExportFixtures.uuid(1),
                             frame: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                             photoID: ref.id, crop: .full, isLocked: false)
        let dpi = Preflight.effectiveDPI(ref: ref, slot: slot,
                                         trimSize: SizeInches(width: 10, height: 8))
        #expect(dpi == 750)
    }

    @Test func effectiveDPIGoldenLowRes() {
        // 800×600, full crop, same slot: min(800/5, 600/4) = min(160, 150) = 150.
        let ref = ExportFixtures.photoRef(1, pixelWidth: 800, pixelHeight: 600)
        let slot = PhotoSlot(id: ExportFixtures.uuid(1),
                             frame: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                             photoID: ref.id, crop: .full, isLocked: false)
        let dpi = Preflight.effectiveDPI(ref: ref, slot: slot,
                                         trimSize: SizeInches(width: 10, height: 8))
        #expect(dpi == 150)
    }

    @Test func effectiveDPIGoldenWithCrop() {
        // 4000×3000 cropped to the center half (0.5×0.5 of the photo):
        // cropped pixels = 2000×1500, placed 5×4 in → min(400, 375) = 375.
        let ref = ExportFixtures.photoRef(1, pixelWidth: 4000, pixelHeight: 3000)
        let slot = PhotoSlot(id: ExportFixtures.uuid(1),
                             frame: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                             photoID: ref.id,
                             crop: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                             isLocked: false)
        let dpi = Preflight.effectiveDPI(ref: ref, slot: slot,
                                         trimSize: SizeInches(width: 10, height: 8))
        #expect(dpi == 375)
    }

    @Test func lowResolutionWarnsBelow200AndNotAt200() {
        // 7×7 trim, half-size slot → placed 3.5×3.5 in.
        // 700×700 px → DPI 200 exactly → NO warning (threshold is < 200).
        // 699×699 px → 199.71… → floor 199 → warning.
        var book = ExportFixtures.book(standardCount: 20)
        book.photoLibrary[1] = ExportFixtures.photoRef(1, pixelWidth: 700, pixelHeight: 700)
        book.photoLibrary[2] = ExportFixtures.photoRef(2, pixelWidth: 699, pixelHeight: 699)
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        #expect(issues.count == 1)
        #expect(issues.first?.kind == .lowResolution(PhotoID(rawValue: "p2"), effectiveDPI: 199))
        #expect(issues.first?.pageIndex == 2)
        #expect(issues.first?.isBlocking == false)
    }

    // MARK: textOverflow

    @Test func longTextInTinyFrameOverflows() {
        var book = ExportFixtures.book(standardCount: 20)
        // A one-line-high band (3% of 7 in = 15.12 pt) holding many lines
        // of 0.05-factor text (25.2 pt) must overflow.
        let slot = TextSlot(
            id: ExportFixtures.uuid(3000),
            frame: NormRect(x: 0.1, y: 0.1, width: 0.3, height: 0.03),
            text: StyledText(string: "An extremely long caption that cannot possibly fit "
                                   + "inside a single short line of this narrow text zone",
                             fontName: "", pointSizeFactor: 0.05,
                             colorHex: "#000000", alignment: .leading),
            isLocked: false)
        book.pages[1].textSlots = [slot]
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        #expect(issues.count == 1)
        #expect(issues.first?.kind == .textOverflow(pageID: book.pages[1].id))
        #expect(issues.first?.pageIndex == 1)
        #expect(issues.first?.isBlocking == false)
    }

    @Test func fittingTextDoesNotOverflow() {
        var book = ExportFixtures.book(standardCount: 20)
        let slot = TextSlot(
            id: ExportFixtures.uuid(3000),
            frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2),
            text: StyledText(string: "Short", fontName: "", pointSizeFactor: 0.05,
                             colorHex: "#000000", alignment: .center),
            isLocked: false)
        book.pages[1].textSlots = [slot]
        #expect(Preflight.check(book, preset: ExportFixtures.preset).isEmpty)
    }

    @Test func emptyTextNeverOverflows() {
        var book = ExportFixtures.book(standardCount: 20)
        let slot = TextSlot(
            id: ExportFixtures.uuid(3000),
            frame: NormRect(x: 0.1, y: 0.1, width: 0.001, height: 0.001),
            text: StyledText(string: "", fontName: "", pointSizeFactor: 0.05,
                             colorHex: "#000000", alignment: .center),
            isLocked: false)
        book.pages[1].textSlots = [slot]
        #expect(Preflight.check(book, preset: ExportFixtures.preset).isEmpty)
    }

    // MARK: deterministic ordering

    @Test func bookLevelIssueComesFirstThenPageOrder() {
        var book = ExportFixtures.book(standardCount: 19)        // count issue
        book.photoLibrary[7].isMissing = true                    // page 7 issue
        book.photoLibrary[2] = ExportFixtures.photoRef(2, pixelWidth: 300, pixelHeight: 300)
        let issues = Preflight.check(book, preset: ExportFixtures.preset)
        #expect(issues.count == 3)
        #expect(issues[0].pageIndex == nil)        // pageCountOutOfRange
        #expect(issues[1].pageIndex == 2)          // lowResolution, page order
        #expect(issues[2].pageIndex == 7)          // missingPhoto
    }
}
