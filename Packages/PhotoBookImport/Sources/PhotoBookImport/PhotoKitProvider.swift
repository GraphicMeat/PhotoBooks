import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import Photos
import Synchronization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Thin PhotoKit adapter — pure mapping from PhotoKit types to contract
/// types, no business logic. `PHImageManager` is not unit-testable; behavior
/// is verified by the manual checklist in the plan. Everything testable
/// lives elsewhere (`MetadataReader`, `FileSystemProvider`,
/// `ImageOrientationNormalizer`).
public struct PhotoKitProvider: PhotoProvider {

    public init() {}

    /// `.readWrite` is PhotoKit's *read* access level (there is no read-only
    /// level; `.addOnly` cannot fetch). Returns `true` for `.authorized`
    /// and `.limited` — limited-library mode is fully supported.
    public static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - PhotoProvider

    /// "Recents" (the user-library smart album) first, then user albums
    /// sorted by title.
    public func collections() async throws -> [PhotoCollection] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoProviderError.permissionDenied
        }

        var collections: [PhotoCollection] = []

        let recents = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        for index in 0..<recents.count {
            collections.append(Self.photoCollection(from: recents.object(at: index)))
        }

        let albumOptions = PHFetchOptions()
        albumOptions.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: albumOptions)
        for index in 0..<albums.count {
            if Task.isCancelled { throw PhotoProviderError.cancelled }
            collections.append(Self.photoCollection(from: albums.object(at: index)))
        }
        return collections
    }

    public func photoRefs(in collection: PhotoCollection) async throws -> [PhotoRef] {
        let fetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [collection.id], options: nil)
        guard let assetCollection = fetch.firstObject else {
            // Contract has no "unknown collection" case; the collection ID
            // names the unavailable asset group.
            throw PhotoProviderError.assetUnavailable(PhotoID(rawValue: collection.id))
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: assetCollection, options: options)

        var refs: [PhotoRef] = []
        refs.reserveCapacity(assets.count)
        for index in 0..<assets.count {
            if Task.isCancelled { throw PhotoProviderError.cancelled }
            let asset = assets.object(at: index)
            refs.append(PhotoRef(
                id: PhotoID(rawValue: asset.localIdentifier),
                source: .photoKit(localIdentifier: asset.localIdentifier),
                pixelWidth: asset.pixelWidth,      // PHAsset reports display dims
                pixelHeight: asset.pixelHeight,    // (orientation already applied)
                captureDate: asset.creationDate,
                isMissing: false
            ))
        }
        return refs
    }

    /// Maps a set of PhotoKit local identifiers (e.g. from the native
    /// `PhotosPicker`) to `PhotoRef`s, preserving the caller's order.
    /// `PHFetchResult` does not guarantee input order, so build a lookup and
    /// map `identifiers` through it; identifiers with no matching asset are
    /// skipped. Not part of `PhotoProvider` — the picker path calls the
    /// concrete `PhotoKitProvider`.
    public func photoRefs(forIdentifiers identifiers: [String]) async throws -> [PhotoRef] {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        byID.reserveCapacity(fetch.count)
        for index in 0..<fetch.count {
            let asset = fetch.object(at: index)
            byID[asset.localIdentifier] = asset
        }

        var refs: [PhotoRef] = []
        refs.reserveCapacity(identifiers.count)
        for identifier in identifiers {
            if Task.isCancelled { throw PhotoProviderError.cancelled }
            guard let asset = byID[identifier] else { continue }
            refs.append(PhotoRef(
                id: PhotoID(rawValue: asset.localIdentifier),
                source: .photoKit(localIdentifier: asset.localIdentifier),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                captureDate: asset.creationDate,
                isMissing: false
            ))
        }
        return refs
    }

    public func thumbnail(for ref: PhotoRef, maxPixelSize: Int) async throws -> CGImage {
        let asset = try Self.asset(for: ref)

        let options = PHImageRequestOptions()
        // .highQualityFormat (asynchronous) delivers exactly ONE result
        // callback, so the continuation below resumes exactly once.
        // .opportunistic would deliver a degraded image first — two
        // callbacks — and trap the continuation.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true      // iCloud originals
        options.isSynchronous = false

        let tracker = RequestTracker()
        let refID = ref.id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: maxPixelSize, height: maxPixelSize),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
                        continuation.resume(throwing: PhotoProviderError.cancelled)
                        return
                    }
                    // Belt-and-braces: .highQualityFormat never delivers
                    // degraded results, but a degraded result must never
                    // resume the continuation (the final one follows).
                    if (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true {
                        return
                    }
                    if Task.isCancelled {
                        continuation.resume(throwing: PhotoProviderError.cancelled)
                        return
                    }
                    guard let cgImage = Self.cgImage(from: image) else {
                        continuation.resume(throwing: PhotoProviderError.assetUnavailable(refID))
                        return
                    }
                    continuation.resume(returning: cgImage)
                }
                tracker.store(requestID)
            }
        } onCancel: {
            tracker.cancel()
        }
    }

    /// Full-resolution original bytes via `requestImageDataAndOrientation`
    /// (single callback by definition), decoded through the shared ImageIO
    /// path with orientation normalized.
    public func fullImage(for ref: PhotoRef) async throws -> CGImage {
        let asset = try Self.asset(for: ref)

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true      // iCloud download at export time
        options.isSynchronous = false

        let tracker = RequestTracker()
        let refID = ref.id
        let (data, orientation): (Data, UInt32) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = PHImageManager.default().requestImageDataAndOrientation(
                    for: asset, options: options
                ) { data, _, orientation, info in
                    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
                        continuation.resume(throwing: PhotoProviderError.cancelled)
                        return
                    }
                    if Task.isCancelled {
                        continuation.resume(throwing: PhotoProviderError.cancelled)
                        return
                    }
                    guard let data else {
                        continuation.resume(throwing: PhotoProviderError.assetUnavailable(refID))
                        return
                    }
                    continuation.resume(returning: (data, orientation.rawValue))
                }
                tracker.store(requestID)
            }
        } onCancel: {
            tracker.cancel()
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let raw = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let upright = ImageOrientationNormalizer.normalize(raw, exifOrientation: orientation)
        else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        return upright
    }

    // MARK: - Helpers

    private static func asset(for ref: PhotoRef) throws -> PHAsset {
        guard case .photoKit(let localIdentifier) = ref.source else {
            // Filesystem refs belong to FileSystemProvider.
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else {
            throw PhotoProviderError.assetUnavailable(ref.id)
        }
        return asset
    }

    private static func photoCollection(from assetCollection: PHAssetCollection) -> PhotoCollection {
        let estimated = assetCollection.estimatedAssetCount
        return PhotoCollection(
            id: assetCollection.localIdentifier,
            title: assetCollection.localizedTitle ?? "Untitled",
            estimatedCount: estimated == NSNotFound ? nil : estimated
        )
    }

    #if canImport(UIKit)
    private static func cgImage(from image: UIImage?) -> CGImage? {
        image?.cgImage
    }
    #elseif canImport(AppKit)
    private static func cgImage(from image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    #endif

    /// Bridges Swift task cancellation to `PHImageManager` request
    /// cancellation. `onCancel` can fire before the request ID is stored;
    /// the `cancelled` flag closes that race.
    private final class RequestTracker: Sendable {
        private struct State: Sendable {
            var requestID: PHImageRequestID?
            var cancelled = false
        }

        private let state = Mutex(State())

        func store(_ requestID: PHImageRequestID) {
            let cancelNow = state.withLock { state in
                state.requestID = requestID
                return state.cancelled
            }
            if cancelNow {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }

        func cancel() {
            let requestID = state.withLock { state -> PHImageRequestID? in
                state.cancelled = true
                return state.requestID
            }
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
}
