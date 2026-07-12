import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PhotoCuratorTests {

    private let day: TimeInterval = 86_400
    private let epoch = Date(timeIntervalSince1970: 1_600_000_000)

    private func candidate(
        _ id: String,
        quality: Double,
        dayOffset: Double?,
        cluster: Int,
        utility: Bool = false
    ) -> CurationCandidate {
        CurationCandidate(
            id: PhotoID(rawValue: id),
            quality: quality,
            captureDate: dayOffset.map { epoch.addingTimeInterval($0 * day) },
            clusterID: cluster,
            isUtility: utility)
    }

    /// clusterCount clusters, membersPerCluster members each; quality descends
    /// within a cluster so member 0 is the representative. Dates spread one day
    /// per candidate so buckets are populated.
    private func clustered(_ clusterCount: Int, membersPerCluster: Int) -> [CurationCandidate] {
        var out: [CurationCandidate] = []
        for c in 0..<clusterCount {
            for m in 0..<membersPerCluster {
                out.append(candidate(
                    "c\(c)_m\(m)",
                    quality: Double(membersPerCluster - m),   // m0 highest
                    dayOffset: Double(c * membersPerCluster + m),
                    cluster: c))
            }
        }
        return out
    }

    // (a) determinism
    @Test func sameInputTwiceIsIdentical() {
        let input = clustered(4, membersPerCluster: 5)
        let first = PhotoCurator.select(from: input, target: .photos(7))
        let second = PhotoCurator.select(from: input, target: .photos(7))
        #expect(first == second)
    }

    // (b) cluster exclusivity: 3 clusters x 10, N=3 -> exactly one per cluster
    @Test func nEqualsClusterCountGivesOnePerCluster() {
        let input = clustered(3, membersPerCluster: 10)
        let picks = PhotoCurator.select(from: input, target: .photos(3))
        #expect(picks.count == 3)
        let clusters = picks.map { id in input.first { $0.id == id }!.clusterID }
        #expect(Set(clusters) == Set([0, 1, 2]))
    }

    // (c) overflow: N=5 -> all 3 clusters + 2 extra members
    @Test func overflowRepresentsAllClustersPlusExtras() {
        let input = clustered(3, membersPerCluster: 10)
        let picks = PhotoCurator.select(from: input, target: .photos(5))
        #expect(picks.count == 5)
        let clusters = picks.map { id in input.first { $0.id == id }!.clusterID }
        #expect(Set(clusters) == Set([0, 1, 2]))
    }

    // (d) time coverage: 100 photos over 10 distinct days (10/day, distinct
    // clusters), N=10 -> at least 8 distinct days represented.
    @Test func timeCoverageSpreadsAcrossDays() {
        var input: [CurationCandidate] = []
        var cluster = 0
        for d in 0..<10 {
            for p in 0..<10 {
                input.append(candidate(
                    "d\(d)_p\(p)",
                    quality: Double(p),
                    dayOffset: Double(d),
                    cluster: cluster))
                cluster += 1
            }
        }
        let picks = PhotoCurator.select(from: input, target: .photos(10))
        #expect(picks.count == 10)
        let days = picks.map { id -> Double in
            let date = input.first { $0.id == id }!.captureDate!
            return (date.timeIntervalSince(epoch) / day).rounded()
        }
        #expect(Set(days).count >= 8)
    }

    // (e) utility never picked, even when N exceeds non-utility count
    @Test func utilityNeverPicked() {
        var input = [
            candidate("real0", quality: 5, dayOffset: 0, cluster: 0),
            candidate("real1", quality: 4, dayOffset: 1, cluster: 1),
            candidate("real2", quality: 3, dayOffset: 2, cluster: 2),
        ]
        for i in 0..<10 {
            input.append(candidate("util\(i)", quality: 100, dayOffset: Double(i), cluster: 50 + i, utility: true))
        }
        let picks = PhotoCurator.select(from: input, target: .photos(50))
        #expect(picks.count == 3)
        #expect(!picks.contains(PhotoID(rawValue: "util0")))
        #expect(Set(picks) == Set([PhotoID(rawValue: "real0"), PhotoID(rawValue: "real1"), PhotoID(rawValue: "real2")]))
    }

    // (f) .pages(20) -> 40 photos, against the real constant
    @Test func pagesTargetUsesIdealPhotosPerPage() {
        let expected = Int((20.0 * Paginator.idealPhotosPerPage).rounded())
        #expect(expected == 40)
        var input: [CurationCandidate] = []
        for i in 0..<60 {
            input.append(candidate("p\(i)", quality: Double(i), dayOffset: Double(i), cluster: i))
        }
        let picks = PhotoCurator.select(from: input, target: .pages(20))
        #expect(picks.count == 40)
    }

    // (g) N > available -> all non-utility returned
    @Test func nGreaterThanAvailableReturnsAll() {
        let input = clustered(2, membersPerCluster: 3)  // 6 non-utility
        let picks = PhotoCurator.select(from: input, target: .photos(1000))
        #expect(picks.count == 6)
        #expect(Set(picks) == Set(input.map { $0.id }))
    }

    // (h) output is chronological (nil dates last)
    @Test func outputIsChronological() {
        var input: [CurationCandidate] = []
        for i in 0..<8 {
            input.append(candidate("dated\(i)", quality: Double(i), dayOffset: Double(7 - i), cluster: i))
        }
        input.append(candidate("nilA", quality: 9, dayOffset: nil, cluster: 20))
        input.append(candidate("nilB", quality: 9, dayOffset: nil, cluster: 21))
        let picks = PhotoCurator.select(from: input, target: .photos(10))
        let dates = picks.map { id in input.first { $0.id == id }!.captureDate }
        // non-decreasing, nils only at the tail
        var seenNil = false
        var previous: Date? = nil
        for date in dates {
            if let date {
                #expect(!seenNil, "dated candidate must not follow a nil-date one")
                if let previous { #expect(previous <= date) }
                previous = date
            } else {
                seenNil = true
            }
        }
    }

    // (i) all-nil-dates still works, picks by quality/cluster rules
    @Test func allNilDatesWorks() {
        var input: [CurationCandidate] = []
        // two clusters, three members each, all undated
        for c in 0..<2 {
            for m in 0..<3 {
                input.append(candidate("c\(c)m\(m)", quality: Double(10 - m), dayOffset: nil, cluster: c))
            }
        }
        let picks = PhotoCurator.select(from: input, target: .photos(2))
        #expect(picks.count == 2)
        // N == clusterCount -> one representative per cluster (the m0 of each)
        #expect(Set(picks) == Set([PhotoID(rawValue: "c0m0"), PhotoID(rawValue: "c1m0")]))
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(PhotoCurator.select(from: [], target: .photos(5)).isEmpty)
    }
}
