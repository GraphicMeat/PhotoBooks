import Foundation
import PhotoBookCore
import PhotoBookImport
import Testing
@testable import SetupFeature

@Suite struct SubfolderSelectionModelTests {

    private func makeFolders() -> [FolderInfo] {
        [
            FolderInfo(url: URL(fileURLWithPath: "/root"), relativePath: "", imageCount: 3),
            FolderInfo(url: URL(fileURLWithPath: "/root/a"), relativePath: "a", imageCount: 5),
            FolderInfo(url: URL(fileURLWithPath: "/root/b"), relativePath: "b", imageCount: 2)
        ]
    }

    private func makeRefs(_ names: [String]) -> [PhotoRef] {
        names.map { name in
            PhotoRef(id: PhotoID(rawValue: name), source: .file(bookmark: Data()),
                     pixelWidth: 8, pixelHeight: 8, captureDate: nil, isMissing: false)
        }
    }

    @Test func startsAllCheckedWithTotalCount() {
        let model = SubfolderSelectionModel(folders: makeFolders())
        #expect(model.allSelected)
        #expect(model.selectedCount == 10)
        #expect(model.selectedURLs.count == 3)
    }

    @Test func uncheckingUpdatesCountAndOrder() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        model.setChecked(folders[1], false)
        #expect(!model.allSelected)
        #expect(model.selectedCount == 5)
        #expect(model.selectedURLs == [folders[0].url, folders[2].url])
        model.setChecked(folders[1], true)
        #expect(model.selectedCount == 10)
    }

    @Test func toggleAllFlips() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        model.toggleAll()
        #expect(model.selectedCount == 0)
        #expect(model.selectedURLs.isEmpty)
        model.toggleAll()
        #expect(model.allSelected)
        // Partial selection → toggleAll selects everything.
        model.setChecked(folders[0], false)
        model.toggleAll()
        #expect(model.allSelected)
    }

    @Test func previewStartsOnFirstFolder() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        #expect(model.previewFolder == folders[0])
    }

    @Test func excludingPhotosAdjustsCounts() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        let refs = makeRefs(["a1", "a2", "a3", "a4", "a5"])
        model.setRefs(refs, for: folders[1].url)

        model.togglePhoto(refs[0].id, in: folders[1])
        model.togglePhoto(refs[1].id, in: folders[1])
        #expect(model.selectedCount(in: folders[1]) == 3)
        #expect(model.selectedCount == 8)      // 3 + 3 + 2
        #expect(!model.isPhotoSelected(refs[0], in: folders[1]))
        #expect(model.isPhotoSelected(refs[2], in: folders[1]))

        model.togglePhoto(refs[0].id, in: folders[1])   // re-include
        #expect(model.selectedCount == 9)
    }

    @Test func uncheckedFolderContributesZeroAndPhotoTapRechecks() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        let refs = makeRefs(["b1", "b2"])
        model.setRefs(refs, for: folders[2].url)

        model.setChecked(folders[2], false)
        #expect(model.selectedCount(in: folders[2]) == 0)
        #expect(!model.isPhotoSelected(refs[0], in: folders[2]))

        // Tapping a photo in an unchecked folder re-checks the folder with
        // only the tapped photo selected.
        model.togglePhoto(refs[0].id, in: folders[2])
        #expect(model.isChecked(folders[2]))
        #expect(model.isPhotoSelected(refs[0], in: folders[2]))
        #expect(!model.isPhotoSelected(refs[1], in: folders[2]))
        #expect(model.selectedCount(in: folders[2]) == 1)
    }

    @Test func unloadedFolderUsesScanCount() {
        let folders = makeFolders()
        let model = SubfolderSelectionModel(folders: folders)
        #expect(model.selectedCount(in: folders[0]) == 3)   // no refs loaded
    }
}
