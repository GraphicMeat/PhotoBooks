import Foundation
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
}
