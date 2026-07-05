/// Justified, zero-crop packing — the "Google Photos" gallery arrangement.
///
/// Each photo's slot is sized to the photo's OWN aspect ratio, so an
/// aspect-fill render shows the whole photo with no zoom and no crop. Photos
/// are packed into rows that fill the content width; the stacked rows are then
/// contained (never enlarged past the width) and centered in the content rect,
/// so the page is filled with whole photos and never with cropped ones.
///
/// Pure and deterministic: no RNG, no I/O. The same inputs always yield the
/// same boxes, and the provider serializes them so reopening never re-lays out.
enum JustifiedLayout {

    /// One candidate arrangement plus how well its stacked rows fill the
    /// content height (smaller error = tighter fill, smaller margins).
    struct Arrangement {
        var boxes: [NormRect]
        var fillError: Double
        var rows: Int
    }

    /// Slots whose on-page aspect equals each photo's aspect, packed to fill
    /// the content rect with the row count that fills its height best.
    static func boxes(aspects: [Double], content: NormRect,
                      pageAspect: Double, gutter: Double) -> [NormRect] {
        arrangements(aspects: aspects, content: content,
                     pageAspect: pageAspect, gutter: gutter).first?.boxes ?? [content]
    }

    /// Every viable row-count arrangement, best fill first. The provider offers
    /// the top few as competing candidates (and alternatives-strip options).
    static func arrangements(aspects: [Double], content: NormRect,
                             pageAspect: Double, gutter: Double) -> [Arrangement] {
        guard !aspects.isEmpty else { return [] }
        // Normalized slot aspect (width/height in page space) that renders the
        // photo undistorted: photoAspect / pageAspect. Guarded away from zero.
        let r = aspects.map { max(0.05, $0 / max(pageAspect, 0.0001)) }
        let n = r.count

        var result: [Arrangement] = []
        for rows in 1...n {
            let (boxes, usedHeight) = build(r, rows: rows, content: content, gutter: gutter)
            guard !boxes.isEmpty else { continue }
            // Contain (never enlarge past the width) and center in the content rect.
            let s = min(1.0, content.height / max(usedHeight, 1e-9))
            let blockW = content.width * s
            let blockH = usedHeight * s
            let ox = content.x + (content.width - blockW) / 2
            let oy = content.y + (content.height - blockH) / 2
            let placed = boxes.map { b -> NormRect in
                NormRect(x: ox + (b.x - content.x) * s,
                         y: oy + (b.y - content.y) * s,
                         width: b.width * s, height: b.height * s)
            }
            result.append(Arrangement(boxes: placed,
                                      fillError: abs(usedHeight - content.height),
                                      rows: rows))
        }
        // Best fill first; ties broken by fewer rows for a calmer page.
        return result.sorted { a, b in
            if abs(a.fillError - b.fillError) > 1e-9 { return a.fillError < b.fillError }
            return a.rows < b.rows
        }
    }

    /// Boxes filling the content WIDTH in `rows` justified rows (pre-contain),
    /// plus the total stacked height. Boxes are in content space, rows stacked
    /// from `content.y` downward.
    private static func build(_ r: [Double], rows: Int, content: NormRect,
                              gutter: Double) -> (boxes: [NormRect], usedHeight: Double) {
        let groups = partition(r, into: rows)
        var boxes = [NormRect](repeating: .full, count: r.count)
        var y = content.y
        for (gi, group) in groups.enumerated() {
            let aspectSum = group.reduce(0.0) { $0 + r[$1] }
            let gutters = Double(group.count - 1) * gutter
            let rowHeight = (content.width - gutters) / max(aspectSum, 1e-9)
            var x = content.x
            for idx in group {
                let w = r[idx] * rowHeight
                boxes[idx] = NormRect(x: x, y: y, width: w, height: rowHeight)
                x += w + gutter
            }
            y += rowHeight
            if gi < groups.count - 1 { y += gutter }
        }
        return (boxes, y - content.y)
    }

    /// Split `r`'s indices into exactly `rows` contiguous, non-empty groups,
    /// balanced so each row's aspect-sum is near the average (keeps row heights
    /// even). Deterministic greedy with a guard that always leaves enough
    /// photos for the remaining rows.
    private static func partition(_ r: [Double], into rows: Int) -> [[Int]] {
        let n = r.count
        guard rows > 1, rows <= n else { return [Array(0..<n)] }
        let target = r.reduce(0, +) / Double(rows)
        var groups: [[Int]] = []
        var current: [Int] = []
        var currentSum = 0.0
        for i in 0..<n {
            current.append(i)
            currentSum += r[i]
            let remainingPhotos = n - i - 1
            let rowsStillNeeded = rows - groups.count - 1   // after closing this row
            // Must close now if the rest exactly fills the remaining rows; may
            // close early once this row has reached the average aspect-sum.
            let mustClose = remainingPhotos <= rowsStillNeeded
            let mayClose = currentSum >= target
            if groups.count < rows - 1, mustClose || mayClose {
                groups.append(current)
                current = []
                currentSum = 0
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
