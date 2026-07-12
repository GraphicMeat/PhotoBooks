import AppSupport
import EditCore
import ExportFeature
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SetupFeature
import SwiftUI

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
                    Section("Cover") {
                        sidebarRow(index: 0, page: cover)
                            .tag(cover.id)
                    }
                }
                Section("Pages") {
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
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            spreadDetail
        }
        .navigationTitle(book.title)
        .inspector(isPresented: $showTray) {
            TrayView(unplacedPhotoIDs: editor.unplacedPhotoIDs,
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
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.separator, lineWidth: 0.5))
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
                    Text("Cover")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                } else {
                    Text("Page \(index)")
                        .font(.caption)
                }
                if book.missingPhotoCount(on: page) > 0 {
                    Label("Missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                if editor.pageIndexesWithWarnings.contains(index) {
                    Label("Warning", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("page-warning-badge-\(index)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(page.isLocked ? "Unlock Page" : "Lock Page",
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
                    CoverSheetView(backPage: book.backCover, title: book.title,
                                   book: book, preset: editor.preset, imageStore: imageStore) {
                        editablePage(at: coverIdx)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // A first-class spread row renders its two member pages flush at
                    // the gutter (spacing: 0) so a panorama reads continuously across
                    // the seam. Normal facing pairs keep the standard gap (spacing: 8).
                    let isSpreadRow: Bool = spread.left.map { book.pages[$0].spreadID != nil } ?? false
                    HStack(spacing: isSpreadRow ? 0 : 8) {
                        editablePage(at: spread.left)
                        editablePage(at: spread.right)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("No pages")
                    .foregroundStyle(.secondary)
            }
        }
        .background(Color(white: 0.93))
        .modifier(PhotoActionsInlineOverlay(editor: editor))
        .modifier(TextActionsInlineOverlay(editor: editor))
        .snackbar(editor.isReplacing
            ? SnackbarConfig(message: "Select a photo to swap in",
                             actionTitle: "Cancel",
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
            Button {
                editor.reshuffleSelectedPage()
            } label: {
                Label("Reshuffle Page", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(editor.selectedPageID == nil)
            .help("Regenerate the selected page's layout (locked content survives)")
            .accessibilityIdentifier("toolbar-reshuffle-page")

            Button {
                editor.reshuffleBook()
            } label: {
                Label("Reshuffle Book", systemImage: "shuffle")
            }
            .help("Regenerate every unlocked page")
            .accessibilityIdentifier("toolbar-reshuffle-book")

            Button {
                editor.toggleSelectedPageLock()
            } label: {
                Label(editor.selectedPageIsLocked ? "Unlock Page" : "Lock Page",
                      systemImage: editor.selectedPageIsLocked ? "lock.fill" : "lock.open")
            }
            .disabled(editor.selectedPageID == nil)
            .help(editor.selectedPageIsLocked
                  ? "Unlock this page so reshuffle can re-lay it"
                  : "Lock this page so reshuffle skips it")
            .accessibilityIdentifier("toolbar-lock-page")

            Button {
                editor.convertSelectedSpread()
            } label: {
                Label("Merge into Spread", systemImage: "rectangle.split.2x1")
            }
            .disabled(!editor.canConvertSelectedToSpread)
            .help("Merge this facing pair into a single panoramic spread")
            .accessibilityIdentifier("spread-merge")

            Button {
                editor.revertSelectedSpread()
            } label: {
                Label("Split Spread", systemImage: "rectangle.split.2x1.slash")
            }
            .disabled(!editor.canRevertSelectedSpread)
            .help("Split this spread back into two independent pages")
            .accessibilityIdentifier("spread-split")

            Button {
                editor.increaseSelectedPageDensity()
            } label: {
                Label("More Photos", systemImage: "plus.rectangle")
            }
            .disabled(!editor.canIncreaseSelectedPageDensity)
            .help("Move one more photo onto this page from the next page")
            .accessibilityIdentifier("density-increase")

            Button {
                editor.decreaseSelectedPageDensity()
            } label: {
                Label("Fewer Photos", systemImage: "minus.rectangle")
            }
            .disabled(!editor.canDecreaseSelectedPageDensity)
            .help("Move one photo from this page onto the next page")
            .accessibilityIdentifier("density-decrease")

            Menu {
                Picker("Photo edges", selection: Binding(
                    get: { editor.selectedPageEdgeStyle },
                    set: { editor.setSelectedPageEdgeStyle($0) }
                )) {
                    Text("Framed").tag(EdgeStyle.framed)
                    Text("Tiled").tag(EdgeStyle.tiled)
                    Text("Borderless").tag(EdgeStyle.borderless)
                }
            } label: {
                Label(edgeStyleLabel(editor.selectedPageEdgeStyle),
                      systemImage: edgeStyleIcon(editor.selectedPageEdgeStyle))
            }
            .disabled(editor.selectedPageID == nil)
            .help("Photo edges for this page — Framed (margin + gaps), Tiled (fills to edge, keeps gaps), or Borderless (edge-to-edge, no gaps).")
            .accessibilityIdentifier("toolbar-edge-style-page")

            ColorPicker("Page background", selection: Binding(
                get: { Color(hex: editor.selectedPageEffectiveBackgroundHex) },
                set: { editor.setSelectedPageBackground($0.rgbHexString) }
            ), supportsOpacity: false)
            .disabled(editor.selectedPageID == nil)
            .help("Set the background color of the selected page")
            .accessibilityIdentifier("page-bg-color")

            Button("Reset to book default") { editor.resetSelectedPageToDefault() }
                .disabled(editor.selectedPageID == nil)
                .help("Reset this page: clear its color, edge style, and photo sizing back to the book default")

            ColorPicker("Book background", selection: Binding(
                get: { Color(hex: editor.bookBackgroundHex) },
                set: { editor.setBookBackground($0.rgbHexString) }
            ), supportsOpacity: false)
            .help("Set the default background color for every page")
            .accessibilityIdentifier("book-bg-color")

            Menu {
                Picker("Photo edges (all pages)", selection: Binding(
                    get: { editor.bookEdgeStyle },
                    set: { editor.setBookEdgeStyle($0) }
                )) {
                    Text("Framed").tag(EdgeStyle.framed)
                    Text("Tiled").tag(EdgeStyle.tiled)
                    Text("Borderless").tag(EdgeStyle.borderless)
                }
            } label: {
                Label("All pages: \(edgeStyleLabel(editor.bookEdgeStyle))",
                      systemImage: edgeStyleIcon(editor.bookEdgeStyle))
            }
            .help("Photo edges for the whole book — sets every page's default. Pages you've set individually keep their own choice.")
            .accessibilityIdentifier("toolbar-edge-style-book")

            Button {
                editor.toggleSelectedSlotLock()
            } label: {
                Label(editor.selectedSlotIsLocked ? "Unlock Frame" : "Lock Frame",
                      systemImage: editor.selectedSlotIsLocked ? "lock.square.fill" : "lock.square")
            }
            .disabled(editor.selectedSlotID == nil)
            .help("Locked frames are skipped by reshuffle; unlocking returns the frame to the engine")
            .accessibilityIdentifier("toolbar-lock-slot")

            Button {
                editor.addTextSlotToSelectedPage()
            } label: {
                Label("Add Text", systemImage: "textbox")
            }
            .disabled(!editor.canAddTextToSelectedPage)
            .help("Add a text box to the selected page")
            .accessibilityIdentifier("toolbar-add-text")

            Button {
                if let slotID = editor.selectedTextSlotID {
                    editor.beginTextEditing(slotID)
                }
            } label: {
                Label("Edit Text", systemImage: "character.cursor.ibeam")
            }
            .disabled(editor.selectedTextSlotID == nil)
            .help("Edit the caption in the selected text frame")
            .accessibilityIdentifier("toolbar-edit-text")

            Button {
                editor.removeSelectedTextSlot()
            } label: {
                Label("Delete Text", systemImage: "trash.slash")
            }
            .disabled(editor.selectedTextSlotID == nil)
            .help("Delete the selected text box")
            .accessibilityIdentifier("toolbar-delete-text")

            Button {
                editor.removeSelectedPhoto()
            } label: {
                Label("Remove Photo", systemImage: "trash")
            }
            .disabled(!editor.selectedSlotHasPhoto)
            .help("Empty the selected frame; the photo returns to the tray")
            .accessibilityIdentifier("toolbar-remove-photo")

            Button {
                editor.placeRemaining()
            } label: {
                Label("Place Remaining", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(editor.unplacedPhotoIDs.isEmpty)
            .help("Lay out every unplaced photo on new pages at the end")
            .accessibilityIdentifier("toolbar-place-remaining")

            Button {
                showTray.toggle()
            } label: {
                Label("Photo Tray", systemImage: "tray.full")
            }
            .help("Show or hide the tray of unplaced photos")
            .accessibilityIdentifier("tray-toggle")

            Menu {
                ForEach(ExportModel.ExportTarget.allCases, id: \.self) { target in
                    Button(target.menuTitle) { exportModel.begin(target) }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export the book to a PDF or print service")
            .accessibilityIdentifier("toolbar-export")

            Button {
                showPresetPicker = true
            } label: {
                Label("Book Format…", systemImage: "aspectratio")
            }
            .help("Switch the print preset; a cross-shape switch relays out unlocked pages")
            .accessibilityIdentifier("toolbar-book-format")
        }
    }

    // MARK: Missing-photo banner (relink flow)

    @ViewBuilder
    private func missingBanner(pages: [Page]) -> some View {
        let missingCount = pages.reduce(0) { $0 + book.missingPhotoCount(on: $1) }
        if missingCount > 0 {
            HStack {
                Label(missingCount == 1 ? "1 photo is missing."
                                        : "\(missingCount) photos are missing.",
                      systemImage: "exclamationmark.triangle.fill")
                Spacer()
                Button("Relink…") { showRelinkSheet = true }
                    .help("Find the missing photos or remove them from the book")
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
        case .framed: return "Framed"
        case .tiled: return "Tiled"
        case .borderless: return "Borderless"
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
                                Text(page.role == .cover ? "Cover" : "Page \(index)")
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
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("reorder-toggle")
                }
            }
            .fullScreenCover(item: $zoomedPage) { target in
                ZoomablePageView(page: book.pages[target.index], book: book,
                                 preset: editor.preset, imageStore: imageStore)
            }
            .sheet(isPresented: $showTray) {
                TrayView(unplacedPhotoIDs: editor.unplacedPhotoIDs,
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
                ? SnackbarConfig(message: "Select a photo to swap in",
                                 actionTitle: "Cancel",
                                 isPresented: Binding(get: { editor.isReplacing },
                                                      set: { show in if !show { editor.cancelReplace() } }),
                                 action: { editor.cancelReplace() })
                : nil)
            .modifier(PhotoActionsInlineOverlay(editor: editor))
            .modifier(TextActionsInlineOverlay(editor: editor))
        }
    }

    private var reorderSheet: some View {
        NavigationStack {
            List {
                if let cover = book.pages.first, cover.role == .cover {
                    Section("Cover") {
                        Label("Cover stays first", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Pages") {
                    ForEach(standardPages) { page in
                        let index = book.pages.firstIndex(where: { $0.id == page.id }) ?? 0
                        Text("Page \(index)")
                    }
                    .onMove { source, destination in
                        editor.movePages(fromStandardOffsets: source, toStandardOffset: destination)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showReorderSheet = false }
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

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(SelectedSlotBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, editor.selectedSlotID != nil, !editor.isReplacing {
                    let rect = proxy[anchor]
                    let gap: CGFloat = 44
                    let placeAbove = rect.minY > 72
                    let centerY = placeAbove ? rect.minY - gap : rect.maxY + gap
                    PhotoActionsPopover(editor: editor)
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
