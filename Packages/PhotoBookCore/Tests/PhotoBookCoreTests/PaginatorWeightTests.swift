import Testing
import Foundation
@testable import PhotoBookCore

struct PaginatorWeightTests {
    // Same named preset the legacy PaginatorTests pin against, so cross-test
    // expectations (e.g. the [0..<7, 7..<14] split below) line up exactly.
    private let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    /// AnalyzedPhoto with an explicit weight and cluster index (cluster drives
    /// split costs the same way the legacy paginator tests do).
    private func photo(_ name: String, weight: Int = 1, cluster: Int = 0) -> AnalyzedPhoto {
        let ref = PhotoRef(id: PhotoID(rawValue: name),
                           source: .file(bookmark: Data()),
                           pixelWidth: 4000, pixelHeight: 3000)
        return AnalyzedPhoto(ref: ref, orientation: .landscape,
                             clusterIndex: cluster, weight: weight)
    }

    /// With all weights == 1 the weight budget reduces to the plain photo-count
    /// behavior: pages honor the orientation cap, keep the cluster boundary at
    /// index 7 intact, and cover every photo. (Weights only matter when an
    /// importance score lifts a photo above 1 — see the hero test below.)
    @Test func allWeightOneRespectsCapsAndClusterBoundary() {
        let photos = (0..<7).map { photo("a\($0)", cluster: 0) }
            + (0..<7).map { photo("b\($0)", cluster: 1) }
        let ranges = Paginator.paginate(photos, preset: preset)
        #expect(ranges.allSatisfy { $0.count <= Paginator.maxPhotosPerPage })
        for range in ranges {
            #expect(!(range.lowerBound < 7 && range.upperBound > 7),
                    "page \(range) straddles the cluster boundary")
        }
        #expect(ranges.flatMap(Array.init) == Array(0..<14))
    }

    @Test func heroWeightForcesSoloPage() {
        var photos = (0..<6).map { photo("p\($0)", cluster: 0) }
        photos[3] = photo("hero", weight: Paginator.maxWeightPerPage, cluster: 0)
        let ranges = Paginator.paginate(photos, preset: preset)
        let heroRange = ranges.first { $0.contains(3) }!
        #expect(heroRange == 3..<4)        // hero alone on its page
    }

    @Test func noPageExceedsWeightCapacity() {
        let weights = [3, 1, 1, 3, 2, 1, 3, 1]
        let photos = weights.enumerated().map {
            photo("p\($0.offset)", weight: $0.element, cluster: 0)
        }
        let ranges = Paginator.paginate(photos, preset: preset)
        for range in ranges {
            let pageWeight = range.reduce(0) { $0 + photos[$1].weight }
            #expect(pageWeight <= Paginator.maxWeightPerPage)
        }
        #expect(ranges.flatMap { Array($0) } == Array(0..<weights.count))
    }

    @Test func midWeightPagesHoldFewerPhotos() {
        // 6 normal (weight 1) photos fit one page (weight 6 ≤ 9), so they pack
        // tight. 6 mid (weight 3) photos sum to weight 18 and cannot — the cap
        // forces strictly more pages. `>` (not `>=`) is the real invariant.
        let mids = (0..<6).map { photo("m\($0)", weight: 3, cluster: 0) }
        let norms = (0..<6).map { photo("n\($0)", weight: 1, cluster: 0) }
        let midPages = Paginator.paginate(mids, preset: preset).count
        let normPages = Paginator.paginate(norms, preset: preset).count
        #expect(midPages > normPages)
    }
}
