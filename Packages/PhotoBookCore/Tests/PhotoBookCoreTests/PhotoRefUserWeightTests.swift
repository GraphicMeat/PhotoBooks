import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PhotoRefUserWeightTests {

    private func ref() -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: "p1"),
                 source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000)
    }

    @Test func defaultsToNil() {
        #expect(ref().userWeight == nil)
    }

    @Test func decodingLegacyJSONWithoutFieldYieldsNil() throws {
        // A document saved before this feature has no "userWeight" key.
        let legacy = """
        {"id":"p1","source":{"file":{"bookmark":""}},"pixelWidth":4000,"pixelHeight":3000,"isMissing":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PhotoRef.self, from: legacy)
        #expect(decoded.userWeight == nil)
    }

    @Test func roundTripsWhenSet() throws {
        var r = ref()
        r.userWeight = 4
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(PhotoRef.self, from: data)
        #expect(back.userWeight == 4)
    }
}
