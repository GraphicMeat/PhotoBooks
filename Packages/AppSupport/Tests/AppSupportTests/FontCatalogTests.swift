import Foundation
import Testing
@testable import AppSupport

@Suite struct FontCatalogTests {

    @Test func familiesAreNonEmptyAndSorted() {
        let families = FontCatalog.families()
        #expect(!families.isEmpty)
        let names = families.map(\.displayName)
        #expect(names == names.sorted())
    }

    @Test func everyFamilyCarriesAPostScriptName() {
        #expect(FontCatalog.families().allSatisfy { !$0.postScriptName.isEmpty })
    }

    @Test func helveticaIsAvailableOnApplePlatforms() {
        #expect(FontCatalog.families().contains { $0.displayName == "Helvetica" })
    }
}
