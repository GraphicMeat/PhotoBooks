import AppSupport
import EditCore
import ExportFeature
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SetupFeature
import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum EditorZoomMode: Equatable {
    case fitSpread
    case percentage(Int)
    case printSize
}

private extension EditorZoomMode {
    var percentageValue: Int? {
        if case .percentage(let value) = self { return value }
        return nil
    }
}

/// Presentation-only workspace behind the book. "Transparent" uses the
/// familiar checkerboard convention; it does not alter exported pages.
private struct EditorCanvasBackground: View {
    let mode: String
    let customColor: Color

    var body: some View {
        switch mode {
        case "black": Color.black
        case "clear": checkerboard
        case "custom": customColor
        default: Color.white
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let cell: CGFloat = 18
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color(white: 0.82) : Color(white: 0.96)
                    context.fill(Path(CGRect(x: CGFloat(column) * cell,
                                             y: CGFloat(row) * cell,
                                             width: cell, height: cell)),
                                 with: .color(color))
                }
            }
        }
    }
}

/// Sizes the document itself at the requested zoom, rather than applying a
/// visual scale transform. That keeps PageView geometry, hit testing, resize
/// handles, and text rendering in the same coordinate system.
private struct ZoomableEditorCanvas<Content: View>: View {
    @Binding var mode: EditorZoomMode
    let trimSize: SizeInches
    let pageCount: Int
    let extraWidthInches: Double
    @ViewBuilder let content: () -> Content
    @GestureState private var pinchScale = 1.0

    var body: some View {
        GeometryReader { proxy in
            let documentInches = CGSize(width: trimSize.width * Double(pageCount) + extraWidthInches,
                                        height: trimSize.height)
            let baseSize = size(for: mode, documentInches: documentInches,
                                viewport: proxy.size)
            let displaySize = CGSize(width: baseSize.width * pinchScale,
                                     height: baseSize.height * pinchScale)
            ScrollView([.horizontal, .vertical]) {
                content()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .padding(32)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollIndicators(mode == .fitSpread ? .hidden : .automatic)
            .animation(.easeInOut(duration: 0.22), value: mode)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinchScale) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        let naturalWidth = max(1, documentInches.width * 72)
                        let startingPercent = baseSize.width / naturalWidth * 100
                        let result = min(800, max(10,
                            Int((startingPercent * value.magnification).rounded())))
                        mode = .percentage(result)
                    }
            )
        }
    }

    private func size(for mode: EditorZoomMode, documentInches: CGSize,
                      viewport: CGSize) -> CGSize {
        switch mode {
        case .fitSpread:
            let available = CGSize(width: max(1, viewport.width - 64),
                                   height: max(1, viewport.height - 64))
            let scale = min(available.width / documentInches.width,
                            available.height / documentInches.height)
            return CGSize(width: documentInches.width * scale,
                          height: documentInches.height * scale)
        case .percentage(let percent):
            let pointsPerInch = 72.0 * Double(percent) / 100.0
            return CGSize(width: documentInches.width * pointsPerInch,
                          height: documentInches.height * pointsPerInch)
        case .printSize:
            let ppi = Self.approximateScreenPointsPerInch
            return CGSize(width: documentInches.width * ppi,
                          height: documentInches.height * ppi)
        }
    }

    private static var approximateScreenPointsPerInch: Double {
        #if os(macOS)
        if let value = NSScreen.main?.deviceDescription[.resolution] as? NSValue {
            return max(72, value.sizeValue.width)
        }
        #endif
        return 72
    }
}

/// The editing browser: Plan 4's spread browser + the full v1 light-edit
/// loop. All edits go through `BookEditorModel` (D1); this view owns only
/// presentation state (tray/reorder/relink visibility).
///
/// macOS and regular-width iPad: `NavigationSplitView` — reorderable page
/// thumbnails (cover pinned), editable spread detail, template strip below,
/// photo tray as a trailing inspector.
/// Compact iPhone: vertical page scroll with editable pages, bottom-sheet
/// tray, reorder + zoom behind explicit buttons (D14).
public struct BookBrowserView: View {
    @ObservedObject var document: BookDocument
    let imageStore: any ImageStore
    let editor: BookEditorModel
    let exportModel: ExportModel

    public init(document: BookDocument, imageStore: any ImageStore,
                editor: BookEditorModel, exportModel: ExportModel) {
        self.document = document
        self.imageStore = imageStore
        self.editor = editor
        self.exportModel = exportModel
    }

    @Environment(\.undoManager) private var undoManager
    @State private var showTray = false
    @State private var showRelinkSheet = false
    @State private var showPresetPicker = false
    @State private var showCanvasColorPicker = false
    @AppStorage("editor-canvas-background-mode") private var canvasBackgroundMode = "white"
    @AppStorage("editor-canvas-background-color") private var canvasBackgroundHex = "#D9D9D9"
    @State private var zoomMode: EditorZoomMode = .fitSpread
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var zoomedPage: ZoomTarget?
    @State private var showReorderSheet = false
    #endif

    private var book: Book { document.book }

    public var body: some View {
        @Bindable var editor = editor
        Group {
            #if os(macOS)
            splitBrowser
            #else
            if horizontalSizeClass == .regular {
                splitBrowser
            } else {
                compactBrowser
            }
            #endif
        }
        .environment(editor)
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { editor.undoManager = $1 }
        .task { await editor.runMissingPhotoSweep() }
        .task { editor.runPreflightNow() }
        .onChange(of: document.book) { editor.schedulePreflight() }
        .focusedSceneValue(\.exportModel, exportModel)
        .sheet(isPresented: exportSheetBinding) {
            ExportFlowView(model: exportModel, editor: editor)
        }
        .sheet(item: $editor.cropEditingContext) { context in
            CropEditorView(context: context, imageStore: imageStore)
                .environment(editor)
        }
        .sheet(item: $editor.textEditingContext) { context in
            TextEditorOverlay(context: context,
                              trimHeightInches: editor.preset.trimSize.height)
                .environment(editor)
        }
        .sheet(isPresented: $showRelinkSheet) {
            RelinkView(document: document)
                .environment(editor)
        }
        .sheet(isPresented: $showPresetPicker) {
            PresetPickerView()
                .environment(editor)
        }
    }

    // MARK: Selection binding (sidebar/list selection lives on the model)

    private var pageSelection: Binding<UUID?> {
        Binding(get: { editor.selectedPageID }, set: { editor.selectPage($0) })
    }

    // MARK: Export sheet presentation (Plan 6)

    private var exportSheetBinding: Binding<Bool> {
        Binding(get: { exportModel.isFlowPresented },
                set: { if !$0 { exportModel.dismissFlow() } })
    }

    // MARK: Editing interactions (wired into PageView per D3)

    private var editingInteractions: PageEditingInteractions {
        PageEditingInteractions(
            onTapPhotoSlot: { editor.tapPhotoSlot($0) },
            onDoubleTapPhotoSlot: { editor.beginCropEditing($0) },
            onTapTextSlot: { editor.tapTextSlot($0) },
            onDoubleTapTextSlot: { editor.beginTextEditing($0) },
            onSetPhotoSlotFrame: { slotID, frame in editor.setPhotoSlotFrame(slotID, to: frame) },
            onSetTextSlotFrame: { slotID, frame in editor.setTextSlotFrame(slotID, to: frame) }
        )
    }

    // MARK: Split layout (macOS / iPad regular)

    private var splitBrowser: some View {
        NavigationSplitView {
            List(selection: pageSelection) {
                if let cover = book.pages.first, cover.role == .cover {
                    Section(String(localized: "Cover", bundle: .module)) {
                        sidebarRow(index: 0, page: cover)
                            .tag(cover.id)
                    }
                }
                Section(String(localized: "Pages", bundle: .module)) {
                    ForEach(standardPages) { page in
                        let index = book.pages.firstIndex(where: { $0.id == page.id }) ?? 0
                        sidebarRow(index: index, page: page)
                            .tag(page.id)
                    }
                    .onMove { source, destination in
                        editor.movePages(fromStandardOffsets: source, toStandardOffset: destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
        } detail: {
            spreadDetail
        }
        .navigationTitle(book.title)
        .inspector(isPresented: $showTray) {
            TrayView(unplacedPhotos: editor.unplacedPhotos,
                     imageStore: imageStore,
                     hasSelectedSlot: editor.selectedSlotID != nil,
                     onTapPhoto: { editor.assignFromTray($0) })
                .inspectorColumnWidth(min: 200, ideal: 248)
        }
        .toolbar { editingToolbar }
    }

    private var standardPages: [Page] {
        let coverCount = (book.pages.first?.role == .cover) ? 1 : 0
        return Array(book.pages.dropFirst(coverCount))
    }

    /// A page's sidebar thumbnail. First-class spread halves render as a
    /// folded open-book (both pages joined at a center spine fold) so the row
    /// reads as a two-page spread; standalone pages render as a single page.
    @ViewBuilder
    private func pageThumbnail(_ page: Page) -> some View {
        let pair = page.spreadID.map { id in
            book.pages.filter { $0.spreadID == id }
        } ?? []
        if pair.count == 2 {
            HStack(spacing: 0) {
                ForEach(pair) { half in
                    PageView(page: half, book: book, preset: editor.preset,
                             imageStore: imageStore, highlightedSlotID: nil)
                }
            }
            .overlay(alignment: .center) {
                Rectangle().fill(.black.opacity(0.18)).frame(width: 1)  // spine fold
            }
        } else {
            PageView(page: page, book: book, preset: editor.preset, imageStore: imageStore,
                     highlightedSlotID: nil)
        }
    }

    private func sidebarRow(index: Int, page: Page) -> some View {
        HStack(spacing: 10) {
            pageThumbnail(page)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 0.5))
                .overlay(alignment: .topLeading) {
                    if page.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if editor.pagesNeedingReview.contains(page.id) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                            .padding(2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                if page.role == .cover {
                    Text("Cover", bundle: .module)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                } else {
                    Text("Page \(index)", bundle: .module)
                        .font(.caption)
                }
                if book.missingPhotoCount(on: page) > 0 {
                    Label(String(localized: "Missing", bundle: .module), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                if editor.pageIndexesWithWarnings.contains(index) {
                    Label(String(localized: "Warning", bundle: .module), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("page-warning-badge-\(index)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button(page.isLocked
                       ? String(localized: "Unlock Page", bundle: .module)
                       : String(localized: "Lock Page", bundle: .module),
                   systemImage: page.isLocked ? "lock.open" : "lock") {
                editor.togglePageLock(page.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("page-thumbnail-\(index)")
    }

    // MARK: Detail: editable spread + template strip

    private var spreadDetail: some View {
        let pageIndex = editor.selectedPageID
            .flatMap { id in book.pages.firstIndex(where: { $0.id == id }) } ?? 0
        let spreads = SpreadPairing.spreads(for: book.pages)
        let spreadIndex = SpreadPairing.spreadIndex(for: book.pages, pageIndex: pageIndex)
        let spread = spreads.indices.contains(spreadIndex) ? spreads[spreadIndex] : spreads.last
        return VStack(spacing: 0) {
            if let spread {
                let isCoverSpread: Bool = spread.left == nil
                    && spread.right.map { book.pages[$0].role == .cover } == true
                // The cover spread's CoverSheetView also renders the back cover
                // (book.backCover) — a photo surface OUTSIDE book.pages[] — so its
                // banner must count that page too, or a missing back-cover photo
                // shows no warning while it's visible on screen.
                let bannerPages = [spread.left, spread.right].compactMap { $0.map { book.pages[$0] } }
                    + (isCoverSpread ? [book.backCover].compactMap { $0 } : [])
                missingBanner(pages: bannerPages)
                if isCoverSpread, let coverIdx = spread.right {
                    zoomableCanvas(pageCount: 2,
                                   extraWidthInches: editor.preset.spineBase
                                     + editor.preset.spinePerPage * Double(standardPages.count)) {
                        CoverSheetView(backPage: book.backCover, title: book.title,
                                       book: book, preset: editor.preset, imageStore: imageStore) {
                            editablePage(at: coverIdx)
                        }
                    }
                } else {
                    // A first-class spread row renders its two member pages flush at
                    // the gutter (spacing: 0) so a panorama reads continuously across
                    // the seam. Normal facing pairs keep the standard gap (spacing: 8).
                    let isSpreadRow: Bool = spread.left.map { book.pages[$0].spreadID != nil } ?? false
                    zoomableCanvas(pageCount: 2) {
                        HStack(spacing: isSpreadRow ? 0 : 8) {
                            editablePage(at: spread.left)
                            editablePage(at: spread.right)
                        }
                        .overlay {
                            if spreadSeparatorVisible(left: spread.left, right: spread.right) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.3))
                                    .frame(width: 1)
                                    .allowsHitTesting(false)
                                    .accessibilityIdentifier("spread-separator")
                            }
                        }
                    }
                }
                if editor.selectedPageID != nil && !editor.spreadTemplateOptions.isEmpty {
                    SpreadTemplateStripView(templates: editor.spreadTemplateOptions,
                                            pageAspect: editor.preset.trimSize.aspectRatio,
                                            onApply: { templateID in
                                                editor.applySpreadTemplate(templateID)
                                            })
                } else if editor.selectedPageID != nil && !editor.layoutOptionsByCount.isEmpty {
                    TemplateStripView(groups: editor.layoutOptionsByCount,
                                      pageAspect: editor.preset.trimSize.aspectRatio,
                                      onApply: { count, candidate in
                                          editor.applyLayoutOption(count: count, candidate: candidate)
                                      })
                }
            } else {
                Text("No pages", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        }
        .background {
            EditorCanvasBackground(mode: canvasBackgroundMode,
                                   customColor: Color(hex: canvasBackgroundHex))
                .ignoresSafeArea()
        }
        .modifier(PhotoActionsInlineOverlay(editor: editor,
                                            slotIsLocked: editor.selectedSlotIsLocked,
                                            pageIsLocked: editor.selectedPageIsLocked))
        .modifier(TextActionsInlineOverlay(editor: editor))
        .snackbar(editor.isReplacing
            ? SnackbarConfig(message: String(localized: "Select a photo to swap in", bundle: .module),
                             actionTitle: String(localized: "Cancel", bundle: .module),
                             isPresented: Binding(get: { editor.isReplacing },
                                                  set: { show in if !show { editor.cancelReplace() } }),
                             action: { editor.cancelReplace() })
            : nil)
        #if os(macOS)
        // Window-level Escape: `.onExitCommand` only fires when the detail view
        // holds focus, but a tap-selected photo/text slot doesn't grant it, so
        // a hidden `.cancelAction` button catches Escape regardless of focus.
        // First Escape leaves replace mode; otherwise it clears the selection
        // so the photo/text actions popover + handles hide.
        .background {
            Button("") {
                if editor.isReplacing { editor.cancelReplace() } else { editor.deselectSlots() }
            }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .focusable()
        // The detail must remain focusable for Return/Delete shortcuts, but a
        // macOS resize can promote it to key focus and draw a giant blue ring
        // around the entire canvas. Selection chrome belongs on slots only.
        .focusEffectDisabled()
        .onKeyPress(.return) {
            if let slotID = editor.selectedTextSlotID {
                editor.beginTextEditing(slotID)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            if editor.selectedTextSlotID != nil {
                editor.removeSelectedTextSlot()
                return .handled
            }
            return .ignored
        }
        #endif
    }

    private func zoomableCanvas<Content: View>(pageCount: Int, extraWidthInches: Double = 0,
                                                @ViewBuilder content: @escaping () -> Content) -> some View {
        ZoomableEditorCanvas(mode: $zoomMode,
                             trimSize: editor.preset.trimSize,
                             pageCount: pageCount,
                             extraWidthInches: extraWidthInches,
                             content: content)
    }

    @ViewBuilder
    private func editablePage(at index: Int?) -> some View {
        if let index, book.pages.indices.contains(index) {
            PageView(page: book.pages[index], book: book, preset: editor.preset,
                     imageStore: imageStore,
                     highlightedSlotID: editor.selectedSlotID ?? editor.selectedTextSlotID,
                     replaceSourceSlotID: editor.replaceSourceSlotID)
                .editing(editingInteractions)
        } else {
            Color(white: 0.97)
                .aspectRatio(editor.preset.trimSize.aspectRatio, contentMode: .fit)
        }
    }

    // MARK: Toolbar (shared by both layouts)

    @ToolbarContentBuilder
    private var editingToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button {
                    editor.tryAnotherSelectedLayout()
                } label: {
                    Label(String(localized: "Try Another Layout", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!editor.canTryAnotherSelectedLayout)
                .accessibilityIdentifier("toolbar-reshuffle-page")

                Button {
                    editor.toggleSelectedPageLock()
                } label: {
                    Label(editor.selectedPageIsLocked
                              ? String(localized: "Unlock Page", bundle: .module)
                              : String(localized: "Lock Page", bundle: .module),
                          systemImage: editor.selectedPageIsLocked ? "lock.open" : "lock")
                }
                .disabled(editor.selectedPageID == nil)
                .accessibilityIdentifier("toolbar-lock-page")

                Divider()
                Button(String(localized: "Merge Facing Pages", bundle: .module), systemImage: "rectangle.split.2x1") {
                    editor.convertSelectedSpread()
                }
                .disabled(!editor.canConvertSelectedToSpread)
                .accessibilityIdentifier("spread-merge")

                Button(String(localized: "Split Spread", bundle: .module), systemImage: "rectangle.split.2x1.slash") {
                    editor.revertSelectedSpread()
                }
                .disabled(!editor.canRevertSelectedSpread)
                .accessibilityIdentifier("spread-split")

                Divider()
                Button(String(localized: "Add One Photo", bundle: .module), systemImage: "plus.rectangle") {
                    editor.increaseSelectedPageDensity()
                }
                .disabled(!editor.canIncreaseSelectedPageDensity)
                .accessibilityIdentifier("density-increase")

                Button(String(localized: "Remove One Photo", bundle: .module), systemImage: "minus.rectangle") {
                    editor.decreaseSelectedPageDensity()
                }
                .disabled(!editor.canDecreaseSelectedPageDensity)
                .accessibilityIdentifier("density-decrease")

                Divider()
                Picker(String(localized: "Photo Edges", bundle: .module), selection: Binding(
                    get: { editor.selectedPageEdgeStyle },
                    set: { editor.setSelectedPageEdgeStyle($0) }
                )) {
                    Text("Framed", bundle: .module).tag(EdgeStyle.framed)
                    Text("Tiled", bundle: .module).tag(EdgeStyle.tiled)
                    Text("Borderless", bundle: .module).tag(EdgeStyle.borderless)
                }
                .accessibilityIdentifier("toolbar-edge-style-page")

                ColorPicker(String(localized: "Page Background", bundle: .module), selection: Binding(
                    get: { Color(hex: editor.selectedPageEffectiveBackgroundHex) },
                    set: { editor.setSelectedPageBackground($0.rgbHexString) }
                ), supportsOpacity: false)
                .disabled(editor.selectedPageID == nil)
                .accessibilityIdentifier("page-bg-color")

                Button(String(localized: "Reset Page Style", bundle: .module), systemImage: "arrow.uturn.backward") {
                    editor.resetSelectedPageToDefault()
                }
                .disabled(editor.selectedPageID == nil)
            } label: {
                Label(String(localized: "Page", bundle: .module), systemImage: "doc")
            }
            .help(Text("Layout and appearance for the selected page", bundle: .module))

            Menu {
                Button(String(localized: "Add Text", bundle: .module), systemImage: "textbox") {
                    editor.addTextSlotToSelectedPage()
                }
                .disabled(!editor.canAddTextToSelectedPage)
                .accessibilityIdentifier("toolbar-add-text")

                Button(String(localized: "Place Remaining Photos", bundle: .module), systemImage: "rectangle.stack.badge.plus") {
                    editor.placeRemaining()
                }
                .disabled(editor.unplacedPhotoIDs.isEmpty)
                .accessibilityIdentifier("toolbar-place-remaining")
            } label: {
                Label(String(localized: "Add", bundle: .module), systemImage: "plus")
            }
            .help(Text("Add content to the book", bundle: .module))

            Menu {
                Button(String(localized: "Rebuild Unlocked Pages", bundle: .module), systemImage: "shuffle") {
                    editor.reshuffleBook()
                }
                .accessibilityIdentifier("toolbar-reshuffle-book")

                Divider()
                ColorPicker(String(localized: "Book Background", bundle: .module), selection: Binding(
                    get: { Color(hex: editor.bookBackgroundHex) },
                    set: { editor.setBookBackground($0.rgbHexString) }
                ), supportsOpacity: false)
                .accessibilityIdentifier("book-bg-color")

                Picker(String(localized: "Default Photo Edges", bundle: .module), selection: Binding(
                    get: { editor.bookEdgeStyle },
                    set: { editor.setBookEdgeStyle($0) }
                )) {
                    Text("Framed", bundle: .module).tag(EdgeStyle.framed)
                    Text("Tiled", bundle: .module).tag(EdgeStyle.tiled)
                    Text("Borderless", bundle: .module).tag(EdgeStyle.borderless)
                }
                .accessibilityIdentifier("toolbar-edge-style-book")

                Divider()
                Button(String(localized: "Book Size and Format…", bundle: .module), systemImage: "aspectratio") {
                    showPresetPicker = true
                }
                .accessibilityIdentifier("toolbar-book-format")
            } label: {
                Label(String(localized: "Book", bundle: .module), systemImage: "book.closed")
            }
            .help(Text("Settings that affect the whole book", bundle: .module))
            .accessibilityIdentifier("toolbar-book-menu")

            Button {
                showTray.toggle()
            } label: {
                Label(String(localized: "Photos", bundle: .module), systemImage: showTray ? "tray.full.fill" : "tray.full")
            }
            .help(showTray
                      ? Text("Hide unplaced photos", bundle: .module)
                      : Text("Show unplaced photos", bundle: .module))
            .accessibilityIdentifier("tray-toggle")

            Menu {
                canvasBackgroundChoice(String(localized: "White", bundle: .module), systemImage: "square.fill", mode: "white")
                canvasBackgroundChoice(String(localized: "Black", bundle: .module), systemImage: "square.fill", mode: "black")
                canvasBackgroundChoice(String(localized: "Transparent", bundle: .module), systemImage: "square.grid.3x3.square", mode: "clear")
                Divider()
                Button(String(localized: "Custom Color…", bundle: .module), systemImage: "paintpalette") {
                    showCanvasColorPicker = true
                }
            } label: {
                Label(String(localized: "Canvas", bundle: .module), systemImage: canvasBackgroundMode == "clear"
                      ? "square.grid.3x3.square" : "circle.lefthalf.filled")
            }
            .help(Text("Change the workspace color behind the book", bundle: .module))
            .accessibilityIdentifier("canvas-background-menu")
            .popover(isPresented: $showCanvasColorPicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Canvas Color", bundle: .module)
                        .font(.headline)
                    Text("This changes only the workspace behind the book.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker(String(localized: "Custom color", bundle: .module), selection: Binding(
                        get: { Color(hex: canvasBackgroundHex) },
                        set: { color in
                            canvasBackgroundHex = color.rgbHexString
                            canvasBackgroundMode = "custom"
                        }
                    ), supportsOpacity: false)
                    .accessibilityIdentifier("canvas-custom-color-picker")
                    HStack {
                        Spacer()
                        Button(String(localized: "Done", bundle: .module)) { showCanvasColorPicker = false }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
                .frame(width: 280)
            }

            HStack(spacing: 0) {
                Button { zoomOut() } label: {
                    Image(systemName: "minus")
                }
                .help(Text("Zoom out", bundle: .module))
                .keyboardShortcut("-", modifiers: .command)
                .accessibilityIdentifier("canvas-zoom-out")

                Menu {
                    Button(String(localized: "Fit Spread", bundle: .module)) { zoomMode = .fitSpread }
                        .keyboardShortcut("0", modifiers: .command)
                    Button(String(localized: "Actual Print Size", bundle: .module)) { zoomMode = .printSize }
                    Divider()
                    ForEach([25, 50, 75, 100, 125, 150, 200, 400], id: \.self) { percent in
                        Button {
                            zoomMode = .percentage(percent)
                        } label: {
                            Text(verbatim: "\(percent)%")
                        }
                    }
                } label: {
                    Text(zoomLabel)
                        .monospacedDigit()
                        .frame(minWidth: 42)
                }
                .help(Text("Choose a zoom level", bundle: .module))
                .accessibilityIdentifier("canvas-zoom-menu")

                Button { zoomIn() } label: {
                    Image(systemName: "plus")
                }
                .help(Text("Zoom in", bundle: .module))
                .keyboardShortcut("+", modifiers: .command)
                .accessibilityIdentifier("canvas-zoom-in")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(ExportModel.ExportTarget.allCases, id: \.self) { target in
                    Button(target.menuTitle) { exportModel.begin(target) }
                        .accessibilityIdentifier("toolbar-export-\(target.rawValue)")
                }
            } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
            }
            .help(Text("Export or print your finished book", bundle: .module))
            .accessibilityIdentifier("toolbar-export")
        }
    }

    private func canvasBackgroundChoice(_ title: String, systemImage: String,
                                        mode: String) -> some View {
        Button {
            canvasBackgroundMode = mode
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                if canvasBackgroundMode == mode {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var zoomLabel: String {
        switch zoomMode {
        case .fitSpread: String(localized: "Fit", bundle: .module)
        case .printSize: String(localized: "Print", bundle: .module)
        case .percentage(let percent): "\(percent)%"
        }
    }

    private let zoomSteps = [25, 50, 75, 100, 125, 150, 200, 400]

    private func zoomIn() {
        let current = zoomMode.percentageValue ?? 75
        zoomMode = .percentage(zoomSteps.first(where: { $0 > current }) ?? zoomSteps.last!)
    }

    private func zoomOut() {
        let current = zoomMode.percentageValue ?? 125
        zoomMode = .percentage(zoomSteps.last(where: { $0 < current }) ?? zoomSteps.first!)
    }

    // MARK: Missing-photo banner (relink flow)

    @ViewBuilder
    private func missingBanner(pages: [Page]) -> some View {
        let missingCount = pages.reduce(0) { $0 + book.missingPhotoCount(on: $1) }
        if missingCount > 0 {
            HStack {
                Label(String(localized: "\(missingCount) photos are missing.", bundle: .module),
                      systemImage: "exclamationmark.triangle.fill")
                Spacer()
                Button(String(localized: "Relink…", bundle: .module)) { showRelinkSheet = true }
                    .help(Text("Find the missing photos or remove them from the book", bundle: .module))
                    .accessibilityIdentifier("relink-banner-button")
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.yellow.opacity(0.25))
            .accessibilityIdentifier("missing-photos-banner")
        }
    }

    // MARK: Edge-style helpers

    private func edgeStyleLabel(_ style: EdgeStyle) -> String {
        switch style {
        case .framed: return String(localized: "Framed", bundle: .module)
        case .tiled: return String(localized: "Tiled", bundle: .module)
        case .borderless: return String(localized: "Borderless", bundle: .module)
        }
    }

    private func edgeStyleIcon(_ style: EdgeStyle) -> String {
        switch style {
        case .framed: return "rectangle.inset.filled"
        case .tiled: return "square.grid.2x2"
        case .borderless: return "rectangle.fill"
        }
    }

    // MARK: Compact layout (iPhone)

    #if os(iOS)
    struct ZoomTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var compactBrowser: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 6) {
                            // The cover row's CoverSheetView also renders the back
                            // cover (book.backCover, a photo surface outside pages[]),
                            // so its banner must include that page too.
                            missingBanner(pages: page.role == .cover
                                ? [page] + [book.backCover].compactMap { $0 }
                                : [page])
                            if page.role == .cover {
                                CoverSheetView(backPage: book.backCover, title: book.title,
                                               book: book, preset: editor.preset,
                                               imageStore: imageStore) {
                                    PageView(page: page, book: book, preset: editor.preset,
                                             imageStore: imageStore,
                                             highlightedSlotID: editor.selectedSlotID ?? editor.selectedTextSlotID,
                                             replaceSourceSlotID: editor.replaceSourceSlotID)
                                        .editing(editingInteractions)
                                }
                                // Fixed row height for the three-panel cover sheet in the
                                // compact scroll; the sheet scales to fit within it.
                                .frame(height: 200)
                                .onAppear {
                                    if editor.selectedPageID == nil { editor.selectPage(page.id) }
                                }
                            } else {
                                PageView(page: page, book: book, preset: editor.preset,
                                         imageStore: imageStore,
                                         highlightedSlotID: editor.selectedSlotID ?? editor.selectedTextSlotID,
                                         replaceSourceSlotID: editor.replaceSourceSlotID)
                                    .editing(editingInteractions)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .shadow(radius: 2)
                                    .onAppear {
                                        if editor.selectedPageID == nil { editor.selectPage(page.id) }
                                    }
                            }
                            HStack(spacing: 12) {
                                Text(page.role == .cover ? "Cover" : "Page \(index)", bundle: .module)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if page.isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if editor.pagesNeedingReview.contains(page.id) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Button {
                                    editor.selectPage(page.id)
                                } label: {
                                    Image(systemName: editor.selectedPageID == page.id
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                }
                                .accessibilityIdentifier("select-page-\(index)")
                                Button {
                                    zoomedPage = ZoomTarget(index: index)
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                }
                                .accessibilityIdentifier("zoom-page-\(index)")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editingToolbar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showReorderSheet = true
                    } label: {
                        Label(String(localized: "Reorder", bundle: .module), systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("reorder-toggle")
                }
            }
            .fullScreenCover(item: $zoomedPage) { target in
                ZoomablePageView(page: book.pages[target.index], book: book,
                                 preset: editor.preset, imageStore: imageStore)
            }
            .sheet(isPresented: $showTray) {
                TrayView(unplacedPhotos: editor.unplacedPhotos,
                         imageStore: imageStore,
                         hasSelectedSlot: editor.selectedSlotID != nil,
                         onTapPhoto: { editor.assignFromTray($0) })
                    .presentationDetents([.height(160), .medium])
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(160)))
            }
            .sheet(isPresented: $showReorderSheet) {
                reorderSheet
            }
            .snackbar(editor.isReplacing
                ? SnackbarConfig(message: String(localized: "Select a photo to swap in", bundle: .module),
                                 actionTitle: String(localized: "Cancel", bundle: .module),
                                 isPresented: Binding(get: { editor.isReplacing },
                                                      set: { show in if !show { editor.cancelReplace() } }),
                                 action: { editor.cancelReplace() })
                : nil)
            .modifier(PhotoActionsInlineOverlay(editor: editor,
                                                slotIsLocked: editor.selectedSlotIsLocked,
                                                pageIsLocked: editor.selectedPageIsLocked))
            .modifier(TextActionsInlineOverlay(editor: editor))
        }
    }

    private var reorderSheet: some View {
        NavigationStack {
            List {
                if let cover = book.pages.first, cover.role == .cover {
                    Section(String(localized: "Cover", bundle: .module)) {
                        Label(String(localized: "Cover stays first", bundle: .module), systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "Pages", bundle: .module)) {
                    ForEach(standardPages) { page in
                        let index = book.pages.firstIndex(where: { $0.id == page.id }) ?? 0
                        Text("Page \(index)", bundle: .module)
                    }
                    .onMove { source, destination in
                        editor.movePages(fromStandardOffsets: source, toStandardOffset: destination)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "Reorder Pages", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { showReorderSheet = false }
                }
            }
        }
    }
    #endif
}

#if os(iOS)
/// Full-screen page with basic pinch zoom — carried from Plan 4 unchanged
/// (D14: zoom moved behind an explicit button; editing happens inline).
struct ZoomablePageView: View {
    let page: Page
    let book: Book
    let preset: PrintPreset
    let imageStore: any ImageStore

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            PageView(page: page, book: book, preset: preset, imageStore: imageStore,
                     highlightedSlotID: nil)
                .scaleEffect(zoom * pinch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            zoom = min(8, max(1, zoom * value.magnification))
                        }
                )
                .onTapGesture(count: 2) { zoom = 1 }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
    }
}
#endif

/// Floating, NON-transient actions panel over the selected photo slot.
///
/// Rendered as an inline card (not a `.popover`) so it never captures the
/// pointer the way a transient macOS popover does — the page's move/resize
/// handles underneath stay draggable. Only the card itself is hit-testable;
/// the surrounding (empty) `GeometryReader` space passes clicks through to the
/// handles. The card sits just above the selected slot, flipping below when
/// the slot is near the top edge. Selection is sticky: it is no longer cleared
/// by dismissing the panel (there is nothing to dismiss) — tapping the photo
/// again toggles it off.
private struct PhotoActionsInlineOverlay: ViewModifier {
    let editor: BookEditorModel
    let slotIsLocked: Bool
    let pageIsLocked: Bool

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(SelectedSlotBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, editor.selectedSlotID != nil, !editor.isReplacing {
                    let rect = proxy[anchor]
                    let gap: CGFloat = 44
                    let placeAbove = rect.minY > 72
                    let centerY = placeAbove ? rect.minY - gap : rect.maxY + gap
                    PhotoActionsPopover(editor: editor,
                                        slotIsLocked: slotIsLocked,
                                        pageIsLocked: pageIsLocked)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                        .shadow(radius: 8, y: 2)
                        .fixedSize()
                        .position(x: rect.midX, y: centerY)
                        .accessibilityIdentifier("photo-actions-popover")
                }
            }
        }
    }
}
