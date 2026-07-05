import CoreGraphics
import Foundation
import PhotoBookCore
import PhotoBookImport
import PhotoBookRender

/// The app's `ImageStore`: routes a `PhotoID` to its `PhotoRef` (via a
/// closure reading the CURRENT document book — refs change when Plan 5
/// adds relinking, so they are never captured), then to the matching
/// provider by source. Thumbnails are cached per (id, size-bucket);
/// `fullImage` is an uncached passthrough — export (Plan 6) streams
/// full-res page-by-page and must not pin them in memory.
public final class AppImageStore: ImageStore {
    private let fileSystemProvider: FileSystemProvider
    private let photoKitProvider: PhotoKitProvider
    private let refProvider: @Sendable () -> [PhotoID: PhotoRef]
    private let cache = ThumbnailCache()

    public init(fileSystemProvider: FileSystemProvider,
                photoKitProvider: PhotoKitProvider,
                refProvider: @escaping @Sendable () -> [PhotoID: PhotoRef]) {
        self.fileSystemProvider = fileSystemProvider
        self.photoKitProvider = photoKitProvider
        self.refProvider = refProvider
    }

    public func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
        let bucket = SlotGeometryBuckets.bucket(forMaxPixelSize: maxPixelSize)
        if let cached = cache.image(for: id, bucket: bucket) { return cached }
        let ref = try ref(for: id)
        let image = try await provider(for: ref).thumbnail(for: ref, maxPixelSize: bucket)
        cache.store(image, for: id, bucket: bucket)
        return image
    }

    public func cachedThumbnail(for id: PhotoID, maxPixelSize: Int) -> CGImage? {
        let bucket = SlotGeometryBuckets.bucket(forMaxPixelSize: maxPixelSize)
        return cache.image(for: id, bucket: bucket)
    }

    public func fullImage(for id: PhotoID) async throws -> CGImage {
        let ref = try ref(for: id)
        return try await provider(for: ref).fullImage(for: ref)
    }

    private func ref(for id: PhotoID) throws -> PhotoRef {
        guard let ref = refProvider()[id] else {
            throw PhotoProviderError.assetUnavailable(id)
        }
        return ref
    }

    private func provider(for ref: PhotoRef) -> any PhotoProvider {
        switch ref.source {
        case .photoKit: photoKitProvider
        case .file: fileSystemProvider
        }
    }
}

/// Size bucketing for cache keys: requests are rounded UP to 256 px
/// multiples so a resizing window reuses one cached decode per bucket
/// instead of re-decoding every pixel of drag.
enum SlotGeometryBuckets {
    static func bucket(forMaxPixelSize maxPixelSize: Int) -> Int {
        max(256, (maxPixelSize + 255) / 256 * 256)
    }
}

/// `NSCache` wrapper for decoded thumbnails. `NSCache` is thread-safe and
/// evicts under memory pressure (the spec's editing memory discipline);
/// the wrapper exists because `NSCache` needs class keys and a cost model.
final class ThumbnailCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImage>()

    init(totalCostLimitBytes: Int = 256 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    private func key(_ id: PhotoID, _ bucket: Int) -> NSString {
        "\(id.rawValue)#\(bucket)" as NSString
    }

    func image(for id: PhotoID, bucket: Int) -> CGImage? {
        cache.object(forKey: key(id, bucket))
    }

    func store(_ image: CGImage, for id: PhotoID, bucket: Int) {
        cache.setObject(image, forKey: key(id, bucket), cost: image.bytesPerRow * image.height)
    }
}
