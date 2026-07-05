import CoreGraphics
import PhotoBookCore
import SwiftUI

// MARK: - Slot content (pure, synchronous)

/// What a photo slot currently shows. Pure data — both the async screen
/// path and the synchronous snapshot path (golden tests, Plan 6 previews)
/// reduce to this before drawing, so they cannot diverge.
enum PhotoSlotDisplayState: Equatable {
    /// Slot has no photo assigned (`photoID == nil`).
    case empty
    /// Thumbnail fetch is in flight.
    case loading
    /// Thumbnail decoded; drawn with `SlotGeometry.imageDrawRect`.
    case loaded(CGImage)
    /// `PhotoRef.isMissing`, the ID has no `PhotoRef`, or the fetch failed.
    case missing
}

/// Draws one photo slot's content at a fixed size. No async, no state —
/// everything it renders is a pure function of its inputs.
struct PhotoSlotContent: View {
    let state: PhotoSlotDisplayState
    let crop: NormRect
    let size: CGSize
    let cornerRadius: Double
    let isHighlighted: Bool
    var isReplaceSource: Bool = false

    var body: some View {
        ZStack {
            switch state {
            case .empty, .loading:
                Color(white: 0.85)
            case .loaded(let image):
                let drawRect = SlotGeometry.imageDrawRect(
                    slotRect: CGRect(origin: .zero, size: size),
                    crop: crop,
                    pixelWidth: image.width,
                    pixelHeight: image.height
                )
                Color(white: 0.85)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: drawRect.width, height: drawRect.height)
                    .position(x: drawRect.midX, y: drawRect.midY)
            case .missing:
                Color(white: 0.8)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: max(12, min(size.width, size.height) * 0.25)))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if isReplaceSource {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            } else if isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 3)
            }
        }
    }
}

/// Draws one text slot's content at a fixed size. Font lookup is by
/// PostScript name (`Font.custom` falls back to the system font when the
/// name is unknown); "" defers to the book style's default font.
struct TextSlotContent: View {
    let text: StyledText
    let defaultFontName: String
    let size: CGSize
    let renderHeight: Double

    var body: some View {
        let points = SlotGeometry.fontPoints(factor: text.pointSizeFactor, renderHeight: renderHeight)
        let fontName = text.fontName.isEmpty ? defaultFontName : text.fontName
        Text(text.string)
            .font(.custom(fontName, fixedSize: points))
            .foregroundStyle(Color(hex: text.colorHex))
            .multilineTextAlignment(Self.textAlignment(text.alignment))
            .frame(width: size.width, height: size.height,
                   alignment: Self.frameAlignment(text.alignment))
            .clipped()
    }

    /// Model alignment → SwiftUI multiline text alignment.
    static func textAlignment(_ alignment: PhotoBookCore.TextAlignment) -> SwiftUI.TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// Model alignment → frame alignment (horizontal; vertically centered).
    static func frameAlignment(_ alignment: PhotoBookCore.TextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

// MARK: - Shared page chrome

/// Lays out one page at a fixed render size: background color, then photo
/// slots, then text slots — content for BOTH injected (async + editing
/// chrome on screen, preloaded plain content in snapshots). All coordinates
/// come from `SlotGeometry`.
struct PageLayoutView<SlotView: View, TextView: View>: View {
    let page: Page
    let style: BookStyle
    let renderSize: CGSize
    @ViewBuilder let photoSlotContent: (PhotoSlot, CGRect, Double) -> SlotView
    @ViewBuilder let textSlotContent: (TextSlot, CGRect) -> TextView

    var body: some View {
        let radius = SlotGeometry.cornerRadius(style: style, in: renderSize)
        ZStack(alignment: .topLeading) {
            Color(hex: page.effectiveBackgroundHex(bookDefault: style.backgroundColorHex))
            ForEach(page.photoSlots) { slot in
                let rect = SlotGeometry.rect(for: slot.frame, in: renderSize)
                photoSlotContent(slot, rect, radius)
                    .position(x: rect.midX, y: rect.midY)
            }
            ForEach(page.textSlots) { slot in
                let rect = SlotGeometry.rect(for: slot.frame, in: renderSize)
                textSlotContent(slot, rect)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: renderSize.width, height: renderSize.height)
    }
}

// MARK: - Async slot loading (screen path)

/// Loads and shows one photo slot's thumbnail. The load task is keyed on
/// photo ID + bucketed pixel size, so scrolling and window resizes reuse
/// in-flight work and the view never reloads for sub-bucket size changes.
struct AsyncPhotoSlotView: View {
    let slot: PhotoSlot
    let ref: PhotoRef?
    let imageStore: any ImageStore
    let size: CGSize
    let cornerRadius: Double
    let isHighlighted: Bool
    var isReplaceSource: Bool = false

    @State private var loadedImage: CGImage?
    @State private var loadFailed = false

    private struct LoadKey: Equatable {
        var photoID: PhotoID?
        var pixelSize: Int
    }

    /// The state to draw. When no image has loaded yet, fall back to a
    /// synchronous cache peek so a reflow (new slot IDs, fresh `@State`) paints
    /// the already-cached thumbnail on first frame instead of a gray placeholder.
    private func displayState(pixelSize: Int) -> PhotoSlotDisplayState {
        guard let photoID = slot.photoID else { return .empty }
        guard let ref, !ref.isMissing, !loadFailed else { return .missing }
        let shownImage = loadedImage
            ?? imageStore.cachedThumbnail(for: photoID, maxPixelSize: pixelSize)
        if let shownImage { return .loaded(shownImage) }
        return .loading
    }

    var body: some View {
        let pixelSize = SlotGeometry.thumbnailPixelSize(for: size)
        PhotoSlotContent(state: displayState(pixelSize: pixelSize), crop: slot.crop, size: size,
                         cornerRadius: cornerRadius, isHighlighted: isHighlighted,
                         isReplaceSource: isReplaceSource)
            .task(id: LoadKey(photoID: slot.photoID, pixelSize: pixelSize)) {
                loadedImage = nil
                loadFailed = false
                guard let photoID = slot.photoID, let ref, !ref.isMissing else { return }
                do {
                    loadedImage = try await imageStore.thumbnail(for: photoID, maxPixelSize: pixelSize)
                } catch is CancellationError {
                    // View went away or the key changed — keep current state.
                } catch {
                    loadFailed = true
                }
            }
    }
}

// MARK: - Editing chrome (Plan 5, additive)

/// Per-slot editing chrome: lock badge, selection ring for text slots,
/// tap/double-tap routing, and the per-slot accessibility identifier.
/// With `nil` interactions it passes content through UNTOUCHED — browsing
/// behavior (and the golden images) stay byte-identical to Plan 4.
struct SlotEditingModifier: ViewModifier {
    enum Kind: String {
        case photo, text
    }

    let slotID: UUID
    let kind: Kind
    let index: Int
    let isLocked: Bool
    let isHighlighted: Bool
    let interactions: PageEditingInteractions?

    func body(content: Content) -> some View {
        if let interactions {
            content
                .overlay {
                    if kind == .text && isHighlighted {
                        Rectangle().stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .gesture(ExclusiveGesture(
                    TapGesture(count: 2).onEnded {
                        switch kind {
                        case .photo: interactions.onDoubleTapPhotoSlot(slotID)
                        case .text: interactions.onDoubleTapTextSlot(slotID)
                        }
                    },
                    TapGesture().onEnded {
                        switch kind {
                        case .photo: interactions.onTapPhotoSlot(slotID)
                        case .text: interactions.onTapTextSlot(slotID)
                        }
                    }
                ))
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("slot-\(kind.rawValue)-\(index)")
        } else {
            content
        }
    }
}

// MARK: - Public views (contract)

/// Renders one book page at its preset's aspect ratio, sized by its
/// container. Photo slots load thumbnails asynchronously through the
/// injected `ImageStore`; `highlightedSlotID` draws an accent border
/// (photo slots) or ring (text slots, editing mode only).
public struct PageView: View {
    let page: Page
    let book: Book
    let preset: PrintPreset
    let imageStore: any ImageStore
    let highlightedSlotID: UUID?
    let replaceSourceSlotID: UUID?
    var interactions: PageEditingInteractions?

    /// Live move/resize preview for the highlighted photo slot (nil when idle).
    @State private var previewFrame: (slotID: UUID, frame: NormRect)?

    public init(page: Page, book: Book, preset: PrintPreset, imageStore: any ImageStore,
                highlightedSlotID: UUID?, replaceSourceSlotID: UUID? = nil) {
        self.page = page
        self.book = book
        self.preset = preset
        self.imageStore = imageStore
        self.highlightedSlotID = highlightedSlotID
        self.replaceSourceSlotID = replaceSourceSlotID
    }

    /// Editing chrome (additive, Plan 5): slot tap/double-tap callbacks, lock
    /// badges, selection ring on text slots, and per-slot accessibility
    /// identifiers (`slot-photo-<index>` / `slot-text-<index>`, page-local
    /// indices). `nil` (the default) renders exactly the Plan 4 browsing
    /// behavior — pixel-tested.
    public func editing(_ interactions: PageEditingInteractions?) -> PageView {
        var copy = self
        copy.interactions = interactions
        return copy
    }

    public var body: some View {
        let refByID = Dictionary(book.photoLibrary.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        GeometryReader { proxy in
            PageLayoutView(page: page, style: book.style, renderSize: proxy.size) { slot, rect, radius in
                let effectiveFrame = (previewFrame?.slotID == slot.id) ? previewFrame!.frame : slot.frame
                let effectiveRect = SlotGeometry.rect(for: effectiveFrame, in: proxy.size)
                AsyncPhotoSlotView(
                    slot: slot,
                    ref: slot.photoID.flatMap { refByID[$0] },
                    imageStore: imageStore,
                    size: effectiveRect.size,
                    cornerRadius: radius,
                    isHighlighted: slot.id == highlightedSlotID,
                    isReplaceSource: slot.id == replaceSourceSlotID
                )
                .modifier(SlotEditingModifier(
                    slotID: slot.id, kind: .photo,
                    index: page.photoSlots.firstIndex(where: { $0.id == slot.id }) ?? 0,
                    isLocked: slot.isLocked,
                    isHighlighted: slot.id == highlightedSlotID,
                    interactions: interactions))
                .anchorPreference(key: SelectedSlotBoundsKey.self, value: .bounds) {
                    slot.id == highlightedSlotID ? $0 : nil
                }
                .offset(x: effectiveRect.midX - rect.midX, y: effectiveRect.midY - rect.midY)
            } textSlotContent: { slot, rect in
                let effectiveFrame = (previewFrame?.slotID == slot.id) ? previewFrame!.frame : slot.frame
                let effectiveRect = SlotGeometry.rect(for: effectiveFrame, in: proxy.size)
                TextSlotContent(text: slot.text,
                                defaultFontName: book.style.defaultFontName,
                                size: effectiveRect.size,
                                renderHeight: Double(proxy.size.height))
                    .modifier(SlotEditingModifier(
                        slotID: slot.id, kind: .text,
                        index: page.textSlots.firstIndex(where: { $0.id == slot.id }) ?? 0,
                        isLocked: slot.isLocked,
                        isHighlighted: slot.id == highlightedSlotID,
                        interactions: interactions))
                    .anchorPreference(key: SelectedSlotBoundsKey.self, value: .bounds) {
                        slot.id == highlightedSlotID ? $0 : nil
                    }
                    .offset(x: effectiveRect.midX - rect.midX, y: effectiveRect.midY - rect.midY)
            }
            .overlay {
                if let interactions,
                   let slot = page.photoSlots.first(where: { $0.id == highlightedSlotID }) {
                    let live = (previewFrame?.slotID == slot.id) ? previewFrame!.frame : slot.frame
                    let aspect = preset.trimSize.aspectRatio      // width / height
                    let margin = book.style.pageMargin
                    // pageMargin is a fraction of the min page dimension;
                    // convert to a normalized inset per axis.
                    let insetX = margin * min(1.0, 1.0 / aspect)
                    let insetY = margin * min(1.0, aspect)
                    SlotManipulationHandles(
                        slotID: slot.id,
                        frame: live,
                        renderSize: proxy.size,
                        pageInsetX: insetX,
                        pageInsetY: insetY,
                        neighbors: page.photoSlots.filter { $0.id != slot.id }.map(\.frame),
                        onPreview: { newFrame in
                            if let newFrame { previewFrame = (slot.id, newFrame) }
                            else { previewFrame = nil }
                        },
                        onCommit: { finalFrame in
                            previewFrame = nil
                            interactions.onSetPhotoSlotFrame(slot.id, finalFrame)
                        }
                    )
                }
            }
            .overlay {
                if let interactions,
                   let slot = page.textSlots.first(where: { $0.id == highlightedSlotID }) {
                    let live = (previewFrame?.slotID == slot.id) ? previewFrame!.frame : slot.frame
                    let aspect = preset.trimSize.aspectRatio      // width / height
                    let margin = book.style.pageMargin
                    // pageMargin is a fraction of the min page dimension;
                    // convert to a normalized inset per axis.
                    let insetX = margin * min(1.0, 1.0 / aspect)
                    let insetY = margin * min(1.0, aspect)
                    let neighbors = page.photoSlots.map(\.frame)
                        + page.textSlots.filter { $0.id != slot.id }.map(\.frame)
                    TextSlotManipulationHandles(
                        slotID: slot.id,
                        frame: live,
                        renderSize: proxy.size,
                        pageInsetX: insetX,
                        pageInsetY: insetY,
                        neighbors: neighbors,
                        onPreview: { newFrame in
                            if let newFrame { previewFrame = (slot.id, newFrame) }
                            else { previewFrame = nil }
                        },
                        onCommit: { finalFrame in
                            previewFrame = nil
                            interactions.onSetTextSlotFrame(slot.id, finalFrame)
                        }
                    )
                }
            }
        }
        .aspectRatio(preset.trimSize.aspectRatio, contentMode: .fit)
    }
}

/// Two facing pages with a spine gap. `nil` page = blank (page-colored)
/// placeholder, so single-page spreads (cover, odd tail) keep their shape.
public struct SpreadView: View {
    let leftPage: Page?
    let rightPage: Page?
    let book: Book
    let preset: PrintPreset
    let imageStore: any ImageStore

    /// Spine gap between facing pages, in points.
    static let spineGap: CGFloat = 8

    public init(leftPage: Page?, rightPage: Page?, book: Book, preset: PrintPreset,
                imageStore: any ImageStore) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.book = book
        self.preset = preset
        self.imageStore = imageStore
    }

    public var body: some View {
        HStack(spacing: Self.spineGap) {
            pageOrBlank(leftPage)
            pageOrBlank(rightPage)
        }
    }

    @ViewBuilder
    private func pageOrBlank(_ page: Page?) -> some View {
        if let page {
            PageView(page: page, book: book, preset: preset, imageStore: imageStore,
                     highlightedSlotID: nil)
        } else {
            Color(hex: book.style.backgroundColorHex)
                .opacity(0.5)
                .aspectRatio(preset.trimSize.aspectRatio, contentMode: .fit)
        }
    }
}

// MARK: - Synchronous snapshot (golden tests, Plan 6 previews)

/// Renders a page synchronously from preloaded images — no tasks, no state.
/// `ImageRenderer` cannot pump `.task` modifiers, so golden tests prefetch
/// thumbnails from an `ImageStore` and hand them in here. Uses the same
/// `PageLayoutView`/`PhotoSlotContent`/`SlotGeometry` as `PageView`, so a
/// golden match here pins the screen renderer's layout math too. Editing
/// chrome never appears here — snapshots are print-truth.
struct PageSnapshotView: View {
    let page: Page
    let book: Book
    let renderSize: CGSize
    let images: [PhotoID: CGImage]

    var body: some View {
        PageLayoutView(page: page, style: book.style, renderSize: renderSize) { slot, rect, radius in
            PhotoSlotContent(state: displayState(for: slot), crop: slot.crop, size: rect.size,
                             cornerRadius: radius, isHighlighted: false)
        } textSlotContent: { slot, rect in
            TextSlotContent(text: slot.text,
                            defaultFontName: book.style.defaultFontName,
                            size: rect.size,
                            renderHeight: Double(renderSize.height))
        }
    }

    private func displayState(for slot: PhotoSlot) -> PhotoSlotDisplayState {
        guard let photoID = slot.photoID else { return .empty }
        let ref = book.photoLibrary.first { $0.id == photoID }
        guard let ref, !ref.isMissing else { return .missing }
        guard let image = images[photoID] else { return .missing }
        return .loaded(image)
    }
}
