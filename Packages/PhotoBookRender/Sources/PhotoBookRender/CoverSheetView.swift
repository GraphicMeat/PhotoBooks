import PhotoBookCore
import SwiftUI

/// The full cover sheet as seen in the editor: back cover | spine (title) |
/// front cover, sized in true proportion via `CoverSheetGeometry`. The front
/// is injected (so it stays the editable `PageView`); the back panel becomes
/// editable too once `interactions` are supplied, and the spine becomes a
/// button when `onEditTitle` is. With all three omitted the sheet is the
/// read-only preview the thumbnail row draws.
public struct CoverSheetView<Front: View>: View {
    let backPage: Page?
    let book: Book
    let preset: PrintPreset
    let imageStore: any ImageStore
    /// Editing chrome for the back cover. nil → read-only preview.
    var interactions: PageEditingInteractions?
    var highlightedSlotID: UUID?
    var replaceSourceSlotID: UUID?
    /// Opens the book-title editor from the spine. nil → the spine is inert.
    var onEditTitle: (@MainActor () -> Void)?
    /// Tooltip for the spine button; supplied by the caller so the localized
    /// string stays in the feature package that owns the catalog.
    var editTitleHelp: String = ""
    @ViewBuilder let front: () -> Front

    /// Hover highlight on the spine — without it a thin, unlabeled bar gives
    /// no hint that it is the way to rename the book.
    @State private var spineHovered = false

    public init(backPage: Page?, book: Book, preset: PrintPreset,
                imageStore: any ImageStore,
                interactions: PageEditingInteractions? = nil,
                highlightedSlotID: UUID? = nil,
                replaceSourceSlotID: UUID? = nil,
                onEditTitle: (@MainActor () -> Void)? = nil,
                editTitleHelp: String = "",
                @ViewBuilder front: @escaping () -> Front) {
        self.backPage = backPage
        self.book = book
        self.preset = preset
        self.imageStore = imageStore
        self.interactions = interactions
        self.highlightedSlotID = highlightedSlotID
        self.replaceSourceSlotID = replaceSourceSlotID
        self.onEditTitle = onEditTitle
        self.editTitleHelp = editTitleHelp
        self.front = front
    }

    private var standardPageCount: Int {
        book.pages.count(where: { $0.role == .standard })
    }

    /// Same spine-width contract the PDF exporter uses, so the on-screen spine
    /// matches the printed one exactly (single source of truth).
    private var spineInches: Double {
        ExportPlan.spineWidthInches(preset: preset, standardPageCount: standardPageCount)
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = CoverSheetGeometry.layout(available: proxy.size,
                                                   trimSize: preset.trimSize,
                                                   spineInches: spineInches)
            HStack(spacing: 0) {
                backPanel
                    .frame(width: layout.back.width, height: layout.back.height)
                spineBar(width: layout.spine.width, height: layout.spine.height)
                front()
                    .frame(width: layout.front.width, height: layout.front.height)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // `.contain` first: a bare `accessibilityIdentifier` on a container
        // OVERWRITES every descendant's identifier — that is what used to hide
        // the spine, the back cover and the slots from the accessibility tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cover-sheet")
    }

    @ViewBuilder
    private var backPanel: some View {
        if let backPage {
            PageView(page: backPage, book: book, preset: preset,
                     imageStore: imageStore, highlightedSlotID: highlightedSlotID,
                     replaceSourceSlotID: replaceSourceSlotID)
                .editing(interactions)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cover-back")
        } else {
            Color(hex: book.style.backgroundColorHex)
                .aspectRatio(preset.trimSize.aspectRatio, contentMode: .fit)
                .accessibilityIdentifier("cover-back")
        }
    }

    /// The spine. When editable, an overlaid transparent button carries the
    /// click — kept a SIBLING of the title text so the title stays its own
    /// accessibility element instead of being folded into the button.
    private func spineBar(width: CGFloat, height: CGFloat) -> some View {
        spineContent(width: width, height: height)
            .overlay {
                if let onEditTitle {
                    Button(action: onEditTitle) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .overlay {
                                if spineHovered {
                                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .onHover { spineHovered = $0 }
                    .help(editTitleHelp)
                    .accessibilityIdentifier("cover-spine-edit")
                }
            }
    }

    /// The title, in the SAME resolved style the exported cover prints
    /// (`ExportPlan.spineText`) — the sheet's height is the on-screen render
    /// height, so the model's size factor lands at the printed proportion.
    private func spineContent(width: CGFloat, height: CGFloat) -> some View {
        let text = ExportPlan.spineText(for: book, preset: preset)
        let fontName = text.fontName.isEmpty ? book.style.defaultFontName : text.fontName
        let points = max(1, SlotGeometry.fontPoints(factor: text.pointSizeFactor,
                                                    renderHeight: Double(height)))
        return ZStack {
            Color(hex: book.style.backgroundColorHex)
            Text(text.string)
                .font(.custom(fontName, fixedSize: points))
                .foregroundStyle(Color(hex: text.colorHex))
                .lineLimit(1)
                .fixedSize()
                // Pre-rotation frame spans the spine length, so its alignment
                // is the alignment ALONG the spine: leading = top, after the
                // clockwise turn below.
                .frame(width: height, height: width,
                       alignment: TextSlotContent.frameAlignment(text.alignment))
                .rotationEffect(.degrees(90))          // top-to-bottom (US spine convention)
                .accessibilityIdentifier("cover-spine-title")
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
