#!/usr/bin/env bash
# Renders src/*.html to 2540x1520 PNGs (Product Hunt gallery 1270x760 at 2x) with headless Chrome.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PROFILE="$(mktemp -d)"
trap 'rm -rf "$PROFILE"' EXIT
for f in src/*.html; do
  name="$(basename "$f" .html)"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --user-data-dir="$PROFILE" \
    --window-size=1270,760 --force-device-scale-factor=2 \
    --virtual-time-budget=6000 \
    --screenshot="$PWD/$name.png" "file://$PWD/$f" >/dev/null 2>&1
  echo "rendered $name.png"
done
