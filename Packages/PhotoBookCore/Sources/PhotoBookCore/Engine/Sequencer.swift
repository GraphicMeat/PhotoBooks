/// Internal: wraps the analyzer's ordered output and exposes cluster
/// boundaries to the paginator. The order IS the analyzer's order — the
/// sequencer never reorders.
struct Sequencer {
    let photos: [AnalyzedPhoto]

    init(photos: [AnalyzedPhoto]) {
        self.photos = photos
    }

    /// Contiguous ranges of equal `clusterIndex`, in photo order.
    var clusterRanges: [Range<Int>] {
        guard !photos.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var start = 0
        for index in 1..<photos.count
        where photos[index].clusterIndex != photos[index - 1].clusterIndex {
            ranges.append(start..<index)
            start = index
        }
        ranges.append(start..<photos.count)
        return ranges
    }

    /// True when a page split between photos[index − 1] and photos[index]
    /// falls on a cluster boundary (sequence edges always count as
    /// boundaries — there is nothing to keep together across them).
    func isClusterBoundary(_ index: Int) -> Bool {
        if index <= 0 || index >= photos.count { return true }
        return photos[index - 1].clusterIndex != photos[index].clusterIndex
    }
}
