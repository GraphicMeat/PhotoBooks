/// Pure mapping from a photo's content-importance estimate to a layout
/// "weight" — how much of a page's capacity it consumes. Deterministic, no
/// I/O. nil importance (not analyzed) and the feature-off path both yield
/// weight 1, which makes the Paginator byte-identical to the pre-importance
/// engine.
public enum ImportanceWeight {

    /// At/above this importance a photo becomes a "hero" and takes a page to
    /// itself.
    static let heroThreshold = 0.80

    /// Non-hero photos cap at this weight. A weight-3 photo roughly fills the
    /// ~3-weight page target on its own, so it shares its page with few others.
    /// Reachable non-hero weights are therefore [1...midWeightCap]; the hero
    /// value (maxWeight) is separate, so weights between midWeightCap and
    /// maxWeight are deliberately unoccupied.
    static let midWeightCap = 3

    /// A hero's weight. Equal to the per-page capacity (Paginator.maxPhotosPerPage,
    /// which the Paginator also exposes as maxWeightPerPage) so a hero exactly
    /// fills a page and cannot share it. The coupling is asserted by
    /// ImportanceWeightTests.heroThresholdMapsToPageMax.
    public static let maxWeight = Paginator.maxPhotosPerPage

    /// importance (or nil) → integer weight in [1, maxWeight].
    public static func weight(forImportance importance: Double?) -> Int {
        guard let raw = importance else { return 1 }
        let clamped = min(max(raw, 0.0), 1.0)
        if clamped >= heroThreshold { return maxWeight }
        let scaled = clamped / heroThreshold          // [0, 1)
        return 1 + Int((scaled * Double(midWeightCap - 1)).rounded())
    }
}
