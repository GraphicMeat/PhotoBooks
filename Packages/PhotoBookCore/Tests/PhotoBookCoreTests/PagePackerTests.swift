import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PagePackerTests {
    private func photo(_ id: String, cluster: Int, weight: Int = 1,
                       orientation: Orientation = .landscape, aspect: Double = 1.333) -> AnalyzedPhoto {
        let w = 4000, h = Int(Double(w) / aspect)
        return AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: w, pixelHeight: h),
            orientation: orientation, clusterIndex: cluster, weight: weight)
    }
    private let byCount: ([AnalyzedPhoto]) -> Double = { $0.count >= 4 ? 0.85 : 0.4 }

    @Test func growsToTargetThenStarts() {
        let photos = (0..<8).map { photo("p\($0)", cluster: 0) }
        #expect(PagePacker.pack(photos: photos, coverage: byCount) == [[0, 1, 2, 3], [4, 5, 6, 7]])
    }

    @Test func capsAtEight() {
        let photos = (0..<10).map { photo("p\($0)", cluster: 0) }
        #expect(PagePacker.pack(photos: photos) { _ in 0.1 }.first?.count == 8)
    }

    @Test func bestFillPicksByOrientation() {
        let photos = [photo("a", cluster: 0, orientation: .landscape),
                      photo("b", cluster: 0, orientation: .landscape),
                      photo("c", cluster: 0, orientation: .portrait, aspect: 0.75)]
        let cov: ([AnalyzedPhoto]) -> Double = { $0.contains { $0.orientation == .portrait } ? 0.9 : 0.3 }
        // Best-fill pulls the portrait (index 2) ahead of the landscape (index 1);
        // the min-fill of 3 then takes the last photo too → order [0, 2, 1].
        #expect(PagePacker.pack(photos: photos, coverage: cov).first == [0, 2, 1])
    }

    /// A normal page never stops at 1–2 photos just because a single photo
    /// aspect-fills the page: min-fill groups them (heroes stay solo, tested above).
    @Test func minFillGroupsNormalPages() {
        let photos = (0..<6).map { photo("p\($0)", cluster: 0) }
        let groups = PagePacker.pack(photos: photos) { _ in 0.95 }   // 1 photo already "full"
        #expect(groups.allSatisfy { $0.count >= 3 })
        #expect(groups == [[0, 1, 2], [3, 4, 5]])
    }

    /// An event whose tail would be a lonely sub-min page is absorbed instead:
    /// 4 photos → one page of 4, not 3 + a lonely 1.
    @Test func absorbsSubMinEventTail() {
        let photos = (0..<4).map { photo("p\($0)", cluster: 0) }
        let groups = PagePacker.pack(photos: photos) { $0.count >= 3 ? 0.85 : 0.4 }
        #expect(groups == [[0, 1, 2, 3]])
    }

    @Test func heroIsAlwaysSolo() {
        let photos = [photo("a", cluster: 0), photo("hero", cluster: 0, weight: 6),
                      photo("b", cluster: 0), photo("c", cluster: 0)]
        let groups = PagePacker.pack(photos: photos) { _ in 0.1 }
        #expect(groups.contains([1]))
        #expect(groups.allSatisfy { $0 == [1] || !$0.contains(1) })
    }

    @Test func panoramaIsAlwaysSolo() {
        let photos = [photo("a", cluster: 0), photo("pano", cluster: 0, aspect: 3.0),
                      photo("b", cluster: 0)]
        #expect(PagePacker.pack(photos: photos) { _ in 0.1 }.contains([1]))
    }

    @Test func crossesEventToFillVoidUnderTarget() {
        let photos = (0..<2).map { photo("a\($0)", cluster: 0) }
                   + (0..<2).map { photo("b\($0)", cluster: 1) }
        // Page covered ≥ target (0.85): stays within its event (no cross).
        #expect(PagePacker.pack(photos: photos) { _ in 0.85 }.first == [0, 1])
        // Page under target (0.6): exhausts event 0, then crosses into event 1
        // to fill the void.
        #expect((PagePacker.pack(photos: photos) { _ in 0.6 }.first?.count ?? 0) > 2)
    }

    @Test func isDeterministic() {
        let photos = (0..<8).map { photo("p\($0)", cluster: 0) }
        #expect(PagePacker.pack(photos: photos, coverage: byCount)
                == PagePacker.pack(photos: photos, coverage: byCount))
    }

    @Test func emptyReturnsEmpty() {
        #expect(PagePacker.pack(photos: []) { _ in 0 }.isEmpty)
    }
}
