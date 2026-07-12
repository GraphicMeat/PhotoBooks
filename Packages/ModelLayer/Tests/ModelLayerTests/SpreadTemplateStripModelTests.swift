import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

/// Task B5: `BookEditorModel.spreadTemplateOptions` + `applySpreadTemplate`
/// plumbing — selection populates the strip's data, and applying is a single
/// undoable mutation, mirroring `SpreadEditingTests`'s convert/revert pattern.
@MainActor
@Suite struct SpreadTemplateStripModelTests {

    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func ref(_ id: String, width: Int = 4000, height: Int = 3000,
                     hours: Double) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: width, pixelHeight: height,
                 captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
    }

    /// A book whose lone ultra-wide photo auto-promotes to a 1-photo panorama
    /// spread (`BookEngine.panoramaAspectThreshold`), so its photo count (1)
    /// always matches a bundled template ("spread-panorama") — unlike
    /// `convertToSpread`, whose combined facing-pair count depends on
    /// pagination and isn't guaranteed to match any template count.
    private func fixtureBookWithSpread() -> (book: Book, spreadID: UUID, memberLeftID: UUID) {
        let photos: [PhotoRef] = [
            ref("a1", hours: 0), ref("a2", hours: 0.2), ref("a3", hours: 0.4),
            ref("pano", width: 8000, height: 2000, hours: 50),   // aspect 4.0 → lone-cluster panorama
            ref("b1", hours: 100), ref("b2", hours: 100.2), ref("b3", hours: 100.4)
        ]
        let base = BookEngine().makeBook(title: "SpreadStrip", photos: photos,
                                         preset: Self.preset, style: .standard, seed: 7)
        guard let spreadID = base.spreads.first?.id else {
            fatalError("fixture must auto-promote a panorama spread")
        }
        let memberLeftID = base.pages.first { $0.spreadID == spreadID && $0.half == .left }!.id
        return (base, spreadID, memberLeftID)
    }

    private func makeModel(_ book: Book) -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: book)
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo
        return (model, document, undo)
    }

    // MARK: - Selection populates spreadTemplateOptions

    @Test func selectingSpreadMemberPopulatesSpreadTemplateOptions() throws {
        let (book, _, memberLeftID) = fixtureBookWithSpread()
        let (model, document, _) = makeModel(book)

        model.selectPage(memberLeftID)
        let spread = try #require(document.book.spreads.first)
        #expect(!model.spreadTemplateOptions.isEmpty)
        #expect(model.spreadTemplateOptions.allSatisfy { $0.photoCount == spread.photoSlots.count })
        // A non-spread page selection empties it back out.
        let standardPage = document.book.pages.first { $0.role == .standard && $0.spreadID == nil }!
        model.selectPage(standardPage.id)
        #expect(model.spreadTemplateOptions.isEmpty)
    }

    @Test func spreadTemplateOptionsEmptyWithNoSelection() {
        let (book, _, _) = fixtureBookWithSpread()
        let (model, _, _) = makeModel(book)
        #expect(model.spreadTemplateOptions.isEmpty)
    }

    // MARK: - Apply routes through apply() and is undoable

    @Test func applySpreadTemplateIsUndoable() throws {
        let (book, spreadID, memberLeftID) = fixtureBookWithSpread()
        let (model, document, undo) = makeModel(book)
        model.selectPage(memberLeftID)

        guard let templateID = model.spreadTemplateOptions.first?.id else {
            Issue.record("fixture spread has no matching templates")
            return
        }

        let before = try BookSerializer.encode(document.book)
        model.applySpreadTemplate(templateID)

        let spreadAfter = try #require(document.book.spreads.first { $0.id == spreadID })
        if case .template(let id) = spreadAfter.origin {
            #expect(id == templateID)
        } else {
            Issue.record("expected spread origin to be .template(\(templateID))")
        }
        #expect(try BookSerializer.encode(document.book) != before)

        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
    }

    @Test func applySpreadTemplateWithoutSelectionIsANoOp() {
        let (book, _, _) = fixtureBookWithSpread()
        let (model, document, undo) = makeModel(book)
        let before = document.book
        model.applySpreadTemplate("spread-center-columns-3")
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    // MARK: - Convert keeps selection alive (QA fix)

    /// `convertToSpread` mints fresh member-page IDs. After
    /// `convertSelectedSpread` the selection must point at a live member page
    /// of the new spread and the spread-template strip must be populated —
    /// a 2-photo spread offers spread-split-two-thirds and spread-two-up.
    @Test func convertSelectedSpreadKeepsSelectionAndPopulatesStrip() throws {
        // Cover + two 1-photo standard pages → facing pair (1,2) → 2-photo spread.
        let refs = [ref("p1", hours: 0), ref("p2", hours: 1)]
        var book = Book(title: "Convert", presetID: Self.preset.id, style: .standard)
        book.photoLibrary = refs
        func page(_ photoID: PhotoID, role: PageRole) -> Page {
            Page(role: role, origin: .template(id: "one-full-bleed"),
                 photoSlots: [PhotoSlot(id: UUID(), frame: .full, photoID: photoID,
                                        crop: .full, isLocked: false)])
        }
        book.pages = [page(refs[0].id, role: .cover),
                      page(refs[0].id, role: .standard),
                      page(refs[1].id, role: .standard)]

        let (model, document, _) = makeModel(book)
        model.selectPage(document.book.pages[1].id)
        #expect(model.canConvertSelectedToSpread)

        model.convertSelectedSpread(seed: 42)

        let spread = try #require(document.book.spreads.first)
        #expect(spread.photoSlots.count == 2)
        // Selection points at a LIVE member page of the new spread.
        let selected = try #require(document.book.pages.first { $0.id == model.selectedPageID })
        #expect(selected.spreadID == spread.id)
        // And the strip is populated with the 2-photo templates.
        let ids = Set(model.spreadTemplateOptions.map(\.id))
        #expect(ids.contains("spread-split-two-thirds"))
        #expect(ids.contains("spread-two-up"))
    }

    @Test func applySpreadTemplateOnNonSpreadPageIsANoOp() {
        let (book, _, _) = fixtureBookWithSpread()
        let (model, document, undo) = makeModel(book)
        let standardPage = document.book.pages.first { $0.role == .standard && $0.spreadID == nil }!
        model.selectPage(standardPage.id)
        let before = document.book
        model.applySpreadTemplate("spread-center-columns-3")
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }
}
