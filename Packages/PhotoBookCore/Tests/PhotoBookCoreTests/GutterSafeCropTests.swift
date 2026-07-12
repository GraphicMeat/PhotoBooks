import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct GutterSafeCropTests {

    // Square pages → spreadAspect = 2. A full-canvas hero slot {0,0,1,1} then
    // has slotAspect = (1·2)/1 = 2.

    // MARK: - dead-center hero (worked example)

    /// Worked example — square-page full-canvas hero, photoAspect 4:
    ///   slotAspect  = (1·2)/1                = 2
    ///   cropW       = slotAspect/photoAspect = 2/4        = 0.5
    ///   defaultCropX= (1 − 0.5)/2                          = 0.25
    /// Salient dead-center (x = 0.5) projects to:
    ///   slotX = 0 + ((0.5 − 0.25)/0.5)·1     = 0.5        → in the [0.46,0.54] band.
    /// Tie at the gutter → escape via the LEFT edge (0.46):
    ///   cropX = 0.5 − 0.5·(0.46 − 0)/1       = 0.5 − 0.23 = 0.27
    /// Re-projecting with cropX = 0.27:
    ///   slotX = ((0.5 − 0.27)/0.5)·1         = 0.46        = left band edge. ✓
    @Test func deadCenterHeroShiftsProjectionToBandEdge() {
        let crop = GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5))
        let c = try! #require(crop)
        #expect(abs(c.width - 0.5) < 1e-9)
        #expect(c.height == 1)
        #expect(c.y == 0)
        #expect(abs(c.x - 0.27) < 1e-9)
        // Projection lands exactly on the left band edge.
        let slotX = (0.5 - c.x) / c.width
        #expect(abs(slotX - 0.46) < 1e-9)
    }

    // MARK: - nil / no-op paths

    @Test func nilSalientCenterReturnsNil() {
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2, salientCenter: nil) == nil)
    }

    @Test func nonStraddlingSlotReturnsNil() {
        // Wholly on the left page.
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 0.4, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5)) == nil)
        // Wholly on the right page.
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0.55, y: 0, width: 0.4, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test func photoNarrowerThanSlotHasNoSlackReturnsNil() {
        // photoAspect 1 < slotAspect 2 → cropW would be 2 (> 1): no horizontal
        // slack, nothing to shift.
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 1, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test func photoExactlyMatchingSlotAspectHasNoSlackReturnsNil() {
        // photoAspect == slotAspect → cropW == 1.
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 2, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test func salientAlreadyOutsideBandReturnsNil() {
        // cropW 0.5, defaultCropX 0.25. Salient at x = 0.9 projects to
        // slotX = ((0.9 − 0.25)/0.5) clamped, but 0.9 is inside window [0.25,0.75]?
        // No: 0.9 > 0.75 → invisible → clamped to slot right edge (1.0), far
        // outside the band.
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.9, y: 0.5)) == nil)
        // A visible salient that projects clear of the band (slotX ≈ 0.6).
        // salient.x = 0.25 + 0.6·0.5 = 0.55 → slotX = 0.6, outside [0.46,0.54].
        #expect(GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.55, y: 0.5)) == nil)
    }

    // MARK: - nearer-edge escape, both sides

    @Test func salientLeftOfGutterEscapesViaLeftEdge() {
        // projected 0.48 (left of center): salient.x = 0.25 + 0.48·0.5 = 0.49.
        let crop = GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.49, y: 0.5))
        let c = try! #require(crop)
        let slotX = (0.49 - c.x) / c.width
        #expect(abs(slotX - 0.46) < 1e-9)  // exits LEFT band edge
    }

    @Test func salientRightOfGutterEscapesViaRightEdge() {
        // projected 0.52 (right of center): salient.x = 0.25 + 0.52·0.5 = 0.51.
        let crop = GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.51, y: 0.5))
        let c = try! #require(crop)
        let slotX = (0.51 - c.x) / c.width
        #expect(abs(slotX - 0.54) < 1e-9)  // exits RIGHT band edge
    }

    // MARK: - clamp best-effort

    @Test func insufficientSlackClampsToWindowEdge() {
        // photoAspect 2.05, slotAspect 2 → cropW = 2/2.05 ≈ 0.97561,
        // valid range [0, 1 − cropW ≈ 0.02439]. Dead-center salient wants
        // cropX ≈ 0.0512 (> upper bound) to reach the left edge, so it clamps
        // to 1 − cropW — a valid, partially-improved crop.
        let crop = GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 2.05, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5))
        let c = try! #require(crop)
        let cropW = 2.0 / 2.05
        #expect(abs(c.width - cropW) < 1e-9)
        #expect(abs(c.x - (1 - cropW)) < 1e-9)  // clamped to upper bound
        #expect(c.x >= 0 && c.x <= 1 - c.width)
    }

    // MARK: - crop stays in [0,1] and slices complementarily

    @Test func shiftedCropStaysWithinUnitAndSlicesIntoComplementaryHalves() {
        let crop = GutterSafeCrop.crop(
            slotFrame: NormRect(x: 0, y: 0, width: 1, height: 1),
            photoAspect: 4, spreadAspect: 2,
            salientCenter: NormPoint(x: 0.5, y: 0.5))
        let c = try! #require(crop)
        #expect(c.x >= 0 && c.maxX <= 1 + 1e-12)

        // A full-canvas spread carrying the shifted crop still slices into two
        // contiguous, complementary half-crops (left tail meets right head).
        let spread = Spread(
            origin: .template(id: "spread-panorama"),
            photoSlots: [SpreadPhotoSlot(
                frame: NormRect(x: 0, y: 0, width: 1, height: 1),
                photoID: PhotoID(rawValue: "pano"), crop: c)])
        let (left, right) = spread.slice()
        let lc = left.photoSlots[0].crop
        let rc = right.photoSlots[0].crop
        #expect(abs(lc.x - c.x) < 1e-9)                 // left starts at crop start
        #expect(abs(lc.maxX - rc.x) < 1e-9)             // halves meet
        #expect(abs(rc.maxX - c.maxX) < 1e-9)           // right ends at crop end
        #expect(abs((lc.width + rc.width) - c.width) < 1e-9)
    }
}
