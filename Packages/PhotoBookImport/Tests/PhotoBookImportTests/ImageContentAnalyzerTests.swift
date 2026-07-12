import Testing
import Foundation
import CoreGraphics
import PhotoBookCore
import PhotoBookImportTestSupport
@testable import PhotoBookImport

struct ImageContentAnalyzerTests {

    // A high-frequency checkerboard (sharp) vs a flat field (blurry).
    private func checkerboard(side: Int = 64, cell: Int = 4) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<side {
            for x in 0..<side {
                let on = ((x / cell) + (y / cell)) % 2 == 0
                let v: CGFloat = on ? 1 : 0
                ctx.setFillColor(CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    private func flat(side: Int = 64) -> CGImage {
        MockPhotoProvider.makeImage(width: side, height: side)   // solid gray
    }

    /// Black field with a bright filled disc whose center sits at the given
    /// TOP-LEFT-origin normalized position — a strong attention-saliency cue.
    private func subject(side: Int = 128, cx: Double, cy: Double, radius: Int = 22) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // CGContext origin is bottom-left; flip cy so the disc lands where a
        // top-left-origin reader expects it.
        let px = cx * Double(side)
        let py = (1 - cy) * Double(side)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: px - Double(radius), y: py - Double(radius),
                                   width: Double(radius * 2), height: Double(radius * 2)))
        return ctx.makeImage()!
    }

    // MARK: - Aesthetics mapping (pure)

    @Test func aestheticsMapsMinusOneToOneOntoUnit() {
        #expect(ImageContentAnalyzer.mapAesthetics(-1) == 0)
        #expect(abs(ImageContentAnalyzer.mapAesthetics(0) - 0.5) < 1e-9)
        #expect(ImageContentAnalyzer.mapAesthetics(1) == 1)
    }

    @Test func aestheticsMappingClampsOutOfRange() {
        #expect(ImageContentAnalyzer.mapAesthetics(-2) == 0)
        #expect(ImageContentAnalyzer.mapAesthetics(5) == 1)
    }

    // MARK: - Quality blend (pure)

    @Test func qualityFallsBackToImportanceWhenAestheticsNil() {
        #expect(ImageContentAnalyzer.quality(importance: 0.7, aesthetics: nil) == 0.7)
    }

    @Test func qualityIsHalfImportanceHalfAesthetics() {
        #expect(abs(ImageContentAnalyzer.quality(importance: 0.6, aesthetics: 0.2) - 0.4) < 1e-9)
        #expect(abs(ImageContentAnalyzer.quality(importance: 1.0, aesthetics: 0.0) - 0.5) < 1e-9)
    }

    @Test func scoreQualityMatchesPureFormula() {
        let s = ImageContentAnalyzer.score(image: checkerboard())
        #expect(abs(s.quality - ImageContentAnalyzer.quality(importance: s.importance,
                                                             aesthetics: s.aesthetics)) < 1e-9)
    }

    @Test func blendIsWeightedSumClampedToUnit() {
        #expect(ImageContentAnalyzer.blend(faces: 0, saliency: 0, sharpness: 0) == 0)
        #expect(abs(ImageContentAnalyzer.blend(faces: 1, saliency: 0, sharpness: 0) - 0.45) < 1e-9)
        #expect(abs(ImageContentAnalyzer.blend(faces: 0, saliency: 1, sharpness: 0) - 0.35) < 1e-9)
        #expect(abs(ImageContentAnalyzer.blend(faces: 0, saliency: 0, sharpness: 1) - 0.20) < 1e-9)
        #expect(ImageContentAnalyzer.blend(faces: 1, saliency: 1, sharpness: 1) == 1)
    }

    @Test func scoreComponentsAreInUnitRange() {
        let s = ImageContentAnalyzer.score(image: checkerboard())
        for v in [s.faces, s.saliency, s.sharpness, s.importance] {
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test func sharpImageScoresSharperThanFlat() {
        let sharp = ImageContentAnalyzer.score(image: checkerboard()).sharpness
        let blurry = ImageContentAnalyzer.score(image: flat()).sharpness
        #expect(sharp > blurry)
    }

    @Test func analyzePopulatesImportancePreservingOrder() async {
        let provider = MockPhotoProvider()
        let refs = (0..<5).map { i -> PhotoRef in
            let r = PhotoRef(id: PhotoID(rawValue: "p\(i)"),
                             source: .file(bookmark: Data()),
                             pixelWidth: 64, pixelHeight: 64)
            provider.setImage(checkerboard(), for: r.id)
            return r
        }
        let out = await ImageContentAnalyzer.analyze(refs, provider: provider, concurrency: 2)
        #expect(out.map(\.id) == refs.map(\.id))
        #expect(out.allSatisfy { $0.importance != nil })
        #expect(out.allSatisfy { ($0.importance ?? -1) >= 0 && ($0.importance ?? 2) <= 1 })
    }

    @Test func analyzeLeavesImportanceNilWhenThumbnailFails() async {
        let provider = MockPhotoProvider()   // no images set → thumbnail throws
        let refs = [PhotoRef(id: PhotoID(rawValue: "x"),
                             source: .file(bookmark: Data()),
                             pixelWidth: 64, pixelHeight: 64)]
        let out = await ImageContentAnalyzer.analyze(refs, provider: provider)
        #expect(out.first?.importance == nil)
    }

    @Test func analyzeStampsSalientCenterInTopLeftSpace() async {
        // Subject in the top-left quadrant (top-left origin: small x, small y).
        let img = subject(cx: 0.25, cy: 0.25)
        let provider = MockPhotoProvider()
        let ref = PhotoRef(id: PhotoID(rawValue: "s"),
                           source: .file(bookmark: Data()),
                           pixelWidth: 128, pixelHeight: 128)
        provider.setImage(img, for: ref.id)
        let out = await ImageContentAnalyzer.analyze([ref], provider: provider, maxPixelSize: 128)
        let center = out.first?.salientCenter
        #expect(center != nil)
        if let c = center {
            #expect(c.x < 0.5)   // left half
            #expect(c.y < 0.5)   // top half (top-left origin, matches crop NormRect)
        }
    }

    @Test func analyzeRespectsCancellation() async {
        let provider = MockPhotoProvider()
        let refs = (0..<50).map { i -> PhotoRef in
            let r = PhotoRef(id: PhotoID(rawValue: "p\(i)"),
                             source: .file(bookmark: Data()),
                             pixelWidth: 64, pixelHeight: 64)
            provider.setImage(flat(), for: r.id)
            return r
        }
        let task = Task { await ImageContentAnalyzer.analyze(refs, provider: provider) }
        task.cancel()
        let out = await task.value
        #expect(out.count == refs.count)
        #expect(out.map(\.id) == refs.map(\.id))   // order preserved even when cancelled
    }
}
