/// How a photo's pixels are shaped. Square wins inside a 5% tolerance band:
/// |aspectRatio − 1| < 0.05 (matches `PrintPreset.aspectClass` tolerance).
public enum Orientation: String, Codable, Sendable {
    case landscape, portrait, square
}

/// Analyzer output — the ONLY photo representation the layout engine consumes.
/// v2 analyzers (saliency, faces, blur/dupe scores) extend this type without
/// touching the engine.
public struct AnalyzedPhoto: Equatable, Sendable, Identifiable {
    public var ref: PhotoRef
    public var id: PhotoID { ref.id }
    public var orientation: Orientation
    public var clusterIndex: Int           // time-gap cluster; 0-based
    /// Layout weight (page capacity consumed); 1 = normal. Derived from
    /// ref.importance via ImportanceWeight; default 1 keeps the engine
    /// byte-identical when importance is absent.
    public var weight: Int

    public init(ref: PhotoRef, orientation: Orientation, clusterIndex: Int, weight: Int = 1) {
        self.ref = ref
        self.orientation = orientation
        self.clusterIndex = clusterIndex
        self.weight = weight
    }
}
