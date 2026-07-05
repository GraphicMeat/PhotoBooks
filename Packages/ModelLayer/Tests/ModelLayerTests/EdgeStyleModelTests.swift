import AppSupport
import EditCore
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

/// D3: per-page edge-style selection + book-default edge style.
@MainActor
@Suite struct EdgeStyleModelTests {

    // MARK: Fixture helpers

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: EditMutationsTests.fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    // MARK: EditMutations (pure)

    @Test func setPageEdgeStyleOverrideStoresValue() {
        var book = EditMutationsTests.fixtureBook()
        EditMutations.setPageEdgeStyle(in: &book, pageID: EditMutationsTests.page1ID, override: .borderless)
        let page = book.pages.first { $0.id == EditMutationsTests.page1ID }
        #expect(page?.edgeStyleOverride == .borderless)
    }

    @Test func setPageEdgeStyleOverrideNilClearsOverride() {
        var book = EditMutationsTests.fixtureBook()
        EditMutations.setPageEdgeStyle(in: &book, pageID: EditMutationsTests.page1ID, override: .borderless)
        EditMutations.setPageEdgeStyle(in: &book, pageID: EditMutationsTests.page1ID, override: nil)
        let page = book.pages.first { $0.id == EditMutationsTests.page1ID }
        #expect(page?.edgeStyleOverride == nil)
    }

    @Test func setPageEdgeStyleUnknownPageIsNoOp() {
        var book = EditMutationsTests.fixtureBook()
        let before = book
        EditMutations.setPageEdgeStyle(in: &book, pageID: UUID(), override: .borderless)
        #expect(book == before)
    }

    @Test func setBookEdgeStyleFlipsStyleFlag() {
        var book = EditMutationsTests.fixtureBook()
        #expect(book.style.edgeStyle == .framed)
        EditMutations.setBookEdgeStyle(in: &book, .borderless)
        #expect(book.style.edgeStyle == .borderless)
        EditMutations.setBookEdgeStyle(in: &book, .framed)
        #expect(book.style.edgeStyle == .framed)
    }

    // MARK: BookEditorModel (undoable, re-lays page)

    @Test func setSelectedPageEdgeStyleFlipsEffectiveValue() {
        let (model, document, _) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        #expect(model.selectedPageEdgeStyle == .framed)  // starts framed (book default)
        model.setSelectedPageEdgeStyle(.borderless)
        #expect(model.selectedPageEdgeStyle == .borderless)
        model.setSelectedPageEdgeStyle(.framed)
        #expect(model.selectedPageEdgeStyle == .framed)
    }

    @Test func setSelectedPageEdgeStyleIsUndoable() {
        let (model, document, undo) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        let before = document.book
        model.setSelectedPageEdgeStyle(.borderless)
        #expect(document.book != before)
        #expect(undo.canUndo)
        undo.undo()
        // edgeStyleOverride should be restored
        let page = document.book.pages.first { $0.id == EditMutationsTests.page1ID }
        #expect(page?.edgeStyleOverride == nil)
    }

    @Test func setSelectedPageEdgeStyleWithNoSelectionIsNoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.setSelectedPageEdgeStyle(.borderless)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    @Test func setBookEdgeStyleFlipsStyleAndIsUndoable() {
        let (model, document, undo) = makeModel()
        #expect(document.book.style.edgeStyle == .framed)
        model.setBookEdgeStyle(.borderless)
        #expect(document.book.style.edgeStyle == .borderless)
        #expect(undo.canUndo)
        undo.undo()
        #expect(document.book.style.edgeStyle == .framed)
    }

    /// The `bookEdgeStyle` getter (drives the editor's book-wide picker) mirrors
    /// the book default and updates after `setBookEdgeStyle`.
    @Test func bookEdgeStyleReflectsBookDefault() {
        let (model, _, _) = makeModel()
        #expect(model.bookEdgeStyle == .framed)
        model.setBookEdgeStyle(.tiled)
        #expect(model.bookEdgeStyle == .tiled)
    }

    @Test func selectedPageEdgeStyleReflectsEffectiveValue() {
        let (model, document, _) = makeModel()
        // No selection → framed
        #expect(model.selectedPageEdgeStyle == .framed)
        model.selectPage(EditMutationsTests.page1ID)
        // Book default is framed, no override → effective framed
        #expect(model.selectedPageEdgeStyle == .framed)
        // Set book-level default to borderless; effective should now be borderless
        model.setBookEdgeStyle(.borderless)
        #expect(model.selectedPageEdgeStyle == .borderless)
        // Override the page back to framed explicitly
        model.setSelectedPageEdgeStyle(.framed)  // was inheriting borderless → set override to framed
        #expect(model.selectedPageEdgeStyle == .framed)
    }

    /// New coverage: `.tiled` is a distinct third mode, not just an alias for
    /// on/off borderless — verify it round-trips through both the effective
    /// getter and the stored override.
    @Test func setSelectedPageEdgeStyleTiledSticks() {
        let (model, document, _) = makeModel()
        model.selectPage(EditMutationsTests.page1ID)
        model.setSelectedPageEdgeStyle(.tiled)
        #expect(model.selectedPageEdgeStyle == .tiled)
        let page = document.book.pages.first { $0.id == EditMutationsTests.page1ID }
        #expect(page?.edgeStyleOverride == .tiled)
    }

    /// Verifies that setting borderless on a page whose slot is locked still
    /// produces a true full-bleed layout. Under the OLD reshuffle-based code,
    /// `isReshuffleable` returns false for a locked slot, so the page frames
    /// were left as-is (margined). The NEW code uses `edgeStyleCandidate` +
    /// `applyAlternative`, which are lock-agnostic.
    ///
    /// The fixture has no single-photo standard page; page1 has 2 photos.
    /// Full-bleed for 2 photos means the union of slot frames tiles the whole
    /// page: min x == 0, min y == 0, max (x+width) == 1, max (y+height) == 1.
    @Test func setEdgeStyleBorderlessFullBleedsEvenLockedSlot() {
        let (model, document, _) = makeModel()
        let pageID = EditMutationsTests.page1ID
        model.selectPage(pageID)

        // Lock the first slot (simulates a manual crop/swap that would cause
        // the old reshuffle path to skip re-layout).
        model.tapPhotoSlot(EditMutationsTests.slot1aID)   // select
        model.toggleSelectedSlotLock()                    // lock

        // Confirm slot is locked before the toggle.
        let before = document.book.pages.first { $0.id == pageID }!
        #expect(before.photoSlots[0].isLocked == true)

        model.setSelectedPageEdgeStyle(.borderless)

        let after = document.book.pages.first { $0.id == pageID }!
        #expect(after.photoSlots.count >= 1)

        // The union of all photo slot frames must cover the full page with no margin.
        let minX = after.photoSlots.map(\.frame.x).min()!
        let minY = after.photoSlots.map(\.frame.y).min()!
        let maxX = after.photoSlots.map { $0.frame.x + $0.frame.width }.max()!
        let maxY = after.photoSlots.map { $0.frame.y + $0.frame.height }.max()!
        #expect(minX < 1e-9, "Expected left edge at 0, got \(minX)")
        #expect(minY < 1e-9, "Expected top edge at 0, got \(minY)")
        #expect(abs(maxX - 1.0) < 1e-9, "Expected right edge at 1, got \(maxX)")
        #expect(abs(maxY - 1.0) < 1e-9, "Expected bottom edge at 1, got \(maxY)")
    }

    /// A book-wide edge-style change must NOT touch spread members: their
    /// sliced double-wide geometry would be corrupted by a single-page
    /// edge-style candidate. The per-page loop skips `spreadID != nil` pages.
    @Test func setBookEdgeStyleLeavesSpreadMembersUntouched() {
        // Build a book with an eligible facing pair, convert it to a spread.
        func ref(_ id: String, hours: Double) -> PhotoRef {
            PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
        }
        let photos = (0..<12).map { ref("sb\($0)", hours: Double($0) * 0.3) }
        let book = BookEngine().makeBook(title: "SpreadBL", photos: photos,
                                         preset: SpreadEditingTests.preset, style: .standard, seed: 1)
        let document = BookDocument(book: book)
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        model.undoManager = UndoManager()

        // Convert the first eligible facing pair to a spread.
        let spreads = SpreadPairing.spreads(for: document.book.pages)
        guard let row = spreads.first(where: { row in
            guard let l = row.left, let r = row.right else { return false }
            let lp = document.book.pages[l], rp = document.book.pages[r]
            return lp.role == .standard && rp.role == .standard
                && lp.spreadID == nil && rp.spreadID == nil
                && (lp.photoSlots + rp.photoSlots).contains { $0.photoID != nil }
        }), let leftIdx = row.left else {
            Issue.record("No eligible facing pair in fixture"); return
        }
        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 42)

        // Snapshot the spread member pages (frames + spreadID) before the toggle.
        let membersBefore = document.book.pages.filter { $0.spreadID != nil }
        #expect(membersBefore.count == 2)

        model.setBookEdgeStyle(.borderless)

        // Spread members are byte-identical; only their non-spread siblings changed.
        let membersAfter = document.book.pages.filter { $0.spreadID != nil }
        #expect(membersAfter == membersBefore)
    }
}
