import Foundation
import PhotoBookCore
import Testing
@testable import AppSupport

@Suite struct SpreadPairingTests {

    @Test func emptyBookHasNoSpreads() {
        #expect(SpreadPairing.spreads(forPageCount: 0) == [])
    }

    @Test func coverStandsAlone() {
        #expect(SpreadPairing.spreads(forPageCount: 1)
                == [Spread(index: 0, left: nil, right: 0)])
    }

    @Test func interiorPagesPairAfterCover() {
        // cover | 1-2 | 3-4
        #expect(SpreadPairing.spreads(forPageCount: 5) == [
            Spread(index: 0, left: nil, right: 0),
            Spread(index: 1, left: 1, right: 2),
            Spread(index: 2, left: 3, right: 4)
        ])
    }

    @Test func oddInteriorTailLeavesRightBlank() {
        // cover | 1-2 | 3-∅
        #expect(SpreadPairing.spreads(forPageCount: 4) == [
            Spread(index: 0, left: nil, right: 0),
            Spread(index: 1, left: 1, right: 2),
            Spread(index: 2, left: 3, right: nil)
        ])
    }

    @Test func spreadIndexLookupMatchesPairing() {
        let spreads = SpreadPairing.spreads(forPageCount: 7)
        for pageIndex in 0..<7 {
            let spreadIndex = SpreadPairing.spreadIndex(forPageIndex: pageIndex)
            let spread = spreads[spreadIndex]
            #expect(spread.left == pageIndex || spread.right == pageIndex,
                    "page \(pageIndex) not in spread \(spreadIndex)")
        }
    }

    // MARK: - C5: spread-aware pairing

    /// Builds `count` standard pages; the indices in `spreadMemberPairs` become
    /// left/right halves of their own spread (consecutive index pairs).
    private func pages(_ count: Int, spreadLeftIndices: Set<Int> = []) -> [Page] {
        (0..<count).map { i in
            var page = Page(role: i == 0 ? .cover : .standard,
                            origin: .template(id: "t"))
            if spreadLeftIndices.contains(i) {
                let sid = UUID()
                page.spreadID = sid
                page.half = .left
            } else if spreadLeftIndices.contains(i - 1) {
                // The page right after a spread-left is that spread's right half.
                page.spreadID = UUID()   // any non-nil; only half/left detection matters
                page.half = .right
            }
            return page
        }
    }

    @Test func spreadMemberPairFormsOwnRow() {
        // cover | spread(1,2) | 3-4
        let p = pages(5, spreadLeftIndices: [1])
        // Give the spread members a shared id so right-detection works.
        var pgs = p
        let sid = pgs[1].spreadID!
        pgs[2].spreadID = sid
        let rows = SpreadPairing.spreads(for: pgs)
        #expect(rows == [
            Spread(index: 0, left: nil, right: 0),
            Spread(index: 1, left: 1, right: 2),
            Spread(index: 2, left: 3, right: 4)
        ])
    }

    @Test func spreadShiftsSubsequentPairingParity() {
        // cover | 1-2 | spread(3,4) | 5-6
        var pgs = pages(7)
        let sid = UUID()
        pgs[3].spreadID = sid; pgs[3].half = .left
        pgs[4].spreadID = sid; pgs[4].half = .right
        let rows = SpreadPairing.spreads(for: pgs)
        #expect(rows == [
            Spread(index: 0, left: nil, right: 0),
            Spread(index: 1, left: 1, right: 2),
            Spread(index: 2, left: 3, right: 4),   // the spread, its own row
            Spread(index: 3, left: 5, right: 6)
        ])
    }

    @Test func twoAdjacentSpreadsEachGetOwnRow() {
        // cover | spread(1,2) | spread(3,4)
        var pgs = pages(5)
        let s1 = UUID(); pgs[1].spreadID = s1; pgs[1].half = .left
        pgs[2].spreadID = s1; pgs[2].half = .right
        let s2 = UUID(); pgs[3].spreadID = s2; pgs[3].half = .left
        pgs[4].spreadID = s2; pgs[4].half = .right
        let rows = SpreadPairing.spreads(for: pgs)
        #expect(rows == [
            Spread(index: 0, left: nil, right: 0),
            Spread(index: 1, left: 1, right: 2),
            Spread(index: 2, left: 3, right: 4)
        ])
    }

    @Test func plainPagesMatchCountBasedPairing() {
        // With no spread members, the page-aware rule equals the parity rule.
        let pgs = pages(6)
        #expect(SpreadPairing.spreads(for: pgs)
                == SpreadPairing.spreads(forPageCount: 6))
    }

    @Test func spreadAwareIndexLookupFindsContainingRow() {
        var pgs = pages(7)
        let sid = UUID()
        pgs[3].spreadID = sid; pgs[3].half = .left
        pgs[4].spreadID = sid; pgs[4].half = .right
        let rows = SpreadPairing.spreads(for: pgs)
        for pageIndex in 0..<7 {
            let idx = SpreadPairing.spreadIndex(for: pgs, pageIndex: pageIndex)
            let row = rows[idx]
            #expect(row.left == pageIndex || row.right == pageIndex,
                    "page \(pageIndex) not in row \(idx)")
        }
    }

    @Test func missingPhotoCountCountsMissingAndDanglingRefs() {
        var book = Book(title: "T", presetID: "blurb-small-square", style: .standard)
        book.photoLibrary = [
            PhotoRef(id: PhotoID(rawValue: "ok"), source: .file(bookmark: Data()),
                     pixelWidth: 100, pixelHeight: 100),
            PhotoRef(id: PhotoID(rawValue: "gone"), source: .file(bookmark: Data()),
                     pixelWidth: 100, pixelHeight: 100, isMissing: true)
        ]
        let page = Page(origin: .template(id: "grid"), photoSlots: [
            PhotoSlot(frame: .full, photoID: PhotoID(rawValue: "ok")),          // fine
            PhotoSlot(frame: .full, photoID: PhotoID(rawValue: "gone")),        // isMissing
            PhotoSlot(frame: .full, photoID: PhotoID(rawValue: "dangling")),    // no ref
            PhotoSlot(frame: .full, photoID: nil)                               // empty ≠ missing
        ])
        #expect(book.missingPhotoCount(on: page) == 2)
    }
}
