#!/bin/bash
# iPhone Duo smoke run (Mac mini). Builds PhotoBooks for the iPhone Duo
# simulator, runs the DuoSmokeUITests tour, and at every checkpoint the test
# reaches, folds the simulator through the poses it asks for (closed = outer
# display, half/flat = inner display), saving one PNG per pose. Then runs the
# regular-width editor test on an iPad Pro 13-inch (M5) simulator, which
# rotates itself and asks for plain "shot" captures.
#
#   scripts/duo/duo-smoke.sh <out-dir>
#
# Through the job queue, from a worktree:
#   ~/.claude/bin/testq ~/.claude/bin/minijob bash -c \
#     'scripts/duo/duo-smoke.sh out >&2; tar -C out -cf - .' > duo.tar
#
# Env: DUO_UDID (default: the first "iPhone Duo" simulator),
#      DUO_OUTER_DISPLAY / DUO_INNER_DISPLAY (simctl display ids),
#      DUO_ONLY_TESTING (default: the whole PhotoBooksDuoUITests target),
#      IPAD_UDID (default: the newest "iPad Pro 13-inch (M5)"; "none" skips).
# Writes: <out>/<checkpoint>-<n>-<pose>.png, build.log, test.log,
#         test-summary.txt, DuoSmoke.xcresult, and ipad-* equivalents.
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
IPAD=${IPAD_UDID:-$(xcrun simctl list devices available | sed -n 's/^ *iPad Pro 13-inch (M5) (\([0-9A-F-]*\)).*/\1/p' | tail -1)}
[ -n "$UDID" ] || { echo "duo-smoke: no iPhone Duo simulator found" >&2; exit 1; }
log() { echo "duo-smoke: $*" >&2; }

cleanup_device() {  # uninstall needs the device booted, so before shutdown
    xcrun simctl uninstall "$1" "$APP_ID" >/dev/null 2>&1
    xcrun simctl uninstall "$1" "$RUNNER_ID" >/dev/null 2>&1
    xcrun simctl shutdown "$1" >/dev/null 2>&1
}
cleanup() {
    for device in "$UDID" ${IPAD:+"$IPAD"}; do
        [ "$device" = none ] || cleanup_device "$device"
    done
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

boot() {  # boot <udid> [display]; bootstatus can report done (even "Data
          # Migration Failed") well before SpringBoard draws, so wait for a frame.
    log "booting $1"
    xcrun simctl boot "$1" 2>/dev/null
    xcrun simctl bootstatus "$1" -b >/dev/null || return 1
    for _ in $(seq 60); do
        xcrun simctl io "$1" screenshot ${2:+--display="$2"} "$WORK/probe.png" >/dev/null 2>&1 && break
        sleep 3
    done
    xcrun simctl status_bar "$1" override --time 9:41 --batteryLevel 100 --cellularBars 4 >/dev/null 2>&1
}

pose() {  # pose <closed|half|flat|deg|shot>; the hinge animates, so let it settle.
    [ "$1" = shot ] && { sleep 1.5; return; }
    "$WORK/duo-hinge" -d "$UDID" "$1" >&2 && sleep 2.5
}
capture() {  # capture <udid> <name> <pose>
    local display=$INNER
    [ "$3" = closed ] && display=$OUTER
    [ "$3" = shot ] && display=""
    xcrun simctl io "$1" screenshot ${display:+--display="$display"} "$OUT/$2-$3.png" >/dev/null 2>&1 \
        || log "screenshot failed: $2 ($3, display ${display:-default})"
}

# run_tests <udid> <only-testing> <prefix>: runs the UI tests in the background
# and serves their checkpoints until xcodebuild exits; returns its status.
run_tests() {
    local device=$1 only=$2 prefix=$3
    log "running $only on $device"
    rm -rf "$OUT/${prefix}DuoSmoke.xcresult"
    TEST_RUNNER_DUO_HOST_SYNC=1 TEST_RUNNER_DUO_FIXTURES="$WORK/fixtures" \
    xcodebuild test-without-building -project PhotoBooks.xcodeproj -scheme "PhotoBooks iOS UITests" \
        -destination "id=$device" -derivedDataPath "$WORK/dd" -only-testing:"$only" \
        -resultBundlePath "$OUT/${prefix}DuoSmoke.xcresult" > "$OUT/${prefix}test.log" 2>&1 &
    local test_pid=$! data sync_dir ready name n p
    while kill -0 "$test_pid" 2>/dev/null; do
        data=$(xcrun simctl get_app_container "$device" "$RUNNER_ID" data 2>/dev/null)
        sync_dir=$data/tmp/duo-sync
        if [ -n "$data" ] && [ -d "$sync_dir" ]; then
            for ready in "$sync_dir"/ready-*; do
                [ -e "$ready" ] || continue
                name=${ready##*/ready-}
                [ -e "$sync_dir/done-$name" ] && continue
                n=0
                for p in $(cat "$ready"); do
                    n=$((n + 1)); pose "$p"; capture "$device" "$name-$n" "$p"
                done
                log "captured $name ($(tr '\n' ' ' < "$ready"))"
                touch "$sync_dir/done-$name"
            done
        fi
        sleep 1
    done
    wait "$test_pid"; local status=$?
    grep -E "Test Case .*(passed|failed|skipped)|error:|Executed [0-9]+ test" "$OUT/${prefix}test.log" \
        | tee "$OUT/${prefix}test-summary.txt" >&2
    log "xcodebuild test on $device exit $status"
    return "$status"
}

boot "$UDID" "$OUTER" || exit 1
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

run_tests "$UDID" "$ONLY" ""; status=$?
"$WORK/duo-hinge" -d "$UDID" flat >&2
cleanup_device "$UDID"

if [ -n "$IPAD" ] && [ "$IPAD" != none ]; then
    if boot "$IPAD"; then
        run_tests "$IPAD" PhotoBooksDuoUITests/DuoSmokeUITests/testRegularEditorChrome ipad- \
            || status=$((status ? status : 1))
    else
        log "iPad simulator $IPAD did not boot"; status=1
    fi
else
    log "no iPad Pro 13-inch (M5) simulator; skipped"
fi
log "exit $status; captures in $OUT"
exit "$status"
