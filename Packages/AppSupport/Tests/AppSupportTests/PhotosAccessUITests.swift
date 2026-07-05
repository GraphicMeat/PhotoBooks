import Photos
import Testing
@testable import AppSupport

@Suite struct PhotosAccessUITests {

    @Test func authorizedProceedsNormally() {
        #expect(photosAccessUI(for: .authorized) == .proceed)
    }

    @Test func limitedProceedsWithTheBanner() {
        // Spec: "limited mode functional" — same flow as authorized, plus
        // the informational banner with the Manage… affordance.
        #expect(photosAccessUI(for: .limited) == .proceedWithLimitedBanner)
    }

    @Test func deniedShowsTheExplainer() {
        #expect(photosAccessUI(for: .denied) == .explainer)
    }

    @Test func restrictedShowsTheExplainer() {
        // Parental controls / MDM: the user may not be ABLE to grant
        // access; the explainer's folder escape hatch is the working path.
        #expect(photosAccessUI(for: .restricted) == .explainer)
    }

    @Test func notDeterminedShowsTheExplainer() {
        // Defensive: the flow always requests first, so a still-undetermined
        // status should not occur — but if it does, the explainer (with its
        // folder escape hatch) is the safe answer.
        #expect(photosAccessUI(for: .notDetermined) == .explainer)
    }
}
