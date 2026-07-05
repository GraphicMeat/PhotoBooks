import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

/// Phase B density stepper: increaseSelectedPageDensity /
/// decreaseSelectedPageDensity, plus the can… guard properties.
@MainActor
@Suite struct DensityStepperTests {

    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    /// 14 photos spread across 3 time clusters — similar to the core fixture;
    /// guarantees multiple standard pages with varying photo counts.
    private func fixtureBook() -> Book {
        func ref(_ id: String, hours: Double) -> PhotoRef {
            PhotoRef(id: PhotoID(rawValue: id),
                     source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
        }
        let photos: [PhotoRef] = [
            ref("d01", hours: 0), ref("d02", hours: 0.3), ref("d03", hours: 0.6),
            ref("d04", hours: 0.9), ref("d05", hours: 5), ref("d06", hours: 5.3),
            ref("d07", hours: 5.6), ref("d08", hours: 5.9), ref("d09", hours: 10),
            ref("d10", hours: 10.3), ref("d11", hours: 10.6), ref("d12", hours: 10.9),
            ref("d13", hours: 16), ref("d14", hours: 16.3),
        ]
        return BookEngine().makeBook(title: "Density Fixture", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 1)
    }

    private func makeModel() -> (model: BookEditorModel, document: BookDocument, undo: UndoManager) {
        let document = BookDocument(book: fixtureBook())
        let model = BookEditorModel(document: document, photoKitProvider: PhotoKitProvider())
        let undoManager = UndoManager()
        model.undoManager = undoManager
        return (model, document, undoManager)
    }

    /// Returns all placed photo IDs across standard pages.
    private func placedIDs(in book: Book) -> Set<PhotoID> {
        Set(book.pages.filter { $0.role == .standard }
            .flatMap { $0.photoSlots.compactMap(\.photoID) })
    }

    // MARK: Increase

    @Test func increaseRoutedThroughApplyIsUndoable() throws {
        let (model, document, undo) = makeModel()
        let standardPages = document.book.pages.filter { $0.role == .standard }
        // Find a page with ≥2 photos so increase has a downstream photo.
        guard let target = standardPages.first(where: { $0.photoSlots.count >= 2 }) else { return }

        model.selectPage(target.id)
        guard model.canIncreaseSelectedPageDensity else { return }

        let before = try BookSerializer.encode(document.book)
        let beforeCount = target.photoSlots.count

        model.increaseSelectedPageDensity(seed: 10)

        #expect(try BookSerializer.encode(document.book) != before)
        let afterPage = document.book.pages.first(where: { $0.id == target.id })!
        #expect(afterPage.photoSlots.count == beforeCount + 1)
        // Photo set unchanged.
        #expect(placedIDs(in: document.book) == placedIDs(in: try BookSerializer.decode(before)))

        // Undo restores.
        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
    }

    // MARK: Decrease

    @Test func decreaseRoutedThroughApplyIsUndoable() throws {
        let (model, document, undo) = makeModel()
        let standardPages = document.book.pages.filter { $0.role == .standard }
        guard let target = standardPages.first(where: { $0.photoSlots.count >= 2 }) else { return }

        model.selectPage(target.id)
        guard model.canDecreaseSelectedPageDensity else { return }

        let before = try BookSerializer.encode(document.book)
        let beforeCount = target.photoSlots.count

        model.decreaseSelectedPageDensity(seed: 11)

        let afterPage = document.book.pages.first(where: { $0.id == target.id })!
        #expect(afterPage.photoSlots.count == beforeCount - 1)
        #expect(placedIDs(in: document.book) == placedIDs(in: try BookSerializer.decode(before)))

        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(document.book) == before)
    }

    // MARK: can… guard properties

    @Test func canIncreaseIsFalseWithNoSelection() {
        let (model, _, _) = makeModel()
        #expect(!model.canIncreaseSelectedPageDensity)
    }

    @Test func canDecreaseIsFalseWithNoSelection() {
        let (model, _, _) = makeModel()
        #expect(!model.canDecreaseSelectedPageDensity)
    }

    @Test func canDecreaseIsFalseOnOnePhotoPage() {
        let (model, document, _) = makeModel()
        let standardPages = document.book.pages.filter { $0.role == .standard }
        if let onePage = standardPages.first(where: { $0.photoSlots.count == 1 }) {
            model.selectPage(onePage.id)
            #expect(!model.canDecreaseSelectedPageDensity)
        }
        // If no 1-photo page exists in the fixture, push one there.
        else if let target = standardPages.first(where: { $0.photoSlots.count >= 2 }) {
            model.selectPage(target.id)
            model.decreaseSelectedPageDensity(seed: 12)
            // After decrease the original page now has count−1; keep
            // decreasing until count == 1 or no longer eligible.
            while model.canDecreaseSelectedPageDensity {
                model.decreaseSelectedPageDensity(seed: 13)
            }
            #expect(!model.canDecreaseSelectedPageDensity)
        }
    }

    @Test func canIncreaseIsFalseOnLastPageWhenNoDownstreamPhoto() {
        let (model, document, _) = makeModel()
        let standardPages = document.book.pages.filter { $0.role == .standard }
        // The last standard page has no downstream page → can't increase.
        guard let lastPage = standardPages.last else { return }
        model.selectPage(lastPage.id)
        #expect(!model.canIncreaseSelectedPageDensity)
    }

    @Test func increaseWithoutSelectionIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.increaseSelectedPageDensity(seed: 20)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }

    @Test func decreaseWithoutSelectionIsANoOp() {
        let (model, document, undo) = makeModel()
        let before = document.book
        model.decreaseSelectedPageDensity(seed: 21)
        #expect(document.book == before)
        #expect(!undo.canUndo)
    }
}
