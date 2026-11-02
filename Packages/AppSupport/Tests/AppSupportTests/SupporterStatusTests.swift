import Foundation
import Testing
@testable import AppSupport

@Suite struct SupporterStatusTests {
    private func emptyDefaults() -> UserDefaults {
        let suite = "SupporterStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func nobodyIsASupporterByDefault() {
        #expect(!SupporterStatus.isSupporter(defaults: emptyDefaults()))
    }

    @Test func donationDeepLinkMakesASupporter() {
        let defaults = emptyDefaults()
        #expect(SupporterStatus.handle(URL(string: "photobooks://donated")!, defaults: defaults))
        #expect(SupporterStatus.isSupporter(defaults: defaults))
    }

    @Test(arguments: ["photobooks://other", "https://donated", "otherapp://donated"])
    func otherLinksChangeNothing(link: String) {
        let defaults = emptyDefaults()
        #expect(!SupporterStatus.handle(URL(string: link)!, defaults: defaults))
        #expect(!SupporterStatus.isSupporter(defaults: defaults))
    }
}
