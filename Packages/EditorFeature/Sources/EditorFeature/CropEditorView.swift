import CoreGraphics
import EditCore
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SwiftUI

/// Crop/pan editor: the image at the slot's TRUE aspect, drag to pan, pinch
/// (or the +/− buttons, for mouse users) to zoom. All math is `adjustedCrop`
/// (golden-tested, Task 1); the preview is `CroppedPhotoView` (Task 3), so
/// the editor never re-derives drawing math (D4). Done commits through the
/// editor model, which locks the slot.
struct CropEditorView: View {
    let context: CropEditorContext
    let imageStore: any ImageStore

    @Environment(BookEditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var image: CGImage?
    @State private var baseCrop: NormRect
    @State private var dragTranslation: CGSize = .zero
    @State private var magnification: Double = 1
    @State private var editorSize: CGSize = CGSize(width: 300, height: 300)
    @State private var isQuickZoomed = false

    init(context: CropEditorContext, imageStore: any ImageStore) {
        self.context = context
        self.imageStore = imageStore
        // Normalize the stored crop (often the engine default `.full`) to
        // the centered aspect-fill window — the identity property of
        // adjustedCrop (D5). Identity needs no real view size.
        _baseCrop = State(initialValue: adjustedCrop(
            base: context.baseCrop, translation: .zero, zoomDelta: 1,
            photoAspect: context.photoAspect, slotAspect: context.slotAspect,
            viewSize: CGSize(width: 300, height: 300)))
    }

    private func liveCrop(viewSize: CGSize) -> NormRect {
        adjustedCrop(base: baseCrop, translation: dragTranslation, zoomDelta: magnification,
                     photoAspect: context.photoAspect, slotAspect: context.slotAspect,
                     viewSize: viewSize)
    }

    /// Folds in-flight gesture deltas into the base crop and resets them —
    /// called on EVERY gesture end so simultaneous pan+pinch stays exact.
    private func bakeGesture(viewSize: CGSize) {
        baseCrop = liveCrop(viewSize: viewSize)
        dragTranslation = .zero
        magnification = 1
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Drag to position. Double-click to zoom in or out; pinch or use + / − for finer control.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack {
                    Color(white: 0.2)
                    if let image {
                        CroppedPhotoView(image: image, crop: liveCrop(viewSize: proxy.size))
                    } else {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    toggleQuickZoom(at: location, viewSize: proxy.size)
                }
                .gesture(SimultaneousGesture(
                    DragGesture()
                        .onChanged { dragTranslation = $0.translation }
                        .onEnded { _ in bakeGesture(viewSize: proxy.size) },
                    MagnifyGesture()
                        .onChanged { magnification = $0.magnification }
                        .onEnded { _ in bakeGesture(viewSize: proxy.size) }
                ))
                .onAppear { editorSize = proxy.size }
                .onChange(of: proxy.size) { editorSize = $1 }
            }
            .aspectRatio(context.slotAspect, contentMode: .fit)
            .frame(minWidth: 280, minHeight: 200)

            HStack(spacing: 12) {
                Button {
                    baseCrop = adjustedCrop(base: baseCrop, translation: .zero, zoomDelta: 0.8,
                                            photoAspect: context.photoAspect,
                                            slotAspect: context.slotAspect, viewSize: editorSize)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help(Text("Zoom out", bundle: .module))
                .accessibilityIdentifier("crop-editor-zoom-out")
                Button {
                    baseCrop = adjustedCrop(base: baseCrop, translation: .zero, zoomDelta: 1.25,
                                            photoAspect: context.photoAspect,
                                            slotAspect: context.slotAspect, viewSize: editorSize)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help(Text("Zoom in", bundle: .module))
                .accessibilityIdentifier("crop-editor-zoom-in")
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("crop-editor-cancel")
                Button(String(localized: "Done", bundle: .module)) {
                    bakeGesture(viewSize: editorSize)
                    editor.commitCrop(slotID: context.slotID, crop: baseCrop)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help(Text("Apply this crop and lock the frame", bundle: .module))
                .accessibilityIdentifier("crop-editor-done")
            }
        }
        .padding()
        .task {
            image = try? await imageStore.thumbnail(for: context.photoID, maxPixelSize: 2048)
        }
    }

    private func toggleQuickZoom(at location: CGPoint, viewSize: CGSize) {
        bakeGesture(viewSize: viewSize)
        if isQuickZoomed {
            baseCrop = adjustedCrop(base: .full, translation: .zero, zoomDelta: 1,
                                    photoAspect: context.photoAspect,
                                    slotAspect: context.slotAspect, viewSize: viewSize)
            isQuickZoomed = false
            return
        }

        let unitX = min(1, max(0, location.x / max(1, viewSize.width)))
        let unitY = min(1, max(0, location.y / max(1, viewSize.height)))
        let newWidth = baseCrop.width / 2
        let newHeight = baseCrop.height / 2
        let centerX = baseCrop.x + baseCrop.width * unitX
        let centerY = baseCrop.y + baseCrop.height * unitY
        baseCrop = NormRect(
            x: min(1 - newWidth, max(0, centerX - newWidth / 2)),
            y: min(1 - newHeight, max(0, centerY - newHeight / 2)),
            width: newWidth,
            height: newHeight)
        isQuickZoomed = true
    }
}
