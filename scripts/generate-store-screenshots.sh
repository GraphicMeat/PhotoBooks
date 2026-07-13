#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREENSHOTS="$ROOT/store-screenshots"
TEMPLATES="$SCREENSHOTS/templates"
RAW="$SCREENSHOTS/raw"
OUTPUT="$SCREENSHOTS/output"
DERIVED="$SCREENSHOTS/.derived-data"
RENDERER="$ROOT/scripts/render-store-screenshots.swift"
staged_fixture=""

cleanup() {
  [[ -n "$staged_fixture" ]] && rm -rf "$staged_fixture"
}
trap cleanup EXIT INT TERM

locale="en-US"
all_locales=0
templates_only=0
photo_folder=""

usage() {
  print "Usage: $0 [--locale STORE_LOCALE | --all-locales] [--photo-folder DIR] [--templates-only]"
}

while (( $# > 0 )); do
  case "$1" in
    --locale)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      locale="$2"
      shift 2
      ;;
    --all-locales)
      all_locales=1
      shift
      ;;
    --templates-only)
      templates_only=1
      shift
      ;;
    --photo-folder)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      photo_folder="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

# store locale | Xcode language | Xcode region. Keep this in the same order as
# store-screenshots/locales.json; the JSON is consumed by later translation
# automation while this compact table keeps the local runner dependency-free.
typeset -a configured_locales=(
  "en-US|en|US"
  "de-DE|de|DE"
  "es-ES|es|ES"
  "fr-FR|fr|FR"
  "it|it|IT"
  "ja|ja|JP"
  "ko|ko|KR"
  "pt-BR|pt-BR|BR"
  "zh-Hans|zh-Hans|CN"
)

typeset -a selected
if (( all_locales )); then
  selected=("${configured_locales[@]}")
else
  for entry in "${configured_locales[@]}"; do
    if [[ "${entry%%|*}" == "$locale" ]]; then selected+=("$entry"); fi
  done
  if (( ${#selected[@]} == 0 )); then
    print -u2 "Unknown store locale '$locale'. See $SCREENSHOTS/locales.json."
    exit 2
  fi
fi

if (( ! templates_only )); then
  command -v xcodegen >/dev/null || {
    print -u2 "xcodegen is required. Install it with: brew install xcodegen"
    exit 1
  }
  xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"

  staged_fixture="/private/tmp/PhotoBooksScreenshotFixture"
  rm -rf "$staged_fixture"
  if [[ -n "$photo_folder" ]]; then
    [[ -d "$photo_folder" ]] || { print -u2 "Photo folder not found: $photo_folder"; exit 1; }
    mkdir -p "$staged_fixture"
    staged_count=0
    for image in "$photo_folder"/*(N.); do
      extension="${image:e:l}"
      case "$extension" in
        jpg|jpeg|png|heic|heif|tif|tiff) ;;
        *) continue ;;
      esac
      cp "$image" "$staged_fixture/$(printf '%03d' $staged_count).$extension"
      (( staged_count += 1 ))
      (( staged_count >= 40 )) && break
    done
    (( staged_count > 0 )) || { print -u2 "No supported images in $photo_folder"; exit 1; }
    print "Staged $staged_count photos from $photo_folder"
  fi
fi

for entry in "${selected[@]}"; do
  store="${entry%%|*}"
  remainder="${entry#*|}"
  language="${remainder%%|*}"
  region="${remainder##*|}"
  copy="$SCREENSHOTS/copy/$store.json"
  if [[ ! -f "$copy" ]]; then
    print -u2 "Missing localized marketing copy: $copy"
    print -u2 "English is the source; add this locale before rendering its final set."
    exit 1
  fi

  mkdir -p "$RAW/$store" "$OUTPUT/$store" "$DERIVED"
  if (( ! templates_only )); then
    print "Capturing PhotoBooks in $language-$region…"
    result="$DERIVED/result-$store.xcresult"
    attachments="$DERIVED/attachments-$store"
    rm -rf "$result" "$attachments"
    xcodebuild \
      -project "$ROOT/PhotoBooks.xcodeproj" \
      -scheme PhotoBooks \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath "$result" \
      -only-testing:PhotoBooksUITests/ScreenshotTests/testCaptureStoreViews \
      -testLanguage "$language" \
      -testRegion "$region" \
      test
    xcrun xcresulttool export attachments --path "$result" --output-path "$attachments"
    find "$RAW/$store" -type f -name '*.png' -delete
    for index in {0..40}; do
      name=$(plutil -extract "0.attachments.$index.suggestedHumanReadableName" raw \
        -o - "$attachments/manifest.json" 2>/dev/null) || continue
      exported=$(plutil -extract "0.attachments.$index.exportedFileName" raw \
        -o - "$attachments/manifest.json")
      for template in "$TEMPLATES"/*.json; do
        template_id=$(plutil -extract id raw -o - "$template")
        if [[ "$name" == "${template_id}_"* ]]; then
          cp "$attachments/$exported" "$RAW/$store/$template_id.png"
          break
        fi
      done
    done
    raw_count=$(find "$RAW/$store" -type f -name '*.png' | wc -l | tr -d ' ')
    [[ "$raw_count" == "10" ]] || {
      print -u2 "Expected 10 captured views, found $raw_count"
      exit 1
    }
  fi

  print "Composing $store at 2880 x 1800…"
  mkdir -p "$DERIVED/swift-module-cache" "$DERIVED/clang-module-cache"
  SWIFT_MODULECACHE_PATH="$DERIVED/swift-module-cache" \
  CLANG_MODULE_CACHE_PATH="$DERIVED/clang-module-cache" \
  swift "$RENDERER" \
    --templates "$TEMPLATES" \
    --copy "$copy" \
    --raw "$RAW/$store" \
    --output "$OUTPUT/$store"

  count=$(find "$OUTPUT/$store" -type f -name '*.png' | wc -l | tr -d ' ')
  [[ "$count" == "10" ]] || { print -u2 "Expected 10 outputs, found $count"; exit 1; }
  for image in "$OUTPUT/$store"/*.png; do
    width=$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')
    height=$(sips -g pixelHeight "$image" | awk '/pixelHeight/ {print $2}')
    [[ "$width" == "2880" && "$height" == "1800" ]] || {
      print -u2 "Wrong dimensions for $image: ${width}x${height}"
      exit 1
    }
  done
done

print "Done: $OUTPUT"
