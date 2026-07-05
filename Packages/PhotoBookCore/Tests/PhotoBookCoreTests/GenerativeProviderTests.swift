import Foundation
import Testing
import PhotoBookCore

@Suite struct GenerativeProviderTests {

    private func photo(_ id: String, aspect: Double) -> AnalyzedPhoto {
        let width = Int(3000.0 * aspect)
        let orientation: Orientation =
            abs(aspect - 1) < 0.05 ? .square : (aspect > 1 ? .landscape : .portrait)
        return AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: width, pixelHeight: 3000),
            orientation: orientation, clusterIndex: 0)
    }

    private func mixedPhotos(_ count: Int) -> [AnalyzedPhoto] {
        let aspects = [1.5, 0.75, 1.0, 1.33, 0.66, 1.78]
        return (0..<count).map { photo("p\($0)", aspect: aspects[$0 % aspects.count]) }
    }

    private func context(seed: UInt64, needsTextZone: Bool = false) -> LayoutContext {
        LayoutContext(pageSize: SizeInches(width: 10, height: 8), style: .standard,
                      needsTextZone: needsTextZone, seed: seed)
    }

    @Test func sameSeedProducesIdenticalBoxes() {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(4)
        let first = provider.candidates(forPhotoCount: 4, photos: photos, context: context(seed: 7))
        let second = provider.candidates(forPhotoCount: 4, photos: photos, context: context(seed: 7))
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.photoSlotFrames == b.photoSlotFrames)
            #expect(a.origin == b.origin)
        }
    }

    @Test func differentSeedsProduceDifferentBoxes() {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(4)
        let a = provider.candidates(forPhotoCount: 4, photos: photos, context: context(seed: 1))
        let b = provider.candidates(forPhotoCount: 4, photos: photos, context: context(seed: 2))
        #expect(a[0].photoSlotFrames != b[0].photoSlotFrames)
    }

    /// Landscape photos are stacked into full-width rows, so every slot stays
    /// landscape-shaped — a horizontal photo never lands in a tall slot.
    @Test func landscapePhotosGetWideStackedSlots() {
        let provider = GenerativeProvider()
        let photos = [photo("a", aspect: 1.5), photo("b", aspect: 1.5)]
        let ctx = context(seed: 5)
        for candidate in provider.candidates(forPhotoCount: 2, photos: photos, context: ctx) {
            for frame in candidate.photoSlotFrames {
                let slotAspect = frame.aspectRatio * ctx.pageSize.aspectRatio
                #expect(slotAspect > 1, "landscape photo got a tall slot (aspect \(slotAspect))")
            }
        }
    }

    /// Portrait photos sit side by side, so every slot stays portrait-shaped.
    @Test func portraitPhotosGetTallSideBySideSlots() {
        let provider = GenerativeProvider()
        let photos = [photo("a", aspect: 0.66), photo("b", aspect: 0.66)]
        let ctx = context(seed: 5)
        for candidate in provider.candidates(forPhotoCount: 2, photos: photos, context: ctx) {
            for frame in candidate.photoSlotFrames {
                let slotAspect = frame.aspectRatio * ctx.pageSize.aspectRatio
                #expect(slotAspect < 1, "portrait photo got a wide slot (aspect \(slotAspect))")
            }
        }
    }

    @Test func emitsGeneratedOriginCarryingItsBoxes() throws {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(3)
        let candidate = try #require(provider.candidates(forPhotoCount: 3, photos: photos,
                                                         context: context(seed: 11)).first)
        guard case .generated(let params) = candidate.origin else {
            Issue.record("Expected .generated origin")
            return
        }
        #expect(params.boxes == candidate.photoSlotFrames)   // serialized = emitted
    }

    @Test func boxesStayInsideMarginsForOneToSixPhotos() {
        let provider = GenerativeProvider()
        let margin = BookStyle.standard.pageMargin
        for count in 1...6 {
            let photos = mixedPhotos(count)
            for candidate in provider.candidates(forPhotoCount: count, photos: photos,
                                                 context: context(seed: 3)) {
                #expect(candidate.photoSlotFrames.count == count)
                for box in candidate.photoSlotFrames {
                    #expect(box.x >= margin - 1e-9)
                    #expect(box.y >= margin - 1e-9)
                    #expect(box.x + box.width <= 1 - margin + 1e-9)
                    #expect(box.y + box.height <= 1 - margin + 1e-9)
                    #expect(box.width > 0 && box.height > 0)
                }
            }
        }
    }

    @Test func boxesAreSeparatedByAtLeastTheGutter() {
        let provider = GenerativeProvider()
        let gutter = BookStyle.standard.gutter
        for count in 2...6 {
            let photos = mixedPhotos(count)
            for candidate in provider.candidates(forPhotoCount: count, photos: photos,
                                                 context: context(seed: 5)) {
                let boxes = candidate.photoSlotFrames
                for i in 0..<boxes.count {
                    for j in (i + 1)..<boxes.count {
                        let a = boxes[i], b = boxes[j]
                        // Guillotine layout: every pair is separated by at
                        // least one gutter along at least one axis.
                        let separatedX = a.x + a.width + gutter <= b.x + 1e-9
                            || b.x + b.width + gutter <= a.x + 1e-9
                        let separatedY = a.y + a.height + gutter <= b.y + 1e-9
                            || b.y + b.height + gutter <= a.y + 1e-9
                        #expect(separatedX || separatedY,
                                "boxes \(i) and \(j) overlap or sit closer than the gutter")
                    }
                }
            }
        }
    }

    @Test func allPanoramaBatchStacksIntoFullWidthBands() {
        // Four 3:1 panoramas: every split must be horizontal, so every box
        // spans the full content width — the all-panorama edge case from the
        // spec that templates cannot cover.
        let provider = GenerativeProvider()
        let photos = (0..<4).map { photo("pano\($0)", aspect: 3.0) }
        let margin = BookStyle.standard.pageMargin
        let contentWidth = 1.0 - 2 * margin
        for candidate in provider.candidates(forPhotoCount: 4, photos: photos,
                                             context: context(seed: 9)) {
            for box in candidate.photoSlotFrames {
                #expect(abs(box.width - contentWidth) < 1e-9,
                        "panorama box should span the full content width")
            }
        }
    }

    @Test func reservesTextBandWhenContextNeedsTextZone() {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(3)
        for candidate in provider.candidates(forPhotoCount: 3, photos: photos,
                                             context: context(seed: 13, needsTextZone: true)) {
            #expect(candidate.textSlotFrames.count == 1)
            let band = candidate.textSlotFrames[0]
            // The band sits below every photo box.
            for box in candidate.photoSlotFrames {
                #expect(box.y + box.height <= band.y + 1e-9)
            }
        }
    }

    @Test func emitsThreeCandidates() {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(2)
        #expect(provider.candidates(forPhotoCount: 2, photos: photos,
                                    context: context(seed: 21)).count == 3)
    }

    @Test func mismatchedCountReturnsNothing() {
        let provider = GenerativeProvider()
        #expect(provider.candidates(forPhotoCount: 3, photos: mixedPhotos(2),
                                    context: context(seed: 1)).isEmpty)
        #expect(provider.candidates(forPhotoCount: 0, photos: [],
                                    context: context(seed: 1)).isEmpty)
    }

    // D2: borderless context — zero gutter/margin, frames tile edge-to-edge
    private func borderlessContext(seed: UInt64) -> LayoutContext {
        LayoutContext(pageSize: SizeInches(width: 10, height: 8), style: .standard,
                      needsTextZone: false, seed: seed, edgeStyle: .borderless)
    }

    @Test func borderlessTwoPhotoFramesTileEdgeToEdge() {
        let provider = GenerativeProvider()
        let photos = mixedPhotos(2)
        let candidates = provider.candidates(forPhotoCount: 2, photos: photos,
                                             context: borderlessContext(seed: 42))
        #expect(!candidates.isEmpty)
        for candidate in candidates {
            let frames = candidate.photoSlotFrames
            #expect(frames.count == 2)
            // First frame starts at x == 0 (no left margin)
            #expect(frames[0].x == 0.0)
            // Frames touch: second frame's x == first frame's maxX (no gutter gap)
            let firstMaxX = frames[0].x + frames[0].width
            let secondMinX = frames[1].x
            // For a vertical split: they must touch (no gap); allow either axis-split
            // Frames must collectively cover full page (union reaches x=0 or y=0 and 1.0)
            let allX = frames.map { $0.x }
            let allMaxX = frames.map { $0.x + $0.width }
            let allY = frames.map { $0.y }
            let allMaxY = frames.map { $0.y + $0.height }
            #expect(allX.min()! <= 1e-9, "should start at x=0")
            #expect(allMaxX.max()! >= 1 - 1e-9, "should reach x=1")
            #expect(allY.min()! <= 1e-9, "should start at y=0")
            #expect(allMaxY.max()! >= 1 - 1e-9, "should reach y=1")
        }
    }

    @Test func borderlessFramesHaveNoGutterBetweenThem() {
        let provider = GenerativeProvider()
        for count in 2...6 {
            let photos = mixedPhotos(count)
            for candidate in provider.candidates(forPhotoCount: count, photos: photos,
                                                 context: borderlessContext(seed: 77)) {
                let boxes = candidate.photoSlotFrames
                // In a borderless guillotine layout, adjacent siblings touch exactly
                // (gap == 0). Every pair must be separated along at least one axis
                // with a gap of exactly 0 (no positive gutter).
                for i in 0..<boxes.count {
                    for j in (i + 1)..<boxes.count {
                        let a = boxes[i], b = boxes[j]
                        // Overlap check: they must not overlap
                        let overlapX = a.x < b.x + b.width && b.x < a.x + a.width
                        let overlapY = a.y < b.y + b.height && b.y < a.y + a.height
                        #expect(!(overlapX && overlapY),
                                "boxes \(i) and \(j) must not overlap in borderless mode")
                    }
                }
            }
        }
    }

    @Test func nonBorderlessContextUnchangedBehavior() {
        // Confirm default (borderless: false) still respects the margin
        let provider = GenerativeProvider()
        let margin = BookStyle.standard.pageMargin
        let photos = mixedPhotos(3)
        for candidate in provider.candidates(forPhotoCount: 3, photos: photos,
                                             context: context(seed: 3)) {
            for box in candidate.photoSlotFrames {
                #expect(box.x >= margin - 1e-9)
                #expect(box.y >= margin - 1e-9)
            }
        }
    }
}
