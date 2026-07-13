# PhotoBooks

![PhotoBooks editor](docs/app-workspace.webp)

Native Apple-ecosystem photobook app (iOS 18+ / macOS 15+, SwiftUI). Imports photos
from Apple Photos or the filesystem, auto-arranges them into album page layouts with
a hybrid layout engine (templates + generative partitioning, unified by a scorer),
supports light manual edits, and exports print-ready PDFs (Blurb PDF-to-Book, generic
print) plus a shareable digital PDF.

## Repository layout

- `Packages/PhotoBookCore` — document model, layout engine, scoring, pagination (pure Swift, no UI imports)
- `Packages/PhotoBookImport` — photo source providers (PhotoKit, filesystem)
- `Packages/PhotoBookRender` — screen + PDF renderers (shared layout math; WYSIWYG screen/print)
- `App/` — multiplatform SwiftUI document app (browse, edit, export)
- `docs/superpowers/` — implementation plans

## Development

Run the package test suites:

```sh
swift test --package-path Packages/PhotoBookCore
swift test --package-path Packages/PhotoBookImport
swift test --package-path Packages/PhotoBookRender
```

Generate the Xcode project and build/test the app (the `.xcodeproj` is generated, not committed):

```sh
xcodegen generate
xcodebuild -project PhotoBooks.xcodeproj -scheme PhotoBooks -destination 'platform=macOS' test
```
