# Best-N Curation + Two-Page Spreads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-select the best N photos from thousands (quality + dedupe + time diversity, with review grid in the new-book wizard), then add four 2-page spread templates with auto-promotion, a spread layout strip, and gutter-safe cropping.

**Architecture:** Vision work (aesthetics, feature prints) stays in `PhotoBookImport`; the pure selection algorithm (`PhotoCurator`) and all engine changes live in `PhotoBookCore`; wizard UI in `SetupFeature`; editor strip in `EditorFeature`/`ModelLayer`. Spec: `docs/superpowers/specs/2026-07-12-curation-and-spreads-design.md` — read it first.

**Tech Stack:** Swift 6, SPM packages, XCTest, Vision framework (macOS 15 / iOS 18 floor), xcodegen for the app project.

**Conventions (read before any task):**
- TDD: failing test → minimal code → green → commit. Run package tests with `swift test --package-path Packages/<Pkg>`.
- PhotoBookCore is pure — no Vision/IO imports there, ever.
- Engine determinism is load-bearing: consume seeds/IDs unconditionally, in fixed order (see `Spread.slice()` and `BookEngine.buildSpread` for the pattern).
- Commit after each task: `git add <files> && git commit` with a concise message. Do not push.
- If you add app-target test files, run `xcodegen generate` (gotcha: project is generated, new files silently not built otherwise). SPM package tests don't need this.

---

## Feature A — Best-N Curation

### Task A1: Schema v5 — `PhotoRef.salientCenter` (Sonnet)

**Files:**
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Model/PhotoRef.swift`
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Model/Book.swift` (`currentSchemaVersion` 4 → 5, version-history comment)
- Test: `Packages/PhotoBookCore/Tests/PhotoBookCoreTests/` (find the existing serializer/schema test file and extend it)

- [ ] **Step 1: Write failing tests**: (a) `PhotoRef` with `salientCenter: NormPoint(x: 0.7, y: 0.4)` round-trips through `BookSerializer`; (b) a v4-encoded book JSON (no `salientCenter` key, `schemaVersion: 4`) decodes with `salientCenter == nil`; (c) freshly encoded book stamps `schemaVersion == 5`. Follow the exact pattern of the existing v3→v4 tests in the schema test file.
- [ ] **Step 2: Run tests, verify they fail** (`swift test --package-path Packages/PhotoBookCore --filter <TestClass>`).
- [ ] **Step 3: Implement**: add `public var salientCenter: NormPoint?` to `PhotoRef` (decode with `decodeIfPresent`; check whether `PhotoRef` has explicit `CodingKeys`/init(from:) — if synthesized, the optional is automatic). Bump `Book.currentSchemaVersion` to 5 and add history comment `v4→v5: PhotoRef.salientCenter (optional, additive — decodeIfPresent → nil)`. Add the pass-through migration step exactly like v3/v4 did (check `migrationStep` — additive versions may need only the version-stamp transform). Confirm `NormPoint` exists in PhotoBookCore; if only `NormRect` exists, add a minimal `public struct NormPoint: Codable, Hashable, Sendable { public var x: Double; public var y: Double }` next to `NormRect`.
- [ ] **Step 4: Full package tests green**: `swift test --package-path Packages/PhotoBookCore`.
- [ ] **Step 5: Commit** (`feat: schema v5 — PhotoRef.salientCenter`).

### Task A2: Aesthetics + utility + salient center in `ImageContentAnalyzer` (Opus)

**Files:**
- Modify: `Packages/PhotoBookImport/Sources/PhotoBookImport/ImageContentAnalyzer.swift`
- Test: `Packages/PhotoBookImport/Tests/PhotoBookImportTests/` (extend existing analyzer tests; use `PhotoBookImportTestSupport` fixtures/patterns)

**Interface to build (exact):**
```swift
public struct ImportanceScore: Equatable, Sendable {
    public var faces: Double
    public var saliency: Double
    public var sharpness: Double
    public var aesthetics: Double?     // VNCalculateImageAestheticsScoresRequest.overallScore mapped [-1,1]→[0,1]; nil if request failed
    public var isUtility: Bool         // from aesthetics observation; false when unavailable
    public var salientCenter: NormPoint?  // center of best salient object rect (area×confidence winner); nil if none
    public var importance: Double      // existing blend, unchanged formula
    public var quality: Double         // aesthetics != nil ? 0.5*importance + 0.5*aesthetics! : importance
}
```
- `blend(faces:saliency:sharpness:)` unchanged (byte-compat with existing importance).
- `score(image:)` runs the existing requests plus `VNCalculateImageAestheticsScoresRequest` in the same handler pass; aesthetics failure → `aesthetics = nil`, `isUtility = false` (spec: defensive fallback, quality falls back to importance).
- `analyze(_:provider:...)` additionally stamps `ref.salientCenter` (Vision rect is bottom-left normalized — convert to top-left image space consistent with `NormRect` conventions used elsewhere; check how crop rects are oriented in `SlotGeometry` and match).
- Expose the pure blend/quality math as static funcs so tests don't need Vision.

- [ ] **Step 1: Failing tests** (pure math first): `quality == importance` when aesthetics nil; `quality == 0.5*importance + 0.5*aes` otherwise; aesthetics [-1,1]→[0,1] mapping (−1→0, 0→0.5, 1→1, clamped). Then integration-ish: `analyze` stamps `salientCenter` on refs for a generated test image with an off-center high-contrast subject (follow existing analyzer test patterns — they already generate synthetic CGImages for face/saliency tests; reuse those helpers).
- [ ] **Step 2: Verify fail.**
- [ ] **Step 3: Implement minimal.**
- [ ] **Step 4: `swift test --package-path Packages/PhotoBookImport` green.**
- [ ] **Step 5: Commit** (`feat: aesthetics score, utility flag, salient center in ImageContentAnalyzer`).

### Task A3: `CurationAnalyzer` — feature-print near-dupe clustering (Opus)

**Files:**
- Create: `Packages/PhotoBookImport/Sources/PhotoBookImport/CurationAnalyzer.swift`
- Test: `Packages/PhotoBookImport/Tests/PhotoBookImportTests/CurationAnalyzerTests.swift`

**Interface (exact):**
```swift
public struct CurationCandidate: Equatable, Sendable, Identifiable {
    public var id: PhotoID
    public var quality: Double
    public var captureDate: Date?
    public var clusterID: Int      // 0-based; singleton photos get their own cluster
    public var isUtility: Bool
}

public enum CurationAnalyzer {
    public static let duplicateDistanceThreshold: Float = 0.5   // tune against Vision docs; VNFeaturePrintObservation.computeDistance
    public static let burstTimeWindow: TimeInterval = 600       // 10 min

    // Pure, testable core: cluster by (distance < threshold && time gap <= window).
    // `distance` injected so tests never touch Vision.
    static func clusters(
        photos: [(id: PhotoID, captureDate: Date?)],
        distance: (PhotoID, PhotoID) -> Float
    ) -> [PhotoID: Int]

    // Production entry: computes VNGenerateImageFeaturePrintRequest per 256px thumbnail
    // (reuse ImageContentAnalyzer's bounded-concurrency + progress + cancellation pattern),
    // then calls the pure core. Refs must already be analyzed (quality from ImportanceScore path).
    public static func candidates(
        for refs: [PhotoRef],
        provider: any PhotoProvider,
        quality: [PhotoID: Double],
        utility: Set<PhotoID>,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async -> [CurationCandidate]
}
```
**Algorithm for `clusters`:** sort by captureDate (nil-dated last, stable); union-find; compare each photo only against neighbors within `burstTimeWindow` in the sorted order (sliding window — never O(n²) across the full set); nil-dated photos are only compared among themselves within the trailing group, same window semantics treating them as equal-time. Union when `distance < duplicateDistanceThreshold`. Cluster IDs = order of first appearance (deterministic).

- [ ] **Step 1: Failing tests for the pure core**: burst of 5 near-identical (distance 0.1) within 2 min → one cluster; same distance but 3 h apart → separate clusters; distance 2.0 within 1 min → separate; determinism (same input → same IDs); window is sliding (A~B, B~C chains merge even if A–C gap > window? No — union-find merges via B; assert that); 1,000 synthetic photos completes fast (sanity, not a benchmark).
- [ ] **Step 2: Verify fail.** — **Step 3: Implement.** — **Step 4: Package green.**
- [ ] **Step 5: Commit** (`feat: CurationAnalyzer near-duplicate clustering`).

### Task A4: `PhotoCurator` — pure selection algorithm (Opus)

**Files:**
- Create: `Packages/PhotoBookCore/Sources/PhotoBookCore/Curation/PhotoCurator.swift`
- Create: `Packages/PhotoBookCore/Tests/PhotoBookCoreTests/PhotoCuratorTests.swift`

**PhotoBookCore is pure** — so `CurationCandidate` must be visible here. Move the struct into PhotoBookCore (`Curation/CurationCandidate.swift`) and have PhotoBookImport (which depends on Core) use it; adjust Task A3's import accordingly (A3 and A4 executors coordinate via the orchestrator; whichever runs second fixes the import).

**Interface (exact):**
```swift
public enum CurationTarget: Equatable, Sendable {
    case photos(Int)
    case pages(Int)   // photoCount = pages * Paginator.idealPhotosPerPage, rounded, clamped [1, available]
}

public enum PhotoCurator {
    public static func select(from candidates: [CurationCandidate], target: CurationTarget) -> [PhotoID]
}
```
**Algorithm (spec §A3, exact):**
1. Resolve N from target (clamp to non-utility candidate count).
2. Drop `isUtility` candidates.
3. Within each cluster sort by (quality desc, id asc); representative = first.
4. Buckets: sort dated candidates by captureDate; split the date span into `min(N, clusterCount)` equal-duration buckets; undated candidates form one trailing bucket.
5. Round-robin buckets in chronological order; each visit picks the highest-(quality, id-asc-tiebreak) *cluster representative* not yet picked whose cluster is unpicked, from that bucket; skip empty buckets.
6. When every cluster has one pick and N not reached: continue round-robin picking best remaining *members* (second-best per cluster, etc.).
7. Stop at N. Return in pick order? No — return sorted by captureDate (nil last, id-tiebreak) so book order is chronological.

- [ ] **Step 1: Failing tests**: (a) determinism — same input twice → identical output; (b) cluster exclusivity — 3 clusters × 10 members, N=3 → exactly one per cluster; (c) overflow — same, N=5 → 3 reps + 2 second-bests, still max ⌈N/clusters⌉ spread; (d) time coverage — 100 photos across 10 distinct days, N=10 → at least 8 distinct days represented; (e) utility never picked even when N > non-utility count; (f) `.pages(20)` with idealPhotosPerPage 2.0 → 40 photos; (g) N > available → all non-utility returned; (h) output chronological; (i) all-nil-dates still works.
- [ ] **Step 2: Verify fail.** — **Step 3: Implement.** — **Step 4: `swift test --package-path Packages/PhotoBookCore` green** (confirm `Paginator.idealPhotosPerPage` is accessible; if `internal`, add a `public static` accessor or mirror the constant with a cross-reference comment).
- [ ] **Step 5: Commit** (`feat: PhotoCurator best-N selection`).

### Task A5: Wizard curation step — state model + UI (Sonnet)

**Files:**
- Create: `Packages/SetupFeature/Sources/SetupFeature/CurationStepModel.swift` (pure observable state — all logic here, testable)
- Create: `Packages/SetupFeature/Sources/SetupFeature/CurationStepView.swift`
- Modify: `Packages/SetupFeature/Sources/SetupFeature/NewBookSetupView.swift` (add `case curation` to `Step`, route flows)
- Modify: `Packages/SetupFeature/Package.swift` (add `SetupFeatureTests` test target — none exists)
- Create: `Packages/SetupFeature/Tests/SetupFeatureTests/CurationStepModelTests.swift`

**`CurationStepModel` (exact):**
```swift
@MainActor @Observable
public final class CurationStepModel {
    public enum Phase { case pickingTarget, analyzing(done: Int, total: Int), reviewing }
    public enum Unit: String, CaseIterable { case photos, pages }

    public private(set) var phase: Phase = .pickingTarget
    public var unit: Unit = .photos
    public var targetValue: Int = 50            // presets 25/50/100 + custom stepper
    public private(set) var candidates: [CurationCandidate] = []
    public private(set) var pickedIDs: Set<PhotoID> = []
    public var photoCount: Int                  // resolved N (pages → photos via CurationTarget)
    public var pickedCount: Int { pickedIDs.count }

    public func startAnalysis(...)              // runs ImageContentAnalyzer.analyze + CurationAnalyzer.candidates + PhotoCurator.select; cancellable
    public func cancelAnalysis()                // → caller falls back to use-all
    public func toggle(_ id: PhotoID)
    public var leftOutByCluster: [(clusterID: Int, members: [CurationCandidate])]  // quality-sorted within cluster
}
```
**Wizard routing:** Photos flow `.photoGrid` Continue → `.curation` (operates on grid-selected set); folder flow `handleFolderPick` → `.curation` (today jumps to `.preset`). "Use all photos" button and analysis-cancel both → `.preset` with the full set (exact current behavior). Review grid: two `LazyVGrid` sections (Picked / Left out grouped by cluster) reusing `ProviderThumbnailCell`; tap toggles; live "97 of 100" count; Continue → `.preset` passing `pickedIDs` as the selection. `generate(with:)` keeps stamped `importance` (skip re-analysis when already stamped — check the `analyzeImportance` gate and don't run `ImageContentAnalyzer.analyze` twice; refs already carry importance from curation).

- [ ] **Step 1: Add test target to `Packages/SetupFeature/Package.swift`** (mirror another package's testTarget block).
- [ ] **Step 2: Failing tests for model**: pages⇄photos conversion (20 pages → 40 photos); preset selection updates `photoCount`; toggle adds/removes; picked count live; `leftOutByCluster` groups + sorts by quality desc; cancel during `.analyzing` returns to caller-visible cancelled state.
- [ ] **Step 3: Verify fail.** — **Step 4: Implement model, then view + routing** (view: no logic beyond bindings; `.help` tooltips per house convention; hidden `.keyboardShortcut(.cancelAction)` for Escape per repo gotcha).
- [ ] **Step 5: `swift test --package-path Packages/SetupFeature` green; `swift build` for SetupFeature.**
- [ ] **Step 6: Commit** (`feat: curation step in new-book wizard`).

### Task A6: Integration + full verification of Feature A (Sonnet)

- [ ] **Step 1: All package tests**: run `swift test --package-path Packages/<P>` for PhotoBookCore, PhotoBookImport, SetupFeature, ModelLayer.
- [ ] **Step 2: App build**: `xcodegen generate && xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks -destination 'platform=macOS' build` (check scheme name via `xcodebuild -list`).
- [ ] **Step 3: Fix anything red; commit** (`chore: feature A integration green`).

**QA gate (orchestrator, after A6):** code-review agent pass over `git diff <base>..HEAD`, verify spec §A coverage, then proceed to B.

---

## Feature B — Two-Page Spreads

### Task B1: Four spread templates (Sonnet)

**Files:**
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/spread-templates.json` (locate actual resource path via `grep -r "spread-templates" Packages/PhotoBookCore`)
- Test: extend the existing `SpreadTemplateProvider` test file

**Templates (double-wide canvas, x∈0…1, gutter x=0.5; frames must tile without overlap; text frames: none):**
1. `hero-full` — photoCount 1: `[{x:0, y:0, w:1, h:1}]`
2. `center-columns-3` — photoCount 3: center `{x:0.30, y:0, w:0.40, h:1}`, left `{x:0, y:0, w:0.30, h:1}`, right `{x:0.70, y:0, w:0.30, h:1}`
3. `center-columns-5` — photoCount 5: center `{x:0.30, y:0, w:0.40, h:1}`, left col `{x:0, y:0, w:0.30, h:0.5}` + `{x:0, y:0.5, w:0.30, h:0.5}`, right col mirrored
4. `split-two-thirds` — photoCount 2: `{x:0, y:0, w:0.667, h:1}` + `{x:0.667, y:0, w:0.333, h:1}`
5. `split-two-thirds-3` — photoCount 3: big `{x:0, y:0, w:0.667, h:1}`, right stacked `{x:0.667, y:0, w:0.333, h:0.5}` + `{x:0.667, y:0.5, w:0.333, h:0.5}`
6. `panorama-band-3` — photoCount 3: band `{x:0, y:0.25, w:1, h:0.5}`, top `{x:0, y:0, w:1, h:0.25}`, bottom `{x:0, y:0.75, w:1, h:0.25}`

Match the JSON schema of existing entries exactly (id/photoCount/photoFrames/textFrames field names).

- [ ] **Step 1: Failing tests**: `templates(forPhotoCount: 1)` contains `hero-full`; each new template's frames cover the unit canvas (union area ≈ 1.0, no pairwise overlap — write area/intersection helpers in the test); `blueprint()` for `hero-full` produces one slot straddling the gutter and `slice()` splits it into complementary half-crops.
- [ ] **Step 2: Verify fail.** — **Step 3: Add JSON.** — **Step 4: Package green.** — **Step 5: Commit** (`feat: four two-page spread templates`).

### Task B2: EdgeStyle-aware `buildSpread` (Opus)

**Files:**
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/BookEngine.swift` (`buildSpread`, ~lines 97-140)
- Test: extend BookEngine spread tests

Current bug: `buildSpread` hardcodes `NormRect.full.inset(by: style.pageMargin)` and `style.gutter`, ignoring `style.edgeStyle`. Fix to mirror `JustifiedProvider.swift:26-31`: `hasOuterMargin == false` → zero margin; `keepsGutter == false` → zero gutter. Respect per-page `edgeStyleOverride` resolution if that's how standard pages resolve it (check `makeStandardPage` — use the same resolution helper).

- [ ] **Step 1: Failing tests**: book style `.borderless` → spread slot frames reach 0/1 edges (margin 0, gutter 0); `.tiled` → margin 0, gutter preserved; `.framed` → byte-identical frames to current behavior (regression guard: assert against current known-good values, captured before the change).
- [ ] **Step 2: Verify fail.** — **Step 3: Implement.** — **Step 4: Package green (all existing spread/determinism tests must stay green).** — **Step 5: Commit** (`fix: buildSpread honors EdgeStyle`).

### Task B3: Gutter-safe crop bias (Opus)

**Files:**
- Create: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/GutterSafeCrop.swift`
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/BookEngine.swift` (apply in `buildSpread` and wherever template application binds photos — coordinate with B4/B5)
- Create: `Packages/PhotoBookCore/Tests/PhotoBookCoreTests/GutterSafeCropTests.swift`

**Pure function (exact):**
```swift
enum GutterSafeCrop {
    static let gutterBand = 0.08   // fraction of spread width centered on x=0.5

    /// For a slot straddling the gutter: returns a crop rect (source-photo normalized space,
    /// aspect-fill for slotFrame within the spread canvas) shifted horizontally by the minimum
    /// amount so salientCenter's projected x lands outside [0.5 - band/2, 0.5 + band/2] of the
    /// spread. nil salientCenter or non-straddling slot → nil (caller keeps default .full crop).
    static func crop(
        slotFrame: NormRect,          // double-wide canvas space
        photoAspect: Double,          // w/h
        spreadAspect: Double,         // 2 × page aspect
        salientCenter: NormPoint?
    ) -> NormRect?
}
```
Math: compute the aspect-fill visible source window for the slot (same formula as `SlotGeometry.imageDrawRect`, inverted to source space); map salientCenter through crop→slot projection to spread x; if inside the band, shift the crop window horizontally (clamped to [0,1] source bounds) so the projected point exits the band on the nearer side; if the photo lacks slack to shift (crop already at bounds), return the clamped best effort. Fully deterministic, no randomness.

- [ ] **Step 1: Failing tests**: salient center dead-center on 1-photo hero slot → crop shifts so projected x = band edge (assert exact value); salient center already outside band → nil; nil salientCenter → nil; non-straddling slot → nil; insufficient slack → crop pinned at source bound; shift direction is nearer band edge; crop stays within [0,1].
- [ ] **Step 2: Verify fail.** — **Step 3: Implement + wire into `buildSpread` photo binding** (slot.crop = result ?? .full; note `slice()` splits crops — verify a shifted crop slices into complementary halves, add one test).
- [ ] **Step 4: Package green.** — **Step 5: Commit** (`feat: gutter-safe crop for spread slots`).

### Task B4: Importance-driven auto-promotion to hero spreads (Opus)

**Files:**
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/BookEngine.swift` (`makeBook` grouping loop ~64-73, `repaginateBook`)
- Test: extend BookEngine tests

**Rules (spec §B, exact):**
- Candidate: single-photo group where `importance >= ImportanceWeight.heroThreshold` (0.80) AND `aspectRatio >= 1.2` (near-landscape; panoramas ≥ 2.2 keep their existing unconditional path).
- Caps: max one auto-hero per `clusterIndex` (from `AnalyzedPhoto`); at least 6 non-spread pages between consecutive auto-spreads (count pages emitted since last spread).
- Promotion routes the group to `buildSpread` with the `hero-full` template geometry (single full-canvas slot), photo bound with gutter-safe crop from B3.
- Determinism: promotion decision derives only from photo data + position, no RNG; existing seed-consumption order untouched for non-promoted groups (regression: books without hero-importance photos are byte-identical to before — add that exact test: encode book pre/post with same seed, compare JSON).

- [ ] **Step 1: Failing tests**: 0.85-importance landscape photo among 20 mid photos → exactly one spread, that photo; two 0.85 photos same cluster → one spread; two hero photos 3 pages apart → second not promoted (spacing); portrait 0.85 → not promoted; no-hero book byte-identical regression; `repaginateBook` respects existing-spread boundaries (already guarded — keep green).
- [ ] **Step 2: Verify fail.** — **Step 3: Implement.** — **Step 4: Package green.** — **Step 5: Commit** (`feat: auto-promote hero photos to full spreads`).

### Task B5: Spread layout strip + template application (Sonnet)

**Files:**
- Modify: `Packages/PhotoBookCore/Sources/PhotoBookCore/Engine/BookEngine.swift` — add:
```swift
public func spreadLayoutOptions(for spreadID: UUID, in book: Book, preset: PrintPreset)
    -> [(count: Int, templates: [SpreadTemplateProvider.Template])]
public func applySpreadTemplate(_ templateID: String, to spreadID: UUID, in book: Book,
    preset: PrintPreset) -> Book   // rebinds existing photos in order (extra slots empty, extra photos dropped? NO — only offer counts within ±0 of current photo count in options; apply asserts count match), re-slices, gutter-safe crops
```
- Modify: `Packages/ModelLayer/Sources/ModelLayer/BookEditorModel.swift` — `refreshAlternatives()` populates `spreadLayoutOptionsByCount` when selected page has `spreadID`; add `applySpreadTemplate` mutation (undo-registered like existing mutations — copy the pattern of the page-template apply).
- Modify: `Packages/EditorFeature/Sources/EditorFeature/TemplateStripView.swift` + `BookBrowserView.swift:290-292` — strip shows spread templates when selection is a spread member (wireframes render the double-wide canvas at `2 × pageAspect`).
- Tests: `PhotoBookCoreTests` for options/apply; `ModelLayerTests` for model plumbing + undo.

Options offered = templates with `photoCount == spread.photoSlots.count` only (matches strip's per-count grouping; no photo add/remove in v1).

- [ ] **Step 1: Failing tests**: options for 3-photo spread → contains `center-columns-3`, `split-two-thirds-3`, `panorama-band-3`, excludes 1/2/5-photo; apply `center-columns-3` → same 3 photoIDs in template order, slot frames match template, pages re-sliced deterministically (apply twice → identical); apply registers undo (ModelLayer test); applying template mismatched count → precondition/no-op (pick one, test it).
- [ ] **Step 2: Verify fail.** — **Step 3: Implement Core, then ModelLayer, then views.** — **Step 4: PhotoBookCore + ModelLayer + EditorFeature packages green.** — **Step 5: Commit** (`feat: spread template strip and application`).

### Task B6: Integration + full verification of Feature B (Sonnet)

- [ ] **Step 1: All package tests** (PhotoBookCore, PhotoBookImport, PhotoBookRender goldens, EditCore, ModelLayer, AppSupport, EditorFeature, DocumentUI, SetupFeature).
- [ ] **Step 2: `xcodegen generate` + macOS `xcodebuild` green.**
- [ ] **Step 3: Commit** (`chore: feature B integration green`).

**Final QA gate (orchestrator):** code-review agents over full branch diff, spec-coverage check both features, live smoke via built app where feasible.
