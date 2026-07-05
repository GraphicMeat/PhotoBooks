import EditCore
import Foundation
import PhotoBookCore
import SwiftUI
import Testing
@testable import ModelLayer

@Suite struct MovePagesParityTests {

    /// Exhaustive: every non-empty source subset × every destination over
    /// five standard pages (31 × 6 = 186 cases) matches the real API, and
    /// the cover never moves.
    @Test func movePagesMatchesMoveFromOffsetsForAllCases() {
        let letters = ["A", "B", "C", "D", "E"]
        for sourceMask in 1..<(1 << letters.count) {
            let source = IndexSet((0..<letters.count).filter { sourceMask & (1 << $0) != 0 })
            for destination in 0...letters.count {
                var expected = letters
                expected.move(fromOffsets: source, toOffset: destination)

                var book = Book(title: "T", presetID: "blurb-small-square", style: .standard)
                book.pages = [Page(role: .cover, origin: .template(id: "cover-hero"))]
                    + letters.map { Page(id: UUID(), origin: .template(id: $0)) }
                EditMutations.movePages(in: &book, fromStandardOffsets: source,
                                        toStandardOffset: destination)
                let actual = book.pages.dropFirst().map { page -> String in
                    if case .template(let id) = page.origin { return id }
                    return "?"
                }
                #expect(Array(actual) == expected, "source \(Array(source)) dest \(destination)")
                #expect(book.pages[0].role == .cover)
            }
        }
    }
}
