import Foundation

/// How many photos the curator should keep.
public enum CurationTarget: Equatable, Sendable {
    /// Keep exactly this many (clamped to what's available).
    case photos(Int)
    /// Keep enough to roughly fill this many pages:
    /// `pages * Paginator.idealPhotosPerPage`, rounded, clamped.
    case pages(Int)
}

/// Picks the best N of many candidate photos with time-spread diversity and
/// near-duplicate suppression. Pure and deterministic: `quality` comes from
/// Vision scoring and `clusterID` from burst clustering (both upstream in
/// PhotoBookImport); this only decides the final set.
public enum PhotoCurator {

    public static func select(from candidates: [CurationCandidate], target: CurationTarget) -> [PhotoID] {
        let pool = candidates.filter { !$0.isUtility }
        guard !pool.isEmpty else { return [] }

        // Distinct clusters (order-independent count).
        let clusterCount = Set(pool.map { $0.clusterID }).count

        // Resolve and clamp N.
        let rawN: Int
        switch target {
        case .photos(let n): rawN = n
        case .pages(let p):  rawN = Int((Double(p) * Paginator.idealPhotosPerPage).rounded())
        }
        let n = min(max(rawN, 1), pool.count)

        // Representative = highest-(quality desc, id asc) member of each cluster.
        let repIDs = Set(Set(pool.map { $0.clusterID }).map { cluster in
            pool.filter { $0.clusterID == cluster }.min(by: betterFirst)!.id
        })

        // Bucket by capture time. Dated candidates split the span into
        // min(N, clusterCount) equal-duration buckets; undated form a trailing
        // bucket. Each bucket's members are sorted best-first for picking.
        let orderedBuckets = buildBuckets(pool: pool, n: n, clusterCount: clusterCount)

        var pickedIDs = Set<PhotoID>()
        var pickedClusters = Set<Int>()
        var result: [CurationCandidate] = []

        // Phase 1 — one unpicked-cluster representative per bucket per round.
        var progress = true
        while result.count < n && progress {
            progress = false
            for bucket in orderedBuckets {
                if result.count >= n { break }
                if let pick = bucket.first(where: {
                    repIDs.contains($0.id) && !pickedClusters.contains($0.clusterID)
                }) {
                    result.append(pick)
                    pickedIDs.insert(pick.id)
                    pickedClusters.insert(pick.clusterID)
                    progress = true
                }
            }
        }

        // Phase 2 — every cluster now has a pick; fill remaining slots with the
        // best not-yet-picked members, still round-robin bucket by bucket.
        progress = true
        while result.count < n && progress {
            progress = false
            for bucket in orderedBuckets {
                if result.count >= n { break }
                if let pick = bucket.first(where: { !pickedIDs.contains($0.id) }) {
                    result.append(pick)
                    pickedIDs.insert(pick.id)
                    progress = true
                }
            }
        }

        // Book order: chronological, nil dates last, id-asc tiebreak.
        return result.sorted(by: chronological).map { $0.id }
    }

    // MARK: - Ordering

    /// Quality descending, id ascending.
    private static func betterFirst(_ a: CurationCandidate, _ b: CurationCandidate) -> Bool {
        if a.quality != b.quality { return a.quality > b.quality }
        return a.id.rawValue < b.id.rawValue
    }

    /// Capture date ascending, nil last, id ascending.
    private static func chronological(_ a: CurationCandidate, _ b: CurationCandidate) -> Bool {
        switch (a.captureDate, b.captureDate) {
        case let (da?, db?):
            if da != db { return da < db }
            return a.id.rawValue < b.id.rawValue
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil):   return a.id.rawValue < b.id.rawValue
        }
    }

    // MARK: - Bucketing

    /// Buckets in chronological order (dated buckets first, one trailing undated
    /// bucket last), each sorted best-first. Empty buckets are omitted.
    private static func buildBuckets(pool: [CurationCandidate], n: Int, clusterCount: Int) -> [[CurationCandidate]] {
        let dated = pool.filter { $0.captureDate != nil }.sorted(by: chronological)
        let undated = pool.filter { $0.captureDate == nil }

        var buckets: [[CurationCandidate]] = []

        if let minDate = dated.first?.captureDate, let maxDate = dated.last?.captureDate {
            let span = maxDate.timeIntervalSince(minDate)
            let bucketCount = span == 0 ? 1 : max(1, min(n, clusterCount))
            var grouped = [[CurationCandidate]](repeating: [], count: bucketCount)
            for candidate in dated {
                let index: Int
                if span == 0 {
                    index = 0
                } else {
                    let raw = Int((candidate.captureDate!.timeIntervalSince(minDate) / span) * Double(bucketCount))
                    index = min(max(raw, 0), bucketCount - 1)
                }
                grouped[index].append(candidate)
            }
            buckets = grouped.filter { !$0.isEmpty }
        }

        if !undated.isEmpty {
            buckets.append(undated)
        }

        return buckets.map { $0.sorted(by: betterFirst) }
    }
}
