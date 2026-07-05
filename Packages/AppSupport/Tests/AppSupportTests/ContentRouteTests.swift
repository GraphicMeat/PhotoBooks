import Testing
@testable import AppSupport

@Suite struct ContentRouteTests {
    @Test func emptyNotCreatingShowsWelcome() {
        #expect(contentRoute(pagesEmpty: true, isCreating: false) == .welcome)
    }
    @Test func emptyCreatingShowsSetup() {
        #expect(contentRoute(pagesEmpty: true, isCreating: true) == .setup)
    }
    @Test func populatedShowsBrowser() {
        #expect(contentRoute(pagesEmpty: false, isCreating: false) == .browser)
        #expect(contentRoute(pagesEmpty: false, isCreating: true) == .browser)
    }
}
