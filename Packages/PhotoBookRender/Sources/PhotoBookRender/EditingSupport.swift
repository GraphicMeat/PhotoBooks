import CoreGraphics
import PhotoBookCore
import SwiftUI

/// Slot interaction callbacks for editing mode (Plan 5). Attached to a
/// `PageView` via `.editing(_:)`; all closures run on the main actor — they
/// mutate the app's editor model.
public struct PageEditingInteractions {
    public var onTapPhotoSlot: @MainActor (UUID) -> Void
    public var onDoubleTapPhotoSlot: @MainActor (UUID) -> Void
    public var onTapTextSlot: @MainActor (UUID) -> Void
    public var onDoubleTapTextSlot: @MainActor (UUID) -> Void
    /// Commit a manual move/resize: final frame for the given photo slot.
    public var onSetPhotoSlotFrame: @MainActor (UUID, NormRect) -> Void
    /// Commit a manual move/resize: final frame for the given text slot.
    public var onSetTextSlotFrame: @MainActor (UUID, NormRect) -> Void

    public init(onTapPhotoSlot: @escaping @MainActor (UUID) -> Void,
                onDoubleTapPhotoSlot: @escaping @MainActor (UUID) -> Void,
                onTapTextSlot: @escaping @MainActor (UUID) -> Void,
                onDoubleTapTextSlot: @escaping @MainActor (UUID) -> Void,
                onSetPhotoSlotFrame: @escaping @MainActor (UUID, NormRect) -> Void,
                onSetTextSlotFrame: @escaping @MainActor (UUID, NormRect) -> Void) {
        self.onTapPhotoSlot = onTapPhotoSlot
        self.onDoubleTapPhotoSlot = onDoubleTapPhotoSlot
        self.onTapTextSlot = onTapTextSlot
        self.onDoubleTapTextSlot = onDoubleTapTextSlot
        self.onSetPhotoSlotFrame = onSetPhotoSlotFrame
        self.onSetTextSlotFrame = onSetTextSlotFrame
    }
}

/// Mini wireframe of a layout candidate: page outline, filled photo-slot
/// rects, line hints for text zones. Drawn with `Canvas` through the same
/// `SlotGeometry` mapping as the real renderer (shared invariant 3) — the
/// template strip renders these as tappable previews.
public struct LayoutWireframeView: View {
    let photoFrames: [NormRect]
    let textFrames: [NormRect]

    public init(candidate: LayoutCandidate) {
        self.photoFrames = candidate.photoSlotFrames
        self.textFrames = candidate.textSlotFrames
    }

    public var body: some View {
        Canvas { context, size in
            let pageRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(pageRect), with: .color(.white))
            context.stroke(Path(pageRect), with: .color(.gray), lineWidth: 1)
            for frame in photoFrames {
                let rect = SlotGeometry.rect(for: frame, in: size).insetBy(dx: 1, dy: 1)
                context.fill(Path(rect), with: .color(.gray.opacity(0.35)))
                context.stroke(Path(rect), with: .color(.gray), lineWidth: 1)
            }
            for frame in textFrames {
                let rect = SlotGeometry.rect(for: frame, in: size)
                for line in 0..<3 {
                    let y = rect.minY + rect.height * (Double(line) + 0.5) / 3.0
                    var path = Path()
                    path.move(to: CGPoint(x: rect.minX + 2, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX - 2, y: y))
                    context.stroke(path, with: .color(.gray.opacity(0.6)), lineWidth: 1)
                }
            }
        }
    }
}

/// Live crop preview for the crop editor: draws the full image positioned so
/// that `crop` fills the view (the same `SlotGeometry.imageDrawRect` math the
/// page renderer uses), clipped to the view bounds.
public struct CroppedPhotoView: View {
    let image: CGImage
    let crop: NormRect

    public init(image: CGImage, crop: NormRect) {
        self.image = image
        self.crop = crop
    }

    public var body: some View {
        GeometryReader { proxy in
            let drawRect = SlotGeometry.imageDrawRect(
                slotRect: CGRect(origin: .zero, size: proxy.size),
                crop: crop, pixelWidth: image.width, pixelHeight: image.height)
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: drawRect.width, height: drawRect.height)
                .position(x: drawRect.midX, y: drawRect.midY)
        }
        .clipped()
    }
}
