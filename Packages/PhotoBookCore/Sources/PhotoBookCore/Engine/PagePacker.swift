/// Builds page groups from the analyzed photo sequence, filling voids by pulling
/// the photo that best fills the current layout (portrait or landscape, chosen
/// by `coverage`). A page grows to at most `maxFillPhotos`, and only while it is
/// under `targetCoverage`; fillers come from the page's own event first, but when
/// that event is exhausted and the page is still under `targetCoverage`, fillers
/// cross into the next event to fill the void. Heroes (a single importance-
/// weighted photo that fills a page) and panoramas stay solo. Pure and
/// deterministic given a deterministic `coverage` closure.
enum PagePacker {

    static let targetCoverage = 0.80
    static let maxFillPhotos = 8
    /// A normal page keeps pulling in-event photos until it holds at least this
    /// many, before the coverage stop applies — otherwise a single landscape
    /// (which aspect-fills ~94% of a page) reads as "full" and strands photos on
    /// lonely 1-photo pages. Heroes/panoramas are unaffected: they skip the
    /// growth loop and stay solo.
    static let minFillPhotos = 3

    /// Page groups as photo-index lists (order = placement order).
    static func pack(photos: [AnalyzedPhoto],
                     coverage: ([AnalyzedPhoto]) -> Double) -> [[Int]] {
        var remaining = Array(0..<photos.count)
        var pages: [[Int]] = []
        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var page = [first]
            if !isSolo(first, photos) {
                let cluster = photos[first].clusterIndex
                while page.count < maxFillPhotos {
                    let cov = coverage(page.map { photos[$0] })
                    // Don't close the page if doing so would strand a sub-min
                    // tail of this event on a lonely page — absorb it instead.
                    let inClusterLeft = remaining.lazy.filter {
                        photos[$0].clusterIndex == cluster && !isSolo($0, photos)
                    }.count
                    let wouldStrand = inClusterLeft > 0 && inClusterLeft < minFillPhotos
                    if cov >= targetCoverage && page.count >= minFillPhotos && !wouldStrand { break }
                    guard let pick = chooseFiller(page: page, remaining: remaining,
                                                  photos: photos, cluster: cluster,
                                                  allowCross: cov < targetCoverage,
                                                  coverage: coverage) else { break }
                    remaining.removeAll { $0 == pick }
                    page.append(pick)
                }
            }
            pages.append(page)
        }
        return pages
    }

    private static func isSolo(_ i: Int, _ photos: [AnalyzedPhoto]) -> Bool {
        photos[i].weight >= Paginator.maxWeightPerPage
            || photos[i].ref.aspectRatio >= BookEngine.panoramaAspectThreshold
    }

    private static func chooseFiller(page: [Int], remaining: [Int],
                                     photos: [AnalyzedPhoto], cluster: Int,
                                     allowCross: Bool,
                                     coverage: ([AnalyzedPhoto]) -> Double) -> Int? {
        let inCluster = remaining.filter {
            photos[$0].clusterIndex == cluster && !isSolo($0, photos)
        }
        if !inCluster.isEmpty {
            var candidates: Set<Int> = []
            for o in [Orientation.portrait, .landscape, .square] {
                if let c = inCluster.first(where: { photos[$0].orientation == o }) { candidates.insert(c) }
            }
            if let n = inCluster.first { candidates.insert(n) }
            var best: Int? = nil
            var bestCov = -1.0
            for c in candidates.sorted() {
                let cov = coverage((page + [c]).map { photos[$0] })
                if cov > bestCov + 1e-9 { bestCov = cov; best = c }
            }
            return best
        }
        if allowCross {
            return remaining.first { !isSolo($0, photos) }
        }
        return nil
    }
}
