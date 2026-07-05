import Foundation
import PhotoBookCore

/// Pure mutation cores for every v1 edit (D2). Each function transforms a
/// `Book` in place and is the body of a `BookDocument.mutate` closure in
/// `BookEditorModel` — pure and unit-testable without UI or a document.
/// A failed precondition (unknown slot/page ID) leaves the book untouched,
/// which `mutate`'s no-op detection turns into "no undo registered".
public enum EditMutations {

    /// (pageIndex, photoSlotIndex) of a photo slot, scanning all pages.
    public static func locatePhotoSlot(_ slotID: UUID, in book: Book) -> (pageIndex: Int, slotIndex: Int)? {
        for (pageIndex, page) in book.pages.enumerated() {
            if let slotIndex = page.photoSlots.firstIndex(where: { $0.id == slotID }) {
                return (pageIndex, slotIndex)
            }
        }
        return nil
    }

    /// (pageIndex, textSlotIndex) of a text slot, scanning all pages.
    public static func locateTextSlot(_ slotID: UUID, in book: Book) -> (pageIndex: Int, slotIndex: Int)? {
        for (pageIndex, page) in book.pages.enumerated() {
            if let slotIndex = page.textSlots.firstIndex(where: { $0.id == slotID }) {
                return (pageIndex, slotIndex)
            }
        }
        return nil
    }

    /// Library photos not placed in any photo slot, in stable library order.
    public static func unplacedPhotoIDs(in book: Book) -> [PhotoID] {
        var placed = Set<PhotoID>()
        for page in book.pages {
            for slot in page.photoSlots {
                if let photoID = slot.photoID { placed.insert(photoID) }
            }
        }
        return book.photoLibrary.map(\.id).filter { !placed.contains($0) }
    }

    /// Centered aspect-fill crop for whatever photo sits in the slot; `.full`
    /// for an empty slot or a dangling photo ID.
    private static func recomputedCrop(photoID: PhotoID?, frame: NormRect,
                                       in book: Book, pageSize: SizeInches) -> NormRect {
        guard let photoID,
              let ref = book.photoLibrary.first(where: { $0.id == photoID })
        else { return .full }
        return defaultCrop(photoAspect: ref.aspectRatio,
                            slotAspect: trueSlotAspect(of: frame, pageSize: pageSize))
    }

    // MARK: Swap

    /// Exchanges the photos of two slots (same or different pages; one side
    /// may be empty — that moves the photo). Both crops reset to the centered
    /// aspect-fill crop for their new occupant; both slots lock (D12).
    public static func swapPhotos(in book: inout Book, slotA: UUID, slotB: UUID, pageSize: SizeInches) {
        guard slotA != slotB,
              let a = locatePhotoSlot(slotA, in: book),
              let b = locatePhotoSlot(slotB, in: book) else { return }
        let photoA = book.pages[a.pageIndex].photoSlots[a.slotIndex].photoID
        let photoB = book.pages[b.pageIndex].photoSlots[b.slotIndex].photoID
        setSlot(in: &book, at: a, photoID: photoB, pageSize: pageSize)
        setSlot(in: &book, at: b, photoID: photoA, pageSize: pageSize)
    }

    private static func setSlot(in book: inout Book, at location: (pageIndex: Int, slotIndex: Int),
                                photoID: PhotoID?, pageSize: SizeInches) {
        var slot = book.pages[location.pageIndex].photoSlots[location.slotIndex]
        slot.photoID = photoID
        slot.crop = recomputedCrop(photoID: photoID, frame: slot.frame, in: book, pageSize: pageSize)
        slot.isLocked = (photoID != nil)
        book.pages[location.pageIndex].photoSlots[location.slotIndex] = slot
    }

    // MARK: Tray assign / remove

    /// Puts a library photo into a slot (empty or occupied — a replaced photo
    /// simply becomes unplaced). Crop recomputes; the slot locks.
    public static func assignPhoto(in book: inout Book, photoID: PhotoID, toSlot slotID: UUID,
                                   pageSize: SizeInches) {
        guard book.photoLibrary.contains(where: { $0.id == photoID }),
              let location = locatePhotoSlot(slotID, in: book) else { return }
        setSlot(in: &book, at: location, photoID: photoID, pageSize: pageSize)
    }

    /// Empties a slot back to the tray. The slot stays (frame untouched),
    /// its lock clears, crop resets — the engine may fill it again.
    public static func removePhoto(in book: inout Book, fromSlot slotID: UUID) {
        guard let location = locatePhotoSlot(slotID, in: book) else { return }
        var slot = book.pages[location.pageIndex].photoSlots[location.slotIndex]
        guard slot.photoID != nil else { return }
        slot.photoID = nil
        slot.crop = .full
        slot.isLocked = false
        book.pages[location.pageIndex].photoSlots[location.slotIndex] = slot
    }

    // MARK: Crop / text commits

    /// Commits a crop editor result; the slot locks (manual edit).
    public static func setCrop(in book: inout Book, slotID: UUID, crop: NormRect) {
        guard let location = locatePhotoSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].photoSlots[location.slotIndex].crop = crop
        book.pages[location.pageIndex].photoSlots[location.slotIndex].isLocked = true
    }

    /// Commits a manual move/resize; the slot locks so the engine leaves it put.
    public static func setFrame(in book: inout Book, slotID: UUID, frame: NormRect) {
        guard let location = locatePhotoSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].photoSlots[location.slotIndex].frame = frame
        book.pages[location.pageIndex].photoSlots[location.slotIndex].isLocked = true
    }

    /// Commits a text editor result; the slot locks (manual edit).
    public static func setText(in book: inout Book, slotID: UUID, text: StyledText) {
        guard let location = locateTextSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].textSlots[location.slotIndex].text = text
        book.pages[location.pageIndex].textSlots[location.slotIndex].isLocked = true
    }

    // MARK: Text slot lifecycle (freeform placement)

    /// Adds a default, pinned text box to a page (interior pages only — the
    /// caller gates on role). `isLocked = true`: user text is a freeform
    /// overlay the engine never moves or deletes. The `id` is supplied by the
    /// caller so it can select + open the editor on the new box.
    public static func addTextSlot(in book: inout Book, pageID: UUID, id: UUID = UUID()) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        let slot = TextSlot(
            id: id,
            frame: NormRect(x: 0.25, y: 0.42, width: 0.50, height: 0.16),
            text: StyledText(string: "Text", fontName: "",
                             pointSizeFactor: 0.05, colorHex: "#000000",
                             alignment: .center),
            isLocked: true)
        book.pages[index].textSlots.append(slot)
    }

    /// Commits a manual text-box move/resize; keeps the slot locked so the
    /// engine leaves it put (mirror of `setFrame` for photo slots).
    public static func setTextFrame(in book: inout Book, slotID: UUID, frame: NormRect) {
        guard let location = locateTextSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].textSlots[location.slotIndex].frame = frame
        book.pages[location.pageIndex].textSlots[location.slotIndex].isLocked = true
    }

    /// Deletes a text box from its page.
    public static func removeTextSlot(in book: inout Book, slotID: UUID) {
        guard let location = locateTextSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].textSlots.remove(at: location.slotIndex)
    }

    // MARK: Page lock

    public static func togglePageLock(in book: inout Book, pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        book.pages[index].isLocked.toggle()
    }

    /// Manually toggles a photo slot's lock. Unlocking returns the slot's
    /// content to the engine's pool (spec lock model: lock state visible,
    /// undoable, and reversible).
    public static func togglePhotoSlotLock(in book: inout Book, slotID: UUID) {
        guard let location = locatePhotoSlot(slotID, in: book) else { return }
        book.pages[location.pageIndex].photoSlots[location.slotIndex].isLocked.toggle()
    }

    /// Pages a `.book`-scope reshuffle leaves untouched: the cover (the
    /// engine relayouts standard pages only) plus every page frozen by the
    /// conservative lock policy (Plan 2: a page is reshuffleable only when
    /// neither it nor any of its slots is locked). `changePreset` flags
    /// exactly these pages for review on a cross-class switch — their
    /// frames were designed for the old aspect class.
    public static func reshuffleFrozenPageIDs(in book: Book) -> Set<UUID> {
        Set(book.pages.filter { page in
            page.role == .cover
                || page.isLocked
                || page.photoSlots.contains(where: \.isLocked)
                || page.textSlots.contains(where: \.isLocked)
        }.map(\.id))
    }

    // MARK: Template switch

    /// Applies an engine `LayoutCandidate` to a page: photos flow into the
    /// new frames in slot order (extra photos drop to the tray, missing ones
    /// leave empty slots), crops recompute, slot locks carry over BY SLOT ORDER
    /// (photos in the order they appear in photoSlots), text content carries
    /// over in order, and the page records the candidate's origin (D9).
    public static func applyAlternative(in book: inout Book, candidate: LayoutCandidate,
                                        pageID: UUID, pageSize: SizeInches) {
        guard let pageIndex = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var page = book.pages[pageIndex]

        let placements = page.photoSlots.compactMap { slot in
            slot.photoID.map { (photoID: $0, wasLocked: slot.isLocked) }
        }
        var newPhotoSlots: [PhotoSlot] = []
        for (index, frame) in candidate.photoSlotFrames.enumerated() {
            if index < placements.count {
                let placement = placements[index]
                newPhotoSlots.append(PhotoSlot(
                    frame: frame,
                    photoID: placement.photoID,
                    crop: recomputedCrop(photoID: placement.photoID, frame: frame,
                                         in: book, pageSize: pageSize),
                    isLocked: placement.wasLocked))
            } else {
                newPhotoSlots.append(PhotoSlot(frame: frame))
            }
        }

        let oldTexts = page.textSlots
        var newTextSlots: [TextSlot] = []
        for (index, frame) in candidate.textSlotFrames.enumerated() {
            if index < oldTexts.count {
                newTextSlots.append(TextSlot(frame: frame, text: oldTexts[index].text,
                                             isLocked: oldTexts[index].isLocked))
            } else {
                // Same empty-text defaults the engine uses for fresh zones.
                newTextSlots.append(TextSlot(frame: frame,
                                             text: StyledText(string: "", fontName: "",
                                                              pointSizeFactor: 0.04,
                                                              colorHex: "#000000",
                                                              alignment: .center)))
            }
        }

        page.photoSlots = newPhotoSlots
        page.textSlots = newTextSlots
        page.origin = candidate.origin
        book.pages[pageIndex] = page
    }

    // MARK: Page reorder (cover pinned)

    /// Reorders STANDARD pages; the cover (pages[0] when role == .cover)
    /// never moves. Offsets are in standard-page space: offset 0 is the first
    /// page AFTER the cover. Semantics match SwiftUI's
    /// `onMove(fromOffsets:toOffset:)` — `destination` is expressed in
    /// pre-removal indices (parity-tested exhaustively, D7).
    public static func movePages(in book: inout Book, fromStandardOffsets source: IndexSet,
                                 toStandardOffset destination: Int) {
        let coverCount = (book.pages.first?.role == .cover) ? 1 : 0
        let standard = Array(book.pages.dropFirst(coverCount))
        let sortedSource = source.sorted().filter { standard.indices.contains($0) }
        guard !sortedSource.isEmpty, destination >= 0, destination <= standard.count else { return }

        let moved = sortedSource.map { standard[$0] }
        let removedBeforeDestination = sortedSource.filter { $0 < destination }.count
        var remaining = standard
        for index in sortedSource.reversed() { remaining.remove(at: index) }
        remaining.insert(contentsOf: moved, at: destination - removedBeforeDestination)
        book.pages = Array(book.pages.prefix(coverCount)) + remaining
    }

    // MARK: Edge style (D3)

    /// Sets or clears the per-page edge-style override.
    /// Pass `nil` to inherit from the book's style default.
    /// Leaves the book untouched if the pageID is not found.
    public static func setPageEdgeStyle(in book: inout Book, pageID: UUID, override: EdgeStyle?) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        book.pages[index].edgeStyleOverride = override
    }

    /// Sets the book-wide edge-style default in `book.style`.
    public static func setBookEdgeStyle(in book: inout Book, _ style: EdgeStyle) {
        book.style.edgeStyle = style
    }

    // MARK: Background color

    /// Sets or clears the per-page background override (`nil` = inherit book
    /// default). No-op for an unknown page id.
    public static func setPageBackground(in book: inout Book, pageID: UUID, hex: String?) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        book.pages[index].backgroundColorHex = hex
    }

    /// Sets the book-wide default background.
    public static func setBookBackground(in book: inout Book, hex: String) {
        book.style.backgroundColorHex = hex
    }

    // MARK: Missing photos

    /// Marks library refs missing (stale bookmark / deleted asset).
    public static func markMissing(in book: inout Book, photoIDs: Set<PhotoID>) {
        for index in book.photoLibrary.indices
        where photoIDs.contains(book.photoLibrary[index].id) && !book.photoLibrary[index].isMissing {
            book.photoLibrary[index].isMissing = true
        }
    }

    /// Replaces a missing ref's source with a freshly read one, KEEPING the
    /// original `PhotoID` (slots reference the ID; `MetadataReader` derives a
    /// new path-based ID that must not leak into the library — D8).
    public static func relinkPhoto(in book: inout Book, photoID: PhotoID, with fresh: PhotoRef) {
        guard let index = book.photoLibrary.firstIndex(where: { $0.id == photoID }) else { return }
        var updated = fresh
        updated.id = photoID
        updated.isMissing = false
        book.photoLibrary[index] = updated
    }

    /// Removes a photo from the book entirely: every slot referencing it is
    /// emptied (crop reset, lock cleared — the engine may refill them) and
    /// the library ref is dropped. The PhotoKit-deleted path: relinking is
    /// impossible, so the user removes instead (D8).
    public static func removePhotoFromBook(in book: inout Book, photoID: PhotoID) {
        guard book.photoLibrary.contains(where: { $0.id == photoID }) else { return }
        for pageIndex in book.pages.indices {
            for slotIndex in book.pages[pageIndex].photoSlots.indices
            where book.pages[pageIndex].photoSlots[slotIndex].photoID == photoID {
                book.pages[pageIndex].photoSlots[slotIndex].photoID = nil
                book.pages[pageIndex].photoSlots[slotIndex].crop = .full
                book.pages[pageIndex].photoSlots[slotIndex].isLocked = false
            }
        }
        // The back cover holds a photo slot OUTSIDE `book.pages[]`; clear it
        // the same way or its slot would keep pointing at the dropped photo.
        if book.backCover != nil {
            for slotIndex in book.backCover!.photoSlots.indices
            where book.backCover!.photoSlots[slotIndex].photoID == photoID {
                book.backCover!.photoSlots[slotIndex].photoID = nil
                book.backCover!.photoSlots[slotIndex].crop = .full
                book.backCover!.photoSlots[slotIndex].isLocked = false
            }
        }
        book.photoLibrary.removeAll { $0.id == photoID }
    }
}
