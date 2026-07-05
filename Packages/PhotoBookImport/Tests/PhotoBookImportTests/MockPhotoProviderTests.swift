import CoreGraphics
import Foundation
import PhotoBookCore
import PhotoBookImport
import PhotoBookImportTestSupport
import Testing

@Suite struct MockPhotoProviderTests {

    private func makeRef(_ id: String) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: 40, pixelHeight: 30)
    }

    @Test func returnsStubbedCollectionsAndRefs() async throws {
        let mock = MockPhotoProvider()
        let collection = PhotoCollection(id: "c1", title: "Trip", estimatedCount: 2)
        let refs = [makeRef("p1"), makeRef("p2")]
        mock.setCollections([collection])
        mock.setPhotoRefs(refs, forCollectionID: "c1")

        #expect(try await mock.collections() == [collection])
        #expect(try await mock.photoRefs(in: collection) == refs)
    }

    @Test func servesStubbedImagesForThumbnailAndFullImage() async throws {
        let mock = MockPhotoProvider()
        let ref = makeRef("p1")
        let image = MockPhotoProvider.makeImage(width: 40, height: 30)
        mock.setImage(image, for: ref.id)

        let thumbnail = try await mock.thumbnail(for: ref, maxPixelSize: 100)
        #expect(thumbnail.width == 40)
        #expect(thumbnail.height == 30)
        let full = try await mock.fullImage(for: ref)
        #expect(full.width == 40)
    }

    @Test func recordsCallsInOrder() async throws {
        let mock = MockPhotoProvider()
        let collection = PhotoCollection(id: "c1", title: "Trip")
        let ref = makeRef("p1")
        mock.setCollections([collection])
        mock.setPhotoRefs([ref], forCollectionID: "c1")
        mock.setImage(MockPhotoProvider.makeImage(width: 4, height: 4), for: ref.id)

        _ = try await mock.collections()
        _ = try await mock.photoRefs(in: collection)
        _ = try await mock.thumbnail(for: ref, maxPixelSize: 128)
        _ = try await mock.fullImage(for: ref)

        #expect(mock.recordedCalls == [
            .collections,
            .photoRefs(collectionID: "c1"),
            .thumbnail(id: ref.id, maxPixelSize: 128),
            .fullImage(id: ref.id)
        ])
    }

    @Test func missingStubsThrowAssetUnavailable() async {
        let mock = MockPhotoProvider()
        let ref = makeRef("unknown")
        await #expect(throws: PhotoProviderError.assetUnavailable(ref.id)) {
            _ = try await mock.thumbnail(for: ref, maxPixelSize: 64)
        }
        await #expect(throws: PhotoProviderError.assetUnavailable(PhotoID(rawValue: "ghost"))) {
            _ = try await mock.photoRefs(in: PhotoCollection(id: "ghost", title: "Ghost"))
        }
    }

    @Test func stubbedErrorThrowsAndStillRecords() async {
        let mock = MockPhotoProvider()
        mock.setError(.permissionDenied)

        await #expect(throws: PhotoProviderError.permissionDenied) {
            _ = try await mock.collections()
        }
        #expect(mock.recordedCalls == [.collections])

        mock.setError(nil)
        #expect((try? await mock.collections()) != nil)
    }
}
