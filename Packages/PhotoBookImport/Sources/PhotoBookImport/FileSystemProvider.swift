import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import Synchronization

/// Folder-based photo source. Folder = collection. Security-scoped bookmarks
/// re-locate files across moves and app relaunches; all pixel decodes go
/// through ImageIO.
public struct FileSystemProvider: PhotoProvider {

    /// Image file extensions imported from folders (lowercased comparison):
    /// common formats plus RAW. RAW decode support comes from ImageIO.
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif",
        "dng", "cr2", "cr3", "nef", "arw", "raf"
    ]

    private struct RegisteredFolder: Sendable {
        var url: URL
        var bookmark: Data
        var collection: PhotoCollection
    }

    /// Session-scoped folder registry. `FileSystemProvider` is a struct
    /// (pinned by the contract); shared mutable state lives behind a `Mutex`
    /// in a reference-type box so copies of the provider see one registry.
    private final class Registry: Sendable {
        let folders = Mutex<[String: RegisteredFolder]>([:])
    }

    private let registry = Registry()

    public init() {}

    // MARK: - Folder registration

    /// Registers a folder as a collection for this session. The folder URL
    /// must come from a user grant (file picker / drag-drop); this method
    /// starts security-scoped access, creates a bookmark, and counts the
    /// folder's image files for `estimatedCount`.
    ///
    /// The collection ID is derived from the folder's standardized path
    /// (same SHA-256 scheme as file `PhotoID`s), so re-registering the same
    /// folder updates the existing entry instead of duplicating it.
    public func makeCollection(fromFolder url: URL) throws -> PhotoCollection {
        let folderURL = url.standardizedFileURL
        let didStartScope = folderURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { folderURL.stopAccessingSecurityScopedResource() } }

        let bookmark: Data
        do {
            bookmark = try Self.makeBookmark(for: folderURL)
        } catch {
            // Nonexistent/unreadable folder — keep the provider's single
            // error vocabulary instead of leaking CocoaErrors.
            throw PhotoProviderError.assetUnavailable(MetadataReader.photoID(forFileAt: folderURL))
        }
        let imageCount = try imageFileURLs(in: folderURL).count

        let collection = PhotoCollection(
            id: MetadataReader.photoID(forFileAt: folderURL).rawValue,
            title: folderURL.lastPathComponent,
            estimatedCount: imageCount
        )
        registry.folders.withLock {
            $0[collection.id] = RegisteredFolder(url: folderURL, bookmark: bookmark, collection: collection)
        }
        return collection
    }

    // MARK: - PhotoProvider

    /// Folders registered via `makeCollection(fromFolder:)` this session,
    /// sorted by title (then ID) for stable ordering.
    public func collections() async throws -> [PhotoCollection] {
        registry.folders.withLock { folders in
            folders.values.map(\.collection).sorted {
                ($0.title, $0.id) < ($1.title, $1.id)
            }
        }
    }

    public func photoRefs(in collection: PhotoCollection) async throws -> [PhotoRef] {
        guard let folder = registry.folders.withLock({ $0[collection.id] }) else {
            // The contract's PhotoProviderError has no "unknown collection"
            // case; the collection ID names the unavailable asset group.
            throw PhotoProviderError.assetUnavailable(PhotoID(rawValue: collection.id))
        }

        let folderURL = folder.url
        let didStartScope = folderURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { folderURL.stopAccessingSecurityScopedResource() } }

        var refs: [PhotoRef] = []
        for fileURL in try imageFileURLs(in: folderURL) {
            if Task.isCancelled { throw PhotoProviderError.cancelled }
            // Unreadable or corrupt files are skipped, not fatal: a stray
            // text file named "broken.jpg" must not abort a folder import.
            guard let bookmark = try? Self.makeBookmark(for: fileURL),
                  let ref = try? MetadataReader.photoRef(forFileAt: fileURL, bookmark: bookmark)
            else { continue }
            refs.append(ref)
        }
        return refs
    }

    // MARK: - Decode methods (added in Task 6)

    /// Downsampled decode via `CGImageSourceCreateThumbnailAtIndex` — the
    /// spec's memory discipline for editing. Orientation is baked into the
    /// returned pixels (`kCGImageSourceCreateThumbnailWithTransform`).
    public func thumbnail(for ref: PhotoRef, maxPixelSize: Int) async throws -> CGImage {
        let fileURL = try Self.fileURL(for: ref)
        let didStartScope = fileURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { fileURL.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        let options: [CFString: Any] = [
            // Always decode from the full image — embedded EXIF thumbnails
            // have unpredictable sizes and may lack the orientation bake.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bake EXIF orientation into the pixels.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        return thumbnail
    }

    /// Full-resolution decode via `CGImageSourceCreateImageAtIndex`, then
    /// manual orientation normalization so callers always get upright pixels.
    public func fullImage(for ref: PhotoRef) async throws -> CGImage {
        let fileURL = try Self.fileURL(for: ref)
        let didStartScope = fileURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { fileURL.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let raw = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard let upright = ImageOrientationNormalizer.normalize(raw, exifOrientation: orientation) else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        return upright
    }

    private static func fileURL(for ref: PhotoRef) throws -> URL {
        guard case .file(let bookmark) = ref.source else {
            // PhotoKit refs belong to PhotoKitProvider.
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        return try resolveBookmark(bookmark, refID: ref.id)
    }

    // MARK: - Bookmarks

    /// `.withSecurityScope` on macOS so a sandboxed app can re-open
    /// user-picked files across launches. Unsandboxed processes (e.g.
    /// `swift test` on some host configurations) can be refused scoped
    /// creation — fall back to a plain bookmark (same payload minus the
    /// scope). iOS has no `.withSecurityScope` option: bookmarks of
    /// picker-granted URLs are implicitly security-scoped, so minimal
    /// (empty) options are correct.
    static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        #else
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    /// Bookmark → URL. A *stale* bookmark still resolves — we use the URL
    /// and leave refreshing the stored bookmark to the app layer (this
    /// `PhotoRef` is a value copy; mutating it here would be lost). An
    /// *unresolvable* bookmark (file deleted, garbage data) throws
    /// `.assetUnavailable` — the app layer marks the ref `isMissing` and
    /// offers the relink flow.
    static func resolveBookmark(_ bookmark: Data, refID: PhotoID) throws -> URL {
        var isStale = false
        do {
            #if os(macOS)
            // Security-scoped resolution first; unsandboxed test bookmarks
            // are plain, so fall back to scope-less resolution.
            do {
                return try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                return try URL(
                    resolvingBookmarkData: bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            }
            #else
            return try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #endif
        } catch {
            throw PhotoProviderError.assetUnavailable(refID)
        }
    }

    // MARK: - Enumeration

    /// Non-recursive enumeration of image files, sorted by filename — plain
    /// lexicographic comparison, stable across locales and runs.
    private func imageFileURLs(in folderURL: URL) throws -> [URL] {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw PhotoProviderError.assetUnavailable(MetadataReader.photoID(forFileAt: folderURL))
        }
        return contents
            .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Renders a decoded `CGImage` into a new bitmap with its EXIF orientation
/// applied, so callers always receive upright pixels. Shared by
/// `FileSystemProvider.fullImage` and `PhotoKitProvider.fullImage`.
enum ImageOrientationNormalizer {

    /// EXIF orientation semantics (CIPA DC-008):
    ///
    ///   1 upright · 2 mirrored · 3 rotated 180° · 4 flipped vertically
    ///   5 transposed (mirror + 90°) · 6 rotated 90° CW · 7 transverse
    ///   8 rotated 90° CCW
    ///
    /// Values 5–8 transpose, so output dimensions swap. Returns the input
    /// unchanged for orientation 1 (or any out-of-range value); returns
    /// `nil` only if a bitmap context cannot be created.
    static func normalize(_ image: CGImage, exifOrientation: UInt32) -> CGImage? {
        guard (2...8).contains(exifOrientation) else { return image }

        let storedWidth = CGFloat(image.width)
        let storedHeight = CGFloat(image.height)
        let swapsDimensions = exifOrientation >= 5
        let outputWidth = swapsDimensions ? storedHeight : storedWidth
        let outputHeight = swapsDimensions ? storedWidth : storedHeight

        // Rotation component (mapped from the classic UIImage orientation
        // fix, expressed directly in EXIF values).
        var transform = CGAffineTransform.identity
        switch exifOrientation {
        case 3, 4:            // 180°
            transform = transform.translatedBy(x: outputWidth, y: outputHeight).rotated(by: .pi)
        case 5, 8:            // 90° CCW of stored pixels
            transform = transform.translatedBy(x: outputWidth, y: 0).rotated(by: .pi / 2)
        case 6, 7:            // 90° CW of stored pixels
            transform = transform.translatedBy(x: 0, y: outputHeight).rotated(by: -.pi / 2)
        default:
            break
        }
        // Mirror component.
        switch exifOrientation {
        case 2, 4:            // horizontal mirror
            transform = transform.translatedBy(x: outputWidth, y: 0).scaledBy(x: -1, y: 1)
        case 5, 7:            // mirror across the transposed axis
            transform = transform.translatedBy(x: outputHeight, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(outputWidth),
                  height: Int(outputHeight),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.concatenate(transform)
        // Draw at stored dimensions; the transform maps them onto the
        // (possibly transposed) output rect.
        context.draw(image, in: CGRect(x: 0, y: 0, width: storedWidth, height: storedHeight))
        return context.makeImage()
    }
}
