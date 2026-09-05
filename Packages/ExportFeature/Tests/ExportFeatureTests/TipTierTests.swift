import Testing
@testable import ExportFeature

@Suite struct TipTierTests {
    @Test func productIDsMatchAppStoreConnect() {
        #expect(TipTier.coffee.productID == "com.graphicMeat.PhotoBooks.tip.coffee")
        #expect(TipTier.burger.productID == "com.graphicMeat.PhotoBooks.tip.burger")
        #expect(TipTier.steak.productID == "com.graphicMeat.PhotoBooks.tip.steak")
        #expect(TipTier.allProductIDs == TipTier.allCases.map(\.productID))
    }

    @Test func tierRoundTripsThroughProductID() {
        for tier in TipTier.allCases {
            #expect(TipTier.tier(for: tier.productID) == tier)
        }
        #expect(TipTier.tier(for: "com.graphicMeat.PhotoBooks.tip.tofu") == nil)
        #expect(TipTier.tier(for: "") == nil)
    }

    @Test func tiersAreOrderedCheapestFirst() {
        #expect(TipTier.allCases == [.coffee, .burger, .steak])
    }

    @Test func everyTierHasAnEmojiAndATitle() {
        for tier in TipTier.allCases {
            #expect(!tier.emoji.isEmpty)
            #expect(!tier.title.isEmpty)
        }
    }
}
