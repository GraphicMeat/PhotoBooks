import Foundation

/// One photo offered to the best-N selection algorithm: its quality, when it
/// was taken, and which near-duplicate cluster it belongs to. Pure value type
/// (PhotoBookCore has no Vision dependency) — the impure feature-print
/// clustering lives in PhotoBookImport's `CurationAnalyzer`, which produces
/// these; the pure selection algorithm consumes them here.
public struct CurationCandidate: Equatable, Sendable, Identifiable {
    public var id: PhotoID
    public var quality: Double
    public var captureDate: Date?
    /// 0-based cluster index; singleton photos get their own cluster.
    public var clusterID: Int
    public var isUtility: Bool

    public init(id: PhotoID, quality: Double, captureDate: Date?, clusterID: Int, isUtility: Bool) {
        self.id = id
        self.quality = quality
        self.captureDate = captureDate
        self.clusterID = clusterID
        self.isUtility = isUtility
    }
}
