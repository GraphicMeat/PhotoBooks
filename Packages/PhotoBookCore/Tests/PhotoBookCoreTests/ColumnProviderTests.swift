import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct ColumnProviderTests {
    private let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func photos(_ n: Int) -> [AnalyzedPhoto] {
        (0..<n).map { i in
            AnalyzedPhoto(ref: PhotoRef(id: PhotoID(rawValue: "p\(i)"),
                                        source: .file(bookmark: Data()),
                                        pixelWidth: 4000, pixelHeight: 3000),
                          orientation: .landscape, clusterIndex: 0)
        }
    }
    private func context(needsText: Bool = false, borderless: Bool = false) -> LayoutContext {
        LayoutContext(pageSize: preset.trimSize, style: .standard,
                      needsTextZone: needsText, seed: 7,
                      edgeStyle: borderless ? .borderless : .framed)
    }

    @Test func masonryOffersTwoColumnsForSmallCountsAndThreeForLarge() {
        let p2 = MasonryProvider().candidates(forPhotoCount: 4, photos: photos(4), context: context())
        #expect(p2.count == 1)                                  // only 2-col for n=4
        #expect(p2.allSatisfy { $0.family == .masonry })
        #expect(p2[0].photoSlotFrames.count == 4)
        let p3 = MasonryProvider().candidates(forPhotoCount: 6, photos: photos(6), context: context())
        #expect(p3.count == 2)                                  // 2-col + 3-col for n=6
    }

    @Test func gridOffersSameColumnVariants() {
        let g = GridProvider().candidates(forPhotoCount: 6, photos: photos(6), context: context())
        #expect(g.count == 2)
        #expect(g.allSatisfy { $0.family == .grid })
        #expect(g.allSatisfy { $0.photoSlotFrames.count == 6 })
    }

    @Test func bothOfferBorderlessCandidates() {
        let m = MasonryProvider().candidates(forPhotoCount: 6, photos: photos(6), context: context(borderless: true))
        let g = GridProvider().candidates(forPhotoCount: 6, photos: photos(6), context: context(borderless: true))
        #expect(m.count == 2)                       // 2-col + 3-col (n=6)
        #expect(g.count == 2)
        #expect(m.allSatisfy { $0.family == .masonry })
        #expect(g.allSatisfy { $0.family == .grid })
    }

    /// Borderless masonry spans the full page width and keeps whole photos
    /// (zero-crop). Uses 2 photos (1 per column) so columns fit the page height
    /// and the block is not contained/shrunk.
    @Test func borderlessMasonryFillsWidthZeroCrop() {
        let m = MasonryProvider().candidates(forPhotoCount: 2, photos: photos(2), context: context(borderless: true))
        let boxes = try! #require(m.first).photoSlotFrames
        #expect(boxes.count == 2)
        #expect(boxes.map(\.x).min()! < 1e-6)        // touches left edge
        #expect(boxes.map(\.maxX).max()! > 1 - 1e-6) // touches right edge
        let pageAspect = preset.trimSize.aspectRatio
        for (box, photo) in zip(boxes, photos(2)) {
            #expect(abs(box.aspectRatio * pageAspect - photo.ref.aspectRatio) < 1e-6)
        }
    }

    /// Borderless grid tiles the page edge-to-edge (no margin).
    @Test func borderlessGridTilesEdgeToEdge() {
        let g = GridProvider().candidates(forPhotoCount: 4, photos: photos(4), context: context(borderless: true))
        let boxes = try! #require(g.first { $0.photoSlotFrames.count == 4 }).photoSlotFrames
        #expect(boxes.map(\.x).min()! < 1e-6)
        #expect(boxes.map(\.y).min()! < 1e-6)
        #expect(boxes.map(\.maxX).max()! > 1 - 1e-6)
        #expect(boxes.map(\.maxY).max()! > 1 - 1e-6)
    }

    /// Tiled masonry drops the outer margin (bleeds to the page edge) but keeps
    /// the gutter between columns. Uses 2 photos (1 per column) so the two
    /// side-by-side columns leave a visible inter-column gap.
    @Test func tiledMasonryBleedsToEdgeButKeepsGutter() {
        let ctx = LayoutContext(pageSize: preset.trimSize, style: .standard,
                                needsTextZone: false, seed: 7, edgeStyle: .tiled)
        let boxes = try! #require(MasonryProvider()
            .candidates(forPhotoCount: 2, photos: photos(2), context: ctx).first)
            .photoSlotFrames.sorted { $0.x < $1.x }
        #expect(boxes.count == 2)
        #expect(boxes.map(\.x).min()! < 1e-6)         // no outer margin: touches left edge
        #expect(boxes.map(\.maxX).max()! > 1 - 1e-6)  // spans to the right edge
        let gap = boxes[1].x - boxes[0].maxX          // gutter kept between columns
        #expect(gap > 1e-3)
    }

    /// Interior (non-borderless) masonry still insets by the page margin.
    @Test func interiorMasonryStillHasMargin() {
        let m = MasonryProvider().candidates(forPhotoCount: 2, photos: photos(2), context: context())
        let boxes = try! #require(m.first).photoSlotFrames
        #expect(boxes.map(\.x).min()! > 1e-3)
    }

    @Test func reserveTextBand() {
        let m = MasonryProvider().candidates(forPhotoCount: 4, photos: photos(4), context: context(needsText: true))
        #expect(m[0].textSlotFrames.count == 1)
        let bandTop = m[0].textSlotFrames[0].y
        #expect(m[0].photoSlotFrames.allSatisfy { $0.maxY <= bandTop + 1e-6 })
    }

    @Test func singlePhotoGetsNoColumnCandidates() {
        #expect(MasonryProvider().candidates(forPhotoCount: 1, photos: photos(1), context: context()).isEmpty)
        #expect(GridProvider().candidates(forPhotoCount: 1, photos: photos(1), context: context()).isEmpty)
    }
}
