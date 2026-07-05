import CoreGraphics
import Foundation
import PhotoBookCore
import Testing
@testable import PhotoBookRender

@Suite struct SlotGeometryTests {

    // MARK: rect(for:in:)

    @Test func rectMapsNormalizedFrameIntoRenderSize() {
        let rect = SlotGeometry.rect(for: NormRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
                                     in: CGSize(width: 600, height: 400))
        #expect(rect == CGRect(x: 60, y: 80, width: 300, height: 100))
    }

    @Test func fullFrameFillsRenderSize() {
        let rect = SlotGeometry.rect(for: .full, in: CGSize(width: 600, height: 600))
        #expect(rect == CGRect(x: 0, y: 0, width: 600, height: 600))
    }

    // MARK: imageDrawRect(slotRect:crop:pixelWidth:pixelHeight:)

    @Test func fullCropOnSquareImageInWideSlotAspectFills() {
        // 400×400 image, .full crop, 200×100 slot at origin: scale =
        // max(200/400, 100/400) = 0.5 → drawn 200×200, vertically centered
        // excess clipped: origin y = 50 − 100 = −50.
        let drawRect = SlotGeometry.imageDrawRect(
            slotRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            crop: .full, pixelWidth: 400, pixelHeight: 400)
        #expect(drawRect == CGRect(x: 0, y: -50, width: 200, height: 200))
    }

    @Test func matchingAspectCropFillsSlotExactly() {
        // 800×400 image, crop = center half (x 0.25, w 0.5, full height) →
        // crop pixels 400×400; slot 100×100 at (50, 25): scale 0.25, drawn
        // size 200×100, crop center (400,200)·0.25 = (100,50) pinned to slot
        // center (100,75) → origin (0, 25).
        let drawRect = SlotGeometry.imageDrawRect(
            slotRect: CGRect(x: 50, y: 25, width: 100, height: 100),
            crop: NormRect(x: 0.25, y: 0, width: 0.5, height: 1),
            pixelWidth: 800, pixelHeight: 400)
        #expect(drawRect == CGRect(x: 0, y: 25, width: 200, height: 100))
    }

    @Test func cropRegionLandsExactlyOnSlot() {
        // Property spelled out on one concrete case: the crop region's
        // corners, mapped through the returned rect, land on the slot.
        let slot = CGRect(x: 30, y: 40, width: 120, height: 90)
        let crop = NormRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        let drawRect = SlotGeometry.imageDrawRect(slotRect: slot, crop: crop,
                                                  pixelWidth: 1000, pixelHeight: 1000)
        // crop aspect (400×300 px) == slot aspect (120×90) → exact fill.
        let scaleX = drawRect.width / 1000
        let cropMinX = drawRect.minX + crop.x * 1000 * scaleX
        let cropMinY = drawRect.minY + crop.y * 1000 * (drawRect.height / 1000)
        #expect(abs(cropMinX - slot.minX) < 1e-9)
        #expect(abs(cropMinY - slot.minY) < 1e-9)
        #expect(abs(crop.width * 1000 * scaleX - slot.width) < 1e-9)
    }

    @Test func degenerateCropFallsBackToSlotRect() {
        let slot = CGRect(x: 0, y: 0, width: 100, height: 100)
        let drawRect = SlotGeometry.imageDrawRect(
            slotRect: slot, crop: NormRect(x: 0, y: 0, width: 0, height: 0),
            pixelWidth: 100, pixelHeight: 100)
        #expect(drawRect == slot)
    }

    // MARK: fontPoints(factor:renderHeight:)

    @Test func fontPointsScaleWithRenderHeight() {
        #expect(SlotGeometry.fontPoints(factor: 0.05, renderHeight: 600) == 30)
        #expect(SlotGeometry.fontPoints(factor: 0.05, renderHeight: 3600) == 180)
        #expect(SlotGeometry.fontPoints(factor: 0, renderHeight: 600) == 0)
    }

    // MARK: cornerRadius(style:in:)

    @Test func cornerRadiusUsesMinDimension() {
        var style = BookStyle.standard
        style.cornerRadius = 0.02
        #expect(SlotGeometry.cornerRadius(style: style, in: CGSize(width: 600, height: 400)) == 8)
        #expect(SlotGeometry.cornerRadius(style: BookStyle.standard,
                                          in: CGSize(width: 600, height: 400)) == 0)
    }

    // MARK: thumbnailPixelSize(for:)

    @Test func thumbnailPixelSizeBucketsUpward() {
        // 100 pt longest side → 200 px retina → bucket 256.
        #expect(SlotGeometry.thumbnailPixelSize(for: CGSize(width: 100, height: 50)) == 256)
        // 129 pt → 258 px → bucket 512.
        #expect(SlotGeometry.thumbnailPixelSize(for: CGSize(width: 129, height: 50)) == 512)
        // 256 pt → 512 px → bucket 512 (exact boundary stays).
        #expect(SlotGeometry.thumbnailPixelSize(for: CGSize(width: 256, height: 256)) == 512)
        // Degenerate zero size still returns a sane floor.
        #expect(SlotGeometry.thumbnailPixelSize(for: .zero) == 256)
    }
}
