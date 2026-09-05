import Foundation
import Testing
@testable import ExportFeature

@Suite struct TipTierTests {
    @Test func productIDsMatchAppStoreConnect() {
        #expect(TipTier.coffee.productID == "com.graphicMeat.PhotoBooks.tip.coffee")
        #expect(TipTier.burger.productID == "com.graphicMeat.PhotoBooks.tip.burger")
        #expect(TipTier.steak.productID == "com.graphicMeat.PhotoBooks.tip.steak")
        #expect(TipTier.bbq.productID == "com.graphicMeat.PhotoBooks.tip.bbq")
        #expect(TipTier.brisket.productID == "com.graphicMeat.PhotoBooks.tip.brisket")
        #expect(TipTier.cow.productID == "com.graphicMeat.PhotoBooks.tip.cow")
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
        #expect(TipTier.allCases == [.coffee, .burger, .steak, .bbq, .brisket, .cow])
    }

    @Test func everyTierHasAnEmojiAndATitle() {
        for tier in TipTier.allCases {
            #expect(!tier.emoji.isEmpty)
            #expect(!tier.title.isEmpty)
        }
    }

    @Test func storeKitConfigurationListsEveryTier() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/PhotoBooks.storekit")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let products = try #require(json?["products"] as? [[String: Any]])
        #expect(products.compactMap { $0["productID"] as? String } == TipTier.allProductIDs)
    }
}
