import Foundation
import Observation
import PhotoBookImport

/// Selection state for the subfolder-import sheet: which scanned folders
/// the user wants photos from. All folders start checked.
@Observable
public final class SubfolderSelectionModel {

    public let folders: [FolderInfo]
    private var checked: Set<URL>

    public init(folders: [FolderInfo]) {
        self.folders = folders
        self.checked = Set(folders.map(\.url))
    }

    public var selectedCount: Int {
        folders.filter { checked.contains($0.url) }.map(\.imageCount).reduce(0, +)
    }

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
}
