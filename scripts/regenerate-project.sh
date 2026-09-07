#!/bin/bash
# Scheme build pre-action. Xcode loads its project model before invoking this.
set -euo pipefail
export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

state_dir="$project_root/.build/xcodegen"
mkdir -p "$state_dir"
error_file="$state_dir/error"
changed_file="$state_dir/changed"
# Persist failure because Xcode does not reliably fail builds for pre-actions.
printf '%s\n' 'Project generation did not finish. Check the Regenerate Xcode project pre-action log.' > "$error_file"

if ! command -v xcodegen >/dev/null 2>&1; then
    printf '%s\n' 'XcodeGen is missing. Install it with brew install xcodegen, then Run again.' > "$error_file"
    cat "$error_file" >&2
    exit 1
fi

backup_dir="$(mktemp -d)"
trap 'rm -rf "$backup_dir"' EXIT
project_file="PhotoBooks.xcodeproj/project.pbxproj"
if [ -f "$project_file" ]; then cp -p "$project_file" "$backup_dir/project.pbxproj"; fi

if ! xcodegen generate --quiet > "$state_dir/generation.log" 2>&1; then
    printf '%s\n' 'XcodeGen could not generate the project. See .build/xcodegen/generation.log for details.' > "$error_file"
    cat "$state_dir/generation.log" >&2
    exit 1
fi

# Compare only build configuration, not workspace state or user schemes that
# Xcode itself edits. Such changes caused the previous repeated Run failures.
if cmp -s "$backup_dir/project.pbxproj" "$project_file"; then
    cp -p "$backup_dir/project.pbxproj" "$project_file"
    rm -f "$changed_file"
else
    touch "$changed_file"
fi
# The old pre-action used this marker to force a failed build. It is obsolete.
rm -f "$project_root/.xcodegen-regenerated" "$error_file"
touch "$state_dir/verified"
echo 'PhotoBooks: Xcode project generated successfully.'
