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
}
