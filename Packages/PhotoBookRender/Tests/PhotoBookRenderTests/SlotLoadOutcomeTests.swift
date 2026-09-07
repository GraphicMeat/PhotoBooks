import CoreGraphics
import Foundation
import Testing
@testable import PhotoBookRender

/// Regression guard for the "photos are placeholders until you switch pages"
/// bug: a slot load that was CANCELLED must never latch a failure.
///
/// The providers' contract surfaces cooperative cancellation as their OWN
/// typed error (`PhotoProviderError.cancelled`), never `CancellationError`,
/// so a `catch is CancellationError` arm never matched it. The cancelled
/// task's `catch` then set `loadFailed`, and because that flag is checked
/// before the loaded image, the slot drew the missing-photo placeholder
/// until its load key changed — i.e. until the user switched pages.
@Suite struct SlotLoadOutcomeTests {

    /// Stands in for `PhotoBookImport.PhotoProviderError.cancelled`
    /// (PhotoBookRender does not depend on the import package).
    private struct ProviderCancelled: Error {}
    private struct DecodeFailed: Error {}

    @Test func successShowsTheImage() {
        #expect(SlotLoadOutcome.of(error: nil, taskCancelled: false) == .show)
    }

    @Test func genuineFailureLatchesTheMissingPlaceholder() {
        #expect(SlotLoadOutcome.of(error: DecodeFailed(), taskCancelled: false) == .fail)
    }

    /// THE bug: a typed provider cancellation on a cancelled task is not a
    /// failure, whatever its concrete error type.
    @Test func typedProviderCancellationIsIgnored() {
        #expect(SlotLoadOutcome.of(error: ProviderCancelled(), taskCancelled: true) == .ignore)
    }

    @Test func cancellationErrorIsIgnoredWithoutTheFlag() {
        #expect(SlotLoadOutcome.of(error: CancellationError(), taskCancelled: false) == .ignore)
    }

    /// A decode that finished after its key changed belongs to a slot the
    /// view no longer shows — writing it would race the new key's reset.
    @Test func lateSuccessOnACancelledTaskIsIgnored() {
        #expect(SlotLoadOutcome.of(error: nil, taskCancelled: true) == .ignore)
    }
}
