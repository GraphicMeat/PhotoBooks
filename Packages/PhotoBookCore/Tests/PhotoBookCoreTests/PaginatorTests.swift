import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PaginatorTests {

    private func photo(_ id: String, cluster: Int) -> AnalyzedPhoto {
        AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: 4000, pixelHeight: 3000),
            orientation: .landscape, clusterIndex: cluster)
    }

    /// `count` photos, each its own cluster (all splits free) — isolates the
    /// pacing + page-count parts of the cost model.
    private func singletonClusters(_ count: Int) -> [AnalyzedPhoto] {
        (0..<count).map { photo("p\($0)", cluster: $0) }
    }

    private func photo(_ id: String, cluster: Int, orientation: Orientation) -> AnalyzedPhoto {
        let (w, h): (Int, Int)
        switch orientation {
        case .portrait:  (w, h) = (3000, 4000)
        case .square:    (w, h) = (3000, 3000)
        case .landscape: (w, h) = (4000, 3000)
        }
        return AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: w, pixelHeight: h),
            orientation: orientation, clusterIndex: cluster)
    }

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }

    @Test func mixedOrientationsCanShareAPage() {
        // Justified packing shows every photo whole regardless of orientation,
        // so a landscape and a portrait photo may sit on the same page — the
        // pagination no longer splits on orientation. Two photos (target 1
        // page) land together.
        let photos = [photo("l", cluster: 0, orientation: .landscape),
                      photo("v", cluster: 0, orientation: .portrait)]
        #expect(Paginator.paginate(photos, preset: preset) == [0..<2])
    }

    @Test func coversAllPhotosContiguouslyWithinBounds() {
        for count in [1, 2, 5, 7, 13, 23, 60] {
            let ranges = Paginator.paginate(singletonClusters(count), preset: preset)
            var expectedStart = 0
            for range in ranges {
                #expect(range.lowerBound == expectedStart)
                #expect((1...Paginator.maxPhotosPerPage).contains(range.count), "page of \(range.count) photos")
                expectedStart = range.upperBound
            }
            #expect(expectedStart == count)
        }
    }

    @Test func emptyInputYieldsNoPages() {
        #expect(Paginator.paginate([], preset: preset).isEmpty)
    }

    @Test func singlePhotoIsOneHeroPage() {
        #expect(Paginator.paginate(singletonClusters(1), preset: preset) == [0..<1])
    }

    @Test func prefersSplittingAtClusterBoundary() {
        // Two 7-photo landscape clusters (14 total). The landscape cap (3)
        // forces several pages, but cohesion still keeps the cluster boundary
        // at index 7 intact: no page straddles it.
        let photos = (0..<7).map { photo("a\($0)", cluster: 0) }
            + (0..<7).map { photo("b\($0)", cluster: 1) }
        let ranges = Paginator.paginate(photos, preset: preset)
        for range in ranges {
            let crossesBoundary = range.lowerBound < 7 && range.upperBound > 7
            #expect(!crossesBoundary, "page \(range) straddles the cluster boundary at 7")
        }
        #expect(ranges.flatMap(Array.init) == Array(0..<14))   // full, contiguous
    }

    @Test func avoidsAdjacentPagesWithIdenticalCount() {
        // 6 singleton-cluster photos (all splits free). The same-count penalty
        // keeps no two adjacent pages at the same photo count.
        let ranges = Paginator.paginate(singletonClusters(6), preset: preset)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.count != b.count, "adjacent pages \(a) and \(b) share a count")
        }
    }

    @Test func pagesRespectTheAiryCap() {
        // 18 singleton-cluster photos. Every page stays within the airy cap;
        // the target (⌈18/2⌉ = 9) pulls page counts low.
        let ranges = Paginator.paginate(singletonClusters(18), preset: preset)
        #expect(ranges.allSatisfy { $0.count <= Paginator.maxPhotosPerPage })
        #expect(ranges.flatMap(Array.init) == Array(0..<18))
    }

    @Test func targetPageCountClampsToPhotoCountAndPresetMax() {
        // Airy target: ⌈n/2⌉, clamped by photoCount and the preset's maxPages.
        #expect(Paginator.targetPageCount(photoCount: 18, preset: preset) == 9)
        #expect(Paginator.targetPageCount(photoCount: 1, preset: preset) == 1)
        // 2 photos: ⌈2/2⌉ = 1.
        #expect(Paginator.targetPageCount(photoCount: 2, preset: preset) == 1)
        // 1000 photos: ⌈1000/2⌉ = 500 > maxPages 240 → clamp to 240.
        #expect(Paginator.targetPageCount(photoCount: 1000, preset: preset) == 240)
    }

    /// The photo cap is a hard limit the preset cannot override: nine
    /// single-cluster photos must split across pages of at most six even when
    /// the preset wants a single page.
    @Test func photoCapForcesSplitEvenWhenPresetWantsOnePage() {
        let singlePagePreset = PrintPreset(
            id: "test-single-page", displayName: "Single Page",
            trimSize: SizeInches(width: 8, height: 8),
            bleed: 0, safeMargin: 0,
            minPages: 1, maxPages: 1,
            spineBase: 0, spinePerPage: 0)
        let photos = (0..<9).map { photo("q\($0)", cluster: 0) }
        let ranges = Paginator.paginate(photos, preset: singlePagePreset)
        #expect(ranges.count > 1)                                       // cap forced a split
        #expect(ranges.allSatisfy { $0.count <= Paginator.maxPhotosPerPage })
        #expect(ranges.flatMap(Array.init) == Array(0..<9))
    }

    @Test func isDeterministic() {
        let photos = (0..<4).map { photo("a\($0)", cluster: 0) }
            + (0..<5).map { photo("b\($0)", cluster: 1) }
            + (0..<3).map { photo("c\($0)", cluster: 2) }
        let first = Paginator.paginate(photos, preset: preset)
        let second = Paginator.paginate(photos, preset: preset)
        #expect(first == second)
    }
}
