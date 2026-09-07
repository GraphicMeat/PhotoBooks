#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
state_dir="$project_root/.build/xcodegen"

if [ -f "$state_dir/error" ]; then
    echo "error: $(cat "$state_dir/error")"
    exit 1
fi

if [ ! -f "$state_dir/verified" ] || [ "$project_root/project.yml" -nt "$state_dir/verified" ]; then
    echo 'error: Project generation was skipped. Build using the PhotoBooks or PhotoBooks (Direct) scheme, which regenerates the project automatically.'
    exit 1
fi

if [ -f "$state_dir/changed" ]; then
    if [ "${CONFIGURATION:-Release}" = Debug ]; then
        echo 'warning: Project settings were regenerated. This Debug build uses the settings Xcode already loaded; build again to apply structural or build-setting changes.'
    else
        echo 'error: Project settings were regenerated. Build or Archive again so Xcode uses the updated configuration.'
        exit 1
    fi
fi
