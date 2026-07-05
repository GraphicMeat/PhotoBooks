import Foundation
import Testing
import PhotoBookCore

@Suite struct LayoutScorerTests {

    private func portrait(_ id: String) -> AnalyzedPhoto {
        AnalyzedPhoto(
            ref: PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                          pixelWidth: 3024, pixelHeight: 4032),   // aspect 0.75
            orientation: .portrait, clusterIndex: 0)
    }

    /// The "two-side-by-side" template frames on a 10×8 page.
    private let sideBySideFrames = [
        NormRect(x: 0.05, y: 0.05, width: 0.435, height: 0.90),
        NormRect(x: 0.515, y: 0.05, width: 0.435, height: 0.90)
    ]

    private func context(needsTextZone: Bool = false) -> LayoutContext {
        LayoutContext(pageSize: SizeInches(width: 10, height: 8), style: .standard,
                      needsTextZone: needsTextZone, seed: 1)
    }

    // GOLDEN NUMBER — every component hand-computed.
    //
    // Candidate: two-side-by-side frames, two portrait photos (aspect 0.75),
    // page 10×8 (aspect 1.25), no previous page, no text zone needed.
    //
    // 1. Orientation fit (weight 0.40):
    //    slot true aspect = (0.435 / 0.90) × 1.25 = 0.483333… × 1.25 = 0.604166…
    //    visible fraction = min(0.604166…, 0.75) / max(0.604166…, 0.75)
    //                     = 0.604166… / 0.75 = 29/36 = 0.805555…  (both slots)
    //    component = 0.805555…
    // 2. Whitespace balance (weight 0.15):
    //    covered = 2 × 0.435 × 0.90 = 0.783 → whitespace = 0.217
    //    |0.217 − 0.18| = 0.037 → 1 − 0.037/0.5 = 0.926
    // 3. Visual weight symmetry (weight 0.15): mirrored frames → centroid
    //    exactly (0.5, 0.5) → 1.0
    // 4. Adjacency variety (weight 0.15): no previous page → 1.0
    // 5. Text zone (weight 0.15): not needed → 1.0
    //
    // total = 0.40 × 0.805555… + 0.15 × 0.926 + 0.15 + 0.15 + 0.15
    //       = 0.322222… + 0.1389 + 0.45
    //       = 0.911122222222…
    @Test func goldenScoreTwoPortraitsSideBySide() {
        let candidate = LayoutCandidate(origin: .template(id: "two-side-by-side"),
                                        photoSlotFrames: sideBySideFrames,
                                        textSlotFrames: [])
        let score = LayoutScorer().score(candidate, photos: [portrait("a"), portrait("b")],
                                         context: context(), previousPage: nil)
        #expect(abs(score - 0.9111222222222222) < 1e-9)
    }

    // GOLDEN NUMBER — penalty side.
    //
    // Same candidate and photos, but:
    // - previousPage has the SAME frames → adjacency variety = 0
    // - context.needsTextZone = true and the candidate has no text frames
    //   → text zone availability = 0
    //
    // total = 0.322222… + 0.1389 + 0.15 + 0 + 0 = 0.611122222222…
    @Test func goldenScoreRepeatedShapeAndMissingTextZone() {
        let candidate = LayoutCandidate(origin: .template(id: "two-side-by-side"),
                                        photoSlotFrames: sideBySideFrames,
                                        textSlotFrames: [])
        let previous = Page(origin: .template(id: "two-side-by-side"),
                            photoSlots: sideBySideFrames.map { PhotoSlot(frame: $0) })
        let score = LayoutScorer().score(candidate, photos: [portrait("a"), portrait("b")],
                                         context: context(needsTextZone: true),
                                         previousPage: previous)
        #expect(abs(score - 0.6111222222222222) < 1e-9)
    }

    @Test func differentShapeThanPreviousPageScoresHigherThanRepeat() {
        let scorer = LayoutScorer()
        let photos = [portrait("a"), portrait("b")]
        let repeated = LayoutCandidate(origin: .template(id: "two-side-by-side"),
                                       photoSlotFrames: sideBySideFrames,
                                       textSlotFrames: [])
        let stackedFrames = [
            NormRect(x: 0.05, y: 0.05, width: 0.90, height: 0.435),
            NormRect(x: 0.05, y: 0.515, width: 0.90, height: 0.435)
        ]
        let previous = Page(origin: .template(id: "two-side-by-side"),
                            photoSlots: sideBySideFrames.map { PhotoSlot(frame: $0) })
        let repeatScore = scorer.score(repeated, photos: photos,
                                       context: context(), previousPage: previous)
        // Same geometry, but the previous page was stacked → no repeat.
        let variedPrevious = Page(origin: .template(id: "two-stacked"),
                                  photoSlots: stackedFrames.map { PhotoSlot(frame: $0) })
        let variedScore = scorer.score(repeated, photos: photos,
                                       context: context(), previousPage: variedPrevious)
        #expect(variedScore > repeatScore)
        #expect(abs(variedScore - repeatScore - 0.15) < 1e-9)   // exactly the variety weight
    }

    @Test func betterOrientationFitScoresHigher() {
        // Portrait photos: portrait-ish slots (side-by-side) must beat
        // landscape-ish slots (stacked) on a landscape page, all else equal.
        let scorer = LayoutScorer()
        let photos = [portrait("a"), portrait("b")]
        let sideBySide = LayoutCandidate(origin: .template(id: "two-side-by-side"),
                                         photoSlotFrames: sideBySideFrames,
                                         textSlotFrames: [])
        let stacked = LayoutCandidate(origin: .template(id: "two-stacked"),
                                      photoSlotFrames: [
                                          NormRect(x: 0.05, y: 0.05, width: 0.90, height: 0.435),
                                          NormRect(x: 0.05, y: 0.515, width: 0.90, height: 0.435)
                                      ],
                                      textSlotFrames: [])
        let sideScore = scorer.score(sideBySide, photos: photos, context: context(), previousPage: nil)
        let stackedScore = scorer.score(stacked, photos: photos, context: context(), previousPage: nil)
        #expect(sideScore > stackedScore)
    }

    @Test func lopsidedLayoutScoresLowerThanCentered() {
        let scorer = LayoutScorer()
        let photos = [portrait("a")]
        let centered = LayoutCandidate(origin: .template(id: "x"),
                                       photoSlotFrames: [NormRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)],
                                       textSlotFrames: [])
        let cornered = LayoutCandidate(origin: .template(id: "y"),
                                       photoSlotFrames: [NormRect(x: 0.0, y: 0.0, width: 0.4, height: 0.6)],
                                       textSlotFrames: [])
        let centeredScore = scorer.score(centered, photos: photos, context: context(), previousPage: nil)
        let corneredScore = scorer.score(cornered, photos: photos, context: context(), previousPage: nil)
        #expect(centeredScore > corneredScore)
    }

    @Test func textZoneSatisfactionBeatsAbsenceWhenNeeded() {
        let scorer = LayoutScorer()
        let photos = [portrait("a"), portrait("b")]
        let withText = LayoutCandidate(
            origin: .template(id: "two-side-by-side-caption"),
            photoSlotFrames: [
                NormRect(x: 0.05, y: 0.05, width: 0.435, height: 0.78),
                NormRect(x: 0.515, y: 0.05, width: 0.435, height: 0.78)
            ],
            textSlotFrames: [NormRect(x: 0.05, y: 0.86, width: 0.90, height: 0.09)])
        let withoutText = LayoutCandidate(origin: .template(id: "two-side-by-side"),
                                          photoSlotFrames: sideBySideFrames,
                                          textSlotFrames: [])
        let withScore = scorer.score(withText, photos: photos,
                                     context: context(needsTextZone: true), previousPage: nil)
        let withoutScore = scorer.score(withoutText, photos: photos,
                                        context: context(needsTextZone: true), previousPage: nil)
        #expect(withScore > withoutScore)
    }
}
