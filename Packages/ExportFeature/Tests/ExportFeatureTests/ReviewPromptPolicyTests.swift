import Foundation
import Testing
@testable import ExportFeature

struct ReviewPromptPolicyTests {
    @Test func lowerRatingLocksWebsiteRouteForRestOfFlow() {
        for initial in 1...4 {
            var selection = ReviewRatingSelection()
            selection.select(initial)
            selection.select(5)
            #expect(selection.rating == 5)
            #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: selection.rating,
                handled: false, hasSelectedLowerRating: selection.hasSelectedLowerRating))
        }
    }

    @Test func fiveThenLowerThenFiveStillUsesWebsite() {
        var selection = ReviewRatingSelection()
        selection.select(5)
        #expect(ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: selection.rating,
            handled: false, hasSelectedLowerRating: selection.hasSelectedLowerRating))
        selection.select(3)
        #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: selection.rating,
            handled: false, hasSelectedLowerRating: selection.hasSelectedLowerRating))
        selection.select(5)
        #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: selection.rating,
            handled: false, hasSelectedLowerRating: selection.hasSelectedLowerRating))
    }

    @Test func appStoreInvitationAppearsOnlyAfterFiveStars() {
        for rating in 0...4 {
            #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: rating, handled: false))
        }
        #expect(ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: 5, handled: false))
    }

    @Test func handledReviewsAndDirectBuildsNeverOfferAppStore() {
        for rating in 0...5 {
            #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: true, rating: rating, handled: true))
            #expect(!ReviewPromptPolicy.shouldOfferAppStore(appStoreBuild: false, rating: rating, handled: false))
        }
    }

    @Test @MainActor func clickRemainsQueuedWithoutAConfiguredServer() throws {
        let suite = "PhotoBooks-review-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ReviewClickRecorder.record(rating: 5, defaults: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        let event = try #require(ReviewClickRecorder.pending(defaults: reopened).first)
        #expect(event.type == "app_store_review_clicked")
        #expect(event.rating == 5)
        #expect(ReviewClickRecorder.pending(defaults: reopened).count == 1)
    }
}
