import CoreGraphics
import PhotoBookCore

/// A browsable group of photos: a Photos album or a filesystem folder.
public struct PhotoCollection: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var estimatedCount: Int?

    public init(id: String, title: String, estimatedCount: Int? = nil) {
        self.id = id
        self.title = title
        self.estimatedCount = estimatedCount
    }
}

/// Errors shared by all photo providers.
///
/// `Equatable` conformance is additive to the contract (the contract pins the
/// cases; tests and app-layer error handling need equality).
public enum PhotoProviderError: Error, Equatable {
    case permissionDenied
    case assetUnavailable(PhotoID)
    case cancelled
}

/// Source-agnostic photo access. Async and cancellable: implementations check
/// `Task.isCancelled` inside enumeration loops and surface cooperative
/// cancellation as `PhotoProviderError.cancelled`.
public protocol PhotoProvider: Sendable {
    func collections() async throws -> [PhotoCollection]
    func photoRefs(in collection: PhotoCollection) async throws -> [PhotoRef]
    func thumbnail(for ref: PhotoRef, maxPixelSize: Int) async throws -> CGImage
    func fullImage(for ref: PhotoRef) async throws -> CGImage
}
