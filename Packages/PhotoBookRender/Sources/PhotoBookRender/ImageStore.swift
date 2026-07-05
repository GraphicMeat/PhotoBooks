import CoreGraphics
import PhotoBookCore

/// Bridges import to render: the app layer implements this via the photo
/// providers plus a cache (`AppImageStore`, Plan 4 App layer); tests inject
/// deterministic stubs. Renderers never talk to providers directly.
public protocol ImageStore: Sendable {
    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage
    func fullImage(for id: PhotoID) async throws -> CGImage
    /// Synchronous cache peek: returns an already-cached thumbnail for this id
    /// at (a bucket covering) `maxPixelSize`, or nil if not cached. Lets a view
    /// render a cached image on first paint instead of flashing a placeholder.
    func cachedThumbnail(for id: PhotoID, maxPixelSize: Int) -> CGImage?
}

public extension ImageStore {
    func cachedThumbnail(for id: PhotoID, maxPixelSize: Int) -> CGImage? { nil }
}
