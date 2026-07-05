import CoreGraphics
import Foundation
import PhotoBookCore
import Testing
@testable import EditCore

@Suite struct EditMathTests {

    // MARK: defaultCrop golden values

    @Test func widePhotoIntoSquareSlotCropsSidesEqually() {
        // photoAspect 1.5 into slotAspect 1.0: width = 1/1.5 = 2/3,
        // x = (1 − 2/3)/2 = 1/6, full height.
        let crop = defaultCrop(photoAspect: 1.5, slotAspect: 1.0)
        #expect(abs(crop.x - 1.0 / 6.0) < 1e-12)
        #expect(crop.y == 0)
        #expect(abs(crop.width - 2.0 / 3.0) < 1e-12)
        #expect(crop.height == 1)
    }

    @Test func tallPhotoIntoWideSlotCropsTopAndBottom() {
        // photoAspect 1.0 into slotAspect 2.0: height = 1/2, y = 1/4, full width.
        let crop = defaultCrop(photoAspect: 1.0, slotAspect: 2.0)
        #expect(crop == NormRect(x: 0, y: 0.25, width: 1, height: 0.5))
    }

    @Test func matchingAspectsCropFull() {
        #expect(defaultCrop(photoAspect: 1.5, slotAspect: 1.5) == .full)
    }

    @Test func degenerateAspectsFallBackToFull() {
        #expect(defaultCrop(photoAspect: 0, slotAspect: 1) == .full)
        #expect(defaultCrop(photoAspect: 1, slotAspect: 0) == .full)
        #expect(defaultCrop(photoAspect: -2, slotAspect: 1) == .full)
    }

    @Test func cropPixelAspectAlwaysMatchesSlot() {
        // Property spelled out on concrete pairs: (crop.w·W)/(crop.h·H) == slotAspect.
        for (photoAspect, slotAspect) in [(1.5, 1.0), (0.75, 1.33), (3.2, 0.5), (1.0, 1.0)] {
            let crop = defaultCrop(photoAspect: photoAspect, slotAspect: slotAspect)
            let pixelAspect = (crop.width / crop.height) * photoAspect
            #expect(abs(pixelAspect - slotAspect) < 1e-9, "\(photoAspect) into \(slotAspect)")
        }
    }

    // MARK: trueSlotAspect

    @Test func trueSlotAspectCorrectsForPageAspect() {
        // Half-width full-height slot on a 10×8 landscape page:
        // (0.5·10)/(1.0·8) = 0.625.
        let aspect = trueSlotAspect(of: NormRect(x: 0, y: 0, width: 0.5, height: 1),
                                    pageSize: SizeInches(width: 10, height: 8))
        #expect(abs(aspect - 0.625) < 1e-12)
        // On a square page the frame's own ratio is the true aspect.
        let square = trueSlotAspect(of: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4),
                                    pageSize: SizeInches(width: 7, height: 7))
        #expect(abs(square - 2.0) < 1e-12)
    }

    // MARK: adjustedCrop golden values
    // Base case: 2:1 photo in a square slot → centered crop (0.25, 0, 0.5, 1),
    // ratio = slotAspect/photoAspect = 0.5, 300×300 pt editor view.

    private let base = NormRect(x: 0.25, y: 0, width: 0.5, height: 1)
    private let view = CGSize(width: 300, height: 300)

    @Test func panRightByHalfSlotWidthMovesWindowLeft() {
        // Pan +150 pt of a 300 pt view = half the visible window = 0.25 in
        // crop space; window moves LEFT: x = 0.25 − 0.25 = 0.
        let crop = adjustedCrop(base: base, translation: CGSize(width: 150, height: 0),
                                zoomDelta: 1, photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(crop == NormRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func zoomTwoXCenteredHalvesTheWindow() {
        // height 1 → 0.5, width 0.5 → 0.25, center (0.5, 0.5) preserved.
        let crop = adjustedCrop(base: base, translation: .zero, zoomDelta: 2,
                                photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(crop == NormRect(x: 0.375, y: 0.25, width: 0.25, height: 0.5))
    }

    @Test func panClampsAtPhotoEdges() {
        // Huge pan left → window pushed right, clamps at x = 1 − width = 0.5.
        let left = adjustedCrop(base: base, translation: CGSize(width: -10000, height: 0),
                                zoomDelta: 1, photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(left == NormRect(x: 0.5, y: 0, width: 0.5, height: 1))
        // Huge pan right → clamps at x = 0.
        let right = adjustedCrop(base: base, translation: CGSize(width: 10000, height: 0),
                                 zoomDelta: 1, photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(right == NormRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func zoomOutClampsAtAspectFill() {
        // zoomDelta 0.5 would need height 2 — clamps back to the full-fit
        // window, recentered on the base center.
        let crop = adjustedCrop(base: base, translation: .zero, zoomDelta: 0.5,
                                photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(crop == base)
    }

    @Test func zoomInClampsAtEightX() {
        // zoomDelta 100 clamps the window at maxHeight/8 = 1/8.
        let crop = adjustedCrop(base: base, translation: .zero, zoomDelta: 100,
                                photoAspect: 2, slotAspect: 1, viewSize: view)
        #expect(abs(crop.height - 0.125) < 1e-12)
        #expect(abs(crop.width - 0.0625) < 1e-12)
        // Still centered on the base center.
        #expect(abs((crop.x + crop.width / 2) - 0.5) < 1e-12)
    }

    @Test func identityGestureOnFullCropEqualsCenteredCrop() {
        // The engine's default `.full` crop normalizes to the centered
        // aspect-fill crop on the first (identity) adjustment.
        let normalized = adjustedCrop(base: .full, translation: .zero, zoomDelta: 1,
                                      photoAspect: 1.5, slotAspect: 1, viewSize: view)
        #expect(normalized == defaultCrop(photoAspect: 1.5, slotAspect: 1))
    }

    @Test func panDownAfterZoomMovesWindowUp() {
        // Square photo, square slot: zoom 2 → (0.25, 0.25, 0.5, 0.5); then
        // pan down 150/300 pt = half the window = 0.25 → y = 0.25 − 0.25 = 0.
        let zoomed = adjustedCrop(base: .full, translation: .zero, zoomDelta: 2,
                                  photoAspect: 1, slotAspect: 1, viewSize: view)
        #expect(zoomed == NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let panned = adjustedCrop(base: zoomed, translation: CGSize(width: 0, height: 150),
                                  zoomDelta: 1, photoAspect: 1, slotAspect: 1, viewSize: view)
        #expect(panned == NormRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
    }

    // MARK: text size conversion

    @Test func pointSizeConversionGoldenValues() {
        // 7×7 in book: 7 in · 72 = 504 pt page height; factor 0.05 → 25.2 pt.
        #expect(abs(displayPoints(pointSizeFactor: 0.05, trimHeightInches: 7) - 25.2) < 1e-12)
        #expect(abs(pointSizeFactor(displayPoints: 25.2, trimHeightInches: 7) - 0.05) < 1e-12)
        // 8 in tall book: factor 0.05 → 28.8 pt.
        #expect(abs(displayPoints(pointSizeFactor: 0.05, trimHeightInches: 8) - 28.8) < 1e-12)
    }

    @Test func pointSizeConversionRoundTrips() {
        for points in [9.0, 12.0, 25.2, 96.0] {
            let factor = pointSizeFactor(displayPoints: points, trimHeightInches: 7)
            #expect(abs(displayPoints(pointSizeFactor: factor, trimHeightInches: 7) - points) < 1e-9)
        }
    }
}
