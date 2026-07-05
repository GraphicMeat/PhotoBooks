import Testing
import Foundation
@testable import PhotoBookCore

struct PhotoRefImportanceTests {
    private func ref(importance: Double?) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: "a"),
                 source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000,
                 importance: importance)
    }

    @Test func importanceDefaultsToNil() {
        let r = PhotoRef(id: PhotoID(rawValue: "a"),
                         source: .file(bookmark: Data()),
                         pixelWidth: 4000, pixelHeight: 3000)
        #expect(r.importance == nil)
    }

    @Test func importanceRoundTripsThroughCodable() throws {
        let encoded = try JSONEncoder().encode(ref(importance: 0.73))
        let decoded = try JSONDecoder().decode(PhotoRef.self, from: encoded)
        #expect(decoded.importance == 0.73)
    }

    @Test func nilImportanceOmitsKeyFromJSON() throws {
        let encoded = try JSONEncoder().encode(ref(importance: nil))
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("importance"))
    }

    @Test func legacyJSONWithoutImportanceDecodesToNil() throws {
        // JSON authored before `importance` existed: the key is simply absent.
        // Plain `try` (no fallback) so that if PhotoSource's encoded shape ever
        // drifts, this backward-compat guard fails loudly instead of passing
        // vacuously.
        let legacy = """
        {"id":"a","source":{"file":{"bookmark":""}},\
        "pixelWidth":4000,"pixelHeight":3000,"isMissing":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PhotoRef.self, from: legacy)
        #expect(decoded.importance == nil)
    }
}
