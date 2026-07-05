import Foundation
import PhotoBookCore
import Testing
import PhotoBookImport

@Suite struct PhotoProviderContractTests {

    @Test func photoCollectionMemberwiseInitAndIdentity() {
        let collection = PhotoCollection(id: "folder-1", title: "Holiday", estimatedCount: 12)
        #expect(collection.id == "folder-1")
        #expect(collection.title == "Holiday")
        #expect(collection.estimatedCount == 12)

        let unknownCount = PhotoCollection(id: "folder-2", title: "Misc")
        #expect(unknownCount.estimatedCount == nil)
    }

    @Test func photoCollectionEquality() {
        let a = PhotoCollection(id: "x", title: "X", estimatedCount: 1)
        let b = PhotoCollection(id: "x", title: "X", estimatedCount: 1)
        let c = PhotoCollection(id: "y", title: "X", estimatedCount: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func photoProviderErrorEquality() {
        #expect(PhotoProviderError.permissionDenied == .permissionDenied)
        #expect(PhotoProviderError.cancelled == .cancelled)
        #expect(PhotoProviderError.permissionDenied != .cancelled)
        #expect(PhotoProviderError.assetUnavailable(PhotoID(rawValue: "a"))
                == .assetUnavailable(PhotoID(rawValue: "a")))
        #expect(PhotoProviderError.assetUnavailable(PhotoID(rawValue: "a"))
                != .assetUnavailable(PhotoID(rawValue: "b")))
        #expect(PhotoProviderError.assetUnavailable(PhotoID(rawValue: "a")) != .cancelled)
    }
}
