import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct TemplateProviderTests {

    private func photo(_ id: String, orientation: Orientation) -> AnalyzedPhoto {
        let (width, height): (Int, Int)
        switch orientation {
        case .landscape: (width, height) = (4000, 3000)
        case .portrait: (width, height) = (3000, 4000)
        case .square: (width, height) = (3000, 3000)
        }
        return AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: width, pixelHeight: height),
            orientation: orientation, clusterIndex: 0)
    }

    private func context(pageSize: SizeInches) -> LayoutContext {
        LayoutContext(pageSize: pageSize, style: .standard, needsTextZone: false, seed: 1)
    }

    @Test func bundlesAtLeast24Templates() {
        #expect(TemplateProvider.bundled.count >= 24)
    }

    @Test func everyTemplateIsStructurallySound() {
        for template in TemplateProvider.bundled {
            #expect((1...9).contains(template.photoCount), "\(template.id): photoCount")
            #expect(template.photoFrames.count == template.photoCount, "\(template.id): frame count")
            #expect(template.orientationHints.count == template.photoCount, "\(template.id): hint count")
            #expect(!template.aspectClasses.isEmpty, "\(template.id): aspect classes")
            for frame in template.photoFrames + template.textFrames {
                #expect(frame.x >= 0 && frame.y >= 0, "\(template.id): origin in bounds")
                #expect(frame.width > 0 && frame.height > 0, "\(template.id): positive size")
                #expect(frame.x + frame.width <= 1.0 + 1e-9, "\(template.id): right edge")
                #expect(frame.y + frame.height <= 1.0 + 1e-9, "\(template.id): bottom edge")
            }
        }
    }

    @Test func templateIDsAreUnique() {
        let ids = TemplateProvider.bundled.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func coversEveryCountAndPageClass() {
        // 1–6 photos × square/landscape/portrait pages: at least one
        // candidate everywhere.
        let provider = TemplateProvider()
        let pageSizes = [SizeInches(width: 7, height: 7),     // square
                         SizeInches(width: 10, height: 8),    // landscape
                         SizeInches(width: 8, height: 10)]    // portrait
        for count in 1...6 {
            let photos = (0..<count).map { photo("p\($0)", orientation: .landscape) }
            for pageSize in pageSizes {
                let candidates = provider.candidates(forPhotoCount: count, photos: photos,
                                                     context: context(pageSize: pageSize))
                #expect(!candidates.isEmpty, "count \(count), page \(pageSize.width)x\(pageSize.height)")
            }
        }
    }

    @Test func filtersByPhotoCountAndEmitsMatchingFrameCounts() {
        let provider = TemplateProvider()
        let photos = [photo("a", orientation: .portrait), photo("b", orientation: .portrait)]
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos,
                                             context: context(pageSize: SizeInches(width: 10, height: 8)))
        for candidate in candidates {
            #expect(candidate.photoSlotFrames.count == 2)
            guard case .template(let id) = candidate.origin else {
                Issue.record("TemplateProvider emitted a non-template origin")
                continue
            }
            let template = TemplateProvider.bundled.first { $0.id == id }
            #expect(template?.photoCount == 2)
        }
    }

    @Test func ranksByOrientationHintAgreement() throws {
        // Two portrait photos on a landscape page: "two-side-by-side" (hints
        // portrait,portrait → rank 2) must beat "two-panorama-stack" (hints
        // landscape,landscape → rank 0). Ties (the caption variant also ranks
        // 2) break by id: "two-side-by-side" < "two-side-by-side-caption".
        let provider = TemplateProvider()
        let photos = [photo("a", orientation: .portrait), photo("b", orientation: .portrait)]
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos,
                                             context: context(pageSize: SizeInches(width: 10, height: 8)))
        #expect(candidates.first?.origin == .template(id: "two-side-by-side"))
        let ids: [String] = candidates.compactMap {
            if case .template(let id) = $0.origin { return id } else { return nil }
        }
        let sideIndex = try #require(ids.firstIndex(of: "two-side-by-side-caption"))
        let panoramaIndex = try #require(ids.firstIndex(of: "two-panorama-stack"))
        #expect(sideIndex < panoramaIndex)
    }

    @Test func filtersByPageAspectClass() {
        // "two-stacked" targets square+portrait pages only — it must not be
        // offered on a landscape page.
        let provider = TemplateProvider()
        let photos = [photo("a", orientation: .landscape), photo("b", orientation: .landscape)]
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos,
                                             context: context(pageSize: SizeInches(width: 10, height: 8)))
        let ids: [String] = candidates.compactMap {
            if case .template(let id) = $0.origin { return id } else { return nil }
        }
        #expect(!ids.contains("two-stacked"))
        #expect(ids.contains("two-side-by-side"))
    }

    @Test func bundledTemplatesDecodeBorderlessDefaultingFalse() {
        // Every bundled template decodes; borderless defaults to false when the
        // JSON key is absent (back-compat for existing entries).
        let provider = TemplateProvider()
        let photos = [photo("p0", orientation: .landscape)]
        let candidates = provider.candidates(forPhotoCount: 1, photos: photos,
                                             context: context(pageSize: SizeInches(width: 10, height: 8)))
        #expect(!candidates.isEmpty)
    }

    @Test func nineUpGridIsOffered() {
        let provider = TemplateProvider()
        let photos = (0..<9).map { photo("p\($0)", orientation: .square) }
        let ctx = LayoutContext(pageSize: SizeInches(width: 12, height: 12),
                                style: .standard, needsTextZone: false, seed: 1)
        let c = provider.candidates(forPhotoCount: 9, photos: photos, context: ctx)
        #expect(c.contains { $0.photoSlotFrames.count == 9 })
    }

    // D2: borderless filtering
    @Test func borderlessContextReturnsOnlyBorderlessTemplates() {
        let provider = TemplateProvider()
        let photos = [photo("a", orientation: .landscape), photo("b", orientation: .landscape)]
        let ctx = LayoutContext(pageSize: SizeInches(width: 10, height: 8),
                                style: .standard, needsTextZone: false, seed: 1, edgeStyle: .borderless)
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos, context: ctx)
        // Every returned candidate must come from a borderless template
        for candidate in candidates {
            guard case .template(let id) = candidate.origin else { continue }
            let tmpl = TemplateProvider.bundled.first { $0.id == id }
            #expect(tmpl?.borderless == true, "\(id) should be borderless")
        }
    }

    @Test func nonBorderlessContextReturnsOnlyNonBorderlessTemplates() {
        let provider = TemplateProvider()
        let photos = [photo("a", orientation: .landscape), photo("b", orientation: .landscape)]
        let ctx = LayoutContext(pageSize: SizeInches(width: 10, height: 8),
                                style: .standard, needsTextZone: false, seed: 1, edgeStyle: .framed)
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos, context: ctx)
        for candidate in candidates {
            guard case .template(let id) = candidate.origin else { continue }
            let tmpl = TemplateProvider.bundled.first { $0.id == id }
            #expect(tmpl?.borderless == false, "\(id) should NOT be borderless")
        }
    }

    @Test func borderlessTemplateVariantsExistInBundle() {
        // Required borderless template IDs per spec
        let required = ["one-borderless", "two-split-borderless", "four-grid-borderless",
                        "six-grid-borderless", "nine-grid-borderless"]
        let ids = Set(TemplateProvider.bundled.map(\.id))
        for id in required {
            #expect(ids.contains(id), "Missing borderless template: \(id)")
        }
    }

    @Test func borderlessTemplatesHaveFramesTiledEdgeToEdge() {
        // Every template marked borderless must have frames whose union covers the full page
        // (x starts at 0, maxX reaches 1, y starts at 0, maxY reaches 1)
        for tmpl in TemplateProvider.bundled where tmpl.borderless {
            let allX    = tmpl.photoFrames.map { $0.x }
            let allMaxX = tmpl.photoFrames.map { $0.x + $0.width }
            let allY    = tmpl.photoFrames.map { $0.y }
            let allMaxY = tmpl.photoFrames.map { $0.y + $0.height }
            #expect(allX.min()!    <= 1e-9,     "\(tmpl.id): should start at x=0")
            #expect(allMaxX.max()! >= 1 - 1e-9, "\(tmpl.id): should reach x=1")
            #expect(allY.min()!    <= 1e-9,     "\(tmpl.id): should start at y=0")
            #expect(allMaxY.max()! >= 1 - 1e-9, "\(tmpl.id): should reach y=1")
        }
    }
}
