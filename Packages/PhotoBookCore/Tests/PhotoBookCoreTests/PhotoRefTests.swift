import Foundation
import Testing
import PhotoBookCore

@Suite struct PhotoRefTests {

    @Test func photoIDEncodesAsBareString() throws {
        let id = PhotoID(rawValue: "asset-123")
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"asset-123\"")
    }

    @Test func photoIDCodableRoundTrip() throws {
        let original = PhotoID(rawValue: "IMG_0042")
        let decoded = try JSONDecoder().decode(PhotoID.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func photoSourceCodableRoundTrip() throws {
        let sources: [PhotoSource] = [
            .photoKit(localIdentifier: "ABC-123/L0/001"),
            .file(bookmark: Data([0x01, 0x02, 0x03]))
        ]
        for original in sources {
            let decoded = try JSONDecoder().decode(PhotoSource.self, from: JSONEncoder().encode(original))
            #expect(decoded == original)
        }
    }

    @Test func photoRefCodableRoundTrip() throws {
        let original = PhotoRef(
            id: PhotoID(rawValue: "p1"),
            source: .photoKit(localIdentifier: "LOCAL-1"),
            pixelWidth: 4032,
            pixelHeight: 3024,
            captureDate: Date(timeIntervalSinceReferenceDate: 700_000_000),
            isMissing: false
        )
        let decoded = try JSONDecoder().decode(PhotoRef.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func photoRefAspectRatio() {
        let landscape = PhotoRef(id: PhotoID(rawValue: "l"), source: .file(bookmark: Data()),
                                 pixelWidth: 4000, pixelHeight: 3000)
        #expect(landscape.aspectRatio == 4.0 / 3.0)
        let portrait = PhotoRef(id: PhotoID(rawValue: "p"), source: .file(bookmark: Data()),
                                pixelWidth: 3000, pixelHeight: 4000)
        #expect(portrait.aspectRatio == 0.75)
    }

    @Test func defaultsAreNilCaptureDateAndNotMissing() {
        let ref = PhotoRef(id: PhotoID(rawValue: "x"), source: .file(bookmark: Data()),
                           pixelWidth: 100, pixelHeight: 100)
        #expect(ref.captureDate == nil)
        #expect(ref.isMissing == false)
    }
}
