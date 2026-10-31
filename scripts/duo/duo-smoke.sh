#!/bin/bash
# iPhone Duo smoke run (Mac mini). Builds PhotoBooks for the iPhone Duo
# simulator, runs the DuoSmokeUITests tour, and at every checkpoint the test
# reaches, folds the simulator through the poses it asks for (closed = outer
# display, half/flat = inner display), saving one PNG per pose.
#
#   scripts/duo/duo-smoke.sh <out-dir>
#
# Through the job queue, from a worktree:
#   ~/.claude/bin/testq ~/.claude/bin/minijob bash -c \
#     'scripts/duo/duo-smoke.sh out >&2; tar -C out -cf - .' > duo.tar
#
# Env: DUO_UDID (default: the first "iPhone Duo" simulator),
#      DUO_OUTER_DISPLAY / DUO_INNER_DISPLAY (simctl display ids),
#      DUO_ONLY_TESTING (default: the whole PhotoBooksDuoUITests target).
# Writes: <out>/<checkpoint>-<n>-<pose>.png, build.log, test.log,
#         test-summary.txt, DuoSmoke.xcresult.
set -uo pipefail
export PATH=/opt/homebrew/bin:$PATH

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:?usage: duo-smoke.sh <out-dir>}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
WORK=$ROOT/.build/duo
mkdir -p "$WORK"
cd "$ROOT"

APP_ID=com.graphicMeat.PhotoBooks
RUNNER_ID=com.graphicMeat.PhotoBooksDuoUITests.xctrunner
OUTER=${DUO_OUTER_DISPLAY:-1}
INNER=${DUO_INNER_DISPLAY:-3}
ONLY=${DUO_ONLY_TESTING:-PhotoBooksDuoUITests}
UDID=${DUO_UDID:-$(xcrun simctl list devices available | sed -n 's/^ *iPhone Duo (\([0-9A-F-]*\)).*/\1/p' | head -1)}
[ -n "$UDID" ] || { echo "duo-smoke: no iPhone Duo simulator found" >&2; exit 1; }
log() { echo "duo-smoke: $*" >&2; }

cleanup() {
    xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1
    xcrun simctl uninstall "$UDID" "$RUNNER_ID" >/dev/null 2>&1
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1
}
trap cleanup EXIT

# One UI runner at a time on this machine.
for _ in $(seq 120); do
    pgrep -f "xcodebuild|UITests-Runner" >/dev/null || break
    log "waiting for another xcodebuild/UI runner to finish"; sleep 10
done

log "tools + fixtures"
clang -fobjc-arc -framework Foundation -o "$WORK/duo-hinge" scripts/duo/duo-hinge.m || exit 1
xcrun swift scripts/duo/make-fixtures.swift "$WORK/fixtures" 16 >&2 || exit 1
bash scripts/regenerate-project.sh >&2 || exit 1

log "booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b >/dev/null || exit 1
# bootstatus can report done (even "Data Migration Failed") well before
# SpringBoard draws; wait until the cover display can be captured.
for _ in $(seq 60); do
    xcrun simctl io "$UDID" screenshot --display="$OUTER" "$WORK/probe.png" >/dev/null 2>&1 && break
    sleep 3
done
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 >/dev/null 2>&1

pose() {  # pose <closed|half|flat|deg>; the hinge animates, so let it settle.
    "$WORK/duo-hinge" -d "$UDID" "$1" >&2 && sleep 2.5
}
capture() {  # capture <name> <pose>
    local display=$INNER
    [ "$2" = closed ] && display=$OUTER
    xcrun simctl io "$UDID" screenshot --display="$display" "$OUT/$1-$2.png" >/dev/null 2>&1 \
        || log "screenshot failed: $1 ($2, display $display)"
}

# Which display is lit in each pose (home screen), for checking the ids.
for p in flat closed flat; do
    pose "$p"
    for d in "$OUTER" "$INNER"; do
        xcrun simctl io "$UDID" screenshot --display="$d" "$OUT/00-springboard-$p-display$d.png" >/dev/null 2>&1
    done
done

log "build-for-testing"
if ! xcodebuild build-for-testing -project PhotoBooks.xcodeproj -scheme "PhotoBooks iOS UITests" \
        -configuration Debug -destination "id=$UDID" -derivedDataPath "$WORK/dd" \
        > "$OUT/build.log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$OUT/build.log" | head -40 >&2
    exit 1
fi

# Other windows on the desktop steal UI-test focus.
osascript -e 'tell application "System Events" to set visible of (every process whose name is not "Finder" and background only is false) to false' >/dev/null 2>&1

log "running $ONLY"
rm -rf "$OUT/DuoSmoke.xcresult"
TEST_RUNNER_DUO_HOST_SYNC=1 TEST_RUNNER_DUO_FIXTURES="$WORK/fixtures" \
xcodebuild test-without-building -project PhotoBooks.xcodeproj -scheme "PhotoBooks iOS UITests" \
    -destination "id=$UDID" -derivedDataPath "$WORK/dd" -only-testing:"$ONLY" \
    -resultBundlePath "$OUT/DuoSmoke.xcresult" > "$OUT/test.log" 2>&1 &
test_pid=$!

# Serve the test's checkpoints until xcodebuild exits.
while kill -0 "$test_pid" 2>/dev/null; do
    data=$(xcrun simctl get_app_container "$UDID" "$RUNNER_ID" data 2>/dev/null)
    sync_dir=$data/tmp/duo-sync
    if [ -n "$data" ] && [ -d "$sync_dir" ]; then
        for ready in "$sync_dir"/ready-*; do
            [ -e "$ready" ] || continue
            name=${ready##*/ready-}
            [ -e "$sync_dir/done-$name" ] && continue
            n=0
            for p in $(cat "$ready"); do
                n=$((n + 1)); pose "$p"; capture "$name-$n" "$p"
            done
            log "captured $name ($(tr '\n' ' ' < "$ready"))"
            touch "$sync_dir/done-$name"
        done
    fi
    sleep 1
done
wait "$test_pid"; status=$?
"$WORK/duo-hinge" -d "$UDID" flat >&2

grep -E "Test Case .*(passed|failed|skipped)|error:|Executed [0-9]+ test" "$OUT/test.log" \
    | tee "$OUT/test-summary.txt" >&2
log "xcodebuild test exit $status; captures in $OUT"
exit "$status"
