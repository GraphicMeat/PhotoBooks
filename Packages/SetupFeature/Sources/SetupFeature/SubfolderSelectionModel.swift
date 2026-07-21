import Foundation
import Observation
import PhotoBookCore
import PhotoBookImport

/// Selection state for the subfolder-import sheet: which scanned folders
/// the user wants photos from, plus per-photo exclusions inside folders the
/// user has previewed. All folders start checked, nothing excluded.
@Observable
public final class SubfolderSelectionModel {

    public let folders: [FolderInfo]
    private var checked: Set<URL>

    /// Folder currently shown in the preview grid.
    public var previewFolder: FolderInfo?

    /// Photos the user deselected in the preview grid. IDs are globally
    /// unique, so one set covers all folders.
    public private(set) var excluded: Set<PhotoID> = []

    /// Lazily loaded refs per previewed folder (direct files only).
    public private(set) var refs: [URL: [PhotoRef]] = [:]

    public init(folders: [FolderInfo]) {
        self.folders = folders
        self.checked = Set(folders.map(\.url))
        self.previewFolder = folders.first
    }

    // MARK: - Folder selection

    public var allSelected: Bool { checked.count == folders.count }

    public func isChecked(_ folder: FolderInfo) -> Bool { checked.contains(folder.url) }

    public func setChecked(_ folder: FolderInfo, _ on: Bool) {
        if on { checked.insert(folder.url) } else { checked.remove(folder.url) }
    }

    /// All-on when anything is unchecked; all-off only from the
    /// everything-checked state.
    public func toggleAll() {
        checked = allSelected ? [] : Set(folders.map(\.url))
    }

    /// Checked folders in `folders` (relative-path) order.
    public var selectedURLs: [URL] {
        folders.filter { checked.contains($0.url) }.map(\.url)
    }

    // MARK: - Photo selection

    public func setRefs(_ newRefs: [PhotoRef], for url: URL) {
        refs[url] = newRefs
    }

    public func refs(for folder: FolderInfo) -> [PhotoRef]? { refs[folder.url] }

    public func isPhotoSelected(_ ref: PhotoRef, in folder: FolderInfo) -> Bool {
        isChecked(folder) && !excluded.contains(ref.id)
    }

    /// Toggles one photo. Tapping a photo inside an unchecked folder
    /// re-checks the folder with ONLY the tapped photo selected — drilling
    /// into an off folder means hand-picking, not turning everything on.
    public func togglePhoto(_ id: PhotoID, in folder: FolderInfo) {
        if !isChecked(folder) {
            setChecked(folder, true)
            if let loaded = refs[folder.url] {
                excluded.formUnion(loaded.map(\.id))
            }
            excluded.remove(id)
            return
        }
        if excluded.contains(id) { excluded.remove(id) } else { excluded.insert(id) }
    }

    // MARK: - Counts

    /// Photos this folder contributes: 0 when unchecked, otherwise its
    /// direct-file count minus exclusions made in its preview grid.
    public func selectedCount(in folder: FolderInfo) -> Int {
        guard isChecked(folder) else { return 0 }
        guard let loaded = refs[folder.url] else { return folder.imageCount }
        return loaded.count { !excluded.contains($0.id) }
    }

    public var selectedCount: Int {
        folders.map { selectedCount(in: $0) }.reduce(0, +)
    }
}
