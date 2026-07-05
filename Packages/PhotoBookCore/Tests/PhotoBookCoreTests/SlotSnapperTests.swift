import Foundation
import Testing
import PhotoBookCore

@Suite struct SlotSnapperTests {

    @Test func snapsLeftEdgeToPageMargin() {
        // Left edge at 0.02, margin at 0.05, threshold 0.04 → snaps right to 0.05.
        let frame = NormRect(x: 0.02, y: 0.3, width: 0.3, height: 0.3)
        let out = SlotSnapper.snap(frame, pageInsetX: 0.05, pageInsetY: 0.05, neighbors: [], threshold: 0.04)
        #expect(abs(out.x - 0.05) < 1e-9)
        #expect(abs(out.width - 0.3) < 1e-9)   // size unchanged (translate only)
    }

    @Test func snapsToNeighborRightEdge() {
        // Neighbor occupies x∈[0.1,0.4]; our left edge 0.42 snaps to 0.40.
        let neighbor = NormRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let frame = NormRect(x: 0.42, y: 0.5, width: 0.2, height: 0.2)
        let out = SlotSnapper.snap(frame, pageInsetX: 0.0, pageInsetY: 0.0, neighbors: [neighbor], threshold: 0.03)
        #expect(abs(out.x - 0.40) < 1e-9)
    }

    @Test func noSnapBeyondThreshold() {
        let frame = NormRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        let out = SlotSnapper.snap(frame, pageInsetX: 0.05, pageInsetY: 0.05, neighbors: [], threshold: 0.02)
        #expect(out == frame)   // nothing within threshold → unchanged
    }

    @Test func usesSeparateInsetsPerAxis() {
        // x near the x-margin (0.04), y far from the y-margin.
        let frame = NormRect(x: 0.04, y: 0.5, width: 0.2, height: 0.2)
        let out = SlotSnapper.snap(frame, pageInsetX: 0.05, pageInsetY: 0.10,
                                   neighbors: [], threshold: 0.02)
        #expect(abs(out.x - 0.05) < 1e-9)   // x snapped to x-inset
        #expect(abs(out.y - 0.5) < 1e-9)    // y unchanged (0.10 line is 0.40 away > threshold)
    }
}
