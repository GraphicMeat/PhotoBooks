import Foundation
import PhotoBookCore
import Testing
import PhotoBookImport

@Suite struct SmokeTests {

    /// Proves the PhotoBookCore dependency resolves and Plan 1's public
    /// memberwise inits are available cross-module.
    @Test func coreTypesAreReachable() {
        let ref = PhotoRef(
            id: PhotoID(rawValue: "smoke"),
            source: .file(bookmark: Data()),
            pixelWidth: 100,
            pixelHeight: 50
        )
        #expect(ref.aspectRatio == 2.0)
        #expect(ref.captureDate == nil)
        #expect(ref.isMissing == false)
    }
}
