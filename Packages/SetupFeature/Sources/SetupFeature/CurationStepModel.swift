import Foundation
import Observation
import PhotoBookCore
import PhotoBookImport

/// State + logic for the wizard's curation step: pick a target count (N
/// photos or roughly N pages), run the on-device best-N analysis, then let
/// the user review and adjust which photos made the cut. All Vision work
/// happens in `PhotoBookImport`; this model only orchestrates it and holds
/// UI state, so it's fully testable without Vision (see `applyResults`).
@MainActor @Observable public final class CurationStepModel {

    public enum Phase: Equatable {
        case pickingTarget
        case analyzing(done: Int, total: Int)
        case reviewing
        case cancelled
    }

    public enum Unit: String, CaseIterable {
        case photos, pages
    }

    public private(set) var phase: Phase = .pickingTarget
    public var unit: Unit = .photos
    public var targetValue: Int = 50
    public private(set) var candidates: [CurationCandidate] = []
    public private(set) var pickedIDs: Set<PhotoID> = []
    /// Size of the pool `startAnalysis` will run against. Set at init and
    /// refreshed when analysis starts, so the "≈ N photos" preview is
    /// accurate even before analysis has run.
    public private(set) var availableCount: Int

    private var analysisTask: Task<[PhotoRef]?, Never>?

    public init(availableCount: Int = 0) {
        self.availableCount = availableCount
    }

    public var target: CurationTarget {
        unit == .photos ? .photos(targetValue) : .pages(targetValue)
    }

    /// Preview of how many photos `target` resolves to against the current pool.
    public var resolvedPhotoCount: Int {
        PhotoCurator.resolvedPhotoCount(for: target, available: availableCount)
    }

    public var pickedCount: Int { pickedIDs.count }

    /// Runs the Vision pipeline (one pass: importance scoring + feature
    /// prints per thumbnail, then near-duplicate clustering on the prints)
    /// and best-N selection, updating `phase` with determinate progress.
    /// Returns the analyzed refs (importance/salientCenter stamped) on
    /// success — callers must hang onto them since `candidates` only carries
    /// IDs/quality/date/cluster, not full `PhotoRef`s. Returns nil if
    /// cancelled via `cancelAnalysis()`.
    @discardableResult
    public func startAnalysis(photos: [PhotoRef], provider: any PhotoProvider) async -> [PhotoRef]? {
        availableCount = photos.count
        let total = max(photos.count, 1)
        let target = self.target
        phase = .analyzing(done: 0, total: total)

        let task = Task<[PhotoRef]?, Never> { [weak self] in
            guard let self else { return nil }
            // Single thumbnail pass: prints ride along with scoring, so
            // clustering below needs no second decode (and no second progress
            // stage — one honest 0..total pass).
            let (analyzed, scores, prints) = await ImageContentAnalyzer.analyzeWithScores(
                photos, provider: provider,
                progress: { done, _ in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(done: done, total: total)
                    }
                })
            if Task.isCancelled { return nil }

            let cands = CurationAnalyzer.candidates(for: analyzed, scores: scores, prints: prints)
            if Task.isCancelled { return nil }

            // Task {} inherits this model's MainActor isolation, so no hop is
            // needed here — and no suspension between the cancel check above
            // and applyResults means a cancel can never land in between and
            // get overwritten by .reviewing.
            let picked = PhotoCurator.select(from: cands, target: target)
            applyResults(candidates: cands, picked: picked)
            return analyzed
        }
        analysisTask = task
        return await task.value
    }

    /// Cancels the in-flight analysis (if any) and returns to the target
    /// picker. The in-flight `startAnalysis` call resolves to nil.
    public func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        phase = .cancelled
    }

    public func toggle(_ id: PhotoID) {
        if pickedIDs.contains(id) {
            pickedIDs.remove(id)
        } else {
            pickedIDs.insert(id)
        }
    }

    /// Candidates the user picked, chronological (undated last) — the
    /// review grid's "Picked" section.
    public var pickedCandidates: [CurationCandidate] {
        candidates.filter { pickedIDs.contains($0.id) }.sorted(by: Self.chronological)
    }

    /// Candidates NOT picked, grouped by cluster (quality-descending within
    /// each cluster, clusters ordered by ID) — the review grid's "Left out"
    /// section, so near-duplicates of the same moment sit together.
    public var leftOutByCluster: [(clusterID: Int, members: [CurationCandidate])] {
        let leftOut = candidates.filter { !pickedIDs.contains($0.id) }
        let grouped = Dictionary(grouping: leftOut, by: \.clusterID)
        return grouped.keys.sorted().map { cid in
            (clusterID: cid, members: grouped[cid]!.sorted(by: Self.betterFirst))
        }
    }

    // MARK: - Internal (production result path + no-Vision test seam)

    private func updateProgress(done: Int, total: Int) {
        guard case .analyzing = phase else { return }
        phase = .analyzing(done: done, total: total)
    }

    /// Sets `candidates`/`pickedIDs` and moves to `.reviewing`. Also the seam
    /// tests use to drive `leftOutByCluster`/`pickedCandidates`/`toggle` off
    /// synthetic candidates, without running the Vision pipeline.
    func applyResults(candidates: [CurationCandidate], picked: [PhotoID]) {
        self.candidates = candidates
        self.pickedIDs = Set(picked)
        self.phase = .reviewing
    }

    private static func betterFirst(_ a: CurationCandidate, _ b: CurationCandidate) -> Bool {
        if a.quality != b.quality { return a.quality > b.quality }
        return a.id.rawValue < b.id.rawValue
    }

    private static func chronological(_ a: CurationCandidate, _ b: CurationCandidate) -> Bool {
        switch (a.captureDate, b.captureDate) {
        case let (da?, db?):
            if da != db { return da < db }
            return a.id.rawValue < b.id.rawValue
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return a.id.rawValue < b.id.rawValue
        }
    }
}
