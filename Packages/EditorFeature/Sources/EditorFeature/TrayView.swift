import CoreGraphics
import EditCore
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SwiftUI

/// The photo tray: every library photo not placed in any slot, in stable
/// library order. Presentational (D11): values + closures in. The browser
/// shows it as a trailing inspector (macOS/iPad) or a bottom sheet with
/// detents (iPhone — D14).
struct TrayView: View {
    let unplacedPhotos: [PhotoRef]
    let imageStore: any ImageStore
    let hasSelectedSlot: Bool
    let onTapPhoto: @MainActor (PhotoID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(String(localized: "Available Photos", bundle: .module), systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                    Spacer()
                    Text("\(unplacedPhotos.count) available", bundle: .module)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Divider()
            ScrollView {
                TrayMasonryLayout(minimumColumnWidth: 82, spacing: 8) {
                    ForEach(Array(unplacedPhotos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            onTapPhoto(photo.id)
                        } label: {
                            TrayThumbnail(photoID: photo.id, imageStore: imageStore)
                                .opacity(hasSelectedSlot ? 1 : 0.6)
                        }
                        .layoutValue(key: TrayPhotoAspectRatioKey.self,
                                     value: photo.aspectRatio)
                        .buttonStyle(.plain)
                        .disabled(!hasSelectedSlot)
                        .help(hasSelectedSlot ? Text("Use this photo in the selected frame", bundle: .module)
                                              : Text("Select a frame on the page first", bundle: .module))
                        .accessibilityIdentifier("tray-item-\(index)")
                    }
                }
                .padding(12)
            }
        }
        .accessibilityIdentifier("photo-tray")
    }

    private var hint: String {
        if unplacedPhotos.isEmpty {
            return String(localized: "All available photos are in the book.", bundle: .module)
        }
        if hasSelectedSlot {
            return String(localized: "Choose a photo to replace the selected image or fill its frame.", bundle: .module)
        }
        return String(localized: "These include photos left out of the original selection. Select a frame to use one.", bundle: .module)
    }
}

struct TrayThumbnail: View {
    let photoID: PhotoID
    let imageStore: any ImageStore

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color(white: 0.85)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: photoID) {
            image = try? await imageStore.thumbnail(for: photoID, maxPixelSize: 256)
        }
    }
}

private struct TrayPhotoAspectRatioKey: LayoutValueKey {
    static let defaultValue = 1.0
}

/// Shortest-column masonry layout. Every item receives an explicit frame
/// derived from its source aspect ratio, so portrait and landscape thumbnails
/// keep their natural proportions and adjacent columns never overlap.
private struct TrayMasonryLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        // Custom Layout can be measured first with an infinite/unspecified
        // width. Never convert that proposal to Int in `arrangement`.
        let width = usableWidth(proposal.width)
        let result = arrangement(width: width, subviews: subviews)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: usableWidth(bounds.width), subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX,
                                              y: bounds.minY + frame.minY),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews)
        -> (frames: [CGRect], height: CGFloat) {
        let denominator = max(1, minimumColumnWidth + spacing)
        let proposedColumns = max(1, Int(((width + spacing) / denominator).rounded(.down)))
        // There is no benefit in creating more columns than items, and the
        // cap also prevents pathological allocations from extreme proposals.
        let columnCount = min(max(1, subviews.count), proposedColumns)
        let columnWidth = max(1, (width - CGFloat(columnCount - 1) * spacing)
                                  / CGFloat(columnCount))
        var heights = [CGFloat](repeating: 0, count: columnCount)
        var frames: [CGRect] = []

        for subview in subviews {
            let column = heights.enumerated().min { lhs, rhs in
                lhs.element == rhs.element ? lhs.offset < rhs.offset : lhs.element < rhs.element
            }?.offset ?? 0
            let proposedAspect = CGFloat(subview[TrayPhotoAspectRatioKey.self])
            let aspect = proposedAspect.isFinite && proposedAspect > 0
                ? min(4, max(0.25, proposedAspect)) : 1
            let itemHeight = columnWidth / aspect
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
                                 y: heights[column], width: columnWidth, height: itemHeight))
            heights[column] += itemHeight + spacing
        }

        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }

    private func usableWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0 else {
            return max(1, minimumColumnWidth)
        }
        return proposed
    }
}
