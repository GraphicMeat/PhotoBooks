import Foundation

/// v1 analysis pipeline: chronological ordering, time-gap clustering, and
/// orientation classification. Pure and deterministic — no I/O, no clock.
public enum PhotoAnalyzer {

    /// A gap of MORE than 3 hours between consecutive capture dates starts a
    /// new cluster. Three hours separates "same outing" from "next event"
    /// (morning hike vs evening dinner) without splitting long lunches.
    static let clusterGapSeconds: TimeInterval = 3 * 60 * 60

    /// |aspectRatio − 1| < 0.05 → square. Matches `PrintPreset.aspectClass`.
    static let squareTolerance = 0.05

    /// Sorts chronologically by `captureDate` (stable: equal dates keep their
    /// library order). Photos with nil dates keep their library order and go
    /// to the END of the sequence, forming their own trailing cluster.
    public static func analyze(_ photos: [PhotoRef]) -> [AnalyzedPhoto] {
        let indexed = Array(photos.enumerated())
        let dated = indexed
            .filter { $0.element.captureDate != nil }
            .sorted { a, b in
                let dateA = a.element.captureDate!
                let dateB = b.element.captureDate!
                if dateA != dateB { return dateA < dateB }
                return a.offset < b.offset             // stable tie-break: library order
            }
        let undated = indexed.filter { $0.element.captureDate == nil }
        let ordered = dated.map(\.element) + undated.map(\.element)

        var result: [AnalyzedPhoto] = []
        var clusterIndex = 0
        var previousDate: Date?
        for (position, ref) in ordered.enumerated() {
            if position > 0 {
                if let previous = previousDate, let current = ref.captureDate {
                    if current.timeIntervalSince(previous) > clusterGapSeconds {
                        clusterIndex += 1
                    }
                } else if previousDate != nil && ref.captureDate == nil {
                    // First undated photo after the dated run: new trailing
                    // cluster. Consecutive undated photos then share it.
                    clusterIndex += 1
                }
            }
            result.append(AnalyzedPhoto(ref: ref,
                                        orientation: orientation(of: ref),
                                        clusterIndex: clusterIndex,
                                        weight: ref.userWeight.map { min(max($0, 1), ImportanceWeight.maxWeight) }
                                            ?? ImportanceWeight.weight(forImportance: ref.importance)))
            previousDate = ref.captureDate
        }
        return result
    }

    static func orientation(of ref: PhotoRef) -> Orientation {
        let aspect = ref.aspectRatio
        if abs(aspect - 1) < squareTolerance { return .square }
        return aspect > 1 ? .landscape : .portrait
    }
}
