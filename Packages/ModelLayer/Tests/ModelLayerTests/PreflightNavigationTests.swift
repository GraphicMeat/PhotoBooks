import Foundation
import PhotoBookCore
import PhotoBookImport
import PhotoBookRender
import Testing
@testable import ModelLayer

@MainActor
@Suite struct PreflightNavigationTests {
    @Test func revealsExactPlacementWhenPhotoIsRepeated() throws {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let photoID = PhotoID(rawValue: "repeated")
        let slots = (0..<2).map { _ in
            PhotoSlot(frame: NormRect(x: 0, y: 0, width: 0.5, height: 0.5), photoID: photoID)
        }
        var book = Book(title: "Test", presetID: preset.id, style: .standard)
        book.photoLibrary = [PhotoRef(id: photoID, source: .file(bookmark: Data()), pixelWidth: 100, pixelHeight: 100)]
        book.pages = [Page(role: .standard, origin: .template(id: "test"), photoSlots: slots)]
        let editor = BookEditorModel(document: BookDocument(book: book), photoKitProvider: PhotoKitProvider())
        let issue = try #require(Preflight.check(book, preset: preset).first { $0.slotID == slots[1].id })
        editor.revealPreflightIssue(issue)
        #expect(editor.selectedPageID == book.pages[0].id)
        #expect(editor.selectedSlotID == slots[1].id)
        // Revealing an already selected issue must not toggle selection off.
        editor.revealPreflightIssue(issue)
        #expect(editor.selectedSlotID == slots[1].id)
    }

    @Test func backCoverIssueOpensCoverAndSelectsMissingPhoto() throws {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let slot = PhotoSlot(frame: NormRect(x: 0, y: 0, width: 1, height: 1), photoID: PhotoID(rawValue: "missing"))
        var book = Book(title: "Test", presetID: preset.id, style: .standard)
        book.pages = [Page(role: .cover, origin: .template(id: "cover-hero"))]
        book.backCover = Page(role: .cover, origin: .template(id: "cover-hero"), photoSlots: [slot])
        let editor = BookEditorModel(document: BookDocument(book: book), photoKitProvider: PhotoKitProvider())
        let issue = try #require(Preflight.check(book, preset: preset).first { $0.isBlocking })
        #expect(issue.pageIndex == nil)
        #expect(issue.pageID == book.backCover?.id)
        editor.revealPreflightIssue(issue)
        #expect(editor.selectedPageID == book.pages[0].id)
        #expect(editor.selectedSlotID == slot.id)
    }
}
