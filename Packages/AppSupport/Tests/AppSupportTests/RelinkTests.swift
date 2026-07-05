import Foundation
import PhotoBookCore
import Testing
@testable import AppSupport

@Suite struct RelinkTests {

    private func fileRef(_ name: String, missing: Bool = false) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: name), source: .file(bookmark: Data(name.utf8)),
                 pixelWidth: 100, pixelHeight: 100, isMissing: missing)
    }

    private func photoKitRef(_ name: String, missing: Bool = false) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: name), source: .photoKit(localIdentifier: name),
                 pixelWidth: 100, pixelHeight: 100, isMissing: missing)
    }

    // MARK: Sweep core

    @Test func stalePhotoIDsFlagsOnlyVanishedFileRefs() {
        let library = [fileRef("gone"), fileRef("ok"), photoKitRef("pk"),
                       fileRef("already", missing: true)]
        let stale = MissingPhotoSweep.stalePhotoIDs(in: library) { ref in
            ref.id.rawValue == "ok"   // only "ok" still exists
        }
        #expect(stale == [PhotoID(rawValue: "gone")])
    }

    @Test func stalePhotoIDsAreEmptyWhenEverythingResolves() {
        let library = [fileRef("a"), fileRef("b")]
        #expect(MissingPhotoSweep.stalePhotoIDs(in: library) { _ in true }.isEmpty)
    }

    // MARK: Relink matching

    @Test func matcherMatchesByLastPathComponent() {
        let missing = [fileRef("m1", missing: true), fileRef("m2", missing: true)]
        let folder = [URL(fileURLWithPath: "/picked/IMG_0001.jpg"),
                      URL(fileURLWithPath: "/picked/IMG_0002.jpg"),
                      URL(fileURLWithPath: "/picked/unrelated.png")]
        let names = [PhotoID(rawValue: "m1"): "IMG_0001.jpg",
                     PhotoID(rawValue: "m2"): "IMG_0404.jpg"]   // m2 has no match
        let matches = RelinkMatcher.matches(missing: missing, folderContents: folder) {
            names[$0.id]
        }
        #expect(matches == [PhotoID(rawValue: "m1"): URL(fileURLWithPath: "/picked/IMG_0001.jpg")])
    }

    @Test func matcherSkipsPhotoKitAndResolvedRefs() {
        let refs = [photoKitRef("pk", missing: true), fileRef("resolved", missing: false)]
        let folder = [URL(fileURLWithPath: "/picked/any.jpg")]
        let matches = RelinkMatcher.matches(missing: refs, folderContents: folder) { _ in "any.jpg" }
        #expect(matches.isEmpty)
    }

    @Test func matcherSkipsRefsWithUnknownFilenames() {
        let missing = [fileRef("m1", missing: true)]
        let folder = [URL(fileURLWithPath: "/picked/IMG_0001.jpg")]
        let matches = RelinkMatcher.matches(missing: missing, folderContents: folder) { _ in nil }
        #expect(matches.isEmpty)
    }

    @Test func rememberedFilenameSurvivesFileDeletion() throws {
        // A deleted file's bookmark no longer resolves, but its stored path
        // still yields the filename relink matching keys on.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelinkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("IMG_4242.jpg")
        try Data([0xFF]).write(to: file)
        let bookmark = try file.bookmarkData()
        try FileManager.default.removeItem(at: file)

        let ref = PhotoRef(id: PhotoID(rawValue: "gone"), source: .file(bookmark: bookmark),
                           pixelWidth: 10, pixelHeight: 10, isMissing: true)
        #expect(MissingPhotoSweep.rememberedFilename(for: ref) == "IMG_4242.jpg")
        #expect(MissingPhotoSweep.rememberedFilename(for: photoKitRef("pk")) == nil)
    }
}
