import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct JustifiedSpreadLayoutTests {
    // A 10×8 landscape page → spread canvas is twice as wide.
    private let pageAspect = 1.25
    private var spreadAspect: Double { 2 * pageAspect }   // double-wide canvas
    private let content = NormRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92)
    private let gutter = 0.02

    /// The core no-crop guarantee on the double-wide canvas: every box's true
    /// on-canvas aspect equals its photo's aspect, so `.full` shows the whole photo.
    @Test func slotAspectsMatchPhotoAspectsNoCrop() {
        let aspects = [1.5, 0.75, 1.0, 1.33, 3.0]
        let boxes = JustifiedSpreadLayout.boxes(
            aspects: aspects, content: content,
            spreadAspect: spreadAspect, gutter: gutter)
        #expect(boxes.count == aspects.count)
        for (box, a) in zip(boxes, aspects) {
            #expect(abs(box.aspectRatio * spreadAspect - a) < 1e-6,
                    "box on-canvas aspect \(box.aspectRatio * spreadAspect) != photo \(a)")
        }
    }

    @Test func boxesStayWithinContent() {
        let aspects = [1.5, 0.6, 2.0, 0.9, 1.1, 1.4]
        let boxes = JustifiedSpreadLayout.boxes(
            aspects: aspects, content: content,
            spreadAspect: spreadAspect, gutter: gutter)
        for b in boxes {
            #expect(b.x >= content.x - 1e-6)
            #expect(b.y >= content.y - 1e-6)
            #expect(b.maxX <= content.maxX + 1e-6)
            #expect(b.maxY <= content.maxY + 1e-6)
        }
    }

    /// A lone ultra-wide panorama: one box, sized to the pano aspect, no crop.
    @Test func lonePanoramaFillsWithoutCrop() {
        let boxes = JustifiedSpreadLayout.boxes(
            aspects: [3.0], content: content,
            spreadAspect: spreadAspect, gutter: gutter)
        #expect(boxes.count == 1)
        #expect(abs(boxes[0].aspectRatio * spreadAspect - 3.0) < 1e-6)
        #expect(boxes[0].maxX <= content.maxX + 1e-6)
    }

    @Test func isDeterministic() {
        let aspects = [1.5, 0.75, 1.0, 1.33, 0.9, 1.6]
        let a = JustifiedSpreadLayout.boxes(aspects: aspects, content: content,
                                            spreadAspect: spreadAspect, gutter: gutter)
        let b = JustifiedSpreadLayout.boxes(aspects: aspects, content: content,
                                            spreadAspect: spreadAspect, gutter: gutter)
        #expect(a == b)
    }

    @Test func emptyAspectsReturnsEmpty() {
        let boxes = JustifiedSpreadLayout.boxes(aspects: [], content: content,
                                                spreadAspect: spreadAspect, gutter: gutter)
        #expect(boxes.isEmpty)
    }
}
