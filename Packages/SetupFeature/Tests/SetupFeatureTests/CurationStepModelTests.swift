import CoreGraphics
import Foundation
import Testing
import PhotoBookCore
import PhotoBookImport
import PhotoBookImportTestSupport
@testable import SetupFeature

/// Wraps a `MockPhotoProvider` with an artificial delay on every thumbnail
/// fetch, so cancellation tests have a real window to land in before the
/// (otherwise near-instant, tiny-image) analysis finishes.
private struct SlowPhotoProvider: PhotoProvider {
    let inner: MockPhotoProvider
    let delay: Duration

    func collections() async throws -> [PhotoCollection] { try await inner.collections() }
    func photoRefs(in collection: PhotoCollection) async throws -> [PhotoRef] {
        try await inner.photoRefs(in: collection)
    }
    func thumbnail(for ref: PhotoRef, maxPixelSize: Int) async throws -> CGImage {
        try await Task.sleep(for: delay)
        return try await inner.thumbnail(for: ref, maxPixelSize: maxPixelSize)
    }
    func fullImage(for ref: PhotoRef) async throws -> CGImage {
        try await inner.fullImage(for: ref)
    }
}

@Suite @MainActor struct CurationStepModelTests {

    private let day: TimeInterval = 86_400
    private let epoch = Date(timeIntervalSince1970: 1_600_000_000)

    private func id(_ s: String) -> PhotoID { PhotoID(rawValue: s) }

    private func candidate(
        _ id: String,
        quality: Double,
        dayOffset: Double?,
        cluster: Int,
        utility: Bool = false
    ) -> CurationCandidate {
        CurationCandidate(
            id: PhotoID(rawValue: id),
            quality: quality,
            captureDate: dayOffset.map { epoch.addingTimeInterval($0 * day) },
            clusterID: cluster,
            isUtility: utility)
    }

    // MARK: - Initial state

    @Test func startsInPickingTargetPhase() {
        let model = CurationStepModel(availableCount: 100)
        #expect(model.phase == .pickingTarget)
        #expect(model.pickedCount == 0)
        #expect(model.candidates.isEmpty)
    }

    // MARK: - Target resolution (photos ⇄ pages)

    @Test func photosUnitResolvesToTargetValueClampedToAvailable() {
        let model = CurationStepModel(availableCount: 100)
        model.unit = .photos
        model.targetValue = 40
        #expect(model.resolvedPhotoCount == 40)
    }

    @Test func photosUnitClampsToAvailableWhenTargetExceedsPool() {
        let model = CurationStepModel(availableCount: 10)
        model.unit = .photos
        model.targetValue = 40
        #expect(model.resolvedPhotoCount == 10)
    }

    @Test func pagesUnitResolvesViaRealPaginatorConstant() {
        // Paginator.idealPhotosPerPage == 2.0, so 20 pages → 40 photos.
        let model = CurationStepModel(availableCount: 1000)
        model.unit = .pages
        model.targetValue = 20
        #expect(model.resolvedPhotoCount == 40)
    }

    @Test func changingTargetValueUpdatesResolvedPhotoCount() {
        let model = CurationStepModel(availableCount: 1000)
        model.unit = .photos
        model.targetValue = 25
        #expect(model.resolvedPhotoCount == 25)
        model.targetValue = 100
        #expect(model.resolvedPhotoCount == 100)
        model.unit = .pages
        model.targetValue = 10
        #expect(model.resolvedPhotoCount == 20)
    }

    @Test func targetComputedPropertyMatchesUnit() {
        let model = CurationStepModel(availableCount: 100)
        model.unit = .photos
        model.targetValue = 40
        #expect(model.target == .photos(40))
        model.unit = .pages
        model.targetValue = 20
        #expect(model.target == .pages(20))
    }

    // MARK: - Toggle / pickedCount

    @Test func toggleAddsAndRemovesFromPickedIDs() {
        let model = CurationStepModel(availableCount: 10)
        let candidates = [candidate("a", quality: 1, dayOffset: 0, cluster: 0)]
        model.applyResults(candidates: candidates, picked: [])
        #expect(model.pickedCount == 0)

        model.toggle(id("a"))
        #expect(model.pickedCount == 1)
        #expect(model.pickedCandidates.map(\.id) == [id("a")])

        model.toggle(id("a"))
        #expect(model.pickedCount == 0)
        #expect(model.pickedCandidates.isEmpty)
    }

    // MARK: - leftOutByCluster (synthetic candidates, no Vision)

    @Test func leftOutByClusterGroupsAndSortsByQualityThenClusterID() {
        let candidates = [
            candidate("c1_hi", quality: 0.9, dayOffset: 0, cluster: 1),
            candidate("c1_lo", quality: 0.2, dayOffset: 1, cluster: 1),
            candidate("c0_hi", quality: 0.8, dayOffset: 2, cluster: 0),
            candidate("picked", quality: 0.95, dayOffset: 3, cluster: 2),
        ]
        let model = CurationStepModel(availableCount: candidates.count)
        model.applyResults(candidates: candidates, picked: [id("picked")])

        let groups = model.leftOutByCluster
        #expect(groups.map(\.clusterID) == [0, 1])   // ordered by cluster ID; cluster 2 fully picked so absent
        #expect(groups[1].members.map(\.id) == [id("c1_hi"), id("c1_lo")])   // quality desc within cluster
    }

    @Test func leftOutByClusterExcludesPickedCandidates() {
        let candidates = [
            candidate("a", quality: 1, dayOffset: 0, cluster: 0),
            candidate("b", quality: 1, dayOffset: 1, cluster: 0),
        ]
        let model = CurationStepModel(availableCount: 2)
        model.applyResults(candidates: candidates, picked: [id("a")])
        let groups = model.leftOutByCluster
        #expect(groups.count == 1)
        #expect(groups[0].members.map(\.id) == [id("b")])
    }

    // MARK: - pickedCandidates ordering

    @Test func pickedCandidatesAreChronologicalUndatedLast() {
        let candidates = [
            candidate("late", quality: 1, dayOffset: 5, cluster: 0),
            candidate("undated", quality: 1, dayOffset: nil, cluster: 1),
            candidate("early", quality: 1, dayOffset: 1, cluster: 2),
        ]
        let model = CurationStepModel(availableCount: 3)
        model.applyResults(candidates: candidates, picked: candidates.map(\.id))
        #expect(model.pickedCandidates.map(\.id) == [id("early"), id("late"), id("undated")])
    }

    @Test func pickedCandidatesTiebreaksByIDWhenDatesEqual() {
        let candidates = [
            candidate("b", quality: 1, dayOffset: 0, cluster: 0),
            candidate("a", quality: 1, dayOffset: 0, cluster: 1),
        ]
        let model = CurationStepModel(availableCount: 2)
        model.applyResults(candidates: candidates, picked: candidates.map(\.id))
        #expect(model.pickedCandidates.map(\.id) == [id("a"), id("b")])
    }

    // MARK: - applyResults moves phase to .reviewing

    @Test func applyResultsMovesPhaseToReviewing() {
        let model = CurationStepModel(availableCount: 1)
        model.applyResults(candidates: [candidate("a", quality: 1, dayOffset: 0, cluster: 0)],
                           picked: [id("a")])
        #expect(model.phase == .reviewing)
    }

    // MARK: - Cancellation

    @Test func cancelAnalysisFlipsPhaseToCancelled() {
        let model = CurationStepModel(availableCount: 5)
        model.cancelAnalysis()
        #expect(model.phase == .cancelled)
    }

    @Test func cancellingAnInFlightAnalysisReturnsNilAndSetsCancelledPhase() async {
        let provider = MockPhotoProvider()
        let refs = (0..<5).map { i -> PhotoRef in
            let img = MockPhotoProvider.makeImage(width: 8, height: 8)
            let ref = PhotoRef(id: id("p\(i)"), source: .file(bookmark: Data()),
                               pixelWidth: 8, pixelHeight: 8)
            provider.setImage(img, for: ref.id)
            return ref
        }
        let slow = SlowPhotoProvider(inner: provider, delay: .milliseconds(200))
        let model = CurationStepModel(availableCount: refs.count)
        let analysisTask = Task { await model.startAnalysis(photos: refs, provider: slow) }
        // Cancel almost immediately — the artificial per-thumbnail delay
        // guarantees this lands well before analysis would otherwise finish.
        try? await Task.sleep(for: .milliseconds(10))
        model.cancelAnalysis()
        let result = await analysisTask.value
        #expect(result == nil)
        #expect(model.phase == .cancelled)
    }
}
