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
            Text("Drag to pan. Pinch or use + / − to zoom.")
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
                .help("Zoom out")
                .accessibilityIdentifier("crop-editor-zoom-out")
                Button {
                    baseCrop = adjustedCrop(base: baseCrop, translation: .zero, zoomDelta: 1.25,
                                            photoAspect: context.photoAspect,
                                            slotAspect: context.slotAspect, viewSize: editorSize)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")
                .accessibilityIdentifier("crop-editor-zoom-in")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("crop-editor-cancel")
                Button("Done") {
                    bakeGesture(viewSize: editorSize)
                    editor.commitCrop(slotID: context.slotID, crop: baseCrop)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help("Apply this crop and lock the frame")
                .accessibilityIdentifier("crop-editor-done")
            }
        }
        .padding()
        .task {
            image = try? await imageStore.thumbnail(for: context.photoID, maxPixelSize: 2048)
        }
    }
}
