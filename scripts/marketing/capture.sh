#!/bin/bash
# App Store marketing captures (Mac mini). Creates throwaway simulators, fills
# their Photos library with the marketing photos, and runs
# MarketingCaptureUITests on each; the test asks this script (checkpoint
# files, see the test's doc comment) for every screenshot, screen recording
# and iPhone Duo hinge move.
#
#   scripts/marketing/capture.sh <out-dir>
#
# Through the job queue, from a worktree that holds the photos as untracked
# files in .marketing-photos/ (never commit them):
#   ~/.claude/bin/testq ~/.claude/bin/minijob bash -c \
#     'scripts/marketing/capture.sh out >&2; tar -C out -cf - .' > captures.tar
#
# Env: MARKETING_DEVICES  (default "iphone ipad duo"; "mac" adds the macOS app)
#      MARKETING_PHOTOS_SRC (default .marketing-photos)
#      MARKETING_TESTS    (test method names; default the whole class)
#      MARKETING_SURVEY=1 (also capture every spread), MARKETING_PICKS
#      (page picks, e.g. "designed=5,spread=9,emphasize=7,hero=1")
#      MARKETING_BEATS    (devices that record beats; default "iphone duo-inner")
#      MARKETING_MAC_PICKS (page picks for the Mac book, which places all photos)
#      MARKETING_DUO_POSES (default "closed flat": outer, then inner display)
#      MARKETING_LOCALE   (en-US default; de-DE fr-FR es-ES it ja ko zh-Hans pt-BR):
#                         simulator and app language/region, album and book title
# Writes: <out>/<device>/<shot>.png and <beat>.mp4 (device: iphone, ipad,
#         duo-outer, duo-inner), <out>/logs/*, <out>/recordings.txt.
set -uo pipefail
export PATH=/opt/homebrew/bin:$PATH

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:?usage: capture.sh <out-dir>}
mkdir -p "$OUT/logs" && OUT=$(cd "$OUT" && pwd)
WORK=$ROOT/.build/marketing
rm -rf "$WORK" && mkdir -p "$WORK"
cd "$ROOT"

DEVICES=${MARKETING_DEVICES:-iphone ipad duo}
BEAT_DEVICES=${MARKETING_BEATS:-iphone duo-inner}
PHOTOS_SRC=${MARKETING_PHOTOS_SRC:-$ROOT/.marketing-photos}
APP_ID=com.graphicMeat.PhotoBooks
RUNNER_ID=com.graphicMeat.PhotoBooksDuoUITests.xctrunner
CLASS=PhotoBooksDuoUITests/MarketingCaptureUITests
OUTER=${DUO_OUTER_DISPLAY:-1}
INNER=${DUO_INNER_DISPLAY:-3}
log() { echo "marketing: $(date +%H:%M:%S) $*" >&2; }

LOCALE_ID=${MARKETING_LOCALE:-en-US}
case $LOCALE_ID in    # language | region | album and book title
    en-US)   LANGUAGE=en;      REGION=en_US; TITLE="Summer by the Sea" ;;
    de-DE)   LANGUAGE=de;      REGION=de_DE; TITLE="Sommer am Meer" ;;
    fr-FR)   LANGUAGE=fr;      REGION=fr_FR; TITLE="Un été à la mer" ;;
    es-ES)   LANGUAGE=es;      REGION=es_ES; TITLE="Verano junto al mar" ;;
    it)      LANGUAGE=it;      REGION=it_IT; TITLE="Estate al mare" ;;
    ja)      LANGUAGE=ja;      REGION=ja_JP; TITLE="海辺の夏" ;;
    ko)      LANGUAGE=ko;      REGION=ko_KR; TITLE="바닷가의 여름" ;;
    zh-Hans) LANGUAGE=zh-Hans; REGION=zh_CN; TITLE="海边的夏天" ;;
    pt-BR)   LANGUAGE=pt-BR;   REGION=pt_BR; TITLE="Verão à beira-mar" ;;
    *) echo "marketing: unknown MARKETING_LOCALE $LOCALE_ID" >&2; exit 2 ;;
esac

CREATED=""     # simulators this run made (deleted on exit)
REC_PIDS=""    # running recordVideo processes
REC_FILES=""   # their "<file>|<start epoch>" pairs, finished on stop
now() { /usr/bin/python3 -c 'import time; print(f"{time.time():.3f}")'; }
DEVICE="" KIND="" POSE=""

stop_recordings() {
    local pid entry stopped
    stopped=$(now)
    for pid in $REC_PIDS; do kill -INT "$pid" 2>/dev/null; done
    for pid in $REC_PIDS; do wait "$pid" 2>/dev/null; done
    REC_PIDS=""
    for entry in $REC_FILES; do finish_video "${entry%%|*}" "$(echo "${entry#*|}" | awk -v s="$stopped" '{print s - $1}')"; done
    REC_FILES=""
}

# finish_video <mp4> <wall seconds>: simctl writes a frame only when the
# screen changes, so a still tail is lost; pad it back to the recorded wall
# time, make it 60 fps constant, and turn inner-display videos recorded from
# the folded pose (no rotation tag) landscape like the rest.
finish_video() {
    local file=$1 wall=$2 duration rotation size vf
    [ -s "$file" ] && command -v ffmpeg >/dev/null || return 0
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file")
    rotation=$(ffprobe -v error -select_streams v -show_entries stream_side_data=rotation -of csv=p=0 "$file")
    size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$file")
    vf="tpad=stop_mode=clone:stop_duration=$(awk -v w="$wall" -v d="$duration" 'BEGIN { p = w - d; print (p > 0 ? p : 0) }'),fps=60"
    case $file in
        */duo-inner/*) [ -z "$rotation" ] && [ "${size%,*}" -lt "${size#*,}" ] && vf="transpose=1,$vf" ;;
    esac
    if ffmpeg -v error -y -i "$file" -vf "$vf" -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p \
            -movflags +faststart "${file%.mp4}.tmp.mp4"; then
        mv "${file%.mp4}.tmp.mp4" "$file"
    else
        log "could not finish $file"; rm -f "${file%.mp4}.tmp.mp4"
    fi
}
cleanup() {
    stop_recordings
    local udid
    for udid in $CREATED; do
        xcrun simctl shutdown "$udid" >/dev/null 2>&1
        xcrun simctl delete "$udid" >/dev/null 2>&1
    done
}
trap cleanup EXIT

[ -d "$PHOTOS_SRC" ] || { log "no photos at $PHOTOS_SRC"; exit 1; }

# Leftover simulators from an interrupted run of this script.
xcrun simctl list devices | sed -n 's/^ *PB Marketing .* (\([0-9A-F-]*\)) (Shutdown).*/\1/p' \
    | while read -r stale; do xcrun simctl delete "$stale" && log "deleted stale simulator $stale"; done

# One UI runner at a time on this machine.
for _ in $(seq 120); do
    pgrep -f "xcodebuild|UITests-Runner" >/dev/null || break
    log "waiting for another xcodebuild/UI runner to finish"; sleep 10
done

log "tools, photos, project"
clang -fobjc-arc -framework Foundation -o "$WORK/duo-hinge" scripts/duo/duo-hinge.m || exit 1
xcrun swift scripts/marketing/prepare-photos.swift "$PHOTOS_SRC" "$WORK/photos" 3600 >&2 || exit 1
bash scripts/regenerate-project.sh >&2 || exit 1

make_sim() {  # make_sim <variable> <device type name>: sets the variable to the new udid
    local udid
    udid=$(xcrun simctl create "PB Marketing $2" "$2" 2>>"$OUT/logs/simctl.log") || return 1
    CREATED="$CREATED $udid"
    eval "$1=$udid"
}

wait_frame() {  # wait_frame <udid> [display]: boot; bootstatus can report done
                # well before SpringBoard draws, so wait for a frame.
    xcrun simctl boot "$1" 2>/dev/null
    xcrun simctl bootstatus "$1" -b >/dev/null || return 1
    for _ in $(seq 60); do
        xcrun simctl io "$1" screenshot ${2:+--display="$2"} "$WORK/probe.png" >/dev/null 2>&1 && return 0
        sleep 3
    done
}

boot() {  # boot <udid> [display]: wait for a real frame, then dress the device
    log "booting $1"
    if [ "$LANGUAGE" != en ]; then
        # Before the first boot, so the Photos library (and names such as
        # "Recently Saved") are created in this language.
        local prefs=$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/.GlobalPreferences
        defaults write "$prefs" AppleLanguages -array "$LANGUAGE"
        defaults write "$prefs" AppleLocale -string "$REGION"
    fi
    wait_frame "$@" || return 1
    if [ "$LANGUAGE" != en ] && ! xcrun simctl spawn "$1" defaults read -g AppleLanguages 2>/dev/null | grep -q "$LANGUAGE"; then
        # System UI (Photos picker, Files, document browser) follows the
        # device language, which takes a restart to apply.
        log "setting $1 to $LANGUAGE / $REGION"
        xcrun simctl spawn "$1" defaults write -g AppleLanguages -array "$LANGUAGE"
        xcrun simctl spawn "$1" defaults write -g AppleLocale -string "$REGION"
        xcrun simctl shutdown "$1"
        wait_frame "$@" || return 1
    fi
    xcrun simctl ui "$1" appearance light
    xcrun simctl status_bar "$1" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
    xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences \
        DidShowContinuousPathIntroduction -bool true >/dev/null 2>&1
    log "adding photos to $1"
    xcrun simctl addmedia "$1" "$WORK"/photos/*.jpg || return 1
    # Install first and grant Photos before anything runs: a grant to a
    # running process can kill it, and the runner builds the album itself.
    xcrun simctl install "$1" "$APP_PATH" && xcrun simctl install "$1" "$RUNNER_PATH" || return 1
    xcrun simctl privacy "$1" grant photos "$APP_ID"
    xcrun simctl privacy "$1" grant photos "$RUNNER_ID"
    sleep 5
}

label() {
    if [ "$KIND" = duo ]; then
        [ "$POSE" = closed ] && echo duo-outer || echo duo-inner
    else
        echo "$KIND"
    fi
}
display() {
    if [ "$KIND" = duo ]; then
        [ "$POSE" = closed ] && echo "$OUTER" || echo "$INNER"
    fi
}

hinge() {  # hinge <closed|half|flat|deg> [settle]
    "$WORK/duo-hinge" -d "$DEVICE" "$1" >&2 || log "hinge $1 failed"
    case $1 in
        closed) POSE=closed ;;
        half|flat) POSE=flat ;;
        *) [ "$1" -lt 30 ] 2>/dev/null && POSE=closed || POSE=flat ;;
    esac
    [ -n "${2:-}" ] && sleep "$2"
}

start_rec() {  # start_rec <file> [display]
    mkdir -p "$(dirname "$1")"
    local logf=$OUT/logs/rec-$(basename "$(dirname "$1")")-$(basename "$1" .mp4).log
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 ${2:+--display="$2"} --force "$1" >"$logf" 2>&1 &
    REC_PIDS="$REC_PIDS $!"
    for _ in $(seq 50); do grep -qi "recording started" "$logf" 2>/dev/null && break; sleep 0.2; done
    REC_FILES="$REC_FILES $1|$(now)"
    sleep 0.3
}

run_command() {  # run_command <checkpoint name> <command>
    local name=$1 command=$2 dir file
    dir=$OUT/$(label); mkdir -p "$dir"
    # A test that failed mid-beat leaves its recording running, and a device
    # records one display at a time.
    case $command in rec:*|recouter:*|recinner:*|cleardocs) stop_recordings ;; esac
    case $command in
        shot)
            file=$dir/$name.png
            xcrun simctl io "$DEVICE" screenshot $(display | sed 's/^/--display=/') "$file" >/dev/null 2>&1 \
                || log "screenshot failed: $name" ;;
        rec:*)
            if echo " $BEAT_DEVICES " | grep -q " $(label) "; then
                start_rec "$dir/${command#rec:}.mp4" "$(display)"
            fi ;;
        recouter:*) start_rec "$OUT/duo-outer/${command#recouter:}.mp4" "$OUTER" ;;
        recinner:*) start_rec "$OUT/duo-inner/${command#recinner:}.mp4" "$INNER" ;;
        cleardocs)  # saved books from earlier tests (name clashes, restores)
            dir=$(xcrun simctl get_app_container "$DEVICE" "$APP_ID" data 2>/dev/null)
            [ -n "$dir" ] && rm -rf "$dir/Documents/"* "$dir/Documents/".[!.]* 2>/dev/null ;;
        stop) stop_recordings ;;
        closed|half|flat) [ "$KIND" = duo ] && hinge "$command" 2.5 ;;
        hinge:*) [ "$KIND" = duo ] && hinge "${command#hinge:}" ;;
        wait:*) sleep "${command#wait:}" ;;
        *) log "unknown command $command" ;;
    esac
}

# run_tests <run name> [beats 0|1] [unfold 0|1]: runs the class (or
# MARKETING_TESTS) and serves its checkpoints until xcodebuild exits.
run_tests() {
    local run=$1 beats=${2:-0} unfold=${3:-0} only="" t
    for t in ${MARKETING_TESTS:-}; do only="$only -only-testing:$CLASS/$t"; done
    [ -n "$only" ] || only="-only-testing:$CLASS"
    log "running $run ($(label), beats=$beats)"
    TEST_RUNNER_MARKETING_HOST_SYNC=1 TEST_RUNNER_MARKETING_PHOTOS="$WORK/photos" \
    TEST_RUNNER_MARKETING_BEATS=$beats TEST_RUNNER_MARKETING_UNFOLD=$unfold \
    TEST_RUNNER_MARKETING_SURVEY=${MARKETING_SURVEY:-0} TEST_RUNNER_MARKETING_PICKS=${MARKETING_PICKS:-} \
    TEST_RUNNER_MARKETING_RENAME=${MARKETING_RENAME:-0} \
    TEST_RUNNER_MARKETING_LANGUAGE=$LANGUAGE TEST_RUNNER_MARKETING_REGION=$REGION TEST_RUNNER_MARKETING_TITLE="$TITLE" \
    xcodebuild test-without-building -project PhotoBooks.xcodeproj -scheme "PhotoBooks iOS UITests" \
        -destination "id=$DEVICE" -derivedDataPath "$WORK/dd" $only \
        -resultBundlePath "$WORK/$run.xcresult" > "$OUT/logs/$run-test.log" 2>&1 &
    local test_pid=$! data sync_dir ready name cmd
    while kill -0 "$test_pid" 2>/dev/null; do
        data=$(xcrun simctl get_app_container "$DEVICE" "$RUNNER_ID" data 2>/dev/null)
        sync_dir=$data/tmp/marketing-sync
        if [ -n "$data" ] && [ -d "$sync_dir" ]; then
            for ready in "$sync_dir"/ready-*; do
                [ -e "$ready" ] || continue
                name=${ready##*/ready-}
                [ -e "$sync_dir/done-$name" ] && continue
                for cmd in $(cat "$ready"); do run_command "$name" "$cmd"; done
                log "$run: $name ($(tr '\n' ' ' < "$ready"))"
                touch "$sync_dir/done-$name"
            done
        fi
        sleep 0.5
    done
    wait "$test_pid"; local status=$?
    stop_recordings
    if [ -n "$data" ] && [ -d "$data/tmp/marketing-dumps" ]; then
        mkdir -p "$OUT/logs/$run-dumps" && cp -R "$data/tmp/marketing-dumps/." "$OUT/logs/$run-dumps/"
    fi
    grep -E "Test Case .*(passed|failed|skipped)|error:|Executed [0-9]+ test" "$OUT/logs/$run-test.log" \
        | tee "$OUT/logs/$run-summary.txt" >&2
    log "$run exit $status"
    return "$status"
}

# macOS: MarketingCaptureMacUITests saves kept attachments; export them as
# <out>/mac/<shot>.png. The sandboxed Debug app reads /private/tmp only.
run_mac() {
    local tmpdir=/private/tmp/pb-marketing-$$ status
    rm -rf "$tmpdir" && mkdir -p "$tmpdir/export" && cp -R "$WORK/photos" "$tmpdir/photos"
    osascript -e 'tell application "System Events" to set visible of (every process whose name is not "Finder" and background only is false) to false' >/dev/null 2>&1
    log "running mac"
    TEST_RUNNER_MARKETING_PHOTOS=$tmpdir/photos TEST_RUNNER_MARKETING_EXPORT=$tmpdir/export \
    TEST_RUNNER_MARKETING_PICKS=${MARKETING_MAC_PICKS:-${MARKETING_PICKS:-}} \
    TEST_RUNNER_MARKETING_LANGUAGE=$LANGUAGE TEST_RUNNER_MARKETING_REGION=$REGION TEST_RUNNER_MARKETING_TITLE="$TITLE" \
    xcodebuild test -project PhotoBooks.xcodeproj -scheme PhotoBooks -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$WORK/dd-mac" -only-testing:PhotoBooksUITests/MarketingCaptureMacUITests \
        -resultBundlePath "$WORK/mac.xcresult" > "$OUT/logs/mac-test.log" 2>&1
    status=$?
    rm -rf "$tmpdir"
    grep -E "Test Case .*(passed|failed|skipped)|error:|Executed [0-9]+ test" "$OUT/logs/mac-test.log" \
        | tee "$OUT/logs/mac-summary.txt" >&2
    mkdir -p "$OUT/mac" "$WORK/mac-attachments"
    xcrun xcresulttool export attachments --path "$WORK/mac.xcresult" --output-path "$WORK/mac-attachments" >&2
    /usr/bin/python3 -I - "$WORK/mac-attachments" "$OUT/mac" <<'PY'
import json, os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName", "")
        exported = item.get("exportedFileName", "")
        base, ext = os.path.splitext(name)
        if ext == ".png" and base[:2].isdigit():
            shutil.copy(os.path.join(src, exported), os.path.join(dst, base.split("_")[0] + ".png"))
        elif ext == ".txt":
            shutil.copy(os.path.join(src, exported), os.path.join(dst, "..", "logs", "mac-" + exported))
PY
    log "mac exit $status"
    return "$status"
}

# Simulators first (build-for-testing needs a destination).
for kind in $DEVICES; do
    case $kind in
        iphone) make_sim IPHONE "iPhone 17 Pro Max" || log "cannot create iPhone 17 Pro Max" ;;
        ipad) make_sim IPAD "iPad Pro 13-inch (M5)" || log "cannot create iPad Pro 13-inch (M5)" ;;
        duo) make_sim DUO "iPhone Duo" || log "cannot create iPhone Duo" ;;
    esac
done
FIRST=${IPHONE:-${DUO:-${IPAD:-}}}
if [ -z "$FIRST" ]; then
    [ "$DEVICES" = mac ] || { log "no simulators"; exit 1; }
    run_mac; exit $?
fi

log "build-for-testing"
if ! xcodebuild build-for-testing -project PhotoBooks.xcodeproj -scheme "PhotoBooks iOS UITests" \
        -configuration Debug -destination "id=$FIRST" -derivedDataPath "$WORK/dd" \
        > "$OUT/logs/build.log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$OUT/logs/build.log" | head -40 >&2
    exit 1
fi
PRODUCTS=$WORK/dd/Build/Products/Debug-iphonesimulator
APP_PATH=$PRODUCTS/PhotoBooks.app
RUNNER_PATH=$PRODUCTS/PhotoBooksDuoUITests-Runner.app
[ -d "$APP_PATH" ] && [ -d "$RUNNER_PATH" ] || { log "products missing in $PRODUCTS"; ls "$PRODUCTS" >&2; exit 1; }

# Other windows on the desktop steal UI-test focus.
osascript -e 'tell application "System Events" to set visible of (every process whose name is not "Finder" and background only is false) to false' >/dev/null 2>&1

status=0
beats_for() { echo " $BEAT_DEVICES " | grep -q " $1 " && echo 1 || echo 0; }
for kind in $DEVICES; do
    KIND=$kind POSE=""
    case $kind in
        iphone) DEVICE=${IPHONE:-} ;;
        ipad) DEVICE=${IPAD:-} ;;
        duo) DEVICE=${DUO:-} ;;
        mac) run_mac || status=1; continue ;;
    esac
    [ -n "$DEVICE" ] || { status=1; continue; }
    if [ "$kind" = duo ]; then
        boot "$DEVICE" "$OUTER" || { log "Duo did not boot"; status=1; continue; }
        for duo_pose in ${MARKETING_DUO_POSES:-closed flat}; do
            hinge "$duo_pose" 2.5
            if [ "$duo_pose" = closed ]; then
                run_tests duo-outer "$(beats_for duo-outer)" 0 || status=1
            else
                run_tests duo-inner "$(beats_for duo-inner)" 1 || status=1
            fi
        done
    else
        boot "$DEVICE" || { log "$kind did not boot"; status=1; continue; }
        run_tests "$kind" "$(beats_for "$kind")" 0 || status=1
    fi
    xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1
done

# Recording sanity: duration of every mp4.
for mp4 in "$OUT"/*/*.mp4; do
    [ -e "$mp4" ] || continue
    if command -v ffprobe >/dev/null; then
        echo "${mp4#$OUT/} $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4" 2>&1)"
    else
        echo "${mp4#$OUT/} $(stat -f %z "$mp4") bytes"
    fi
done | tee "$OUT/recordings.txt" >&2
log "exit $status; captures in $OUT"
exit "$status"
