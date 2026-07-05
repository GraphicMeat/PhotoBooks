import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct JustifiedLayoutTests {
    private let content = NormRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    private let pageAspect = 1.25   // a 10×8 landscape page
    private let gutter = 0.02

    /// The core no-crop guarantee: every slot's on-page aspect equals the
    /// aspect of the photo it hosts, so aspect-fill shows the whole photo.
    @Test func slotAspectsMatchPhotoAspectsNoCrop() {
        let aspects = [1.5, 0.75, 1.0, 1.33]
        let boxes = JustifiedLayout.boxes(aspects: aspects, content: content,
                                          pageAspect: pageAspect, gutter: gutter)
        #expect(boxes.count == aspects.count)
        for (box, a) in zip(boxes, aspects) {
            #expect(abs(box.aspectRatio * pageAspect - a) < 1e-6,
                    "slot on-page aspect \(box.aspectRatio * pageAspect) != photo \(a)")
        }
    }

    @Test func boxesStayWithinContent() {
        let aspects = [1.5, 0.6, 2.0, 0.9, 1.1]
        let boxes = JustifiedLayout.boxes(aspects: aspects, content: content,
                                          pageAspect: pageAspect, gutter: gutter)
        for b in boxes {
            #expect(b.x >= content.x - 1e-6)
            #expect(b.y >= content.y - 1e-6)
            #expect(b.maxX <= content.maxX + 1e-6)
            #expect(b.maxY <= content.maxY + 1e-6)
        }
    }

    @Test func singleTallPhotoFitsWithoutCrop() {
        let boxes = JustifiedLayout.boxes(aspects: [0.5], content: content,
                                          pageAspect: pageAspect, gutter: gutter)
        #expect(boxes.count == 1)
        #expect(abs(boxes[0].aspectRatio * pageAspect - 0.5) < 1e-6)
        #expect(boxes[0].maxY <= content.maxY + 1e-6)   // contained to the page height
    }

    @Test func isDeterministic() {
        let aspects = [1.5, 0.75, 1.0, 1.33, 0.9, 1.6]
        let a = JustifiedLayout.boxes(aspects: aspects, content: content,
                                      pageAspect: pageAspect, gutter: gutter)
        let b = JustifiedLayout.boxes(aspects: aspects, content: content,
                                      pageAspect: pageAspect, gutter: gutter)
        #expect(a == b)
    }

    @Test func boxesDoNotOverlap() {
        let aspects = Array(repeating: 1.3, count: 5)
        let boxes = JustifiedLayout.boxes(aspects: aspects, content: content,
                                          pageAspect: pageAspect, gutter: gutter)
        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                let a = boxes[i], b = boxes[j]
                let overlap = a.x < b.maxX - 1e-9 && b.x < a.maxX - 1e-9
                    && a.y < b.maxY - 1e-9 && b.y < a.maxY - 1e-9
                #expect(!overlap, "boxes \(i) and \(j) overlap")
            }
        }
    }
}
