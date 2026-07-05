import Foundation
import PhotoBookCore

/// One spread in the browser: indices into `book.pages` (nil = blank
/// facing page). Pure value — the pairing rule is unit-tested.
public struct Spread: Equatable, Identifiable {
    public var index: Int
    public var left: Int?
    public var right: Int?
    public var id: Int { index }

    public init(index: Int, left: Int?, right: Int?) {
        self.index = index
        self.left = left
        self.right = right
    }
}

public enum SpreadPairing {

    /// Parity pairing for a book with no first-class spreads: the cover
    /// (`pages[0]`) stands alone, then interior pages face each other in
    /// document order — pages 1–2, 3–4, … (0-based). An odd interior tail
    /// leaves the right side blank. The cover sits on the right of its spread,
    /// like a closed book's front.
    public static func spreads(forPageCount pageCount: Int) -> [Spread] {
        guard pageCount > 0 else { return [] }
        var spreads = [Spread(index: 0, left: nil, right: 0)]
        var pageIndex = 1
        while pageIndex < pageCount {
            let right = pageIndex + 1 < pageCount ? pageIndex + 1 : nil
            spreads.append(Spread(index: spreads.count, left: pageIndex, right: right))
            pageIndex += 2
        }
        return spreads
    }

    /// Spread-aware pairing. A first-class spread's two member pages always
    /// form their OWN facing row regardless of global parity: the cover stands
    /// alone, then we walk the interior — when a page is the `.left` half of a
    /// spread we emit `(left:i, right:i+1)` and advance 2; otherwise we pair the
    /// next two consecutive non-spread standard pages. An odd non-spread tail
    /// leaves the right side blank.
    public static func spreads(for pages: [PhotoBookCore.Page]) -> [Spread] {
        guard !pages.isEmpty else { return [] }
        var rows = [Spread(index: 0, left: nil, right: 0)]
        var i = 1
        while i < pages.count {
            if pages[i].spreadID != nil, pages[i].half == .left, i + 1 < pages.count {
                // The spread's two halves are their own row.
                rows.append(Spread(index: rows.count, left: i, right: i + 1))
                i += 2
            } else if pages[i].spreadID != nil {
                // A spread member that is not a clean left-half-with-partner
                // (defensive: orphaned half). Give it its own single row.
                rows.append(Spread(index: rows.count, left: i, right: nil))
                i += 1
            } else {
                // Pair the next page with the following page only if that one is
                // also a non-spread page; a spread member must start its own row.
                let next = i + 1
                if next < pages.count, pages[next].spreadID == nil {
                    rows.append(Spread(index: rows.count, left: i, right: next))
                    i += 2
                } else {
                    rows.append(Spread(index: rows.count, left: i, right: nil))
                    i += 1
                }
            }
        }
        return rows
    }

    /// The row containing `pageIndex` under the parity rule (no spreads).
    static func spreadIndex(forPageIndex pageIndex: Int) -> Int {
        guard pageIndex > 0 else { return 0 }
        return (pageIndex - 1) / 2 + 1
    }

    /// The spread-aware row containing `pageIndex`, computed from the pairing of
    /// `pages`. Falls back to row 0 when the index is out of range.
    public static func spreadIndex(for pages: [PhotoBookCore.Page], pageIndex: Int) -> Int {
        let rows = spreads(for: pages)
        return rows.first(where: { $0.left == pageIndex || $0.right == pageIndex })?.index ?? 0
    }
}

extension Book {
    /// Number of photo slots on `page` whose photo cannot be shown:
    /// the referenced `PhotoRef` is missing, or the ID has no ref at all.
    /// Drives the read-only "N photos missing" banner (relink flow: Plan 5).
    public func missingPhotoCount(on page: Page) -> Int {
        let refByID = Dictionary(photoLibrary.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        return page.photoSlots.count { slot in
            guard let photoID = slot.photoID else { return false }
            guard let ref = refByID[photoID] else { return true }
            return ref.isMissing
        }
    }
}
