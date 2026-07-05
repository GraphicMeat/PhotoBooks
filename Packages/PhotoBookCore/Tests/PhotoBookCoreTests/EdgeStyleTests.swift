import Testing
import Foundation
@testable import PhotoBookCore

@Suite struct EdgeStyleTests {

    @Test func framedHasMarginAndGutter() {
        #expect(EdgeStyle.framed.hasOuterMargin == true)
        #expect(EdgeStyle.framed.keepsGutter == true)
        #expect(EdgeStyle.framed.isFullBleed == false)
    }

    @Test func tiledDropsMarginKeepsGutter() {
        #expect(EdgeStyle.tiled.hasOuterMargin == false)
        #expect(EdgeStyle.tiled.keepsGutter == true)
        #expect(EdgeStyle.tiled.isFullBleed == false)
    }

    @Test func borderlessDropsBoth() {
        #expect(EdgeStyle.borderless.hasOuterMargin == false)
        #expect(EdgeStyle.borderless.keepsGutter == false)
        #expect(EdgeStyle.borderless.isFullBleed == true)
    }

    @Test func rawValueRoundTrips() throws {
        for style in EdgeStyle.allCases {
            let data = try JSONEncoder().encode(style)
            #expect(try JSONDecoder().decode(EdgeStyle.self, from: data) == style)
        }
    }

    // MARK: - Engine behavior (framed/tiled/borderless)

    /// Two analyzed landscape photos (4000×3000 ≈ 1.33) — a single justified row.
    private enum TestPhotos {
        static func landscapePair() -> [AnalyzedPhoto] {
            (0..<2).map { i in
                AnalyzedPhoto(ref: PhotoRef(id: PhotoID(rawValue: "p\(i)"),
                                            source: .file(bookmark: Data()),
                                            pixelWidth: 4000, pixelHeight: 3000),
                              orientation: .landscape, clusterIndex: 0)
            }
        }
    }

    // Uses JustifiedProvider directly: framed insets by pageMargin, tiled insets
    // by 0 but keeps gutter, borderless defers to the generative full-bleed tiler.
    private func ctx(_ edgeStyle: EdgeStyle) -> LayoutContext {
        // Wide page (aspect ≈ 2.67) so two side-by-side 1.33 landscape photos
        // fill best as a SINGLE justified row — the arrangement these tests assume.
        LayoutContext(pageSize: SizeInches(width: 16, height: 6),
                      style: .standard, needsTextZone: false, seed: 42,
                      edgeStyle: edgeStyle)
    }

    @Test func tiledSpansFullPageWidthAcrossARow() {
        // Two landscape photos → one justified row. Framed leaves a left margin;
        // tiled starts at x≈0 and the row spans the full width.
        let photos = TestPhotos.landscapePair()
        let provider = JustifiedProvider()

        let framed = provider.candidates(forPhotoCount: 2, photos: photos, context: ctx(.framed))
        let tiled  = provider.candidates(forPhotoCount: 2, photos: photos, context: ctx(.tiled))

        let framedMinX = framed.first!.photoSlotFrames.map(\.x).min()!
        let tiledMinX  = tiled.first!.photoSlotFrames.map(\.x).min()!
        #expect(framedMinX > 0.01)                    // framed has an outer margin
        #expect(tiledMinX < 0.001)                    // tiled bleeds to the edge

        let tiledMaxX = tiled.first!.photoSlotFrames.map { $0.x + $0.width }.max()!
        #expect(tiledMaxX > 0.999)                    // spans to the right edge
    }

    @Test func tiledKeepsGutterBetweenPhotos() {
        let photos = TestPhotos.landscapePair()
        let tiled = JustifiedProvider()
            .candidates(forPhotoCount: 2, photos: photos, context: ctx(.tiled))
            .first!.photoSlotFrames.sorted { $0.x < $1.x }
        // A visible gap remains between the two slots (gutter kept).
        let gap = tiled[1].x - (tiled[0].x + tiled[0].width)
        #expect(gap > 0.001)
    }

    @Test func borderlessTilesTouchAtFullBleed() {
        let photos = TestPhotos.landscapePair()
        let boxes = JustifiedProvider()
            .candidates(forPhotoCount: 2, photos: photos, context: ctx(.borderless))
            .first!.photoSlotFrames
        // Borderless coverage fills the page (generative full-bleed).
        let area = boxes.reduce(0.0) { $0 + $1.width * $1.height }
        #expect(area > 0.95)
    }
}
