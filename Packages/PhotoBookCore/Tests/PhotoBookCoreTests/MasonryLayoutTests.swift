import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct MasonryLayoutTests {
    private let pageAspect = 1.25
    private let content = NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    private let gutter = 0.02

    /// Zero-crop: every box's on-page true aspect equals its photo's aspect.
    @Test func boxesAreZeroCrop() {
        let aspects = [1.5, 0.75, 1.0, 1.33, 0.9, 1.6]
        let boxes = MasonryLayout.boxes(aspects: aspects, content: content,
                                        pageAspect: pageAspect, gutter: gutter, columns: 2)
        #expect(boxes.count == aspects.count)
        for (b, a) in zip(boxes, aspects) {
            #expect(abs(b.aspectRatio * pageAspect - a) < 1e-6,
                    "box true aspect \(b.aspectRatio * pageAspect) != photo \(a)")
        }
    }

    @Test func boxesStayWithinContent() {
        let aspects = [1.5, 0.6, 2.0, 0.9, 1.1, 1.4, 0.8]
        let boxes = MasonryLayout.boxes(aspects: aspects, content: content,
                                        pageAspect: pageAspect, gutter: gutter, columns: 3)
        for b in boxes {
            #expect(b.x >= content.x - 1e-6)
            #expect(b.y >= content.y - 1e-6)
            #expect(b.maxX <= content.maxX + 1e-6)
            #expect(b.maxY <= content.maxY + 1e-6)
        }
    }

    /// Photos land in exactly `columns` distinct x positions, balanced in count.
    @Test func photosBalanceAcrossColumns() {
        let aspects = Array(repeating: 1.0, count: 6)   // equal → perfectly balanced
        let boxes = MasonryLayout.boxes(aspects: aspects, content: content,
                                        pageAspect: pageAspect, gutter: gutter, columns: 2)
        let xs = boxes.map { ($0.x * 1000).rounded() }
        let distinct = Set(xs)
        #expect(distinct.count == 2)                    // two columns
        let counts = distinct.map { x in xs.filter { $0 == x }.count }
        #expect(counts.max()! - counts.min()! <= 1)     // balanced
    }

    @Test func isDeterministic() {
        let aspects = [1.5, 0.75, 1.0, 1.33, 0.9]
        let a = MasonryLayout.boxes(aspects: aspects, content: content, pageAspect: pageAspect, gutter: gutter, columns: 2)
        let b = MasonryLayout.boxes(aspects: aspects, content: content, pageAspect: pageAspect, gutter: gutter, columns: 2)
        #expect(a == b)
    }

    @Test func emptyReturnsEmpty() {
        #expect(MasonryLayout.boxes(aspects: [], content: content, pageAspect: pageAspect, gutter: gutter, columns: 2).isEmpty)
    }
}
