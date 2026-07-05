/// Column-major, zero-crop packing — the "Pinterest/masonry" arrangement and
/// the column counterpart to `JustifiedLayout`. Each photo fills its column's
/// width at its own aspect (so an aspect-fill render shows the whole photo);
/// photos are assigned to the currently-shortest column to balance heights, and
/// the stacked block is uniformly contained to the page height and centered.
/// Pure and deterministic.
enum MasonryLayout {

    /// One box per photo (in input order), sized to the photo's own aspect.
    /// `columns` >= 1; empty `aspects` → []. `gutter` separates columns and the
    /// stacked photos within a column.
    static func boxes(aspects: [Double], content: NormRect,
                      pageAspect: Double, gutter: Double, columns: Int) -> [NormRect] {
        guard !aspects.isEmpty, columns >= 1 else { return [] }
        let cols = min(columns, aspects.count)
        let colWidth = (content.width - Double(cols - 1) * gutter) / Double(cols)

        // Greedy shortest-column packing. `nextY[c]` is the next free y in column
        // c; `count[c]` how many photos it already holds (for the leading gutter).
        var nextY = [Double](repeating: content.y, count: cols)
        var count = [Int](repeating: 0, count: cols)
        var boxes = [NormRect](repeating: .full, count: aspects.count)
        for (i, a) in aspects.enumerated() {
            let h = colWidth * pageAspect / max(a, 1e-9)
            // Shortest column (lowest used height); ties → lowest index.
            var c = 0
            for k in 1..<cols where nextY[k] < nextY[c] - 1e-12 { c = k }
            if count[c] > 0 { nextY[c] += gutter }
            let x = content.x + Double(c) * (colWidth + gutter)
            boxes[i] = NormRect(x: x, y: nextY[c], width: colWidth, height: h)
            nextY[c] += h
            count[c] += 1
        }

        // Contain (never enlarge) the tallest column to the content height, then
        // center the scaled block. Uniform scale preserves aspect (still zero-crop).
        let usedHeight = (nextY.map { $0 - content.y }.max() ?? 0)
        let s = min(1.0, content.height / max(usedHeight, 1e-9))
        let blockW = content.width * s
        let blockH = usedHeight * s
        let ox = content.x + (content.width - blockW) / 2
        let oy = content.y + (content.height - blockH) / 2
        return boxes.map { b in
            NormRect(x: ox + (b.x - content.x) * s,
                     y: oy + (b.y - content.y) * s,
                     width: b.width * s, height: b.height * s)
        }
    }
}
