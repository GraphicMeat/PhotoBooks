import CoreGraphics
import PhotoBookCore
import Testing
import PhotoBookRender

@Suite struct SmokeTests {

    /// Minimal conformance proving the protocol has exactly the pinned
    /// requirements and that PhotoBookCore types resolve cross-package.
    struct NullStore: ImageStore {
        enum NullStoreError: Error { case empty }
        func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
            throw NullStoreError.empty
        }
        func fullImage(for id: PhotoID) async throws -> CGImage {
            throw NullStoreError.empty
        }
    }

    @Test func imageStoreIsAdoptable() async {
        let store: any ImageStore = NullStore()
        await #expect(throws: NullStore.NullStoreError.empty) {
            _ = try await store.thumbnail(for: PhotoID(rawValue: "x"), maxPixelSize: 64)
        }
        await #expect(throws: NullStore.NullStoreError.empty) {
            _ = try await store.fullImage(for: PhotoID(rawValue: "x"))
        }
    }

    /// The synchronous cache peek used by `AsyncPhotoSlotView`'s first-paint
    /// fast path defaults to nil, so conformers that don't cache (mocks, the
    /// null store) stay valid and simply take the async load path.
    @Test func cachedThumbnailDefaultsToNil() {
        let store: any ImageStore = NullStore()
        #expect(store.cachedThumbnail(for: PhotoID(rawValue: "x"), maxPixelSize: 64) == nil)
    }

    /// A conformer that DOES cache is honored, so the view can paint a
    /// cached image on first frame instead of a placeholder.
    @Test func cachedThumbnailReturnsCachedImage() throws {
        struct CachingStore: ImageStore {
            let cached: CGImage
            func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage { cached }
            func fullImage(for id: PhotoID) async throws -> CGImage { cached }
            func cachedThumbnail(for id: PhotoID, maxPixelSize: Int) -> CGImage? { cached }
        }
        let image = try #require(
            CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        )
        let store: any ImageStore = CachingStore(cached: image)
        #expect(store.cachedThumbnail(for: PhotoID(rawValue: "x"), maxPixelSize: 64) != nil)
    }
}
