import Foundation
import PhotoBookCore

/// Filesystem-reality checks for file-sourced photos. The pure cores take
/// injected closures so tests run without real bookmarks; the real
/// resolvers mirror Plan 3's D4 (security scope first, plain fallback).
public enum MissingPhotoSweep {

    /// File-sourced, not-yet-missing refs whose file no longer exists.
    /// PhotoKit refs are never judged here — the model probes those
    /// through the provider (D8).
    public static func stalePhotoIDs(in library: [PhotoRef],
                                     fileExists: (PhotoRef) -> Bool) -> Set<PhotoID> {
        var stale: Set<PhotoID> = []
        for ref in library where !ref.isMissing {
            guard case .file = ref.source else { continue }
            if !fileExists(ref) { stale.insert(ref.id) }
        }
        return stale
    }

    /// Real existence check: resolve the bookmark, then stat the path under
    /// security scope.
    public static func fileExists(for ref: PhotoRef) -> Bool {
        guard case .file(let bookmark) = ref.source,
              let url = resolvedURL(fromBookmark: bookmark) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func resolvedURL(fromBookmark bookmark: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        if let url = try? URL(resolvingBookmarkData: bookmark,
                              options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url
        }
        #endif
        return try? URL(resolvingBookmarkData: bookmark, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// The filename the bookmark remembers — what relink matching keys on.
    public static func rememberedFilename(for ref: PhotoRef) -> String? {
        guard case .file(let bookmark) = ref.source else { return nil }
        // Bookmark data embeds the original path and yields it WITHOUT
        // resolving — resolution fails outright for deleted files, and the
        // filename is exactly what relink matching needs.
        if let path = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return resolvedURL(fromBookmark: bookmark)?.lastPathComponent
    }

    /// Fresh bookmark for a relinked file (scoped on macOS — Plan 3 D4).
    public static func makeBookmark(for url: URL) -> Data? {
        #if os(macOS)
        if let scoped = try? url.bookmarkData(options: [.withSecurityScope],
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) {
            return scoped
        }
        #endif
        return try? url.bookmarkData()
    }
}

public enum RelinkMatcher {

    /// Pure matching core: missing file-sourced refs ↔ picked-folder files,
    /// keyed on last path component. `filenameForRef` is injected (the real
    /// one is `MissingPhotoSweep.rememberedFilename`); first folder entry
    /// wins on (impossible) duplicate names.
    public static func matches(missing: [PhotoRef], folderContents: [URL],
                               filenameForRef: (PhotoRef) -> String?) -> [PhotoID: URL] {
        let byName = Dictionary(folderContents.map { ($0.lastPathComponent, $0) },
                                uniquingKeysWith: { first, _ in first })
        var result: [PhotoID: URL] = [:]
        for ref in missing {
            guard case .file = ref.source, ref.isMissing,
                  let name = filenameForRef(ref), let url = byName[name] else { continue }
            result[ref.id] = url
        }
        return result
    }
}
