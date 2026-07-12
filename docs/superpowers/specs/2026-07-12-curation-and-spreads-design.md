# Best-N Photo Curation + Two-Page Spread Layouts — Design

Date: 2026-07-12
Branch: `feature/photo-selection-two-page-f12b8b`
Status: approved by user

## Motivation

Reddit user: "My main problem isn't layout, it's choosing from thousands of pics. If the app could automatically find/suggest the top n photos I'd pay $$$." Two features:

- **A — Curation**: auto-select the best N photos (or enough for an X-page book) from thousands, with a review step.
- **B — Spread layouts**: two-page spread templates — one photo across both pages, center photo straddling the gutter with side columns, etc.

Build order: A first, then B. Both land on this branch, sequential commits.

## Feature A — Best-N Curation

### What "best" means

Full curation, three signals:

1. **Quality score** — existing `ImageContentAnalyzer` importance (faces 0.45 + saliency 0.35 + sharpness 0.20) blended with new Apple aesthetics score (`VNCalculateImageAestheticsScoresRequest`, available at our exact floor macOS 15 / iOS 18). Utility shots (`isUtility` — screenshots, receipts, documents) are hard-rejected from auto-picks (still visible in review grid's "Left out" section, user can re-add).
2. **Near-duplicate / burst clustering** — `VNGenerateImageFeaturePrintRequest` per photo (256px thumbnail); two photos join a cluster when feature-print distance is below a threshold AND capture times are within ~10 minutes. A burst of 50 sunset shots becomes one cluster; only its best member is auto-picked until clusters run out.
3. **Time-spread diversity** — picks must cover the whole shoot/trip, not front-load one event.

### Architecture

Vision work stays in `PhotoBookImport` (PhotoBookCore stays pure, per existing contract):

- **`ImageContentAnalyzer`** (extend): add aesthetics request alongside existing face/saliency/sharpness; expose a combined quality score and `isUtility` flag. Same 256px-thumbnail, bounded-concurrency (4), cancellable, progress-reporting pipeline as today.
- **`CurationAnalyzer`** (new, PhotoBookImport): computes feature prints and assigns `clusterID`s (union-find over pairs passing distance + time gates; comparisons limited to a sliding time window so it's not O(n²) over 3,000 photos).

Pure selection algorithm in `PhotoBookCore/Curation/`:

- **`PhotoCurator`** (new): input `[CurationCandidate { id, quality, captureDate?, clusterID, isUtility }]` + target N → output picked ID set. Algorithm:
  1. Drop utility shots.
  2. Sort candidates by quality within each cluster; a cluster's representative is its best member.
  3. Partition the timeline into min(N, distinct-cluster-count) buckets by capture date (undated photos form one trailing bucket).
  4. Round-robin over buckets picking the highest-quality unused cluster representative; when all clusters are represented and N not yet reached, continue round-robin with second-best cluster members.
  5. Deterministic: ties broken by photo ID.
- **Page-count target**: N = requestedPages × `Paginator.idealPhotosPerPage` (2.0), clamped to available photos.

### Wizard UX (SetupFeature)

New `Step.curation` in `NewBookSetupView` between photo loading (`.photoGrid` / folder pick) and `.preset`:

1. Header: "Found 3,000 photos".
2. Target picker: segmented presets (25 / 50 / 100 / custom) with a photos ⇄ pages unit toggle. "Use all photos" skips curation entirely (current behavior preserved).
3. Analyze runs with determinate progress + Cancel (cancel = fall back to "use all", nothing lost).
4. **Review grid**: two sections — **Picked** (count badge, e.g. "100 picked") and **Left out** (cluster-grouped, quality-sorted). Tap toggles membership; live count updates. Continue → `.preset`.
5. Importance scores stamped during analysis persist onto `PhotoRef.importance`, so smart spacing downstream is free (no re-analysis).

The curation step appears unconditionally in both flows: Photos flow after `.photoGrid` (curation operates on the grid-selected set), folder flow directly after folder pick (today it jumps straight to `.preset`). "Use all photos" is always the escape hatch and reproduces today's behavior exactly.

### Data model

No schema change for A itself — `PhotoRef.importance` already exists. Curation results live in wizard state only; the book is built from the final picked set exactly like today's `generate(with:)`.

## Feature B — Two-Page Spread Layouts

### Templates (4 new, in `spread-templates.json`)

All in existing double-wide canvas space (x ∈ 0…1, gutter at x = 0.5):

1. **Hero full-spread** — 1 photo, both pages edge to edge.
2. **Center + side columns** — big photo straddling the gutter center; photo columns on the outer left/right; 3-photo and 5-photo variants.
3. **2/3 + 1/3 split** — photo spans page 1 plus a third of page 2; remaining third is a column (2- and 3-photo variants).
4. **Panorama band** — wide photo spans both pages as a horizontal band; photos above/below (3-photo variant).

### Engine changes (PhotoBookCore)

- **EdgeStyle in `buildSpread`** (bug-fix-grade gap): `BookEngine.buildSpread` currently hardcodes `style.pageMargin`/`style.gutter` and ignores `EdgeStyle`. It gains the same `hasOuterMargin` / `keepsGutter` handling as `JustifiedProvider`, so hero spreads render truly full-bleed under Borderless/Tiled.
- **Auto-promotion**: in the `makeBook`/`repaginateBook` grouping loop (where panorama ≥ 2.2 aspect already promotes), a photo with importance ≥ `ImportanceWeight.heroThreshold` (0.80) and near-landscape aspect is promoted to a hero full-spread, capped at one per time-cluster and with a minimum spacing of ~6 pages between auto-spreads. Panorama promotion unchanged. Determinism rules (fixed seed/ID consumption order) followed exactly.
- **Manual selection**: new `BookEngine.spreadLayoutOptions(for:in:preset:)` enumerating `SpreadTemplateProvider.templates(forPhotoCount:)`; applying a template rebinds the spread's photos in order and re-slices. Exposed through `BookEditorModel`.

### Editor UX (EditorFeature / ModelLayer)

- `TemplateStripView` gains a spread mode: when the selected page belongs to a spread, the strip shows spread templates (grouped by photo count) instead of single-page layouts; tap applies.
- Existing convert-to-spread context menu: after conversion the strip lets the user pick among templates (no separate picker dialog).

### Gutter safety (schema v5)

- `PhotoRef.salientCenter: NormPoint?` — new additive optional field (today face/saliency rects are computed then discarded; analyzer will now persist the primary salient region's center). `Book.currentSchemaVersion` bumps 4 → 5 following the established additive-optional pattern (version bump, no migration transform needed).
- When a spread slot straddles x = 0.5, the slot's `crop` is biased horizontally so the photo's salient center lands outside a gutter band (~8% of spread width centered on the fold). Photos without `salientCenter` keep today's dead-center crop.
- Applies at spread build/rebind time (model level, `buildSpread` + template application); `SlotGeometry` rendering stays untouched.

## Error handling

- Analysis failures per photo (decode error, Vision failure) → photo gets no score, treated as mid-quality (0.5) so it's never silently lost; utility/dedupe skip it.
- Analysis cancellation → wizard falls back to "use all photos" path.
- Aesthetics request unavailable at runtime (defensive) → quality falls back to existing importance blend.
- Missing `spread-templates.json` entries remain a build defect (`fatalError`), matching existing provider contract.

## Testing

- `PhotoBookCoreTests`: `PhotoCurator` determinism, cluster exclusivity (no two same-cluster picks until clusters exhausted), timeline-bucket coverage, page→photo conversion, utility rejection; spread template geometry (slots straddle/split correctly via `slice()`), EdgeStyle-aware `buildSpread`, auto-promotion caps/spacing, gutter-bias crop math, schema v5 round-trip + v4 doc decode.
- `PhotoBookImportTests`: clustering with synthetic feature prints (injected distances), time-gate behavior, aesthetics blend + utility flag (golden thumbnails where feasible), progress/cancel.
- New `SetupFeatureTests` target: curation step state model (target picker math, toggle behavior, counts) — view logic extracted into a testable observable model.
- App build (`xcodegen generate` + `xcodebuild`) green after each phase.

## Delegation (build process)

Orchestrator (this session) plans and QAs only. Implementation delegated to subagents: Sonnet 5 for mechanical/UI tasks, Opus 4.8 for engine/algorithm tasks. Never Fable agents. Sequential task execution, commits to this worktree branch, per existing working-style preferences (local only, no push).
