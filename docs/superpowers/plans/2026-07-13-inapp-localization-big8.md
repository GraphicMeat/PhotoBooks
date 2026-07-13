# In-app Localization (Big 8 + English) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every user-visible string in the PhotoBooks macOS app renders from Xcode String Catalogs, translated into English + the top-revenue Big 8 App Store locales.

**Architecture:** One `Localizable.xcstrings` per string-owning SPM package (dev language `en`), every SwiftUI call site swept to resolve against its module bundle (`bundle: .module`). App-target catalog + `InfoPlist.xcstrings` for the shell. English keys auto-extract at build (`SWIFT_EMIT_LOC_STRINGS`); the 8 translations are filled by per-language subagents. In-app only — no store metadata, screenshots, or translate script.

**Tech Stack:** Swift 6, SwiftUI, SPM (10 path-referenced packages), Xcode 15+ String Catalogs, xcodegen-generated `.xcodeproj`.

## Global Constraints

- **Locales (9):** base `en`; Big 8 = `de`, `fr`, `es`, `it`, `ja`, `ko`, `zh-Hans`, `pt-BR`. No other locales.
- **String-owning packages (only these 4 get catalogs):** `EditorFeature` (~142), `SetupFeature` (~69), `ExportFeature` (~25), `DocumentUI` (~9). The other 6 packages have zero user-visible strings — do not touch them.
- **Repo gotcha:** `.xcodeproj` is gitignored and xcodegen-generated. After adding App-target resources, run `xcodegen generate` or they silently don't build.
- **docs/ is gitignored:** commit spec/plan/doc files with `git add -f`. Source/package files commit normally.
- **Stay local:** commit to `main`, do not push (user preference).
- **Package build gate:** `swift build --package-path Packages/<Pkg>` must succeed after each sweep (compile is the per-task gate). Full app build + UITests run at integration (Task 5).

### Sweep Rules (apply in every package task)

Transform each user-visible literal by its call shape. Real examples are from this codebase.

1. **Bare `Text` and `.help`** — wrap the literal with a bundle-qualified `Text`:
   - `Text("Missing Photos")` → `Text("Missing Photos", bundle: .module)`
   - `.help("Zoom in")` → `.help(Text("Zoom in", bundle: .module))`  *(the `.help(_ text: Text)` overload; default `.help(_:)` resolves against `.main` and would miss the module catalog)*

2. **Initializers whose first arg is a title string** — `Button`, `Label(_:systemImage:)`, `Section`, `Toggle`, `Picker`, `Stepper`, `TextField` (placeholder), `.navigationTitle` — replace the literal with `String(localized:bundle:)`, preserving all other args/closures:
   - `Button("Cancel", role: .cancel) {}` → `Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}`
   - `Label("Layouts for this page", systemImage: "rectangle.3.group")` → `Label(String(localized: "Layouts for this page", bundle: .module), systemImage: "rectangle.3.group")`
   - `.navigationTitle("Export")` → `.navigationTitle(String(localized: "Export", bundle: .module))`

3. **Manual pluralization** — collapse the ternary into ONE format key; add plural variants in the catalog (Task-6 territory, but author the en variants now):
   - `Text("\(group.count) photo\(group.count == 1 ? "" : "s")")` → `Text("\(group.count) photos", bundle: .module)`; catalog key `%lld photos` gets en `one`=`%lld photo`, `other`=`%lld photos`.

4. **Pure value interpolation (no translatable words)** — opt OUT of localization with `verbatim:` (no bundle), so no junk key is emitted:
   - `Text("\(model.targetValue)")` → `Text(verbatim: "\(model.targetValue)")`
   - `Text("\(Int(customTargetRange.lowerBound))")` → `Text(verbatim: "\(Int(customTargetRange.lowerBound))")`

5. **Interpolation WITH translatable words** — keep as a format key with bundle:
   - `Text("Page \(index)")` → `Text("Page \(index)", bundle: .module)` (key `Page %lld`)
   - `Text("\(unplacedPhotos.count) available")` → `Text("\(unplacedPhotos.count) available", bundle: .module)` (key `%lld available`)

6. **Leave untouched:** `Image(systemName:)`, accessibility-only identifiers that are not shown, non-UI strings (log/error internals not surfaced), and anything already `verbatim:`.

**Per-package grep-clean check (must return nothing):**
```bash
grep -rnE 'Text\("|\.help\("|Button\("|Label\("|\.navigationTitle\("|Section\("|Toggle\("|Picker\("|Stepper\("|TextField\("' \
  --include="*.swift" Packages/<Pkg>/Sources | grep -vE 'verbatim:|bundle: \.module|String\(localized:'
```
Any hit is an un-swept literal (or a deliberate `verbatim:` — confirm by eye).

---

### Task 1: DocumentUI — establish the pattern (smallest package)

Proves the whole mechanism end-to-end on 9 call sites before the big sweeps.

**Files:**
- Modify: `Packages/DocumentUI/Package.swift` (add `defaultLocalization`)
- Create: `Packages/DocumentUI/Sources/DocumentUI/Localizable.xcstrings`
- Modify: every `.swift` under `Packages/DocumentUI/Sources/DocumentUI/` with user-visible literals

**Interfaces:**
- Produces: the per-package pattern (Package.swift `defaultLocalization: "en"` + `Localizable.xcstrings` in `Sources/<Target>/` + bundle-swept call sites) that Tasks 2–4 replicate.

- [ ] **Step 1: Add `defaultLocalization` to Package.swift**

In `Packages/DocumentUI/Package.swift`, add the parameter to the `Package(` init (right after `name:`):
```swift
let package = Package(
    name: "DocumentUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    ...
```
*(SPM auto-processes `.xcstrings` under the target's Sources once `defaultLocalization` is set — no explicit `resources:` needed.)*

- [ ] **Step 2: Create the empty catalog**

Create `Packages/DocumentUI/Sources/DocumentUI/Localizable.xcstrings` with:
```json
{
  "sourceLanguage" : "en",
  "strings" : { },
  "version" : "1.0"
}
```

- [ ] **Step 3: List this package's literals**

Run:
```bash
grep -rnE 'Text\("|\.help\("|Button\("|Label\("|\.navigationTitle\("|Section\("|Toggle\("|Picker\("|Stepper\("|TextField\("' \
  --include="*.swift" Packages/DocumentUI/Sources
```
Expected: ~9 hits. Apply the **Sweep Rules** to each.

- [ ] **Step 4: Sweep every literal**

Edit each hit per the Sweep Rules above (bare Text/.help → `Text(..., bundle: .module)`; title-arg inits → `String(localized:bundle:)`; value-only → `verbatim:`).

- [ ] **Step 5: Grep-clean check**

Run the **Per-package grep-clean check** with `<Pkg>=DocumentUI`.
Expected: no output.

- [ ] **Step 6: Compile**

Run: `swift build --package-path Packages/DocumentUI`
Expected: `Build complete!`

- [ ] **Step 7: Run package tests (if any)**

Run: `swift test --package-path Packages/DocumentUI`
Expected: PASS (or "no tests" — DocumentUI may have none; that's fine).

- [ ] **Step 8: Verify extraction populates the catalog**

Build the app so Xcode auto-extracts keys into the catalog:
```bash
xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks \
  -destination 'platform=macOS' SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | tail -5
```
Then confirm keys landed:
```bash
grep -c '"' Packages/DocumentUI/Sources/DocumentUI/Localizable.xcstrings
```
Expected: catalog now contains the swept keys (count > 3). *(If the app scheme isn't generated yet, defer this check to Task 5 and rely on Step 6 compile here.)*

- [ ] **Step 9: Commit**

```bash
git add Packages/DocumentUI
git commit -m "feat(l10n): String Catalog + bundle sweep for DocumentUI"
```

---

### Task 2: ExportFeature (~25 sites)

**Files:**
- Modify: `Packages/ExportFeature/Package.swift`
- Create: `Packages/ExportFeature/Sources/ExportFeature/Localizable.xcstrings`
- Modify: `.swift` files under `Packages/ExportFeature/Sources/ExportFeature/` with literals

**Interfaces:**
- Consumes: the pattern from Task 1.

- [ ] **Step 1: Add `defaultLocalization: "en"`** to `Packages/ExportFeature/Package.swift` (after `name: "ExportFeature",`).

- [ ] **Step 2: Create** `Packages/ExportFeature/Sources/ExportFeature/Localizable.xcstrings` with the empty-catalog JSON from Task 1 Step 2.

- [ ] **Step 3: List literals**

Run:
```bash
grep -rnE 'Text\("|\.help\("|Button\("|Label\("|\.navigationTitle\("|Section\("|Toggle\("|Picker\("|Stepper\("|TextField\("' \
  --include="*.swift" Packages/ExportFeature/Sources
```
Expected: ~25 hits.

- [ ] **Step 4: Sweep every literal** per the Sweep Rules.

- [ ] **Step 5: Grep-clean check** (`<Pkg>=ExportFeature`). Expected: no output.

- [ ] **Step 6: Compile** — `swift build --package-path Packages/ExportFeature`. Expected: `Build complete!`

- [ ] **Step 7: Tests** — `swift test --package-path Packages/ExportFeature`. Expected: PASS.

- [ ] **Step 8: Commit**
```bash
git add Packages/ExportFeature
git commit -m "feat(l10n): String Catalog + bundle sweep for ExportFeature"
```

---

### Task 3: SetupFeature (~69 sites)

**Files:**
- Modify: `Packages/SetupFeature/Package.swift`
- Create: `Packages/SetupFeature/Sources/SetupFeature/Localizable.xcstrings`
- Modify: `.swift` under `Packages/SetupFeature/Sources/SetupFeature/` (`NewBookSetupView`, `PresetPickerView`, `PresetCard`, `CurationStepView`, `PermissionExplainerView`, `CurationStepModel`, …)

**Interfaces:**
- Consumes: pattern from Task 1.

- [ ] **Step 1: Add `defaultLocalization: "en"`** to `Packages/SetupFeature/Package.swift` (after `name: "SetupFeature",`).

- [ ] **Step 2: Create** `Packages/SetupFeature/Sources/SetupFeature/Localizable.xcstrings` (empty-catalog JSON).

- [ ] **Step 3: List literals**
```bash
grep -rnE 'Text\("|\.help\("|Button\("|Label\("|\.navigationTitle\("|Section\("|Toggle\("|Picker\("|Stepper\("|TextField\("' \
  --include="*.swift" Packages/SetupFeature/Sources
```
Expected: ~69 hits. Watch for value-only cases (`Text("\(model.targetValue)")`, `Text("\(Int(customTargetRange.lowerBound))")`) → Rule 4 `verbatim:`, and worded interpolations (`Text("We found \(photos.count) photos. …")`) → Rule 5 with key `We found %lld photos. …`.

- [ ] **Step 4: Sweep every literal** per the Sweep Rules.

- [ ] **Step 5: Grep-clean check** (`<Pkg>=SetupFeature`). Expected: no output.

- [ ] **Step 6: Compile** — `swift build --package-path Packages/SetupFeature`. Expected: `Build complete!`

- [ ] **Step 7: Tests** — `swift test --package-path Packages/SetupFeature`. Expected: PASS.

- [ ] **Step 8: Commit**
```bash
git add Packages/SetupFeature
git commit -m "feat(l10n): String Catalog + bundle sweep for SetupFeature"
```

---

### Task 4: EditorFeature (~142 sites — largest, holds the plural cases)

**Files:**
- Modify: `Packages/EditorFeature/Package.swift`
- Create: `Packages/EditorFeature/Sources/EditorFeature/Localizable.xcstrings`
- Modify: `.swift` under `Packages/EditorFeature/Sources/EditorFeature/` (`BookBrowserView`, `TemplateStripView`, `TrayView`, `RelinkView`, `TextEditorOverlay`, `CropEditorView`, …)

**Interfaces:**
- Consumes: pattern from Task 1.
- Produces: the manual-plural collapse (`%lld photos`) that Task 6 must supply plural variants for in all 9 locales.

- [ ] **Step 1: Add `defaultLocalization: "en"`** to `Packages/EditorFeature/Package.swift` (after `name: "EditorFeature",`).

- [ ] **Step 2: Create** `Packages/EditorFeature/Sources/EditorFeature/Localizable.xcstrings` (empty-catalog JSON).

- [ ] **Step 3: List literals**
```bash
grep -rnE 'Text\("|\.help\("|Button\("|Label\("|\.navigationTitle\("|Section\("|Toggle\("|Picker\("|Stepper\("|TextField\("' \
  --include="*.swift" Packages/EditorFeature/Sources
```
Expected: ~142 hits.

- [ ] **Step 4: Sweep every literal** per the Sweep Rules. Specific known cases:
  - `Text("\(group.count) photo\(group.count == 1 ? "" : "s")")` → `Text("\(group.count) photos", bundle: .module)` (Rule 3 — key `%lld photos`, add en `one`/`other` variants in the catalog).
  - `Text("Page \(index)")` → `Text("Page \(index)", bundle: .module)` (Rule 5).
  - `Text("\(unplacedPhotos.count) available")` → `Text("\(unplacedPhotos.count) available", bundle: .module)` (Rule 5).
  - Pure `pt` size readouts that are number-only → Rule 4 `verbatim:`.

- [ ] **Step 5: Author en plural variants**

In `Localizable.xcstrings`, for each format key that came from a manual plural (e.g. `%lld photos`), set the en `variations.plural` with `one` and `other`. Minimal shape:
```json
"%lld photos" : {
  "localizations" : {
    "en" : { "variations" : { "plural" : {
      "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld photo" } },
      "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld photos" } }
    } } }
  }
}
```

- [ ] **Step 6: Grep-clean check** (`<Pkg>=EditorFeature`). Expected: no output.

- [ ] **Step 7: Compile** — `swift build --package-path Packages/EditorFeature`. Expected: `Build complete!`

- [ ] **Step 8: Tests** — `swift test --package-path Packages/EditorFeature`. Expected: PASS.

- [ ] **Step 9: Commit**
```bash
git add Packages/EditorFeature
git commit -m "feat(l10n): String Catalog + bundle sweep for EditorFeature"
```

---

### Task 5: App target catalog + InfoPlist + xcodegen + full extraction

**Files:**
- Create: `App/Localizable.xcstrings`
- Create: `App/InfoPlist.xcstrings`
- Modify: `App/PhotoBooksApp.swift` (the 1 App-target literal, if user-visible)
- Modify: `project.yml` (developmentLanguage; ensure catalogs in sources)

**Interfaces:**
- Consumes: nothing from prior tasks (independent shell).
- Produces: fully extracted en catalogs across all 5 targets, ready for translation.

- [ ] **Step 1: Sweep the App-target literal**

Run: `grep -rnE 'Text\("|Label\("|Button\("|\.help\("' --include="*.swift" App`
Apply Sweep Rules. In the App target, strings resolve against `Bundle.main` by default, so **no `bundle:` argument** is needed here — a bare `Text("x")` is correct. (Only package code needs `.module`.)

- [ ] **Step 2: Create `App/Localizable.xcstrings`** with the empty-catalog JSON (Task 1 Step 2).

- [ ] **Step 3: Create `App/InfoPlist.xcstrings`**

Seed with the three localizable Info.plist keys (values match current `App/Info.plist`):
```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "PhotoBooks" } } } },
    "NSPhotoLibraryUsageDescription" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "<copy exact value from App/Info.plist>" } } } },
    "UTTypeDescription" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "PhotoBooks Book" } } } }
  },
  "version" : "1.0"
}
```
Read the exact `NSPhotoLibraryUsageDescription` value first: `grep -A1 NSPhotoLibraryUsageDescription App/Info.plist`.

- [ ] **Step 4: Set development language in project.yml**

In `project.yml`, under `options:` add `developmentLanguage: en`. Confirm the `App/` source glob includes `.xcstrings` (it globs `App/`, so the two new catalogs are picked up automatically).

- [ ] **Step 5: Regenerate the project**

Run: `xcodegen generate`
Expected: `Created project at .../PhotoBooks.xcodeproj`

- [ ] **Step 6: Full build with extraction**

Run:
```bash
xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks \
  -destination 'platform=macOS' SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | tail -8
```
Expected: `BUILD SUCCEEDED`. This auto-populates en keys into all 5 catalogs (4 packages + App).

- [ ] **Step 7: Verify every catalog is populated and no literal escaped**

```bash
for c in Packages/EditorFeature/Sources/EditorFeature Packages/SetupFeature/Sources/SetupFeature \
         Packages/ExportFeature/Sources/ExportFeature Packages/DocumentUI/Sources/DocumentUI App; do
  echo "$c: $(grep -o '"stringUnit"' "$c/Localizable.xcstrings" | wc -l) keys"
done
```
Expected: EditorFeature ≫ others; each > 0. Re-run the grep-clean check per package — all empty.

- [ ] **Step 8: Run existing app UITests (en)**

Run the repo's usual app test command (per project convention):
```bash
xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks -destination 'platform=macOS' test 2>&1 | tail -15
```
Expected: all existing tests PASS unchanged.

- [ ] **Step 9: Commit**
```bash
xcodegen generate
git add App/Localizable.xcstrings App/InfoPlist.xcstrings App/PhotoBooksApp.swift project.yml
git commit -m "feat(l10n): App-target + InfoPlist catalogs, developmentLanguage en"
```

---

### Task 6: Translate into the Big 8 + verify

**Files:**
- Modify: all 5 `Localizable.xcstrings` + `App/InfoPlist.xcstrings` (add 8 language columns)

**Interfaces:**
- Consumes: fully-populated en catalogs from Task 5.

- [ ] **Step 1: Dispatch one translation subagent per language**

For each of `de fr es it ja ko zh-Hans pt-BR`, dispatch a subagent with this brief:
> Translate every en value in these 6 String Catalogs into `<locale>`, writing the translation into each key's `localizations.<locale>.stringUnit` with `state: "translated"`. For plural-variation keys (e.g. `%lld photos`), produce the locale's correct CLDR plural categories (`zh-Hans`/`ja`/`ko` use only `other`; `de`/`fr`/`es`/`it`/`pt-BR` use `one`+`other`). Keep `%lld`/`%@`/`\(…)` format specifiers intact and in a natural position. This is a photo-book app for macOS — translate domain terms in-context: Spread (two facing pages), Framed / Borderless / Tiled (edge styles), Gutter, Bleed, Safe area, Cover / Spine / Back cover, Layout, Tray, Relink. Do NOT translate `PhotoBooks` (the app/product name). Catalogs: [list the 6 paths].

Files to hand each agent:
```
Packages/EditorFeature/Sources/EditorFeature/Localizable.xcstrings
Packages/SetupFeature/Sources/SetupFeature/Localizable.xcstrings
Packages/ExportFeature/Sources/ExportFeature/Localizable.xcstrings
Packages/DocumentUI/Sources/DocumentUI/Localizable.xcstrings
App/Localizable.xcstrings
App/InfoPlist.xcstrings
```
*(Run agents sequentially per user preference; each edits distinct locale keys so order doesn't matter.)*

- [ ] **Step 2: Validate catalog JSON**

```bash
for f in Packages/*/Sources/*/Localizable.xcstrings App/Localizable.xcstrings App/InfoPlist.xcstrings; do
  python3 -m json.tool "$f" > /dev/null && echo "OK $f" || echo "BAD JSON $f"
done
```
Expected: all `OK`.

- [ ] **Step 3: Confirm no missing/stale locales**

```bash
for loc in de fr es it ja ko zh-Hans pt-BR; do
  echo "$loc: $(grep -o "\"$loc\"" Packages/EditorFeature/Sources/EditorFeature/Localizable.xcstrings | wc -l) entries"
done
```
Expected: each ≈ the en key count. Spot-check `state` is `translated`, not `needs_review`.

- [ ] **Step 4: Regenerate + build**

```bash
xcodegen generate
xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`; `knownRegions` now includes all 9 locales:
```bash
grep -A12 knownRegions PhotoBooks.xcodeproj/project.pbxproj | grep -E 'en|de|fr|es|it|ja|ko|zh-Hans|pt-BR'
```

- [ ] **Step 5: Live language smoke test**

Launch the built app forcing a locale and eyeball welcome → new-book setup wizard → editor → export:
```bash
open -n "$(find ~/Library/Developer/Xcode/DerivedData -name PhotoBooks.app -path '*Debug*' | head -1)" \
  --args -AppleLanguages '(de)'
```
Repeat with `'(ja)'`. Verify: UI is translated (no raw key names), German long words don't truncate/break layout, CJK renders. *(Note per repo memory: the sandboxed Bash can't reliably kill a running GUI app — quit each instance manually between runs.)*

- [ ] **Step 6: Commit**
```bash
git add Packages/*/Sources/*/Localizable.xcstrings App/Localizable.xcstrings App/InfoPlist.xcstrings
git commit -m "feat(l10n): translate UI into de fr es it ja ko zh-Hans pt-BR"
```

---

## Self-Review

- **Spec coverage:** Catalogs (Tasks 1–5) ✓; per-package bundle sweep (Tasks 1–4) ✓; App + InfoPlist (Task 5) ✓; Package.swift `defaultLocalization` (each task Step 1) ✓; xcodegen + `knownRegions` (Tasks 5–6) ✓; extraction via `SWIFT_EMIT_LOC_STRINGS` (Task 5 Step 6) ✓; translation (Task 6) ✓; verify `-AppleLanguages` de/ja + en UITests (Tasks 5–6) ✓; plural variants (Task 4 Step 5, Task 6 Step 1) ✓. Out-of-scope items (metadata, screenshots, translate script, non-Big-8 locales) carried no tasks — correct.
- **Placeholder scan:** the one intentional fill-in — exact `NSPhotoLibraryUsageDescription` copy — is guarded by a read command (Task 5 Step 3), not a silent TODO.
- **Type consistency:** `bundle: .module` used uniformly in package tasks; App target deliberately bare (Task 5 Step 1 explains why); plural key `%lld photos` referenced identically in Tasks 4 and 6.
