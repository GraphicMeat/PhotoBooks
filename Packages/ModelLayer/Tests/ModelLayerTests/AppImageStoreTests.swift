import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import PhotoBookImport
import Testing
import UniformTypeIdentifiers
@testable import ModelLayer

@Suite struct AppImageStoreTests {

    /// Writes one tiny PNG fixture and returns its PhotoRef (plain bookmark).
    private func makeFixtureRef(in folder: URL, name: String,
                                width: Int, height: Int) throws -> PhotoRef {
        let url = folder.appendingPathComponent(name)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return try MetadataReader.photoRef(forFileAt: url, bookmark: url.bookmarkData())
    }

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func bucketRoundsUpTo256Multiples() {
        #expect(SlotGeometryBuckets.bucket(forMaxPixelSize: 1) == 256)
        #expect(SlotGeometryBuckets.bucket(forMaxPixelSize: 256) == 256)
        #expect(SlotGeometryBuckets.bucket(forMaxPixelSize: 257) == 512)
        #expect(SlotGeometryBuckets.bucket(forMaxPixelSize: 1000) == 1024)
    }

    @Test func thumbnailRoutesToFileProviderAndCaches() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ref = try makeFixtureRef(in: folder, name: "a.png", width: 64, height: 32)

        let refs: [PhotoID: PhotoRef] = [ref.id: ref]
        let store = AppImageStore(fileSystemProvider: FileSystemProvider(),
                                  photoKitProvider: PhotoKitProvider(),
                                  refProvider: { refs })

        let first = try await store.thumbnail(for: ref.id, maxPixelSize: 100)
        #expect(first.width <= 256 && first.height <= 256)
        #expect(first.width > 0)

        // Same bucket → cache hit → the very same CGImage object.
        let second = try await store.thumbnail(for: ref.id, maxPixelSize: 90)
        #expect(first === second)

        // Different bucket → distinct decode.
        let third = try await store.thumbnail(for: ref.id, maxPixelSize: 300)
        #expect(third !== first)
    }

    @Test func unknownPhotoIDThrowsAssetUnavailable() async {
        let store = AppImageStore(fileSystemProvider: FileSystemProvider(),
                                  photoKitProvider: PhotoKitProvider(),
                                  refProvider: { [:] })
        await #expect(throws: PhotoProviderError.assetUnavailable(PhotoID(rawValue: "nope"))) {
            _ = try await store.thumbnail(for: PhotoID(rawValue: "nope"), maxPixelSize: 100)
        }
    }

    @Test func fullImageIsUncachedPassthrough() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ref = try makeFixtureRef(in: folder, name: "b.png", width: 40, height: 40)
        let refs: [PhotoID: PhotoRef] = [ref.id: ref]
        let store = AppImageStore(fileSystemProvider: FileSystemProvider(),
                                  photoKitProvider: PhotoKitProvider(),
                                  refProvider: { refs })
        let first = try await store.fullImage(for: ref.id)
        let second = try await store.fullImage(for: ref.id)
        #expect(first.width == 40)
        #expect(first !== second)   // no caching on the full-res path
    }
}
