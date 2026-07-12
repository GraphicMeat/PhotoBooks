import Testing
import Foundation
import CoreGraphics
import PhotoBookCore
import PhotoBookImportTestSupport
@testable import PhotoBookImport

struct CurationAnalyzerTests {

    private func id(_ s: String) -> PhotoID { PhotoID(rawValue: s) }

    /// Distance closure driven by a set of "similar" unordered pairs: listed
    /// pairs are near-duplicates (distance 0.1 < threshold), everything else
    /// is far (2.0 > threshold).
    private func distance(similar pairs: [(String, String)])
        -> (PhotoID, PhotoID) -> Float {
        let set = Set(pairs.map { Set([$0.0, $0.1]) })
        return { a, b in
            a == b ? 0 : (set.contains(Set([a.rawValue, b.rawValue])) ? 0.1 : 2.0)
        }
    }

    // MARK: - Pure core

    @Test func burstWithinWindowMergesToOneCluster() {
        let base = Date(timeIntervalSince1970: 1000)
        let photos = (0..<5).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0) * 30)))
        }
        // Every consecutive pair near-identical.
        let pairs = (0..<4).map { ("p\($0)", "p\($0 + 1)") }
        let clusters = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: pairs))
        #expect(Set(clusters.values).count == 1)
    }

    @Test func sameBurstFarApartInTimeStaysSeparate() {
        let base = Date(timeIntervalSince1970: 1000)
        // Three hours apart each — outside the 10-min window.
        let photos = (0..<5).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0) * 3 * 3600)))
        }
        let pairs = (0..<4).map { ("p\($0)", "p\($0 + 1)") }
        let clusters = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: pairs))
        #expect(Set(clusters.values).count == 5)
    }

    @Test func farInFeatureSpaceStaysSeparateEvenWhenSimultaneous() {
        let base = Date(timeIntervalSince1970: 1000)
        let photos = (0..<3).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0))))
        }
        // No similar pairs → distance 2.0 everywhere.
        let clusters = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: []))
        #expect(Set(clusters.values).count == 3)
    }

    @Test func determinismSameInputSameIDsTwice() {
        let base = Date(timeIntervalSince1970: 1000)
        let photos = (0..<6).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0) * 60)))
        }
        let pairs = [("p0", "p1"), ("p3", "p4")]
        let a = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: pairs))
        let b = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: pairs))
        #expect(a == b)
    }

    @Test func chainMergesViaUnionFindEvenWhenEndsAreOutOfWindow() {
        // A~B (2 min), B~C (2 min), A–C are ~4 min apart still within window here,
        // so widen: A at t0, B at t0+8min, C at t0+16min. A–C gap = 16min > window,
        // but A~B and B~C each fall inside 10-min window → all three merge.
        let base = Date(timeIntervalSince1970: 1000)
        let photos = [
            (id: id("A"), captureDate: Optional(base)),
            (id: id("B"), captureDate: Optional(base.addingTimeInterval(8 * 60))),
            (id: id("C"), captureDate: Optional(base.addingTimeInterval(16 * 60))),
        ]
        let clusters = CurationAnalyzer.clusters(
            photos: photos, distance: distance(similar: [("A", "B"), ("B", "C")]))
        #expect(clusters[id("A")] == clusters[id("C")])
        #expect(Set(clusters.values).count == 1)
    }

    @Test func nilDatedPhotosClusterAmongThemselves() {
        let photos: [(id: PhotoID, captureDate: Date?)] = [
            (id: id("n0"), captureDate: nil),
            (id: id("n1"), captureDate: nil),
            (id: id("n2"), captureDate: nil),
        ]
        // n0~n1 similar, n2 far.
        let clusters = CurationAnalyzer.clusters(
            photos: photos, distance: distance(similar: [("n0", "n1")]))
        #expect(clusters[id("n0")] == clusters[id("n1")])
        #expect(clusters[id("n2")] != clusters[id("n0")])
        #expect(Set(clusters.values).count == 2)
    }

    @Test func everyPhotoGetsACluster() {
        let base = Date(timeIntervalSince1970: 1000)
        let photos = (0..<4).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0))))
        }
        let clusters = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: []))
        #expect(clusters.count == 4)
        #expect(clusters.keys.sorted { $0.rawValue < $1.rawValue }
            == photos.map(\.id).sorted { $0.rawValue < $1.rawValue })
    }

    @Test func thousandPhotosCompleteQuickly() {
        let base = Date(timeIntervalSince1970: 1000)
        // 60s apart → each 10-min window holds ~10 neighbors, so the sliding
        // window keeps this O(n·window), not O(n²).
        let photos = (0..<1000).map {
            (id: id("p\($0)"), captureDate: Optional(base.addingTimeInterval(Double($0) * 60)))
        }
        let start = Date()
        let clusters = CurationAnalyzer.clusters(photos: photos, distance: distance(similar: []))
        let elapsed = Date().timeIntervalSince(start)
        #expect(clusters.count == 1000)
        #expect(elapsed < 1.0)
    }

    // MARK: - candidates with precomputed prints (single-decode pipeline)

    @Test func candidatesClustersMatchPureCoreOnTheSamePrints() async {
        // Parity: candidates(for:scores:prints:) must produce exactly the
        // clusters the pure core computes from the same prints' distances.
        // Two identical images + one very different, all within the window.
        let provider = MockPhotoProvider()
        let base = Date(timeIntervalSince1970: 1000)
        let same = MockPhotoProvider.makeImage(width: 64, height: 64)  // solid gray
        var refs: [PhotoRef] = []
        for (i, image) in [same, same, checkerboardImage()].enumerated() {
            let ref = PhotoRef(id: id("p\(i)"), source: .file(bookmark: Data()),
                               pixelWidth: 64, pixelHeight: 64,
                               captureDate: base.addingTimeInterval(Double(i)))
            provider.setImage(image, for: ref.id)
            refs.append(ref)
        }
        let (analyzed, scores, prints) = await ImageContentAnalyzer.analyzeWithScores(
            refs, provider: provider)
        let cands = CurationAnalyzer.candidates(for: analyzed, scores: scores, prints: prints)

        let expected = CurationAnalyzer.clusters(
            photos: analyzed.map { (id: $0.id, captureDate: $0.captureDate) },
            distance: { a, b in prints[a]!.distance(to: prints[b]!) })
        #expect(Dictionary(uniqueKeysWithValues: cands.map { ($0.id, $0.clusterID) }) == expected)
        // Identical images cluster together; the checkerboard stands apart.
        #expect(cands[0].clusterID == cands[1].clusterID)
        #expect(cands[2].clusterID != cands[0].clusterID)
        // Scores flowed through (no 0.5 fallback for scored photos).
        #expect(cands.allSatisfy { scores[$0.id] != nil })
    }

    @Test func candidateWithoutPrintIsItsOwnSingletonCluster() {
        let base = Date(timeIntervalSince1970: 1000)
        let refs = (0..<2).map {
            PhotoRef(id: id("p\($0)"), source: .file(bookmark: Data()),
                     pixelWidth: 64, pixelHeight: 64,
                     captureDate: base.addingTimeInterval(Double($0)))
        }
        // No prints at all → every photo infinitely far from everything.
        let cands = CurationAnalyzer.candidates(for: refs, scores: [:], prints: [:])
        #expect(cands.count == 2)
        #expect(cands[0].clusterID != cands[1].clusterID)
        // Unscored fallback: mid-quality, not utility.
        #expect(cands.allSatisfy { $0.quality == 0.5 && !$0.isUtility })
    }

    private func checkerboardImage(side: Int = 64, cell: Int = 4) -> CGImage {
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
}
