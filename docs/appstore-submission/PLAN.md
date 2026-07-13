# macOS App Store Submission — Automation Plan

Goal: submit PhotoBooks (App Store flavor, macOS) with **in-app localization**,
**localized screenshots**, and **localized store metadata**, where every
recurring step runs automatically from CI. One-time account setup stays manual
(it can't be scripted); everything per-release is a single workflow run.

## Tooling decision: fastlane `deliver` on existing GitHub Actions (not Codemagic)

The user asked for "something like Codemagic". Recommendation: **fastlane on
the existing GH Actions setup**, because:

- `release-macos.yml` already works on this repo with all Apple org secrets
  (cert import, notarization creds). Codemagic would mean re-provisioning
  signing/secrets on a second CI system for zero capability gain.
- Codemagic's own metadata publishing is fastlane/Transporter under the hood;
  for *metadata + localized screenshots + privacy details* fastlane `deliver`
  is the most complete tool anywhere (Codemagic's `app-store-connect` CLI
  covers builds well but metadata/screenshots less so).
- Everything stays in-repo and diffable: metadata as text files, screenshots
  as build artifacts, one `Fastfile`.

If we ever want Codemagic, phases 1–4 below carry over unchanged (they're all
repo-local); only phase 5's workflow file would be rewritten.

## Current state (verified in repo)

- **No localization at all**: no `.xcstrings`, `.strings`, or `.lproj`
  anywhere; no `defaultLocalization` in any of the 10 `Package.swift` files.
- ~226 user-facing string literals (`Text(`, `Label(`, `Button(`, `.help(`)
  across 127 non-test Swift files — mostly inside the UI packages
  (SetupFeature, EditorFeature, ExportFeature, DocumentUI, AppSupport), not
  in `App/`.
- App Store Release signing verified working (automatic signing, team
  YXDJG24NWG, sandboxed hardened `.pkg` exported successfully — see memory
  `photobooks-appstore-sandbox-prep`).
- macOS UITest target exists (`Tests/PhotoBooksUITests`, incl.
  `EditingGoldenPathTests`) and Debug entitlements already carry a
  temporary-exception so the sandboxed app can read fixture folders — the
  exact hook screenshot automation needs.
- Still missing on the Apple side: App Store Connect **app record** and an
  **ASC API key** in CI secrets.

## Language set (proposal — trim/extend freely)

In-app + store metadata + screenshots, same set everywhere:

| | |
|---|---|
| Base | `en` (en-US on ASC) |
| Tier 1 | `de-DE`, `fr-FR`, `es-ES`, `it`, `nl-NL` |
| Tier 2 | `ja`, `zh-Hans`, `pt-BR` |

Note: **Lithuanian is not an App Store Connect metadata locale**, so `lt` can
only be an *in-app* language (cheap to add to the catalog) — store listing
would fall back to English for LT storefront.

Every phase below is language-count-agnostic; adding a locale later = one line
in a config array + rerun the translate pipeline.

---

## Phase 1 — In-app localization infrastructure (String Catalogs)

The mechanical foundation. Xcode 15+ String Catalogs (`.xcstrings`), one per
module.

1. **Per-package catalogs.** For each UI package (PhotoBookCore if it has
   user-visible strings, SetupFeature, EditorFeature, ExportFeature,
   DocumentUI, AppSupport, ModelLayer as needed):
   - `defaultLocalization: "en"` in `Package.swift`
   - `Sources/<Target>/Resources/Localizable.xcstrings`
   - Sweep every SwiftUI string literal to reference the module bundle:
     `Text("Key", bundle: .module)`, `Label(_:systemImage:)` →
     `Label(String(localized:bundle:))` etc. `.help()` takes a
     `LocalizedStringKey` but resolves against the **main** bundle, so those
     need `Text(..., bundle: .module)` or `String(localized:, bundle: .module)`
     wrappers. This is the bulk of the work (~226 call sites) and is ideal
     subagent sweep material: one agent per package, compile + snapshot tests
     after each.
   - Interpolated strings (`Text("\(n) photos")`) become format keys with
     proper plural variants in the catalog — the catalog editor/format
     supports `NSStringPluralRuleType` variants natively.
2. **App-target catalog** for the few strings in `App/` +
   `InfoPlist.xcstrings` for `CFBundleDisplayName`,
   `NSPhotoLibraryUsageDescription`, `CFBundleDocumentTypes` /
   `UTTypeDescription` ("PhotoBooks Book").
3. **xcodegen wiring**: add the catalogs to sources (already covered by the
   `App` source glob), set `options.developmentLanguage: en`. Regenerate and
   confirm `knownRegions` picks up all locales after first non-en language
   lands. Remember the repo gotcha: run `xcodegen generate` or new resources
   silently don't build.
4. **Extraction**: build with `SWIFT_EMIT_LOC_STRINGS=YES` (String Catalogs
   auto-populate keys on build) so the en catalogs fill themselves; verify no
   literal escaped the sweep by grepping for un-bundled `Text("` in packages.
5. **Verification**: run the app with `-AppleLanguages '(de)'` (or the
   pseudo-localization scheme option, "double-length pseudolanguage") and eyeball the
   main flows; UITests still pass in en.

Exit criteria: app fully renders from catalogs; a fake `de` translation of a
handful of keys visibly appears when launched with `-AppleLanguages '(de)'`.

## Phase 2 — Automated translation pipeline

"Everything automatic" includes translation itself.

1. `scripts/translate-catalogs.sh` + a small Swift/Python driver that:
   - Walks every `.xcstrings` (they're plain JSON), finds keys whose target
     locale is missing or `stale`,
   - Batches them through the **Claude API** (model `claude-sonnet-5`; a
     translation-quality prompt with app context: photo-book editor, macOS
     menu conventions, keep placeholders `%@`/`%lld` intact, respect plural
     variants), and writes results back with state `"translated"` — never
     touching `"reviewed"` entries, so human fixes are sticky.
   - Deterministic + idempotent: re-running with no new keys is a no-op.
2. Same driver translates **store metadata** (phase 4) and **screenshot
   caption strings** if we add marketing overlays later.
3. CI guard: a check step fails the release build if any locale has missing
   keys, so a merged English string can never silently ship untranslated.
4. Secret: `ANTHROPIC_API_KEY` in repo/org secrets (only used by this step).

Exit criteria: `make translate` (or the script) fills all Tier-1+2 locales;
diff shows only catalog JSON changes; app runs correctly in each language.

## Phase 3 — Localized screenshot automation

fastlane `snapshot` does **not** support macOS, so this is a thin custom
runner around what already exists in the repo.

1. **Demo fixture document**: commit a small `Demo.photobookGraphicMeat`
   package under `Tests/Fixtures/` built from ~10 bundled royalty-free photos
   (reuse the Unsplash-CDN workflow from the demo-recording setup, downscaled
   so the repo stays light). A committed *document* means screenshots need no
   Photos-library permission and no importer run — the Debug entitlements
   fixture-folder exception already covers reading it.
2. **`ScreenshotTests` UITest** (new file in `PhotoBooksUITests`):
   - Launch arg `-ScreenshotMode` → app opens the fixture doc directly and
     sets the window frame to exactly **1440×900 points** (Retina 2x backing
     → 2880×1800 px, an accepted App Store size).
   - Walk 5–6 hero states: welcome/launcher, wizard preset step, editor with
     a finished spread, photo-actions popover / layout strip, cover sheet,
     export/PDF step.
   - `XCTAttachment(screenshot: window.screenshot())`, lifetime
     `.keepAlways`, named `01-welcome` … `06-export`.
3. **Per-locale runner** `scripts/generate-screenshots.sh`:
   - Loops the locale list × `xcodebuild test -only-testing:…ScreenshotTests
     -testLanguage <lang> -testRegion <region> -resultBundlePath …`
     (`-testLanguage/-testRegion` are first-class xcodebuild flags — no
     scheme duplication needed).
   - Extracts PNGs from each `.xcresult` with **xcparse**, normalizes to
     exactly 2880×1800 with `sips` (guard-fail if aspect drifted), and writes
     `fastlane/screenshots/<asc-locale>/<n>-<name>.png` — `deliver`'s native
     layout.
   - Framing/text overlays: skip for v1 (fastlane `frameit` is iOS-device
     focused); raw app windows are standard for Mac listings.
4. Runs both locally and on GH Actions macOS runners (XCUITest works
   headless there; our UITests already run in CI-style invocations).

Exit criteria: one script invocation yields a complete
`fastlane/screenshots/` tree, all locales, correct pixel sizes.

## Phase 4 — Store metadata as code (fastlane `deliver`)

1. `fastlane/Deliverfile` + `fastlane/metadata/` tree:
   - `en-US/`: `name.txt` (PhotoBooks), `subtitle.txt`, `description.txt`,
     `keywords.txt` (100 chars), `release_notes.txt`,
     `promotional_text.txt`, plus shared `support_url.txt`,
     `marketing_url.txt` (graphicmeat.com), `privacy_url.txt`,
     `copyright.txt`, `primary_category.txt`
     (`public.app-category.photography` ↔ `PHOTO_AND_VIDEO`).
   - All other locales generated by the phase-2 translate pipeline (keywords
     get a dedicated prompt — translated keyword *research*, not literal
     translation).
2. **Privacy nutrition labels as code**: `fastlane/app_privacy_details.json`
   + fastlane action `upload_app_privacy_details_to_app_store`. PhotoBooks
   collects nothing → the easiest possible label (`data_not_collected`), and
   it's automatable.
3. **Pricing/availability**: set once in ASC (or `deliver`'s `price_tier`);
   not per-release churn.
4. **Fastfile lanes**:
   - `mac_metadata` — deliver metadata + screenshots only (fast iteration).
   - `mac_release` — archive → export app-store `.pkg` (reuse the exact
     xcodebuild invocation proven in the sandbox-prep work) → `deliver`
     with `pkg:`, `submit_for_review: true`, `automatic_release: false`,
     `precheck_include_in_app_purchases: false`.
   - Auth via **App Store Connect API key** (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
     `ASC_KEY_P8` secrets) — no Apple-ID 2FA sessions in CI.

Exit criteria: `bundle exec fastlane mac_metadata` from a laptop updates the
ASC listing end-to-end, all locales.

## Phase 5 — CI release workflow

New `.github/workflows/appstore-release.yml`, mirroring the conventions of
`release-macos.yml` (workflow_dispatch, version auto-derived from
`MARKETING_VERSION` in project.yml, org Apple secrets):

```
xcodegen → check catalogs complete (phase-2 guard)
        → run package + app tests
        → generate localized screenshots (phase-3 script)
        → archive + export app-store .pkg
        → fastlane deliver (metadata + screenshots + pkg + privacy)
        → submit for review (input flag, default true)
```

- Screenshots are uploaded as workflow artifacts too, so a listing refresh
  never requires an upload.
- `mac_metadata`-only dispatch input for metadata/screenshot tweaks between
  binary releases.
- Keep the Direct/Sparkle release workflow fully independent — same
  `MARKETING_VERSION`, two distribution channels, per the existing
  target-template split.

## One-time manual prerequisites (user actions, ~30 min total)

1. **Create the app record** in App Store Connect (bundle id
   `com.graphicMeat.PhotoBooks`, platform macOS). App creation isn't in the
   public ASC API and `fastlane produce` needs an Apple-ID session, so doing
   this once by hand beats maintaining a 2FA session secret.
2. **Generate an ASC API key** (App Manager role) and add `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_P8` to the GraphicMeat org secrets.
3. Confirm **Paid Apps agreement / banking / tax** if the app won't be free.
4. Add `ANTHROPIC_API_KEY` secret for the translation step.
5. Decide initial **price** + storefront availability.

## Sequencing & effort

| Phase | Depends on | Size |
|---|---|---|
| 1 In-app localization | — | L (the 226-call-site sweep; subagent-per-package) |
| 2 Translation pipeline | 1 | M |
| 3 Screenshot automation | 1 (needs localized UI) | M |
| 4 Metadata as code | 2 (translations) | S |
| 5 CI workflow | 3 + 4 | S |
| Manual prereqs | anytime, parallel | user, ~30 min |

Phases 1→2 are the critical path. 3 and 4 parallelize after 2. A realistic
first milestone: phases 1–2 shipped and verified via `-AppleLanguages`
launches; then 3–5 land together and the first dispatch run submits v1.0.x
for review.

## Risks / open points

- **`bundle: .module` sweep regressions** — a missed bundle arg shows the raw
  key at runtime, not a compile error. Mitigate with the grep guard (no bare
  `Text("` in packages) + a pseudo-locale smoke run.
- **Screenshot determinism on CI** — font rendering/appearance can differ per
  runner image; window-frame capture (not full screen) plus fixed light
  appearance and `defaults`-reset launch args keeps output stable.
- **iOS flavor** — the target is multiplatform; this plan intentionally scopes
  to macOS. The catalogs, translations, metadata tree, and Fastfile all reuse
  directly for a later iOS submission; only screenshots (simulator +
  fastlane snapshot, which *does* support iOS) would be new.
- **Review realities** — first macOS submission commonly gets metadata-level
  rejections (screenshots showing non-final UI, missing privacy URL). Since
  everything is code, fixes are a commit + redispatch.
