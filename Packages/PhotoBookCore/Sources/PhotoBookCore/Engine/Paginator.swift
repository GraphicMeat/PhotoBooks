/// Splits the analyzed photo sequence into per-page groups. Dynamic
/// programming over split points; cost = cluster cohesion + pacing + deviation
/// from the preset's target page count (spec, "Layout engine"). The justified
/// layout shows every photo whole regardless of orientation, so pages may mix
/// landscape and portrait freely; the airy target keeps page counts low.
enum Paginator {

    /// Airy ceiling on photos per page; also the page weight budget (= a hero's
    /// weight, so a hero fills its page alone).
    static let maxPhotosPerPage = 6

    /// Maximum summed photo weight on one page. Equal to maxPhotosPerPage so
    /// that (a) with all weights == 1 the weight budget reduces to the
    /// photo-count behavior, and (b) a hero (ImportanceWeight.maxWeight) fills a
    /// page on its own.
    static let maxWeightPerPage = maxPhotosPerPage

    /// Splitting an event (time cluster) across pages is the worst
    /// storytelling defect. 3.0 strictly exceeds the MAXIMUM combined pacing
    /// gain a split can buy — hero bonus (1.0) + dodged same-count pair (1.5)
    /// + one page of deviation (0.4) = 2.9 — so a mid-cluster split is never
    /// profitable while a boundary split exists.
    static let clusterSplitPenalty = 3.0

    /// Two adjacent pages with identical photo counts read as monotony.
    /// 1.5 loses to clusterSplitPenalty (cohesion first) but beats
    /// pageDeviationPenalty (an extra page is better than a repeated rhythm).
    static let samePagePenalty = 1.5

    /// Negative cost = reward for a 1-photo hero page right AFTER a dense
    /// (4+) grid — the breathing rhythm the spec asks for. One-directional:
    /// rewarding both directions double-counts each sandwich and floods the
    /// book with heroes.
    static let heroBonus = -1.0

    /// Gentle pull toward the target page count: 0.4 per page of deviation.
    /// One page of drift is accepted whenever it saves a cluster split
    /// (0.4 < 3.0) or a monotony pair (0.4 < 1.5), but free-floating page
    /// counts still converge to the target.
    static let pageDeviationPenalty = 0.4

    /// Airy default: aim for ~2 photos per page. The per-orientation caps and
    /// cluster cohesion shape the actual counts around this target.
    static let idealPhotosPerPage = 2.0

    /// Target = totalWeight / 3 (rounded up), capped by the preset's maxPages
    /// and by photoCount (a page holds at least one photo, so pages can never
    /// exceed the number of photos even when weights inflate the total).
    static func targetPageCount(totalWeight: Int, photoCount: Int, preset: PrintPreset) -> Int {
        let raw = Int((Double(totalWeight) / idealPhotosPerPage).rounded(.up))
        return max(1, min(raw, preset.maxPages, photoCount))
    }

    /// Back-compat overload: with all weights == 1, totalWeight == photoCount.
    static func targetPageCount(photoCount: Int, preset: PrintPreset) -> Int {
        targetPageCount(totalWeight: photoCount, photoCount: photoCount, preset: preset)
    }

    /// DP over split points. State = (photos consumed, last group size,
    /// pages used); the page-count dimension is what lets the final
    /// |pages − target| deviation be exact rather than approximated.
    /// All tie-breaks are deterministic (fewer pages, then larger last group,
    /// first-found on exact cost ties in a fixed iteration order).
    static func paginate(_ photos: [AnalyzedPhoto], preset: PrintPreset) -> [Range<Int>] {
        let count = photos.count
        guard count > 0 else { return [] }
        let sequencer = Sequencer(photos: photos)

        // Per-photo layout weights (clamped defensively to [1, cap]). Prefix
        // sums give any group's summed weight in O(1). With every weight == 1
        // the cap check and target below reduce to the photo-count behavior,
        // so this path stays byte-identical to the pre-importance engine.
        let weights = photos.map { max(1, min($0.weight, maxWeightPerPage)) }
        var prefix = [Int](repeating: 0, count: count + 1)
        for i in 0..<count { prefix[i + 1] = prefix[i] + weights[i] }
        func groupWeight(_ start: Int, _ end: Int) -> Int { prefix[end] - prefix[start] }

        // A group [start, end) is a valid page when it is within the airy
        // photo cap and the page weight budget, and does not pack a panorama
        // alongside other photos. An ultra-wide panorama spans a whole spread,
        // so it must land in its own 1-photo group (which makeBook then
        // auto-promotes into a 2-page spread). All constraints are monotonic in
        // `end`, so the DP's `else { break }` (once-invalid-stays-invalid) holds.
        func groupValid(_ start: Int, _ end: Int) -> Bool {
            let size = end - start
            if size > maxPhotosPerPage { return false }
            if groupWeight(start, end) > maxWeightPerPage { return false }
            if size > 1 {
                for i in start..<end where photos[i].ref.aspectRatio >= BookEngine.panoramaAspectThreshold {
                    return false
                }
            }
            return true
        }

        let target = targetPageCount(totalWeight: prefix[count], photoCount: count, preset: preset)

        struct State: Hashable {
            var index: Int        // photos consumed
            var lastSize: Int     // size of the page that ends at `index`
            var pages: Int        // pages used so far
        }

        var bestCost: [State: Double] = [:]
        var parent: [State: State] = [:]

        // Cost charged at the split AFTER a group ending at `index`:
        // free at the sequence end or on a cluster boundary, penalized inside
        // a cluster.
        func splitCost(after index: Int) -> Double {
            if index >= count { return 0 }
            return sequencer.isClusterBoundary(index) ? 0 : clusterSplitPenalty
        }

        // Pacing cost between two consecutive pages.
        func pairCost(previous: Int, current: Int) -> Double {
            var cost = 0.0
            if previous == current { cost += samePagePenalty }
            if previous >= 4 && current == 1 { cost += heroBonus }
            return cost
        }

        // Seed: the first page.
        for size in 1...min(maxPhotosPerPage, count) {
            // Validity is monotonic in `size`, so the first invalid size means
            // every larger one is invalid too — break is safe and prunes the rest.
            guard groupValid(0, size) else { break }
            bestCost[State(index: size, lastSize: size, pages: 1)] = splitCost(after: size)
        }

        // Expand in strictly increasing `index` order so every reachable
        // state exists before it is extended.
        for index in 1..<count {
            for lastSize in 1...maxPhotosPerPage {
                for pages in 1...index {
                    let state = State(index: index, lastSize: lastSize, pages: pages)
                    guard let cost = bestCost[state] else { continue }
                    for size in 1...min(maxPhotosPerPage, count - index) {
                        guard groupValid(index, index + size) else { break }
                        let next = State(index: index + size, lastSize: size, pages: pages + 1)
                        let total = cost
                            + pairCost(previous: lastSize, current: size)
                            + splitCost(after: index + size)
                        if total < (bestCost[next] ?? .infinity) - 1e-12 {
                            bestCost[next] = total
                            parent[next] = state
                        }
                    }
                }
            }
        }

        // Terminal: add the page-count deviation, pick deterministically.
        let terminals = bestCost.keys
            .filter { $0.index == count }
            .sorted { a, b in
                if a.pages != b.pages { return a.pages < b.pages }
                return a.lastSize > b.lastSize
            }
        var bestTerminal = terminals[0]
        var bestTotal = Double.infinity
        for state in terminals {
            let total = bestCost[state]!
                + pageDeviationPenalty * Double(abs(state.pages - target))
            if total < bestTotal - 1e-12 {
                bestTotal = total
                bestTerminal = state
            }
        }

        // Walk parents to recover the group sizes, then convert to ranges.
        var sizes: [Int] = []
        var cursor = bestTerminal
        while true {
            sizes.append(cursor.lastSize)
            guard let previous = parent[cursor] else { break }
            cursor = previous
        }
        sizes.reverse()

        var ranges: [Range<Int>] = []
        var start = 0
        for size in sizes {
            ranges.append(start..<(start + size))
            start += size
        }
        return ranges
    }
}
