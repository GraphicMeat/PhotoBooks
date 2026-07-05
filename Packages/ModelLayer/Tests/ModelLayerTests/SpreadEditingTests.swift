import AppSupport
import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

/// Phase C spread editing: convert/revert on the editor model, undo, and
/// the can… guard properties.
@MainActor
@Suite struct SpreadEditingTests {

    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    /// Builds a book with enough interior standard pages to produce at least
    /// one eligible facing pair for spread conversion.
    private func fixtureBook() -> Book {
        func ref(_ id: String, hours: Double) -> PhotoRef {
            PhotoRef(id: PhotoID(rawValue: id),
                     source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
        }
        let photos: [PhotoRef] = [
            ref("s01", hours: 0),   ref("s02", hours: 0.3),
            ref("s03", hours: 0.6), ref("s04", hours: 0.9),
            ref("s05", hours: 5),   ref("s06", hours: 5.3),
            ref("s07", hours: 5.6), ref("s08", hours: 5.9),
            ref("s09", hours: 10),  ref("s10", hours: 10.3),
            ref("s11", hours: 10.6),ref("s12", hours: 10.9),
        ]
        return BookEngine().makeBook(title: "Spread Fixture", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 1)
    }

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    // MARK: - Eligibility helpers

    /// Returns the index of the first interior standard non-spread page that
    /// forms a complete (left+right) facing pair with another eligible page.
    private func firstEligibleLeftIdx(in book: Book) -> Int? {
        let spreads = SpreadPairing.spreads(for: book.pages)
        for row in spreads {
            guard let leftIdx = row.left, let rightIdx = row.right else { continue }
            let left = book.pages[leftIdx]
            let right = book.pages[rightIdx]
            guard left.role == .standard, right.role == .standard,
                  left.spreadID == nil, right.spreadID == nil,
                  !left.isLocked, !right.isLocked,
                  left.photoSlots.allSatisfy({ !$0.isLocked }),
                  right.photoSlots.allSatisfy({ !$0.isLocked }),
                  (left.photoSlots + right.photoSlots).contains(where: { $0.photoID != nil })
            else { continue }
            return leftIdx
        }
        return nil
    }

    // MARK: - Convert routes through apply and is undoable

    @Test func convertRoutedThroughApplyIsUndoable() throws {
        let (model, document, undo) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else {
            Issue.record("No eligible facing pair in fixture")
            return
        }

        model.selectPage(document.book.pages[leftIdx].id)
        #expect(model.canConvertSelectedToSpread)

        let before = try BookSerializer.encode(document.book)
        let pageCountBefore = document.book.pages.count

        model.convertSelectedSpread(seed: 42)

        // Page count must be unchanged (2 single pages → 2 member pages).
        #expect(document.book.pages.count == pageCountBefore)
        // The book has changed (the pages are now spread members).
        #expect(try BookSerializer.encode(document.book) != before)
        // The two pages at leftIdx and leftIdx+1 are now spread members.
        let newLeft = document.book.pages[leftIdx]
        let newRight = document.book.pages[leftIdx + 1]
        #expect(newLeft.spreadID != nil)
        #expect(newRight.spreadID != nil)
        #expect(newLeft.spreadID == newRight.spreadID)
        #expect(newLeft.half == .left)
        #expect(newRight.half == .right)
        // One new spread in book.spreads.
        #expect(document.book.spreads.count == 1)

        // Undo restores the two independent pages.
        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
        #expect(document.book.spreads.isEmpty)
    }

    // MARK: - Revert routes through apply and is undoable

    @Test func revertRoutedThroughApplyIsUndoable() throws {
        // Build a book that already has a spread (by pre-converting via the engine
        // directly, so the undo stack is clean before the test's single mutation).
        let baseBook = fixtureBook()
        let preset = Self.preset
        guard let leftIdx = firstEligibleLeftIdx(in: baseBook) else {
            Issue.record("No eligible facing pair in fixture")
            return
        }
        let leftID = baseBook.pages[leftIdx].id
        let spreadBook = BookEngine().convertToSpread(baseBook, leftPageID: leftID,
                                                      preset: preset, seed: 43)
        guard spreadBook.spreads.count == 1 else {
            Issue.record("Engine convertToSpread returned unchanged book")
            return
        }

        // Start the model from the already-spread book; undo stack is empty.
        let document = BookDocument(book: spreadBook)
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager()
        model.undoManager = undo

        let beforeRevert = try BookSerializer.encode(document.book)
        let pageCountBefore = document.book.pages.count
        #expect(document.book.spreads.count == 1)

        // Select a spread member and revert.
        let memberPage = document.book.pages[leftIdx]
        model.selectPage(memberPage.id)
        #expect(model.canRevertSelectedSpread)
        #expect(model.selectedPageIsSpreadMember)

        model.revertSelectedSpread(seed: 44)

        // Page count still unchanged (2 members → 2 single pages).
        #expect(document.book.pages.count == pageCountBefore)
        #expect(document.book.spreads.isEmpty)
        // The pages no longer carry spreadID.
        #expect(document.book.pages[leftIdx].spreadID == nil)
        #expect(document.book.pages[leftIdx + 1].spreadID == nil)

        // Undo restores the spread (single mutation on a clean undo stack).
        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == beforeRevert)
        #expect(document.book.spreads.count == 1)
    }

    // MARK: - can… flags

    @Test func canConvertIsFalseWithNoSelection() {
        let (model, _, _) = makeModel()
        #expect(!model.canConvertSelectedToSpread)
    }

    @Test func canRevertIsFalseWithNoSelection() {
        let (model, _, _) = makeModel()
        #expect(!model.canRevertSelectedSpread)
    }

    @Test func canConvertIsFalseOnCoverPage() {
        let (model, document, _) = makeModel()
        let cover = document.book.pages.first(where: { $0.role == .cover })!
        model.selectPage(cover.id)
        #expect(!model.canConvertSelectedToSpread)
    }

    @Test func canConvertIsTrueOnEligiblePair() {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }
        model.selectPage(document.book.pages[leftIdx].id)
        #expect(model.canConvertSelectedToSpread)
    }

    @Test func canConvertIsFalseOnSpreadMember() {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }
        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 45)
        // After conversion, the page is now a spread member — can't convert again.
        model.selectPage(document.book.pages[leftIdx].id)
        #expect(!model.canConvertSelectedToSpread)
    }

    @Test func canRevertIsTrueOnSpreadMember() {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }
        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 46)
        model.selectPage(document.book.pages[leftIdx].id)
        #expect(model.canRevertSelectedSpread)
        #expect(model.selectedPageIsSpreadMember)
    }

    @Test func canRevertIsFalseOnStandardPage() {
        let (model, document, _) = makeModel()
        guard let page = document.book.pages.first(where: { $0.role == .standard }) else { return }
        model.selectPage(page.id)
        #expect(!model.canRevertSelectedSpread)
    }

    @Test func convertWithoutSelectionIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.convertSelectedSpread(seed: 50)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    @Test func revertWithoutSelectionIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.revertSelectedSpread(seed: 51)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    // MARK: - Page count invariant

    @Test func convertDoesNotChangePageCount() {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }
        let countBefore = document.book.pages.count
        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 60)
        #expect(document.book.pages.count == countBefore)
    }

    @Test func revertDoesNotChangePageCount() {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }
        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 61)
        let countAfterConvert = document.book.pages.count
        model.selectPage(document.book.pages[leftIdx].id)
        model.revertSelectedSpread(seed: 62)
        #expect(document.book.pages.count == countAfterConvert)
    }

    // MARK: - Export/render sequence length invariant (Task 2)

    /// Conversion never changes the page sequence length: 2 single pages become
    /// 2 member pages — so export and print rendering see the same page count.
    @Test func convertPreservesExportPageSequenceLength() throws {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }

        let pageCountBefore = document.book.pages.count

        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 70)

        // book.pages.count is the rendered/export sequence — unchanged.
        #expect(document.book.pages.count == pageCountBefore)
        // The new entries are spread members, not net-new pages.
        let memberCount = document.book.pages.filter { $0.spreadID != nil }.count
        #expect(memberCount == 2)
    }

    /// After convert+revert the export sequence is identical to the original.
    @Test func convertThenRevertLeavesExportSequenceLengthUnchanged() throws {
        let (model, document, _) = makeModel()
        guard let leftIdx = firstEligibleLeftIdx(in: document.book) else { return }

        let pageCountBefore = document.book.pages.count

        model.selectPage(document.book.pages[leftIdx].id)
        model.convertSelectedSpread(seed: 71)
        #expect(document.book.pages.count == pageCountBefore)

        model.selectPage(document.book.pages[leftIdx].id)
        model.revertSelectedSpread(seed: 72)
        #expect(document.book.pages.count == pageCountBefore)
        // No spread members remain after full revert.
        #expect(document.book.pages.allSatisfy { $0.spreadID == nil })
        #expect(document.book.spreads.isEmpty)
    }
}
