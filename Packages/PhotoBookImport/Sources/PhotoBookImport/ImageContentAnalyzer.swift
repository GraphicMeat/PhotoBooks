import CoreGraphics
import Foundation
import PhotoBookCore
import Vision

/// One photo's content signals, each in [0,1], plus their blended importance
/// and an aesthetics-aware quality score.
public struct ImportanceScore: Equatable, Sendable {
    public var faces: Double
    public var saliency: Double
    public var sharpness: Double
    /// Vision aesthetics overallScore mapped [-1,1]→[0,1]; nil if the request failed.
    public var aesthetics: Double?
    /// Vision's "utility image" flag (screenshots, receipts, documents);
    /// false when aesthetics is unavailable.
    public var isUtility: Bool
    /// Center of the best salient object (area×confidence winner), in
    /// top-left-origin normalized image space; nil if none found.
    public var salientCenter: NormPoint?
    public var importance: Double

    /// aesthetics != nil ? 0.5·importance + 0.5·aesthetics : importance.
    public var quality: Double {
        ImageContentAnalyzer.quality(importance: importance, aesthetics: aesthetics)
    }

    public init(faces: Double, saliency: Double, sharpness: Double,
                aesthetics: Double? = nil, isUtility: Bool = false,
                salientCenter: NormPoint? = nil, importance: Double) {
        self.faces = faces
        self.saliency = saliency
        self.sharpness = sharpness
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.salientCenter = salientCenter
        self.importance = importance
    }
}

/// Immutable Vision feature print, boxed so it can cross task boundaries.
/// `VNFeaturePrintObservation` isn't `Sendable`, but each observation is a
/// write-once snapshot produced in one task and only read afterwards.
public struct FeaturePrint: @unchecked Sendable {
    public let observation: VNFeaturePrintObservation

    public init(observation: VNFeaturePrintObservation) {
        self.observation = observation
    }

    /// Vision feature-print distance to another print (smaller = more
    /// similar); +∞ if the comparison fails.
    public func distance(to other: FeaturePrint) -> Float {
        var d: Float = 0
        do { try observation.computeDistance(&d, to: other.observation) } catch {
            return .greatestFiniteMagnitude
        }
        return d
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

    /// Pure: map Vision's aesthetics overallScore ([-1,1]) to [0,1], clamped.
    public static func mapAesthetics(_ overallScore: Float) -> Double {
        min(1.0, max(0.0, (Double(overallScore) + 1.0) / 2.0))
    }

    /// Pure: quality blends importance with aesthetics when available, else
    /// falls back to importance alone.
    public static func quality(importance: Double, aesthetics: Double?) -> Double {
        guard let aesthetics else { return importance }
        return 0.5 * importance + 0.5 * aesthetics
    }

    /// Score a single image. Synchronous (Vision.perform blocks).
    public static func score(image: CGImage) -> ImportanceScore {
        let f = faceScore(of: image)
        let (s, center) = saliency(of: image)
        let q = sharpness(of: image)
        let (aes, utility) = aesthetics(of: image)
        return ImportanceScore(faces: f, saliency: s, sharpness: q,
                               aesthetics: aes, isUtility: utility,
                               salientCenter: center,
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
        // includePrints: false — plain analysis callers don't pay for the
        // extra feature-print Vision pass they'd never read.
        await analyzeWithScores(refs, provider: provider, maxPixelSize: maxPixelSize,
                                concurrency: concurrency, includePrints: false,
                                progress: progress).refs
    }

    /// Like `analyze`, but also surfaces the full per-photo `ImportanceScore`
    /// (quality, isUtility, aesthetics…) that `analyze` folds away, plus a
    /// feature print per photo (computed on the same decoded thumbnail, so the
    /// curation pipeline never fetches/decodes a second time). Keyed by
    /// `PhotoID`; a photo whose thumbnail failed or was cancelled has no
    /// scores/prints entry (and its ref's `importance` stays nil). Curation
    /// consumes these via `CurationAnalyzer.candidates`.
    public static func analyzeWithScores(
        _ refs: [PhotoRef],
        provider: any PhotoProvider,
        maxPixelSize: Int = 256,
        concurrency: Int = 4,
        includePrints: Bool = true,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> (refs: [PhotoRef], scores: [PhotoID: ImportanceScore], prints: [PhotoID: FeaturePrint]) {
        guard !refs.isEmpty else { return (refs, [:], [:]) }
        let total = refs.count
        let limit = max(1, concurrency)
        var scores = [Int: ImportanceScore]()
        var prints = [PhotoID: FeaturePrint]()
        var completed = 0

        await withTaskGroup(of: (Int, ImportanceScore?, FeaturePrint?).self) { group in
            var next = 0
            func submit(_ i: Int) {
                let ref = refs[i]
                group.addTask {
                    if Task.isCancelled { return (i, nil, nil) }
                    guard let image = try? await provider.thumbnail(for: ref, maxPixelSize: maxPixelSize)
                    else { return (i, nil, nil) }
                    if Task.isCancelled { return (i, nil, nil) }
                    return (i, score(image: image),
                            includePrints ? featurePrint(of: image) : nil)
                }
            }
            while next < min(limit, total) { submit(next); next += 1 }
            for await (i, value, print) in group {
                if let value { scores[i] = value }
                if let print { prints[refs[i].id] = print }
                completed += 1
                progress?(completed, total)
                if next < total && !Task.isCancelled { submit(next); next += 1 }
            }
        }

        var result = refs
        var byID = [PhotoID: ImportanceScore]()
        for (i, s) in scores {
            result[i].importance = s.importance
            result[i].salientCenter = s.salientCenter
            byID[refs[i].id] = s
        }
        return (result, byID, prints)
    }

    /// Synchronous Vision feature-print request (Vision.perform blocks);
    /// nil on failure.
    private static func featurePrint(of image: CGImage) -> FeaturePrint? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        return (request.results?.first as? VNFeaturePrintObservation)
            .map(FeaturePrint.init)
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

    /// Returns the saliency score plus the center of the best salient object
    /// (area×confidence winner) in top-left-origin normalized image space.
    /// Vision bounding boxes are bottom-left-origin, so y is flipped to match
    /// the crop `NormRect` convention used by `SlotGeometry.imageDrawRect`.
    private static func saliency(of image: CGImage) -> (score: Double, center: NormPoint?) {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return (0, nil) }
        guard let obs = request.results?.first as? VNSaliencyImageObservation else { return (0, nil) }
        let objects = obs.salientObjects ?? []
        guard let winner = objects.max(by: {
            Double($0.boundingBox.width * $0.boundingBox.height) * Double($0.confidence)
            < Double($1.boundingBox.width * $1.boundingBox.height) * Double($1.confidence)
        }) else { return (0, nil) }
        let bb = winner.boundingBox
        let score = Double(bb.width * bb.height) * Double(winner.confidence)
        let center = NormPoint(x: Double(bb.midX), y: 1 - Double(bb.midY))
        return (min(1.0, score), center)
    }

    private static func aesthetics(of image: CGImage) -> (score: Double?, isUtility: Bool) {
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return (nil, false) }
        guard let obs = request.results?.first else { return (nil, false) }
        return (mapAesthetics(obs.overallScore), obs.isUtility)
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
