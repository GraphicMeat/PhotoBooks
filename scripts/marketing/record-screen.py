#!/usr/bin/python3 -I
"""Screen recording that can be stopped: screencapture -v only writes its file
when a key arrives on a terminal (any signal loses the file), so it runs on a
pty and gets a key once the stop file appears.

Usage: record-screen.py <stop-file> <output.mov> [screencapture options]
Needs Screen Recording for the calling session. Frames are written only when
the screen changes: a still tail is missing from the file.
"""
import os
import pty
import select
import sys

stop, output, options = sys.argv[1], sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("/usr/sbin/screencapture", ["screencapture", "-x", "-v", *options, output])
sent = False
while True:
    ready, _, _ = select.select([fd], [], [], 0.1)
    if ready:
        try:
            if not os.read(fd, 4096):
                break
        except OSError:
            break
    if not sent and os.path.exists(stop):
        os.write(fd, b"q")
        sent = True
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
