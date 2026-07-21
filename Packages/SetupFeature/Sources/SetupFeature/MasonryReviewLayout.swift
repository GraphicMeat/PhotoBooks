import SwiftUI

struct PhotoAspectRatioKey: LayoutValueKey {
    static let defaultValue = 1.0
}

/// Pinterest-style shortest-column layout, matching the book engine's masonry
/// treatment while keeping each thumbnail at its natural aspect ratio.
struct MasonryReviewLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                     cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX,
                                              y: bounds.minY + frame.minY),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let count = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        let columnWidth = (width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = [CGFloat](repeating: 0, count: count)
        var frames: [CGRect] = []
        for subview in subviews {
            let column = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let aspect = max(CGFloat(subview[PhotoAspectRatioKey.self]), 0.2)
            let height = columnWidth / aspect
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
                                 y: heights[column], width: columnWidth, height: height))
            heights[column] += height + spacing
        }
        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }
}
