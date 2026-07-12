import Foundation
import Testing
import PhotoBookCore

@Suite struct SpreadTemplateProviderTests {

    @Test func allBundledSpreadTemplatesDecode() {
        // Forcing the bundled load — a decode failure fatalErrors at build/load,
        // so reaching here with a non-empty set proves every template decoded.
        let provider = SpreadTemplateProvider()
        #expect(!provider.allTemplates.isEmpty)
    }

    @Test func panoramaOfferedForCountOne() {
        let provider = SpreadTemplateProvider()
        let templates = provider.templates(forPhotoCount: 1)
        #expect(!templates.isEmpty)
        #expect(templates.contains { template in
            if case .template(let id) = template.origin { return id == "spread-panorama" }
            return false
        })
        // The panorama blueprint has exactly one full-canvas photo slot.
        let pano = templates.first { template in
            if case .template(let id) = template.origin { return id == "spread-panorama" }
            return false
        }!
        #expect(pano.photoSlots.count == 1)
        #expect(pano.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pano.photoSlots[0].photoID == nil)   // blueprint: no photo bound yet
    }

    @Test func twoUpOfferedForCountTwo() {
        let provider = SpreadTemplateProvider()
        let templates = provider.templates(forPhotoCount: 2)
        #expect(templates.contains { template in
            if case .template(let id) = template.origin { return id == "spread-two-up" }
            return false
        })
        let twoUp = templates.first { template in
            if case .template(let id) = template.origin { return id == "spread-two-up" }
            return false
        }!
        #expect(twoUp.photoSlots.count == 2)
        // One slot on the left page (frame center x < 0.5), one on the right.
        let centers = twoUp.photoSlots.map { $0.frame.x + $0.frame.width / 2 }
        #expect(centers.contains { $0 < 0.5 })
        #expect(centers.contains { $0 > 0.5 })
    }

    @Test func templatesMatchRequestedPhotoCount() {
        let provider = SpreadTemplateProvider()
        for count in 1...3 {
            for template in provider.templates(forPhotoCount: count) {
                #expect(template.photoSlots.count == count)
            }
        }
    }

    @Test func templateOrderIsDeterministic() {
        let provider = SpreadTemplateProvider()
        func ids(_ count: Int) -> [String] {
            provider.templates(forPhotoCount: count).compactMap { template in
                if case .template(let id) = template.origin { return id }
                return nil
            }
        }
        #expect(ids(3) == ids(3))
        #expect(ids(1) == ids(1))
    }

    @Test func bundledIncludesThreeUpAndHeroStrip() {
        let provider = SpreadTemplateProvider()
        let allIDs = provider.allTemplates.compactMap { template -> String? in
            if case .template(let id) = template.origin { return id }
            return nil
        }
        #expect(allIDs.contains("spread-three-up"))
        #expect(allIDs.contains("spread-hero-strip"))
    }

    // MARK: - New templates (Task B1)

    private func templateNamed(_ id: String, count: Int, _ provider: SpreadTemplateProvider) -> Spread? {
        provider.templates(forPhotoCount: count).first { template in
            if case .template(let templateID) = template.origin { return templateID == id }
            return false
        }
    }

    @Test func fullCanvasSpreadOfferedForCountOne() {
        let provider = SpreadTemplateProvider()
        let hero = templateNamed("spread-panorama", count: 1, provider)
        #expect(hero != nil)
        #expect(hero?.photoSlots.count == 1)
        #expect(hero?.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Geometry helpers (real tiling checks, not just counts)

    private func area(_ rect: NormRect) -> Double { rect.width * rect.height }

    private func intersectionArea(_ a: NormRect, _ b: NormRect) -> Double {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.x, b.x))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.y, b.y))
        return ix * iy
    }

    /// Frames must tile the double-wide canvas: total area ≈ 1.0 and no pair
    /// overlaps beyond float slop.
    private func assertTiles(_ frames: [NormRect], sourceLocation: SourceLocation = #_sourceLocation) {
        let totalArea = frames.reduce(0) { $0 + area($1) }
        #expect(abs(totalArea - 1.0) < 0.01, "total area \(totalArea)", sourceLocation: sourceLocation)
        for i in frames.indices {
            for j in frames.indices where j > i {
                let overlap = intersectionArea(frames[i], frames[j])
                #expect(overlap < 0.001, "overlap \(overlap) between frame \(i) and \(j)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test func newTemplatesTileTheCanvas() {
        let provider = SpreadTemplateProvider()
        let cases: [(id: String, count: Int)] = [
            ("spread-panorama", 1),
            ("spread-center-columns-3", 3),
            ("spread-center-columns-5", 5),
            ("spread-split-two-thirds", 2),
            ("spread-split-two-thirds-3", 3),
            ("spread-panorama-band-3", 3),
        ]
        for (id, count) in cases {
            guard let template = templateNamed(id, count: count, provider) else {
                Issue.record("missing template \(id)")
                continue
            }
            #expect(template.photoSlots.count == count)
            assertTiles(template.photoSlots.map(\.frame))
        }
    }

    @Test func centerColumnsPutsCenterFrameFirst() {
        let provider = SpreadTemplateProvider()
        let three = templateNamed("spread-center-columns-3", count: 3, provider)!
        #expect(three.photoSlots[0].frame == NormRect(x: 0.30, y: 0, width: 0.40, height: 1))

        let five = templateNamed("spread-center-columns-5", count: 5, provider)!
        #expect(five.photoSlots[0].frame == NormRect(x: 0.30, y: 0, width: 0.40, height: 1))
    }

    @Test func splitTwoThirdsPutsBigFrameFirst() {
        let provider = SpreadTemplateProvider()
        let two = templateNamed("spread-split-two-thirds", count: 2, provider)!
        #expect(two.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 0.667, height: 1))

        let three = templateNamed("spread-split-two-thirds-3", count: 3, provider)!
        #expect(three.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 0.667, height: 1))
    }

    @Test func panoramaBandPutsBandFrameFirst() {
        let provider = SpreadTemplateProvider()
        let band = templateNamed("spread-panorama-band-3", count: 3, provider)!
        #expect(band.photoSlots[0].frame == NormRect(x: 0, y: 0.25, width: 1, height: 0.5))
    }

    /// `spread-panorama`'s single slot straddles the gutter (x:0 w:1 spans both
    /// pages). `slice()` must split it into complementary left/right crops
    /// whose widths sum back to the full source crop.
    @Test func heroFullSliceProducesComplementaryHalfCrops() {
        let provider = SpreadTemplateProvider()
        let hero = templateNamed("spread-panorama", count: 1, provider)!
        let (left, right) = hero.slice()
        #expect(left.photoSlots.count == 1)
        #expect(right.photoSlots.count == 1)
        let leftCrop = left.photoSlots[0].crop
        let rightCrop = right.photoSlots[0].crop
        #expect(abs(leftCrop.width + rightCrop.width - 1.0) < 1e-9)
        #expect(abs(leftCrop.x - 0) < 1e-9)
        #expect(abs(rightCrop.x + rightCrop.width - 1.0) < 1e-9)
        // Each sliced half fills its own page (frame spans full 0-1 on that page).
        #expect(left.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 1, height: 1))
        #expect(right.photoSlots[0].frame == NormRect(x: 0, y: 0, width: 1, height: 1))
    }
}
