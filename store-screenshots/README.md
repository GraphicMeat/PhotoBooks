# App Store screenshots

This folder is the source of truth for the ten macOS App Store marketing
screenshots. Final images are always 2880 x 1800 pixels.

- `copy/en-US.json` contains the approved English headline and subtext.
- `templates/*.json` defines the composition and the predefined app view used
  by each screenshot.
- `locales.json` maps the app's languages to App Store Connect locale folders.
- `raw/<locale>/` and `output/<locale>/` are generated and ignored by Git.

Preview the English templates immediately (missing app captures are rendered
as labelled placeholders):

```sh
scripts/generate-store-screenshots.sh --templates-only --locale en-US
```

Capture the ten predefined app states and compose the English set:

```sh
scripts/generate-store-screenshots.sh --locale en-US
```

Use a private folder of real demo photos without copying them into Git:

```sh
scripts/generate-store-screenshots.sh --locale en-US \
  --photo-folder /Users/Rokas/Pictures/PhotoBooksDemo
```

Capture every configured UI language after localized marketing copy has been
added under `copy/`:

```sh
scripts/generate-store-screenshots.sh --all-locales
```

The full run requires macOS 15+, Xcode, XcodeGen, and a Retina display. The
script fails if a capture or final image is not exactly 2880 x 1800 pixels.
Copy files intentionally live outside the app String Catalogs: they are store
marketing text, and the later translation flow can update them independently
without changing the app binary.
