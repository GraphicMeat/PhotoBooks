#if DEBUG
import Foundation
import ModelLayer
import PhotoBookCore
import PhotoBookImport

/// DEBUG-only deterministic book creation for the UITest smoke path:
/// `PhotoBooks -newBookFromFixtureFolder <path>` makes every NEW document
/// open as a generated book from that folder's images — synchronously, at
/// document creation, with a fixed seed (the UITest asserts page count, so
/// nothing may be async or random).
public enum DebugFixtureBook {

    static let launchArgumentKey = "newBookFromFixtureFolder"

    /// The fixture folder passed at launch, if any.
    /// `-newBookFromFixtureFolder /path` lands in the UserDefaults argument
    /// domain under this key.
    public static var fixtureFolderFromLaunchArguments: URL? {
        guard let path = UserDefaults.standard.string(forKey: launchArgumentKey),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Synchronous folder → Book: enumerate image files (sorted by name for
    /// determinism), read metadata via `MetadataReader`, run the engine with
    /// seed 1. Plain (non-security-scoped) bookmarks: the Debug build's
    /// sandbox temp-folder read exception makes the fixture path readable.
    public static func makeBook(fixtureFolder url: URL) -> Book {
        let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif"]
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let refs = files.compactMap { file -> PhotoRef? in
            guard let bookmark = try? file.bookmarkData() else { return nil }
            return try? MetadataReader.photoRef(forFileAt: file, bookmark: bookmark)
        }

        let preset = PresetLibrary.preset(id: "blurb-small-square") ?? PresetLibrary.all()[0]
        let title = UserDefaults.standard.bool(forKey: "ScreenshotMode")
            ? "Summer Stories" : "Fixture Book"
        return BookEngine().makeBook(title: title, photos: refs, preset: preset,
                                     style: .standard, seed: 1)
    }
}
#endif
