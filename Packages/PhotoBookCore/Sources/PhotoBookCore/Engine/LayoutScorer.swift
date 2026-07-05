import Foundation

public struct ScoredCandidate: Sendable {
    public var candidate: LayoutCandidate
    public var score: Double                    // higher = better

    public init(candidate: LayoutCandidate, score: Double) {
        self.candidate = candidate
        self.score = score
    }
}

/// Provider-blind candidate scoring. Every component maps to 0...1 and the
/// weights sum to 1, so the total score is also 0...1.
public struct LayoutScorer: Sendable {

    /// Crop loss is the most visible layout defect (chopped heads, missing
    /// edges) — orientation fit dominates the score.
    static let orientationWeight = 0.40
    /// The four secondary concerns weigh equally; together they can outvote
    /// orientation (0.60 vs 0.40) only when a candidate fails most of them.
    static let whitespaceWeight = 0.15
    static let symmetryWeight = 0.15
    static let varietyWeight = 0.15
    static let textZoneWeight = 0.15

    /// Classic album pages keep ~18% of the page as whitespace (the standard
    /// style's margins + gutters land there: 1 − 0.9 × 0.9 ≈ 0.19). Deviation
    /// in either direction — cramped or sparse — is penalized linearly,
    /// reaching zero at ±0.5.
    static let targetWhitespace = 0.18

    public init() {}

    public func score(_ candidate: LayoutCandidate, photos: [AnalyzedPhoto],
                      context: LayoutContext, previousPage: Page?) -> Double {
        Self.orientationWeight * orientationFit(candidate, photos: photos, context: context)
            + Self.whitespaceWeight * whitespaceBalance(candidate)
            + Self.symmetryWeight * visualWeightSymmetry(candidate)
            + Self.varietyWeight * adjacencyVariety(candidate, previousPage: previousPage)
            + Self.textZoneWeight * textZoneAvailability(candidate, context: context)
    }

    /// Slot/photo aspects beyond ±0.05 of square read as landscape / portrait;
    /// inside the band they're square (flexible). Matches PhotoAnalyzer.
    static let squareAspectTolerance = 0.05
    /// A landscape photo in a portrait slot (or vice versa) is the defect the
    /// user never wants. Scaling its fit by this factor makes any such
    /// candidate lose decisively to a correctly-oriented one.
    static let oppositeOrientationPenalty = 0.2

    /// Mean visible fraction when each photo aspect-fills its slot. A photo
    /// of aspect p in a slot of true aspect s shows min(p,s)/max(p,s) of its
    /// pixels; the rest is crop loss. A photo placed in an opposite-orientation
    /// slot is additionally penalized so such layouts never win.
    private func orientationFit(_ candidate: LayoutCandidate, photos: [AnalyzedPhoto],
                                context: LayoutContext) -> Double {
        guard !candidate.photoSlotFrames.isEmpty,
              candidate.photoSlotFrames.count == photos.count else { return 0 }
        var total = 0.0
        for (frame, photo) in zip(candidate.photoSlotFrames, photos) {
            let slotAspect = frame.aspectRatio * context.pageSize.aspectRatio
            let photoAspect = photo.ref.aspectRatio
            var fit = min(slotAspect, photoAspect) / max(slotAspect, photoAspect)
            if Self.areOppositeOrientation(slotAspect, photoAspect) {
                fit *= Self.oppositeOrientationPenalty
            }
            total += fit
        }
        return total / Double(photos.count)
    }

    /// True when one aspect is clearly landscape and the other clearly
    /// portrait (square on either side is compatible with both).
    static func areOppositeOrientation(_ a: Double, _ b: Double) -> Bool {
        let hi = 1 + squareAspectTolerance
        let lo = 1 - squareAspectTolerance
        return (a > hi && b < lo) || (a < lo && b > hi)
    }

    /// 1 at exactly the target whitespace fraction, falling linearly to 0 at
    /// a deviation of 0.5. Text zones are intentionally NOT counted as
    /// coverage — they read as structured whitespace.
    private func whitespaceBalance(_ candidate: LayoutCandidate) -> Double {
        let covered = candidate.photoSlotFrames.reduce(0.0) { $0 + $1.width * $1.height }
        let whitespace = max(0, 1 - covered)
        return max(0, 1 - abs(whitespace - Self.targetWhitespace) / 0.5)
    }

    /// Area-weighted centroid of the photo slots vs the page center. Centered
    /// mass scores 1; the score falls linearly and hits 0 when the centroid
    /// is half a page away.
    private func visualWeightSymmetry(_ candidate: LayoutCandidate) -> Double {
        var totalArea = 0.0
        var weightedX = 0.0
        var weightedY = 0.0
        for frame in candidate.photoSlotFrames {
            let area = frame.width * frame.height
            totalArea += area
            weightedX += area * (frame.x + frame.width / 2)
            weightedY += area * (frame.y + frame.height / 2)
        }
        guard totalArea > 0 else { return 0 }
        let dx = weightedX / totalArea - 0.5
        let dy = weightedY / totalArea - 0.5
        let distance = (dx * dx + dy * dy).squareRoot()
        return max(0, 1 - 2 * distance)
    }

    /// 0 when the candidate repeats the previous page's shape signature
    /// (same slot count, same frames up to 0.01), 1 otherwise.
    private func adjacencyVariety(_ candidate: LayoutCandidate, previousPage: Page?) -> Double {
        guard let previous = previousPage else { return 1 }
        let previousSignature = Self.shapeSignature(previous.photoSlots.map(\.frame))
        let candidateSignature = Self.shapeSignature(candidate.photoSlotFrames)
        return previousSignature == candidateSignature ? 0 : 1
    }

    /// 1 when the page's text needs are met (or there are none), 0 when a
    /// text zone is required but the candidate has none.
    private func textZoneAvailability(_ candidate: LayoutCandidate,
                                      context: LayoutContext) -> Double {
        guard context.needsTextZone else { return 1 }
        return candidate.textSlotFrames.isEmpty ? 0 : 1
    }

    /// Order-independent shape fingerprint: slot count + frames rounded to
    /// two decimals, sorted. Two layouts that differ by less than 1% of the
    /// page in every coordinate count as "the same shape".
    static func shapeSignature(_ frames: [NormRect]) -> String {
        let parts = frames
            .map { String(format: "%.2f,%.2f,%.2f,%.2f", $0.x, $0.y, $0.width, $0.height) }
            .sorted()
        return "\(frames.count)|" + parts.joined(separator: ";")
    }
}
