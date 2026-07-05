import AppSupport
import EditCore
import Foundation
import Observation
import PhotoBookCore
import PhotoBookImport
import PhotoBookRender

/// What the crop editor needs to open on a slot: the stored crop plus both
/// TRUE aspects (slot aspect corrected by page size — D6). Derived by the
/// model, consumed by `CropEditorView` (Task 7).
public struct CropEditorContext: Identifiable, Equatable {
    public var slotID: UUID
    public var photoID: PhotoID
    public var baseCrop: NormRect
    public var photoAspect: Double
    public var slotAspect: Double
    public var id: UUID { slotID }

    public init(slotID: UUID, photoID: PhotoID, baseCrop: NormRect,
                photoAspect: Double, slotAspect: Double) {
        self.slotID = slotID
        self.photoID = photoID
        self.baseCrop = baseCrop
        self.photoAspect = photoAspect
        self.slotAspect = slotAspect
    }
}

/// What the text editor needs to open on a text slot: the current styled
/// text as the draft seed. Consumed by `TextEditorOverlay` (Task 6).
public struct TextEditorContext: Identifiable, Equatable {
    public var slotID: UUID
    public var text: StyledText
    public var id: UUID { slotID }

    public init(slotID: UUID, text: StyledText) {
        self.slotID = slotID
        self.text = text
    }
}

/// The single mediator between editing views and the document/engine (D1):
/// wraps `BookDocument` + `BookEngine` + the current `PrintPreset`. Views
/// never call `document.mutate` or the engine directly — every edit is a
/// model method, and every model method is one `apply` call, so undo is
/// uniform by construction. Selection lives here (never undoable).
@Observable @MainActor
public final class BookEditorModel {

    @ObservationIgnored let document: BookDocument
    /// Engine operations (reshuffle/alternatives/placeRemaining) arrive in
    /// Task 5; the instance lives here so they slot in without churn.
    @ObservationIgnored private let engine = BookEngine()
    /// Used by the missing-photo sweep (Task 8) to probe PhotoKit assets.
    @ObservationIgnored private let photoKitProvider: PhotoKitProvider

    /// Supplied by the browser from the SwiftUI environment; every mutation
    /// registers its inverse against it.
    @ObservationIgnored public weak var undoManager: UndoManager?

    // MARK: Selection (model state, never undoable — D1)

    public private(set) var selectedPageID: UUID?
    public private(set) var selectedSlotID: UUID?
    public private(set) var selectedTextSlotID: UUID?

    /// When non-nil, the next photo-slot tap (or tray assignment) replaces the
    /// photo in this slot instead of moving selection. Entered via the popover
    /// Replace button; drives the snackbar. Model state, never undoable.
    public private(set) var replaceSourceSlotID: UUID?

    public var isReplacing: Bool { replaceSourceSlotID != nil }

    // MARK: Sheet routing

    public var cropEditingContext: CropEditorContext?
    public var textEditingContext: TextEditorContext?

    /// Pre-scored "try next layout" candidates for the selected page (the
    /// template strip's data). Refreshed on selection change and after
    /// every mutation — the engine derives them from the page's own UUID,
    /// so they are stable across calls (Plan 2).
    private(set) var alternativeCandidates: [LayoutCandidate] = []

    /// Layout choices for the selected page grouped by photo count (9 → 1),
    /// the count-grouped strip's data. Refreshed with `alternativeCandidates`.
    public private(set) var layoutOptionsByCount: [(count: Int, candidates: [LayoutCandidate])] = []

    // MARK: Review flags (preset switch)

    /// Review flags for pages a cross-class preset switch could NOT
    /// relayout (the cover + lock-frozen pages). Ephemeral UI state, NOT
    /// persisted: the spec's "review flag" is a UX affordance ("look at
    /// this page"), not book content — the model schema is unchanged and
    /// saved documents stay byte-stable. Keyed to the presetID it was
    /// computed under, so undo (which restores the old presetID through
    /// the document snapshot) empties the set with no undo-stack hook —
    /// and redo brings it back.
    private var reviewSet: Set<UUID> = []
    private var reviewPresetID: String?

    public var pagesNeedingReview: Set<UUID> {
        reviewPresetID == document.book.presetID ? reviewSet : []
    }

    public init(document: BookDocument, photoKitProvider: PhotoKitProvider = PhotoKitProvider(),
                preflightDebounce: Duration = .milliseconds(500)) {
        self.document = document
        self.photoKitProvider = photoKitProvider
        self.preflightDebouncer = Debouncer(interval: preflightDebounce)
    }

    // MARK: Derived state

    public var book: Book { document.book }

    public var preset: PrintPreset {
        PresetLibrary.preset(id: document.book.presetID) ?? PresetLibrary.all()[0]
    }

    var pageSize: SizeInches { preset.trimSize }

    public var unplacedPhotoIDs: [PhotoID] { EditMutations.unplacedPhotoIDs(in: document.book) }

    public var selectedSlotHasPhoto: Bool {
        guard let slotID = selectedSlotID,
              let location = EditMutations.locatePhotoSlot(slotID, in: document.book) else { return false }
        return document.book.pages[location.pageIndex].photoSlots[location.slotIndex].photoID != nil
    }

    public var selectedPageIsLocked: Bool {
        guard let pageID = selectedPageID else { return false }
        return document.book.pages.first(where: { $0.id == pageID })?.isLocked ?? false
    }

    /// Effective edge style for the selected page:
    /// page override if set, otherwise the book-level default.
    public var selectedPageEdgeStyle: EdgeStyle {
        guard let pageID = selectedPageID,
              let page = document.book.pages.first(where: { $0.id == pageID }) else { return .framed }
        return page.edgeStyleOverride ?? document.book.style.edgeStyle
    }

    /// True when a standard (interior) page is selected — freeform text is
    /// interior-only; the cover keeps its own title system.
    public var canAddTextToSelectedPage: Bool {
        guard let pageID = selectedPageID,
              let page = document.book.pages.first(where: { $0.id == pageID }) else { return false }
        return page.role == .standard
    }

    // MARK: Selection

    public func selectPage(_ pageID: UUID?) {
        cancelReplace()
        selectedPageID = pageID
        // Opening a page acknowledges its review flag (the flag is a
        // prompt to look at the page, cleared once the user does).
        if let pageID { reviewSet.remove(pageID) }
        refreshAlternatives()
    }

    /// Selection state machine. Default: tap selects; same slot deselects;
    /// a different slot MOVES selection (no implicit swap). In replace mode the
    /// next tap swaps the source slot's photo with the tapped slot, then exits.
    public func tapPhotoSlot(_ slotID: UUID) {
        selectedTextSlotID = nil
        if let source = replaceSourceSlotID {
            replaceSourceSlotID = nil
            if source != slotID {
                let pageSize = pageSize
                apply { EditMutations.swapPhotos(in: &$0, slotA: source, slotB: slotID, pageSize: pageSize) }
            }
            selectedSlotID = nil
            return
        }
        if selectedSlotID == slotID {
            selectedSlotID = nil
        } else {
            selectedSlotID = slotID
            // Selecting a photo also selects its page, so per-page actions
            // (density, background, reset) target the page it lives on.
            if let loc = EditMutations.locatePhotoSlot(slotID, in: document.book) {
                selectedPageID = document.book.pages[loc.pageIndex].id
            }
        }
    }

    /// After a reflow mints new slot IDs, re-point selection to the slot now
    /// holding `photoID` (and its page). Clears slot selection if the photo is
    /// no longer placed.
    private func reselectPhoto(_ photoID: PhotoID?) {
        guard let photoID else { return }
        for page in document.book.pages {
            if let slot = page.photoSlots.first(where: { $0.photoID == photoID }) {
                selectedSlotID = slot.id
                selectedPageID = page.id
                return
            }
        }
        selectedSlotID = nil
    }

    public func beginReplaceSelectedPhoto() {
        guard selectedSlotID != nil, selectedSlotHasPhoto else { return }
        replaceSourceSlotID = selectedSlotID
    }

    public func cancelReplace() {
        replaceSourceSlotID = nil
    }

    public func tapTextSlot(_ slotID: UUID) {
        cancelReplace()
        selectedSlotID = nil
        selectedTextSlotID = selectedTextSlotID == slotID ? nil : slotID
    }

    public func deselectSlots() {
        cancelReplace()
        selectedSlotID = nil
        selectedTextSlotID = nil
    }

    // MARK: Tray

    public func assignFromTray(_ photoID: PhotoID) {
        let slotID = replaceSourceSlotID ?? selectedSlotID
        replaceSourceSlotID = nil
        guard let slotID else { return }
        let pageSize = pageSize
        apply { EditMutations.assignPhoto(in: &$0, photoID: photoID, toSlot: slotID, pageSize: pageSize) }
    }

    public func removeSelectedPhoto() {
        cancelReplace()
        guard let slotID = selectedSlotID else { return }
        apply { EditMutations.removePhoto(in: &$0, fromSlot: slotID) }
    }

    // MARK: Crop

    public func beginCropEditing(_ slotID: UUID) {
        cropEditingContext = cropEditorContext(forSlot: slotID)
    }

    func cropEditorContext(forSlot slotID: UUID) -> CropEditorContext? {
        guard let location = EditMutations.locatePhotoSlot(slotID, in: document.book) else { return nil }
        let slot = document.book.pages[location.pageIndex].photoSlots[location.slotIndex]
        guard let photoID = slot.photoID,
              let ref = document.book.photoLibrary.first(where: { $0.id == photoID }),
              !ref.isMissing
        else { return nil }
        return CropEditorContext(
            slotID: slotID, photoID: photoID, baseCrop: slot.crop,
            photoAspect: ref.aspectRatio,
            slotAspect: trueSlotAspect(of: slot.frame, pageSize: pageSize))
    }

    public func commitCrop(slotID: UUID, crop: NormRect) {
        apply { EditMutations.setCrop(in: &$0, slotID: slotID, crop: crop) }
    }

    // MARK: Text

    public func beginTextEditing(_ slotID: UUID) {
        textEditingContext = textEditorContext(forSlot: slotID)
    }

    func textEditorContext(forSlot slotID: UUID) -> TextEditorContext? {
        guard let location = EditMutations.locateTextSlot(slotID, in: document.book) else { return nil }
        return TextEditorContext(
            slotID: slotID,
            text: document.book.pages[location.pageIndex].textSlots[location.slotIndex].text)
    }

    public func commitText(slotID: UUID, text: StyledText) {
        apply { EditMutations.setText(in: &$0, slotID: slotID, text: text) }
    }

    /// Add a default text box to a page, select it, and open the text editor
    /// so the user can type immediately. The box is a pinned freeform overlay.
    public func addTextSlot(toPageID pageID: UUID) {
        let newID = UUID()
        apply { EditMutations.addTextSlot(in: &$0, pageID: pageID, id: newID) }
        guard EditMutations.locateTextSlot(newID, in: document.book) != nil else { return }
        selectedSlotID = nil
        selectedTextSlotID = newID
        selectedPageID = pageID
        beginTextEditing(newID)
    }

    /// Convenience: add a text box to the currently selected page.
    public func addTextSlotToSelectedPage() {
        guard let pageID = selectedPageID else { return }
        addTextSlot(toPageID: pageID)
    }

    /// Commit a manual move/resize of a text box; locks the slot (no reflow,
    /// so IDs and selection stay stable) — mirror of `setPhotoSlotFrame`.
    public func setTextSlotFrame(_ slotID: UUID, to frame: NormRect) {
        apply { EditMutations.setTextFrame(in: &$0, slotID: slotID, frame: frame) }
    }

    /// Delete the selected text box and clear text selection.
    public func removeSelectedTextSlot() {
        guard let slotID = selectedTextSlotID else { return }
        apply { EditMutations.removeTextSlot(in: &$0, slotID: slotID) }
        selectedTextSlotID = nil
    }

    public var selectedTextSlotIsLocked: Bool {
        guard let slotID = selectedTextSlotID,
              let loc = EditMutations.locateTextSlot(slotID, in: document.book) else { return false }
        return document.book.pages[loc.pageIndex].textSlots[loc.slotIndex].isLocked
    }

    public func toggleSelectedTextSlotLock() {
        guard let slotID = selectedTextSlotID,
              let loc = EditMutations.locateTextSlot(slotID, in: document.book) else { return }
        let newValue = !document.book.pages[loc.pageIndex].textSlots[loc.slotIndex].isLocked
        apply {
            if let l = EditMutations.locateTextSlot(slotID, in: $0) {
                $0.pages[l.pageIndex].textSlots[l.slotIndex].isLocked = newValue
            }
        }
    }

    // MARK: Page lock / reorder

    public func togglePageLock(_ pageID: UUID) {
        apply { EditMutations.togglePageLock(in: &$0, pageID: pageID) }
    }

    public func toggleSelectedPageLock() {
        guard let pageID = selectedPageID else { return }
        togglePageLock(pageID)
    }

    // MARK: Edge style (D3)

    /// Sets the selected page's edge style explicitly, writing a per-page
    /// override AND re-framing the page to the new mode — even when the page or
    /// its slots are locked (an explicit edge-style change overrides the lock
    /// gate). No-op if no page selected or the page is a spread member.
    public func setSelectedPageEdgeStyle(_ style: EdgeStyle,
                                         seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID else { return }
        // Spread members carry sliced double-wide geometry; a single-page
        // candidate would desync them from their partner. Skip.
        guard document.book.pages.first(where: { $0.id == pageID })?.spreadID == nil else { return }
        let preset = preset
        let pageSize = pageSize
        apply { book in
            EditMutations.setPageEdgeStyle(in: &book, pageID: pageID, override: style)
            if let candidate = self.engine.edgeStyleCandidate(for: pageID, in: book,
                                                              edgeStyle: style, preset: preset) {
                EditMutations.applyAlternative(in: &book, candidate: candidate,
                                               pageID: pageID, pageSize: pageSize)
            }
        }
    }

    /// Sets the book-wide edge-style default, re-framing every standard
    /// non-spread page (including locked ones) to its effective mode. Spread
    /// members keep their sliced geometry.
    public func setBookEdgeStyle(_ style: EdgeStyle, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard style != document.book.style.edgeStyle else { return }
        let preset = preset
        let pageSize = pageSize
        apply { book in
            EditMutations.setBookEdgeStyle(in: &book, style)
            let pageIDs = book.pages.filter { $0.role == .standard && $0.spreadID == nil }.map(\.id)
            for pageID in pageIDs {
                guard let page = book.pages.first(where: { $0.id == pageID }) else { continue }
                let effective = page.edgeStyleOverride ?? style
                if let candidate = self.engine.edgeStyleCandidate(for: pageID, in: book,
                                                                  edgeStyle: effective, preset: preset) {
                    EditMutations.applyAlternative(in: &book, candidate: candidate,
                                                   pageID: pageID, pageSize: pageSize)
                }
            }
        }
    }

    // MARK: Background color

    /// Effective background hex of the selected page (override or book
    /// default); book default when nothing is selected. Drives the picker.
    public var selectedPageEffectiveBackgroundHex: String {
        guard let pageID = selectedPageID,
              let page = document.book.pages.first(where: { $0.id == pageID }) else {
            return document.book.style.backgroundColorHex
        }
        return page.effectiveBackgroundHex(bookDefault: document.book.style.backgroundColorHex)
    }

    public var bookBackgroundHex: String { document.book.style.backgroundColorHex }

    /// The book-wide default edge style (applied to any page without its own
    /// `edgeStyleOverride`).
    public var bookEdgeStyle: EdgeStyle { document.book.style.edgeStyle }

    public func setSelectedPageBackground(_ hex: String?) {
        guard let pageID = selectedPageID else { return }
        apply { EditMutations.setPageBackground(in: &$0, pageID: pageID, hex: hex) }
    }

    public func setBookBackground(_ hex: String) {
        apply { EditMutations.setBookBackground(in: &$0, hex: hex) }
    }

    public var selectedSlotIsLocked: Bool {
        guard let slotID = selectedSlotID,
              let location = EditMutations.locatePhotoSlot(slotID, in: document.book) else { return false }
        return document.book.pages[location.pageIndex].photoSlots[location.slotIndex].isLocked
    }

    public func toggleSelectedSlotLock() {
        guard let slotID = selectedSlotID else { return }
        apply { EditMutations.togglePhotoSlotLock(in: &$0, slotID: slotID) }
    }

    // MARK: Photo emphasis (userWeight)

    /// Step for Bigger/Smaller; larger, repeatable step for Make key.
    private static let weightStep = 1
    private static let keyStep = 2

    /// PhotoID bound to the currently selected photo slot, if any.
    private var selectedSlotPhotoID: PhotoID? {
        guard let slotID = selectedSlotID,
              let loc = EditMutations.locatePhotoSlot(slotID, in: document.book) else { return nil }
        return document.book.pages[loc.pageIndex].photoSlots[loc.slotIndex].photoID
    }

    /// Effective layout weight of the selected slot's photo (userWeight if set,
    /// else importance-derived). nil when no photo is selected.
    public var selectedPhotoWeight: Int? {
        guard let photoID = selectedSlotPhotoID,
              let ref = document.book.photoLibrary.first(where: { $0.id == photoID }) else { return nil }
        return ref.userWeight ?? ImportanceWeight.weight(forImportance: ref.importance)
    }

    public var selectedPhotoCanGrow: Bool {
        (selectedPhotoWeight ?? ImportanceWeight.maxWeight) < ImportanceWeight.maxWeight
    }

    public var selectedPhotoCanShrink: Bool {
        (selectedPhotoWeight ?? 1) > 1
    }

    public func makeSelectedPhotoBigger() { adjustSelectedPhotoWeight(by: Self.weightStep) }
    public func makeSelectedPhotoSmaller() { adjustSelectedPhotoWeight(by: -Self.weightStep) }
    public func makeSelectedPhotoKey() { adjustSelectedPhotoWeight(by: Self.keyStep) }

    private func adjustSelectedPhotoWeight(by delta: Int,
                                           seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let photoID = selectedSlotPhotoID,
              let ref = document.book.photoLibrary.first(where: { $0.id == photoID }) else { return }
        let current = ref.userWeight ?? ImportanceWeight.weight(forImportance: ref.importance)
        let target = min(max(current + delta, 1), ImportanceWeight.maxWeight)
        // No-op only when the weight is already materialized at the target,
        // so pushing against a bound (e.g. Smaller at 1) still pins userWeight.
        guard target != ref.userWeight else { return }
        let preset = preset
        apply {
            if let i = $0.photoLibrary.firstIndex(where: { $0.id == photoID }) {
                $0.photoLibrary[i].userWeight = target
            }
            $0 = self.engine.repaginateBook($0, preset: preset, seed: seed)
        }
        // repaginateBook mints new slot IDs — re-point selection to the photo.
        reselectPhoto(photoID)
    }

    // MARK: Manual placement

    /// Commit a manual move or resize of a photo slot. Writes the frame and
    /// locks the slot; no reflow, so slot IDs and selection are stable.
    public func setPhotoSlotFrame(_ slotID: UUID, to frame: NormRect) {
        apply { EditMutations.setFrame(in: &$0, slotID: slotID, frame: frame) }
    }

    /// Return the selected photo to automatic layout: unlock its slot and
    /// reshuffle just its page. Note: a page only reshuffles if it has no other
    /// locked slots (engine `isReshuffleable`); otherwise the unlock still takes
    /// effect and the photo re-flows on the next full reshuffle.
    public func resetSelectedPhotoToAutoLayout(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let slotID = selectedSlotID,
              let loc = EditMutations.locatePhotoSlot(slotID, in: document.book) else { return }
        let pageID = document.book.pages[loc.pageIndex].id
        let photoID = selectedSlotPhotoID
        let preset = preset
        apply {
            if let l = EditMutations.locatePhotoSlot(slotID, in: $0) {
                $0.pages[l.pageIndex].photoSlots[l.slotIndex].isLocked = false
            }
            $0 = self.engine.reshuffle($0, scope: .page(pageID), preset: preset, seed: seed)
        }
        reselectPhoto(photoID)
    }

    public func movePages(fromStandardOffsets source: IndexSet, toStandardOffset destination: Int) {
        apply { EditMutations.movePages(in: &$0, fromStandardOffsets: source, toStandardOffset: destination) }
    }

    // MARK: Template switch

    func applyAlternative(_ candidate: LayoutCandidate, to pageID: UUID) {
        let pageSize = pageSize
        apply { EditMutations.applyAlternative(in: &$0, candidate: candidate, pageID: pageID, pageSize: pageSize) }
    }

    func applySelectedPageAlternative(_ candidate: LayoutCandidate) {
        guard let pageID = selectedPageID else { return }
        applyAlternative(candidate, to: pageID)
    }

    // MARK: Engine operations (seeds default to the app layer's random — D10)

    public func reshuffleBook(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        let preset = preset
        apply { $0 = self.engine.reshuffle($0, scope: .book, preset: preset, seed: seed) }
    }

    public func reshuffleSelectedPage(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID else { return }
        let preset = preset
        apply { $0 = self.engine.reshuffle($0, scope: .page(pageID), preset: preset, seed: seed) }
    }

    // MARK: Per-page density stepper (Phase B)

    /// Whether the selected standard reshuffleable page can absorb one more
    /// photo from its downstream reshuffleable run.
    public var canIncreaseSelectedPageDensity: Bool {
        guard let pageID = selectedPageID,
              let page = document.book.pages.first(where: { $0.id == pageID }),
              page.role == .standard, page.spreadID == nil, !page.isLocked,
              page.photoSlots.allSatisfy({ !$0.isLocked }),
              page.textSlots.allSatisfy({ !$0.isLocked }) else { return false }
        // There must be at least one downstream reshuffleable standard page
        // whose run collectively has more photos than the target page alone.
        // The run boundary mirrors `BookEngine.repaginate`: it stops at the
        // cover, locks, AND spread members — otherwise this would over-count.
        let pages = document.book.pages
        guard let idx = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        let currentCount = page.photoSlots.count
        var runPhotoCount = 0
        var i = idx
        while i < pages.count,
              pages[i].role == .standard,
              pages[i].spreadID == nil,
              !pages[i].isLocked,
              pages[i].photoSlots.allSatisfy({ !$0.isLocked }),
              pages[i].textSlots.allSatisfy({ !$0.isLocked }) {
            runPhotoCount += pages[i].photoSlots.compactMap(\.photoID).count
            i += 1
        }
        return runPhotoCount > currentCount
    }

    /// Whether the selected standard reshuffleable page can shed one photo
    /// downstream (its current photo count is > 1).
    public var canDecreaseSelectedPageDensity: Bool {
        guard let pageID = selectedPageID,
              let page = document.book.pages.first(where: { $0.id == pageID }),
              page.role == .standard, page.spreadID == nil, !page.isLocked,
              page.photoSlots.allSatisfy({ !$0.isLocked }),
              page.textSlots.allSatisfy({ !$0.isLocked }) else { return false }
        return page.photoSlots.count > 1
    }

    public func increaseSelectedPageDensity(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID else { return }
        let photoID = selectedSlotPhotoID
        let preset = preset
        apply { $0 = self.engine.repaginate($0, fromPageID: pageID, delta: +1,
                                             preset: preset, seed: seed) }
        reselectPhoto(photoID)
    }

    public func decreaseSelectedPageDensity(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID else { return }
        let photoID = selectedSlotPhotoID
        let preset = preset
        apply { $0 = self.engine.repaginate($0, fromPageID: pageID, delta: -1,
                                             preset: preset, seed: seed) }
        reselectPhoto(photoID)
    }

    /// Restores the selected page to the book's defaults: clears its background
    /// and edge-style overrides, clears userWeight on its photos, and
    /// re-paginates. One undoable step; selection follows the photo across the
    /// reflow.
    public func resetSelectedPageToDefault(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID else { return }
        let photoID = selectedSlotPhotoID
        let preset = preset
        apply {
            EditMutations.setPageBackground(in: &$0, pageID: pageID, hex: nil)
            EditMutations.setPageEdgeStyle(in: &$0, pageID: pageID, override: nil)
            if let pIdx = $0.pages.firstIndex(where: { $0.id == pageID }) {
                for slot in $0.pages[pIdx].photoSlots {
                    if let pid = slot.photoID,
                       let i = $0.photoLibrary.firstIndex(where: { $0.id == pid }) {
                        $0.photoLibrary[i].userWeight = nil
                    }
                }
            }
            $0 = self.engine.repaginateBook($0, preset: preset, seed: seed)
        }
        reselectPhoto(photoID)
    }

    /// Re-lays the selected page at `count` photos using `candidate`, in ONE
    /// undoable step: when `count` differs from the current photo count,
    /// `repaginate` first reflows the downstream run to free/absorb photos
    /// (locked pages, locked slots, and spreads are never touched), then the
    /// chosen layout is applied. Same count → just swap the layout.
    public func applyLayoutOption(count: Int, candidate: LayoutCandidate,
                                  seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID,
              let current = document.book.pages.first(where: { $0.id == pageID })?.photoSlots.count
        else { return }
        let preset = preset
        let pageSize = pageSize
        apply { book in
            if count != current {
                book = self.engine.repaginate(book, fromPageID: pageID, delta: count - current,
                                              preset: preset, seed: seed)
            }
            EditMutations.applyAlternative(in: &book, candidate: candidate,
                                           pageID: pageID, pageSize: pageSize)
        }
    }

    // MARK: Spread convert / revert (Phase C)

    /// True when the selected page is a spread member (either half).
    var selectedPageIsSpreadMember: Bool {
        guard let pageID = selectedPageID else { return false }
        return document.book.pages.first(where: { $0.id == pageID })?.spreadID != nil
    }

    /// True when the selected standard reshuffleable page is eligible for
    /// conversion to a spread: it must be interior, not already a spread
    /// member, and its facing partner must also be standard and reshuffleable.
    public var canConvertSelectedToSpread: Bool {
        guard let pageID = selectedPageID,
              let idx = document.book.pages.firstIndex(where: { $0.id == pageID }) else { return false }
        let page = document.book.pages[idx]
        // Must be interior standard non-spread reshuffleable page.
        guard page.role == .standard,
              page.spreadID == nil,
              idx > 0,                   // not the cover
              !page.isLocked,
              page.photoSlots.allSatisfy({ !$0.isLocked }),
              page.textSlots.allSatisfy({ !$0.isLocked }) else { return false }
        // Find the facing pair for this page and check the partner.
        let spreads = SpreadPairing.spreads(for: document.book.pages)
        guard let row = spreads.first(where: { $0.left == idx || $0.right == idx }) else { return false }
        // The left page of the row is the leftPageID for convertToSpread.
        // The right page in the row must exist and also be standard/reshuffleable/non-spread.
        guard let leftIdx = row.left, let rightIdx = row.right else { return false }
        let leftPage = document.book.pages[leftIdx]
        let rightPage = document.book.pages[rightIdx]
        guard leftPage.role == .standard, leftPage.spreadID == nil,
              !leftPage.isLocked,
              leftPage.photoSlots.allSatisfy({ !$0.isLocked }),
              leftPage.textSlots.allSatisfy({ !$0.isLocked }),
              rightPage.role == .standard, rightPage.spreadID == nil,
              !rightPage.isLocked,
              rightPage.photoSlots.allSatisfy({ !$0.isLocked }),
              rightPage.textSlots.allSatisfy({ !$0.isLocked }) else { return false }
        // Both pages must have at least one photo between them.
        let hasPhotos = (leftPage.photoSlots + rightPage.photoSlots).contains { $0.photoID != nil }
        return hasPhotos
    }

    /// True when the selected page (or its spread partner) is a spread member,
    /// meaning the spread can be reverted to two independent pages.
    public var canRevertSelectedSpread: Bool {
        selectedPageIsSpreadMember
    }

    /// Converts the selected page's facing pair into a first-class spread.
    /// Resolves the selected page to the left page of its facing row, then
    /// delegates to the engine. No-op when ineligible.
    public func convertSelectedSpread(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID,
              let idx = document.book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        // Resolve the left page of the facing row.
        let spreads = SpreadPairing.spreads(for: document.book.pages)
        guard let row = spreads.first(where: { $0.left == idx || $0.right == idx }),
              let leftIdx = row.left else { return }
        let leftID = document.book.pages[leftIdx].id
        let preset = preset
        apply { $0 = self.engine.convertToSpread($0, leftPageID: leftID, preset: preset, seed: seed) }
    }

    /// Reverts the spread containing the selected page back to two independent
    /// standard pages. No-op when the selected page is not a spread member.
    public func revertSelectedSpread(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        guard let pageID = selectedPageID,
              let sid = document.book.pages.first(where: { $0.id == pageID })?.spreadID else { return }
        let preset = preset
        apply { $0 = self.engine.revertSpread($0, spreadID: sid, preset: preset, seed: seed) }
    }

    public func placeRemaining(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        let preset = preset
        apply { $0 = self.engine.placeRemaining($0, preset: preset, seed: seed) }
    }

    func refreshAlternatives() {
        guard let pageID = selectedPageID,
              document.book.pages.contains(where: { $0.id == pageID }) else {
            alternativeCandidates = []
            layoutOptionsByCount = []
            return
        }
        alternativeCandidates = engine.alternatives(for: pageID, in: document.book,
                                                    preset: preset, limit: 8)
        layoutOptionsByCount = engine.layoutOptions(for: pageID, in: document.book, preset: preset)
    }

    // MARK: Missing photos (sweep is NOT undoable — D8)

    /// Marks vanished photos: file refs via bookmark checks off the main
    /// actor; PhotoKit refs via a 32-px thumbnail probe where ONLY
    /// `assetUnavailable` counts (permission/transient errors never do).
    /// Runs with `undoManager: nil` — it records filesystem reality, not a
    /// user edit (D8).
    public func runMissingPhotoSweep() async {
        let library = document.book.photoLibrary
        var gone = await Task.detached(priority: .utility) {
            MissingPhotoSweep.stalePhotoIDs(in: library, fileExists: MissingPhotoSweep.fileExists(for:))
        }.value
        for ref in library where !ref.isMissing {
            guard case .photoKit = ref.source else { continue }
            do {
                _ = try await photoKitProvider.thumbnail(for: ref, maxPixelSize: 32)
            } catch let error as PhotoProviderError {
                if case .assetUnavailable = error { gone.insert(ref.id) }
            } catch {
                // Transient (network, cancellation): not proof of deletion.
            }
        }
        guard !gone.isEmpty else { return }
        document.mutate({ EditMutations.markMissing(in: &$0, photoIDs: gone) }, undoManager: nil)
    }

    /// Relinks every missing file-sourced photo whose filename appears in
    /// `folder`: fresh bookmark + `MetadataReader` re-read, committed under
    /// the ORIGINAL `PhotoID` in one undoable mutation (D8). Returns the
    /// number of photos relinked.
    @discardableResult
    public func relinkMissingPhotos(toFolder folder: URL) -> Int {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        let missing = document.book.photoLibrary.filter(\.isMissing)
        let matches = RelinkMatcher.matches(missing: missing, folderContents: contents,
                                            filenameForRef: MissingPhotoSweep.rememberedFilename(for:))
        var freshRefs: [PhotoID: PhotoRef] = [:]
        for (photoID, url) in matches {
            guard let bookmark = MissingPhotoSweep.makeBookmark(for: url),
                  let fresh = try? MetadataReader.photoRef(forFileAt: url, bookmark: bookmark)
            else { continue }
            freshRefs[photoID] = fresh
        }
        guard !freshRefs.isEmpty else { return 0 }
        apply { book in
            for (photoID, fresh) in freshRefs {
                EditMutations.relinkPhoto(in: &book, photoID: photoID, with: fresh)
            }
        }
        return freshRefs.count
    }

    public func removeMissingPhoto(_ photoID: PhotoID) {
        apply { EditMutations.removePhotoFromBook(in: &$0, photoID: photoID) }
    }

    // MARK: Book format (spec "Preset switch after creation")

    /// Switches the book's print preset. Same aspect class → instant:
    /// only `presetID` changes; layouts live in normalized 0–1 page
    /// space, so every page rescales untouched. Cross-class → one engine
    /// pass relayouts every reshuffleable page under the new preset
    /// (locked pages and the cover stay byte-identical per the engine's
    /// guarantee), and exactly those untouched pages are flagged in
    /// `pagesNeedingReview` — their frames were designed for the old
    /// aspect class, so the user should look at them. `presetID` updates
    /// in both branches; one undo step restores presetID + pages together
    /// and empties the review set (it is keyed to the new presetID — see
    /// `pagesNeedingReview`).
    public func changePreset(to newPreset: PrintPreset, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        let oldPreset = preset
        guard newPreset.id != oldPreset.id else { return }
        if newPreset.aspectClass == oldPreset.aspectClass {
            apply { $0.presetID = newPreset.id }
            return
        }
        let frozen = EditMutations.reshuffleFrozenPageIDs(in: document.book)
        apply {
            var relaid = self.engine.reshuffle($0, scope: .book, preset: newPreset, seed: seed)
            relaid.presetID = newPreset.id   // reshuffle never touches presetID
            $0 = relaid
        }
        reviewSet = frozen
        reviewPresetID = newPreset.id
    }

    // MARK: Live preflight (Plan 6, D12)

    @ObservationIgnored private let preflightDebouncer: Debouncer

    /// Latest debounced `Preflight.check` result; drives the sidebar's
    /// yellow warning badges and stays warm for the export flow.
    private(set) var preflightIssues: [PreflightIssue] = []

    /// Page indexes carrying at least one non-blocking warning.
    public var pageIndexesWithWarnings: Set<Int> {
        PreflightSummary(issues: preflightIssues).pageIndexesWithWarnings
    }

    /// Browser calls this on every book change; bursts coalesce into one
    /// check half a second after the last edit.
    public func schedulePreflight() {
        preflightDebouncer.schedule { [weak self] in self?.runPreflightNow() }
    }

    /// Synchronous check — also the initial kick when the browser appears.
    public func runPreflightNow() {
        preflightIssues = Preflight.check(document.book, preset: preset)
    }

    /// Blank-pads the book to the preset's minimum page count (the
    /// preflight offer for `pageCountOutOfRange`). Undoable like every edit.
    public func padToMinimumPages() {
        let preset = preset
        apply { ExportPadding.padToMinimum(in: &$0, preset: preset) }
        runPreflightNow()
    }

    // MARK: The one mutation funnel (D1)

    private func apply(_ transform: (inout Book) -> Void) {
        let before = document.book
        document.mutate(transform, undoManager: undoManager)
        // Editing or reshuffling a flagged page also resolves its review
        // flag (the spec's "review" is satisfied by any deliberate user
        // action on the page).
        if !reviewSet.isEmpty, document.book != before {
            for page in document.book.pages
            where reviewSet.contains(page.id)
                && before.pages.first(where: { $0.id == page.id }) != page {
                reviewSet.remove(page.id)
            }
        }
        refreshAlternatives()
    }
}
