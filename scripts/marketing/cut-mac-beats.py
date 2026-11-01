#!/usr/bin/python3 -I
"""Cuts one continuous macOS screen recording into the app-preview beats.

Usage: cut-mac-beats.py <screen.mov> <timeline.txt> <recording start epoch> <out-dir> <report.txt>

The timeline comes from MarketingCaptureMacUITests.test3RecordBeats, one
"<epoch> <event> ..." per line: screen W H / sync / in <beat> x y w h /
out <beat> / skip-start / skip-end / act <what>. Recording time is tied to the
wall clock by the sync marks: a pointer jump after a still desktop is the first
frame after a gap, since screencapture only writes frames on change.

Each beat becomes <out-dir>/<beat>.mp4: the window region at 60 fps constant,
the window's rounded corners filled white so no desktop shows.
"""
import os
import subprocess
import sys

CORNER_RADIUS_PT = 34  # past the true ~26: window corners are not circular arcs
screen_mov, timeline_path, started, out_dir, report_path = sys.argv[1:6]
started = float(started)


def probe(*entries):
    return subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v", *entries,
                                    "-of", "csv=p=0", screen_mov], text=True)


events = []
for line in open(timeline_path, encoding="utf-8"):
    parts = line.split()
    if len(parts) >= 2:
        events.append((float(parts[0]), parts[1], parts[2:]))

pixel_width = int(probe("-show_entries", "stream=width").split(",")[0])
screen_width = next(float(rest[0]) for _, kind, rest in events if kind == "screen")
scale = round(pixel_width / screen_width)
packets = sorted(float(value.strip(", \n")) for value in
                 probe("-show_entries", "packet=pts_time").split("\n") if value.strip(", \n"))

# Wall clock minus recording time.
offset = None
for wall, kind, _ in events:
    if kind != "sync":
        continue
    estimate = wall - started - 1.0
    jumps = [packets[i] for i in range(1, len(packets))
             if packets[i] - packets[i - 1] >= 1.2 and abs(packets[i] - estimate) <= 4]
    if jumps:
        offset = wall - min(jumps, key=lambda value: abs(value - estimate))
        break
report = []
if offset is None:
    offset = started + 1.0
    report.append("WARNING: no sync frame found; assuming the recording started 1.0 s after launch")
report.append(f"recording started {offset - started:.3f} s after launch, {packets[-1]:.1f} s of frames, scale {scale}")

beats = []
current = None
for wall, kind, rest in events:
    if kind == "in":
        current = {"name": rest[0], "frame": [float(v) for v in rest[1:5]], "in": wall, "out": None,
                   "skips": [], "acts": []}
        beats.append(current)
    elif current is None:
        continue
    elif kind == "out":
        current["out"] = wall
        current = None
    elif kind == "skip-start":
        current["skips"].append([wall, None])
    elif kind == "skip-end":
        current["skips"][-1][1] = wall
    elif kind == "act":
        current["acts"].append((wall, " ".join(rest)))


def even(value):
    return int(round(value / 2.0)) * 2


mask = os.path.join(out_dir, ".corner-mask.png")
mask_size = None
for beat in beats:
    if beat["out"] is None:
        report.append(f"{beat['name']}: never finished, skipped")
        continue
    x, y, width, height = beat["frame"]
    crop = [even(width * scale), even(height * scale), even(x * scale), even(y * scale)]
    if mask_size != crop[:2]:
        w, h, r = crop[0], crop[1], CORNER_RADIUS_PT * scale
        distance = f"hypot(max(max({r}-X,X-{w - 1 - r}),0),max(max({r}-Y,Y-{h - 1 - r}),0))"
        subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=white:s={w}x{h}:d=0.04",
                               "-vf", f"format=rgba,geq=r=255:g=255:b=255:a='255*clip({distance}-{r}+1.5,0,1)'",
                               "-frames:v", "1", mask])
        mask_size = crop[:2]
    # Wall windows to keep.
    spans, cursor = [], beat["in"]
    for start, end in beat["skips"]:
        spans.append((cursor, start))
        cursor = end
    spans.append((cursor, beat["out"]))
    spans = [(a - offset, b - offset) for a, b in spans if b > a]

    graph = (f"[0:v]tpad=stop_mode=clone:stop_duration=300,fps=60:start_time=0,"
             f"crop={crop[0]}:{crop[1]}:{crop[2]}:{crop[3]}")
    if len(spans) == 1:
        a, b = spans[0]
        graph += f",trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS[joined];"
    else:
        labels = [f"s{i}" for i in range(len(spans))]
        graph += f",split={len(spans)}" + "".join(f"[{label}in]" for label in labels) + ";"
        for label, (a, b) in zip(labels, spans):
            graph += f"[{label}in]trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS[{label}];"
        graph += "".join(f"[{label}]" for label in labels) + f"concat=n={len(spans)}:v=1:a=0[joined];"
    graph += "[joined][1:v]overlay=shortest=1,format=yuv420p[video]"
    output = os.path.join(out_dir, beat["name"] + ".mp4")
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-i", screen_mov,
                           "-loop", "1", "-framerate", "60", "-i", mask,
                           "-filter_complex", graph, "-map", "[video]", "-c:v", "libx264", "-preset", "medium",
                           "-crf", "16", "-movflags", "+faststart", output])

    def local(wall):  # wall clock to seconds in this mp4 (None when cut out)
        elapsed = 0.0
        t = wall - offset
        for a, b in spans:
            if a <= t <= b:
                return elapsed + t - a
            elapsed += b - a
        return None

    duration = sum(b - a for a, b in spans)
    report.append(f"{beat['name']}.mp4 {duration:.1f} s, window {x:.0f},{y:.0f} {width:.0f}x{height:.0f} pt"
                  + (f", {len(beat['skips'])} hard cut(s)" if beat["skips"] else ""))
    for wall, what in beat["acts"]:
        at = local(wall)
        report.append(f"  {at:6.2f}  {what}" if at is not None else f"     cut  {what}")
for wall, kind, rest in events:
    if kind == "blurb":
        report.append("BLURB ON SCREEN: " + " ".join(rest))
if os.path.exists(mask):
    os.remove(mask)
with open(report_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(report) + "\n")
print("\n".join(report), file=sys.stderr)
