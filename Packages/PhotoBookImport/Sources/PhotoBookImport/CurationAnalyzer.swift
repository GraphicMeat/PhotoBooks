import Foundation
import PhotoBookCore

/// Groups near-duplicate photos (burst frames, near-identical retakes) so the
/// selection algorithm can later keep only the best member of each group.
/// Similarity is a Vision feature-print distance; the pure `clusters` core takes
/// that distance as an injected closure so it stays testable without Vision.
public enum CurationAnalyzer {
    /// Feature-print distances below this count as "same shot". Vision distances
    /// are unbounded (smaller = more similar); 0.5 separates burst frames from
    /// genuinely different compositions in practice.
    public static let duplicateDistanceThreshold: Float = 0.5
    /// Only photos taken within this gap can be near-duplicates — bounds
    /// comparisons to a sliding time window instead of the full O(n²) set.
    public static let burstTimeWindow: TimeInterval = 600   // 10 min

    /// Cap on how many prior undated photos each undated photo is compared
    /// against, so thousands of date-less imports don't degrade to O(n²).
    static let undatedComparisonCap = 32

    // MARK: - Pure core

    /// Cluster photos where `distance(a,b) < duplicateDistanceThreshold` AND the
    /// two were taken within `burstTimeWindow`. Union-find so similarity chains
    /// merge transitively. Deterministic: cluster IDs are 0-based in order of
    /// first appearance in the (stable) capture-date sort.
    ///
    /// Undated photos sort last and are compared only among themselves (treated
    /// as equal-time), each against at most the previous `undatedComparisonCap`
    /// undated photos to keep the undated case bounded too.
    static func clusters(
        photos: [(id: PhotoID, captureDate: Date?)],
        distance: (PhotoID, PhotoID) -> Float
    ) -> [PhotoID: Int] {
        let n = photos.count
        guard n > 0 else { return [:] }

        // Stable sort: dated ascending, undated last, ties broken by input order.
        let order = Array(0..<n).sorted { a, b in
            switch (photos[a].captureDate, photos[b].captureDate) {
            case let (da?, db?): return da == db ? a < b : da < db
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a < b
            }
        }

        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        func maybeUnion(_ i: Int, _ j: Int) {
            if distance(photos[i].id, photos[j].id) < duplicateDistanceThreshold {
                union(i, j)
            }
        }

        // Sliding window over the sorted sequence. `lo` trails `hi` so we only
        // compare photos whose capture-date gap is within the window; undated
        // photos (date == nil) fall through to a count-capped comparison.
        var lo = 0
        for hi in 1..<max(1, n) {
            let cur = photos[order[hi]].captureDate
            if let cur {
                while lo < hi, let loDate = photos[order[lo]].captureDate,
                      cur.timeIntervalSince(loDate) > burstTimeWindow {
                    lo += 1
                }
                for j in lo..<hi where photos[order[j]].captureDate != nil {
                    maybeUnion(order[hi], order[j])
                }
            } else {
                // Undated: compare against the previous `cap` undated photos.
                let start = max(0, hi - undatedComparisonCap)
                for j in start..<hi where photos[order[j]].captureDate == nil {
                    maybeUnion(order[hi], order[j])
                }
            }
        }

        // Assign 0-based cluster IDs by first appearance of each root in sort order.
        var idForRoot = [Int: Int]()
        var result = [PhotoID: Int]()
        for idx in order {
            let root = find(idx)
            let cid = idForRoot[root] ?? {
                let c = idForRoot.count
                idForRoot[root] = c
                return c
            }()
            result[photos[idx].id] = cid
        }
        return result
    }

    // MARK: - Production entry

    /// Cluster refs using feature prints already computed by
    /// `ImageContentAnalyzer.analyzeWithScores` — the print rides along with
    /// scoring on the same decoded thumbnail, so the 3,000-photo flow decodes
    /// each image exactly once. (The wizard is the only caller; there is no
    /// self-computing fallback path.) `scores` supplies quality/isUtility.
    /// A photo without a print is treated as infinitely far from everything
    /// (its own singleton cluster).
    public static func candidates(
        for refs: [PhotoRef],
        scores: [PhotoID: ImportanceScore],
        prints: [PhotoID: FeaturePrint]
    ) -> [CurationCandidate] {
        guard !refs.isEmpty else { return [] }

        let photos = refs.map { (id: $0.id, captureDate: $0.captureDate) }
        let clusterID = clusters(photos: photos) { a, b in
            // Missing print → +∞ so the photo never merges with anything.
            guard let pa = prints[a], let pb = prints[b] else { return .greatestFiniteMagnitude }
            return pa.distance(to: pb)
        }

        return refs.map { ref in
            CurationCandidate(
                id: ref.id,
                // Analysis-failure fallback: unscored photos are mid-quality,
                // never silently dropped from curation.
                quality: scores[ref.id]?.quality ?? 0.5,
                captureDate: ref.captureDate,
                clusterID: clusterID[ref.id] ?? 0,
                isUtility: scores[ref.id]?.isUtility ?? false)
        }
    }
}
