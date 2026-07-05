/// Uniform grid packing — equal cells in `columns` columns and ceil(count/columns)
/// rows. Cells in a full row are identical; a partial last row's cells widen to
/// fill the width so there are no empty gaps. Cells have a fixed aspect that
/// generally differs from the photo, so the renderer center-crops via aspect-fill
/// (a deliberate "tidy grid" look). Pure and deterministic.
enum GridLayout {

    /// `count` frames, row-major. `columns` >= 1; `count` <= 0 → [].
    static func boxes(count: Int, content: NormRect, gutter: Double, columns: Int) -> [NormRect] {
        guard count > 0, columns >= 1 else { return [] }
        let cols = min(columns, count)
        let rows = (count + cols - 1) / cols
        let rowHeight = (content.height - Double(rows - 1) * gutter) / Double(rows)

        var frames: [NormRect] = []
        frames.reserveCapacity(count)
        var placed = 0
        for r in 0..<rows {
            let cellsInRow = min(cols, count - placed)
            let cellWidth = (content.width - Double(cellsInRow - 1) * gutter) / Double(cellsInRow)
            let y = content.y + Double(r) * (rowHeight + gutter)
            for k in 0..<cellsInRow {
                let x = content.x + Double(k) * (cellWidth + gutter)
                frames.append(NormRect(x: x, y: y, width: cellWidth, height: rowHeight))
            }
            placed += cellsInRow
        }
        return frames
    }
}
