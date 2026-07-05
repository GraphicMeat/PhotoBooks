import CoreGraphics
import Foundation
import PhotoBookCore
import Vision

/// One photo's content signals, each in [0,1], plus their blended importance.
public struct ImportanceScore: Equatable, Sendable {
    public var faces: Double
    public var saliency: Double
    public var sharpness: Double
    public var importance: Double

    public init(faces: Double, saliency: Double, sharpness: Double, importance: Double) {
        self.faces = faces
        self.saliency = saliency
        self.sharpness = sharpness
        self.importance = importance
    }
}

/// Impure, on-device image-content analysis. Lives in PhotoBookImport (I/O +
/// ML) so PhotoBookCore stays pure. Vision's `perform` is synchronous, so
/// per-image scoring is a pure function of the pixels; the async `analyze`
/// only adds thumbnail fetching, bounded concurrency, and cancellation.
public enum ImageContentAnalyzer {

    // Blend weights (sum to 1). Sharpness mainly down-weights blurry shots.
    static let faceWeight = 0.45
    static let saliencyWeight = 0.35
    static let sharpnessWeight = 0.20

    // Face bounding boxes are small relative to the frame; scale their summed
    // area so a clear portrait reaches a meaningful score.
    static let faceAreaGain = 3.0

    // Half-saturation constant for the sharpness map v/(v+k), in Laplacian-
    // variance space: at v == k the score is 0.5. Tuned so typical in-focus
    // photos land mid-range and flat/blurry frames stay near 0.
    static let sharpnessHalfSaturation = 0.0025

    /// Pure: weighted blend of the three signals, clamped to [0,1].
    public static func blend(faces: Double, saliency: Double, sharpness: Double) -> Double {
        let v = faceWeight * faces + saliencyWeight * saliency + sharpnessWeight * sharpness
        return min(1.0, max(0.0, v))
    }

    /// Score a single image. Synchronous (Vision.perform blocks).
    public static func score(image: CGImage) -> ImportanceScore {
        let f = faceScore(of: image)
        let s = saliencyScore(of: image)
        let q = sharpness(of: image)
        return ImportanceScore(faces: f, saliency: s, sharpness: q,
                               importance: blend(faces: f, saliency: s, sharpness: q))
    }

    /// Batch: fetch each thumbnail via `provider`, score it, and return the
    /// same refs with `.importance` set — nil where the thumbnail failed or the
    /// run was cancelled before that photo's scoring began. (A partial cancel
    /// can leave some refs scored and others nil; callers should treat nil as
    /// "not scored", not as a signal that the whole run finished.) Bounded to
    /// `concurrency` in-flight scorings; order of the returned array matches
    /// the input.
    public static func analyze(
        _ refs: [PhotoRef],
        provider: any PhotoProvider,
        maxPixelSize: Int = 256,
        concurrency: Int = 4,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [PhotoRef] {
        guard !refs.isEmpty else { return refs }
        let total = refs.count
        let limit = max(1, concurrency)
        var scores = [Int: Double]()
        var completed = 0

        await withTaskGroup(of: (Int, Double?).self) { group in
            var next = 0
            func submit(_ i: Int) {
                let ref = refs[i]
                group.addTask {
                    if Task.isCancelled { return (i, nil) }
                    guard let image = try? await provider.thumbnail(for: ref, maxPixelSize: maxPixelSize)
                    else { return (i, nil) }
                    if Task.isCancelled { return (i, nil) }
                    return (i, score(image: image).importance)
                }
            }
            while next < min(limit, total) { submit(next); next += 1 }
            for await (i, value) in group {
                if let value { scores[i] = value }
                completed += 1
                progress?(completed, total)
                if next < total && !Task.isCancelled { submit(next); next += 1 }
            }
        }

        var result = refs
        for (i, value) in scores { result[i].importance = value }
        return result
    }

    // MARK: - Signals

    private static func faceScore(of image: CGImage) -> Double {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return 0 }
        let faces = request.results ?? []
        guard !faces.isEmpty else { return 0 }
        let area = faces.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        return min(1.0, area * faceAreaGain)
    }

    private static func saliencyScore(of image: CGImage) -> Double {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return 0 }
        guard let obs = request.results?.first as? VNSaliencyImageObservation else { return 0 }
        let objects = obs.salientObjects ?? []
        let best = objects
            .map { Double($0.boundingBox.width * $0.boundingBox.height) * Double($0.confidence) }
            .max() ?? 0
        return min(1.0, best)
    }

    /// Laplacian variance on a 64×64 grayscale downsample, saturating-normalized.
    /// Accepts any CGImage — Core Graphics converts color to gray during draw.
    private static func sharpness(of image: CGImage) -> Double {
        let side = 64
        guard let cs = CGColorSpace(name: CGColorSpace.linearGray)
                ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let ctx = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }
        // Row stride must equal `side` for the `buf[y * side + x]` indexing
        // below; 8-bit single-channel gray makes that exact. Guard in debug so
        // a future bit-depth/colorspace change can't silently corrupt reads.
        assert(ctx.bytesPerRow == side, "unexpected row stride \(ctx.bytesPerRow) != \(side)")
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return 0 }
        let buf = data.bindMemory(to: UInt8.self, capacity: side * side)

        var values: [Double] = []
        values.reserveCapacity((side - 2) * (side - 2))
        func px(_ x: Int, _ y: Int) -> Double { Double(buf[y * side + x]) / 255.0 }
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let lap = px(x, y - 1) + px(x, y + 1) + px(x - 1, y) + px(x + 1, y) - 4 * px(x, y)
                values.append(lap)
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance / (variance + sharpnessHalfSaturation)
    }
}
