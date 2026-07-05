import CoreGraphics
import PhotoBookCore
import PhotoBookImport
import Synchronization

/// Configurable in-memory `PhotoProvider` for tests — used by this package's
/// own tests and by app-layer/renderer plans (import `PhotoBookImportTestSupport`).
/// Thread-safe; records every call in order.
public final class MockPhotoProvider: PhotoProvider {

    /// One recorded provider call, in invocation order.
    public enum Call: Equatable, Sendable {
        case collections
        case photoRefs(collectionID: String)
        case thumbnail(id: PhotoID, maxPixelSize: Int)
        case fullImage(id: PhotoID)
    }

    private struct State: Sendable {
        var collections: [PhotoCollection] = []
        var refsByCollectionID: [String: [PhotoRef]] = [:]
        var imagesByID: [PhotoID: CGImage] = [:]
        var stubbedError: PhotoProviderError?
        var recordedCalls: [Call] = []
    }

    private let state = Mutex(State())

    public init() {}

    // MARK: - Configuration

    public func setCollections(_ collections: [PhotoCollection]) {
        state.withLock { $0.collections = collections }
    }

    public func setPhotoRefs(_ refs: [PhotoRef], forCollectionID id: String) {
        state.withLock { $0.refsByCollectionID[id] = refs }
    }

    /// Serves `image` for both `thumbnail` and `fullImage` of `id`.
    public func setImage(_ image: CGImage, for id: PhotoID) {
        state.withLock { $0.imagesByID[id] = image }
    }

    /// While set, every provider call throws this error (calls are still
    /// recorded). Pass `nil` to clear.
    public func setError(_ error: PhotoProviderError?) {
        state.withLock { $0.stubbedError = error }
    }

    /// Every provider call made so far, in order.
    public var recordedCalls: [Call] {
        state.withLock { $0.recordedCalls }
    }

    // MARK: - PhotoProvider

    public func collections() async throws -> [PhotoCollection] {
        try state.withLock { state in
            state.recordedCalls.append(.collections)
            if let error = state.stubbedError { throw error }
            return state.collections
        }
    }

    public func photoRefs(in collection: PhotoCollection) async throws -> [PhotoRef] {
        try state.withLock { state in
            state.recordedCalls.append(.photoRefs(collectionID: collection.id))
            if let error = state.stubbedError { throw error }
            guard let refs = state.refsByCollectionID[collection.id] else {
                throw PhotoProviderError.assetUnavailable(PhotoID(rawValue: collection.id))
            }
            return refs
        }
    }

    public func thumbnail(for ref: PhotoRef, maxPixelSize: Int) async throws -> CGImage {
        try state.withLock { state in
            state.recordedCalls.append(.thumbnail(id: ref.id, maxPixelSize: maxPixelSize))
            if let error = state.stubbedError { throw error }
            guard let image = state.imagesByID[ref.id] else {
                throw PhotoProviderError.assetUnavailable(ref.id)
            }
            return image
        }
    }

    public func fullImage(for ref: PhotoRef) async throws -> CGImage {
        try state.withLock { state in
            state.recordedCalls.append(.fullImage(id: ref.id))
            if let error = state.stubbedError { throw error }
            guard let image = state.imagesByID[ref.id] else {
                throw PhotoProviderError.assetUnavailable(ref.id)
            }
            return image
        }
    }

    // MARK: - Image factory

    /// Convenience for tests: an opaque solid-gray sRGB image of the given
    /// pixel size. Traps on failure — a host that cannot allocate a tiny
    /// bitmap context cannot run tests at all.
    public static func makeImage(width: Int, height: Int) -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            fatalError("MockPhotoProvider.makeImage: cannot create bitmap context")
        }
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("MockPhotoProvider.makeImage: cannot render image")
        }
        return image
    }
}
