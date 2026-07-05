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
