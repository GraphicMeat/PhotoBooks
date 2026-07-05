import Testing
@testable import AppSupport

@Suite struct SpreadSeparatorTests {
    @Test func separatorShownOnlyWhenBothPagesPresent() {
        #expect(spreadSeparatorVisible(left: 2, right: 3) == true)
        #expect(spreadSeparatorVisible(left: nil, right: 0) == false)   // cover row
        #expect(spreadSeparatorVisible(left: 5, right: nil) == false)   // odd tail
        #expect(spreadSeparatorVisible(left: nil, right: nil) == false)
    }
}
