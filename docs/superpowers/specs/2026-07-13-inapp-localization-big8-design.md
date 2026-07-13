# In-app localization — Big 8 + English

Date: 2026-07-13
Scope: **in-app UI strings only** (String Catalogs + translation). No store
metadata, no localized screenshots, no reusable translate script — those are
deferred to the App Store submission phase (`docs/appstore-submission/PLAN.md`).

## Goal

Every user-visible string in the PhotoBooks macOS app renders from String
Catalogs, translated into the **top-revenue Big 8** App Store product-page
locales plus the English base.

## Locales (9 total)

| Role | Locale codes |
|---|---|
| Base / dev language | `en` |
| Big 8 | `de`, `fr`, `es`, `it`, `ja`, `ko`, `zh-Hans`, `pt-BR` |

All 8 are valid App Store Connect product-page localizations (verified), so the
same set carries forward to store metadata later with no locale churn.

## Where the strings live

User-visible strings exist in exactly **4 UI packages** + the App target +
Info.plist keys. The other 6 SPM packages (AppSupport, PhotoBookCore,
ModelLayer, EditCore, PhotoBookImport, PhotoBookRender) have **zero**
user-visible literals and get no catalog.

| Package | ~call sites |
|---|---|
| EditorFeature | 142 |
| SetupFeature | 69 |
| ExportFeature | 25 |
| DocumentUI | 9 |
| App target | 1 |
| InfoPlist keys | CFBundleDisplayName, NSPhotoLibraryUsageDescription, UTTypeDescription |

Call-site count = `Text/Label/Button/Toggle/Picker/Menu/Section/TextField/Stepper("...")`,
`.help("...")`, `navigationTitle("...")`. ~245 sweep edits total.

## Design

### Mechanism — String Catalogs (`.xcstrings`)

Native Xcode 15+ String Catalogs, one `Localizable.xcstrings` per package that
owns strings, dev language `en`. Native > legacy `.strings`: auto-extraction at
build, plural variants, staleness tracking built in.

### Bundle model — per-package catalogs (not centralized)

SwiftUI `Text("key")` resolves against `Bundle.main` by default. Strings
authored inside an SPM package must resolve against that package's bundle, so
every user-visible call site is swept to reference the module bundle:

- `Text("x")` → `Text("x", bundle: .module)`
- `Label("x", systemImage:)` → `Label { Text("x", bundle: .module) } icon: { ... }`
  (or `Label(String(localized: "x", bundle: .module), systemImage:)`)
- `Button("x") { }` → `Button { } label: { Text("x", bundle: .module) }`
- `.help("x")` resolves against **main** bundle → `.help(Text("x", bundle: .module))`
- `String(localized: "x")` → `String(localized: "x", bundle: .module)`
- Interpolated `"\(n) photos"` → format key with **plural variants** in the
  catalog (`NSStringPluralRuleType`), for every language including en.

Rejected alternative: one central app-target catalog with no sweep. It skips
~245 edits but forfeits auto-extraction and forces permanent manual catalog
maintenance for every future string — debt, not laziness.

### App target + Info.plist

- `Localizable.xcstrings` in the App target for the App/ strings.
- `InfoPlist.xcstrings` in the App target for `CFBundleDisplayName`,
  `NSPhotoLibraryUsageDescription`, and `UTTypeDescription`. This localizes the
  built bundle regardless of which plist template feeds the build
  (`Info.plist` for App Store, `Info-Direct.plist` for the Sparkle/Developer ID
  channel).

### Package.swift

Add `defaultLocalization: "en"` to the 4 UI packages' `Package.swift` and
ensure the catalog is a package resource (it is, via existing source globs; add
explicit `resources:` only if the glob misses `.xcstrings`).

### xcodegen

Catalogs in `App/` are covered by the existing `App` source glob. Set
`options.developmentLanguage: en`. **Run `xcodegen generate`** after adding
resources (repo gotcha: new resources silently don't build otherwise). Confirm
`knownRegions` in the generated project lists all 9 locales once the first
non-en translation lands.

### Translation

Translate **now**, in-session: one subagent per Big-8 language fills its column
across all catalogs, given app context so domain terms land correctly
("Spread", "Framed", "Borderless", "Tiled", "Gutter", "Bleed", "Safe area",
book/cover/spine vocabulary). No reusable script — YAGNI until re-translation
becomes routine.

## Build / extraction flow

1. Add catalogs + `defaultLocalization` + bundle sweep per package.
2. Build each package with `SWIFT_EMIT_LOC_STRINGS=YES` so en catalogs
   self-populate with the swept keys.
3. Grep-verify no un-bundled `Text("` / `.help("` / `String(localized:` escaped
   the sweep in the 4 UI packages.
4. Add the 8 languages to each catalog; run translation subagents.
5. `xcodegen generate`; build the app.

## Verification / exit criteria

- App builds; all existing en UITests pass unchanged.
- `SWIFT_EMIT_LOC_STRINGS` extraction shows every user-visible key present in
  each package's en catalog; zero un-bundled literals remain in the 4 packages.
- Launch `PhotoBooks -AppleLanguages '(de)'` and `'(ja)'`: main flows (welcome,
  new-book setup wizard, editor, export) render translated, no key-name
  fallbacks, no truncation/layout breakage on the long-word languages (de).
- `knownRegions` lists en + the Big 8.

## Explicitly out of scope (deferred)

- Localized App Store metadata (name, description, keywords, privacy strings).
- Localized screenshot automation.
- Reusable/CI translation pipeline script + missing-key CI guard.
- Lithuanian or any locale outside the Big 8.
