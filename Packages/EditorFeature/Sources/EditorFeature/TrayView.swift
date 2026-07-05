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
    let unplacedPhotoIDs: [PhotoID]
    let imageStore: any ImageStore
    let hasSelectedSlot: Bool
    let onTapPhoto: @MainActor (PhotoID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(unplacedPhotoIDs.enumerated()), id: \.element) { index, photoID in
                        Button {
                            onTapPhoto(photoID)
                        } label: {
                            TrayThumbnail(photoID: photoID, imageStore: imageStore)
                                .opacity(hasSelectedSlot ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasSelectedSlot)
                        .help(hasSelectedSlot ? "Place this photo in the selected frame"
                                              : "Select a frame on the page first")
                        .accessibilityIdentifier("tray-item-\(index)")
                    }
                }
                .padding(12)
            }
        }
        .accessibilityIdentifier("photo-tray")
    }

    private var hint: String {
        if unplacedPhotoIDs.isEmpty { return "All photos are placed." }
        if hasSelectedSlot { return "Tap a photo to put it in the selected frame." }
        return "Select a frame on the page, then tap a photo here."
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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: photoID) {
            image = try? await imageStore.thumbnail(for: photoID, maxPixelSize: 256)
        }
    }
}
