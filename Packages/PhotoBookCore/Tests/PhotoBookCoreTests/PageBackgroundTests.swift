import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PageBackgroundTests {
    private func page(bg: String?) -> Page {
        Page(origin: .template(id: "x"), photoSlots: [], textSlots: [],
             backgroundColorHex: bg)
    }
    @Test func overrideWins() {
        #expect(page(bg: "#112233").effectiveBackgroundHex(bookDefault: "#FFFFFF") == "#112233")
    }
    @Test func nilInheritsBookDefault() {
        #expect(page(bg: nil).effectiveBackgroundHex(bookDefault: "#FFFFFF") == "#FFFFFF")
    }
    @Test func absentKeyDecodesToNil() throws {
        let json = #"{"id":"\#(UUID().uuidString)","role":"standard","origin":{"template":{"id":"x"}},"photoSlots":[],"textSlots":[],"isLocked":false}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Page.self, from: data)
        #expect(decoded.backgroundColorHex == nil)
    }
}
