import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import ModelLayer

@MainActor
@Suite struct LayoutOptionsModelTests {
    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func fixtureBook() -> Book {
        func ref(_ id: String, hours: Double) -> PhotoRef {
            PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                     pixelWidth: 4000, pixelHeight: 3000,
                     captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
        }
        let photos = (0..<10).map { ref("q\($0)", hours: Double($0) * 0.4) }
        return BookEngine().makeBook(title: "LO", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 5)
    }

    private func makeModel() -> (BookEditorModel, BookDocument, UndoManager) {
        let doc = BookDocument(book: fixtureBook())
        let model = BookEditorModel(document: doc, photoKitProvider: PhotoKitProvider())
        let undo = UndoManager(); model.undoManager = undo
        return (model, doc, undo)
    }

    @Test func applyLayoutOptionChangesCountAndIsUndoable() throws {
        let (model, doc, undo) = makeModel()
        let target = doc.book.pages.first { $0.role == .standard }!
        model.selectPage(target.id)
        let groups = model.layoutOptionsByCount
        let current = target.photoSlots.count
        guard let group = groups.first(where: { $0.count != current && !$0.candidates.isEmpty })
        else { return }

        let before = try BookSerializer.encode(doc.book)
        model.applyLayoutOption(count: group.count, candidate: group.candidates[0], seed: 9)

        let after = doc.book.pages.first { $0.id == target.id }!
        #expect(after.photoSlots.count == group.count)
        #expect(undo.canUndo)
        undo.undo()
        #expect(try BookSerializer.encode(doc.book) == before)
    }

    @Test func applyLayoutOptionSameCountSwapsLayoutKeepingCount() throws {
        let (model, doc, undo) = makeModel()
        let target = doc.book.pages.first { $0.role == .standard }!
        model.selectPage(target.id)
        let current = target.photoSlots.count
        // The same-count group exists for the current count; pick a candidate
        // whose frames differ from the page's current frames so the layout
        // actually changes (count stays the same — no repaginate).
        guard let group = model.layoutOptionsByCount.first(where: { $0.count == current }),
              let candidate = group.candidates.first(where: {
                  $0.photoSlotFrames != target.photoSlots.map(\.frame)
              }) else { return }

        model.applyLayoutOption(count: current, candidate: candidate, seed: 7)

        let after = doc.book.pages.first { $0.id == target.id }!
        #expect(after.photoSlots.count == current)               // count unchanged
        #expect(after.photoSlots.map(\.frame) == candidate.photoSlotFrames)  // layout swapped
        #expect(undo.canUndo)
    }
}
