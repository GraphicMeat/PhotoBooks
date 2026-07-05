import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct SequencerTests {

    private func photo(_ id: String, cluster: Int) -> AnalyzedPhoto {
        AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: 4000, pixelHeight: 3000),
            orientation: .landscape, clusterIndex: cluster)
    }

    @Test func clusterRangesGroupContiguousRuns() {
        let sequencer = Sequencer(photos: [
            photo("a", cluster: 0), photo("b", cluster: 0),
            photo("c", cluster: 1),
            photo("d", cluster: 2), photo("e", cluster: 2), photo("f", cluster: 2)
        ])
        #expect(sequencer.clusterRanges == [0..<2, 2..<3, 3..<6])
    }

    @Test func singleClusterIsOneRange() {
        let sequencer = Sequencer(photos: [photo("a", cluster: 0), photo("b", cluster: 0)])
        #expect(sequencer.clusterRanges == [0..<2])
    }

    @Test func emptyInputHasNoRanges() {
        #expect(Sequencer(photos: []).clusterRanges.isEmpty)
    }

    @Test func boundaryDetection() {
        let sequencer = Sequencer(photos: [
            photo("a", cluster: 0), photo("b", cluster: 0), photo("c", cluster: 1)
        ])
        #expect(sequencer.isClusterBoundary(0))     // sequence edge
        #expect(!sequencer.isClusterBoundary(1))    // inside cluster 0
        #expect(sequencer.isClusterBoundary(2))     // 0 → 1 boundary
        #expect(sequencer.isClusterBoundary(3))     // sequence edge
    }
}
