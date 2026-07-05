import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct GridLayoutTests {
    private let content = NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    private let gutter = 0.02

    @Test func sixInTwoColumnsIsThreeEqualRows() {
        let boxes = GridLayout.boxes(count: 6, content: content, gutter: gutter, columns: 2)
        #expect(boxes.count == 6)
        let w0 = boxes[0].width, h0 = boxes[0].height
        for b in boxes {
            #expect(abs(b.width - w0) < 1e-9)
            #expect(abs(b.height - h0) < 1e-9)
        }
        #expect(Set(boxes.map { ($0.x * 1000).rounded() }).count == 2)
        #expect(Set(boxes.map { ($0.y * 1000).rounded() }).count == 3)
    }

    /// Odd count: the partial last row widens to fill the page (no empty gap).
    @Test func fiveInTwoColumnsWidensLastRow() {
        let boxes = GridLayout.boxes(count: 5, content: content, gutter: gutter, columns: 2)
        #expect(boxes.count == 5)
        let last = boxes[4]
        #expect(abs(last.width - content.width) < 1e-6)
        #expect(abs(last.x - content.x) < 1e-6)
    }

    @Test func boxesStayWithinContent() {
        let boxes = GridLayout.boxes(count: 7, content: content, gutter: gutter, columns: 3)
        #expect(boxes.count == 7)
        for b in boxes {
            #expect(b.x >= content.x - 1e-6)
            #expect(b.y >= content.y - 1e-6)
            #expect(b.maxX <= content.maxX + 1e-6)
            #expect(b.maxY <= content.maxY + 1e-6)
        }
    }

    @Test func isDeterministicAndEmpty() {
        #expect(GridLayout.boxes(count: 4, content: content, gutter: gutter, columns: 2)
                == GridLayout.boxes(count: 4, content: content, gutter: gutter, columns: 2))
        #expect(GridLayout.boxes(count: 0, content: content, gutter: gutter, columns: 2).isEmpty)
    }
}
