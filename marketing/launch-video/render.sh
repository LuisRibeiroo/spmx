#!/usr/bin/env bash
# Renders index.html to spmx-launch.mp4 (1920x1080, 30 fps): headless Chrome frames -> AVFoundation H.264.
# Preview the animation live by opening index.html in a browser (space = pause, arrows = seek).
set -euo pipefail
cd "$(dirname "$0")"
FPS="${FPS:-30}"
WORK="${WORK:-$(mktemp -d -t spmx-video)}"
mkdir -p "$WORK/frames"
rm -f "$WORK"/frames/f*.png
node capture.mjs "$WORK/frames" "$FPS"
swiftc -O encode.swift -o "$WORK/encode"
"$WORK/encode" "$WORK/frames" "$PWD/spmx-launch.mp4" "$FPS"
echo "frames kept in $WORK/frames"
