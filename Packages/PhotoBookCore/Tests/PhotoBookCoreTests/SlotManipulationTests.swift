import Foundation
import Testing
import PhotoBookCore

@Suite struct SlotManipulationTests {

    @Test func moveTranslatesWithoutResizing() {
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        let moved = SlotManipulation.move(frame, byNormDelta: 0.1, 0.05)
        #expect(abs(moved.x - 0.3) < 1e-12)
        #expect(abs(moved.y - 0.25) < 1e-12)
        #expect(abs(moved.width - 0.3) < 1e-12)
        #expect(abs(moved.height - 0.4) < 1e-12)
    }

    @Test func resizeKeepsAspectRatio() {
        // 0.4 x 0.2 → aspect 2.0. Drag bottom-right outward.
        let frame = NormRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .bottomRight,
                                          byNormDelta: 0.2, 0.0, minShortSide: 0.15)
        #expect(abs(out.width / out.height - 2.0) < 1e-9)   // aspect held
    }

    @Test func resizeAnchorsOppositeCorner() {
        // Dragging top-left must leave bottom-right (maxX, maxY) fixed.
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .topLeft,
                                          byNormDelta: -0.1, -0.05, minShortSide: 0.15)
        #expect(abs(out.maxX - frame.maxX) < 1e-9)
        #expect(abs(out.maxY - frame.maxY) < 1e-9)
        #expect(out.width > frame.width)   // grew
    }

    @Test func resizeClampsToMinShortSide() {
        // Shrink hard; short side must not drop below 0.15.
        let frame = NormRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .bottomRight,
                                          byNormDelta: -0.9, -0.9, minShortSide: 0.15)
        #expect(min(out.width, out.height) >= 0.15 - 1e-9)
        #expect(abs(out.width / out.height - 2.0) < 1e-9)   // aspect still held
    }

    @Test func resizeTopRightAnchorsBottomLeft() {
        // Dragging top-right must leave bottom-left (minX, maxY) fixed.
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .topRight,
                                          byNormDelta: 0.1, -0.05, minShortSide: 0.15)
        #expect(abs(out.x - frame.x) < 1e-9)          // left edge fixed
        #expect(abs(out.maxY - frame.maxY) < 1e-9)    // bottom edge fixed
        #expect(abs(out.width / out.height - 2.0) < 1e-9)
    }

    @Test func resizeBottomLeftAnchorsTopRight() {
        // Dragging bottom-left must leave top-right (maxX, minY) fixed.
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .bottomLeft,
                                          byNormDelta: -0.1, 0.05, minShortSide: 0.15)
        #expect(abs(out.maxX - frame.maxX) < 1e-9)    // right edge fixed
        #expect(abs(out.y - frame.y) < 1e-9)          // top edge fixed
        #expect(abs(out.width / out.height - 2.0) < 1e-9)
    }

    @Test func resizeReturnsFrameForDegenerateInput() {
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.0, height: 0.2)
        let out = SlotManipulation.resize(frame, corner: .bottomRight,
                                          byNormDelta: 0.3, 0.3, minShortSide: 0.15)
        #expect(out == frame)
    }

    // MARK: Free resize (text boxes — width & height independent)

    @Test func resizeFreeChangesWidthAndHeightIndependently() {
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)  // aspect 2.0
        // Drag bottom-right: +0.2 width, +0.0 height. Aspect must NOT be held.
        let out = SlotManipulation.resizeFree(frame, corner: .bottomRight,
                                              byNormDelta: 0.2, 0.0, minShortSide: 0.05)
        #expect(abs(out.width - 0.6) < 1e-9)
        #expect(abs(out.height - 0.2) < 1e-9)     // height unchanged (aspect NOT locked)
        #expect(abs(out.x - 0.2) < 1e-9)          // top-left anchor fixed
        #expect(abs(out.y - 0.2) < 1e-9)
    }

    @Test func resizeFreeAnchorsOppositeCornerForTopLeftDrag() {
        let frame = NormRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let out = SlotManipulation.resizeFree(frame, corner: .topLeft,
                                              byNormDelta: 0.1, 0.1, minShortSide: 0.05)
        #expect(abs(out.maxX - 0.7) < 1e-9)       // bottom-right stays fixed
        #expect(abs(out.maxY - 0.7) < 1e-9)
        #expect(abs(out.width - 0.3) < 1e-9)
        #expect(abs(out.height - 0.3) < 1e-9)
    }

    @Test func resizeFreeClampsEachSideToMinIndependently() {
        let frame = NormRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        // Collapse width past the min; height stays large.
        let out = SlotManipulation.resizeFree(frame, corner: .bottomRight,
                                              byNormDelta: -0.5, 0.0, minShortSide: 0.1)
        #expect(abs(out.width - 0.1) < 1e-9)      // width clamped to min
        #expect(abs(out.height - 0.4) < 1e-9)     // height untouched
    }
}
