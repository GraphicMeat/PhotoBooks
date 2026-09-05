import SwiftUI
import Testing
@testable import AppSupport

@Suite struct SupportOfferTests {
    @Test func tipJarEqualsTipJar() {
        #expect(SupportOffer.tipJar == .tipJar)
    }

    @Test func donateComparesURL() {
        let url = URL(string: "https://graphicmeat.com/donate")!
        #expect(SupportOffer.donate(url) == .donate(url))
        #expect(SupportOffer.donate(url) != .donate(URL(string: "https://example.com")!))
        #expect(SupportOffer.donate(url) != .tipJar)
    }

    @MainActor
    @Test func defaultOfferIsTipJar() {
        #expect(EnvironmentValues().supportOffer == .tipJar)
    }
}
