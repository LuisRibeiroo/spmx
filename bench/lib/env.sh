#!/bin/bash
# Prints the machine/toolchain/pspm metadata block as JSON on stdout.
# Usage: PSPM_BIN=/path/to/pspm lib/env.sh
set -euo pipefail

chip="$(sysctl -n machdep.cpu.brand_string)"
ram_gb="$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))"
macos="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
xcode="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//' || echo unknown)"
swift_v="$("$(xcrun --find swift)" --version 2>&1 | head -1)"
pspm_v="$("${PSPM_BIN:?PSPM_BIN not set}" --version 2>/dev/null || echo unknown)"
commit="$(git -C "$(dirname "$0")/../.." rev-parse --short HEAD 2>/dev/null || echo nogit)"
dirty=""
if [ -n "$(git -C "$(dirname "$0")/../.." status --porcelain -- Sources Package.swift 2>/dev/null)" ]; then dirty="-dirty"; fi

CHIP="$chip" RAM="$ram_gb" MACOS="$macos" XCODE="$xcode" SWIFT="$swift_v" PSPM="${pspm_v}+${commit}${dirty}" /usr/bin/python3 - <<'PY'
import json, os
print(json.dumps({
    "pspm": os.environ["PSPM"],
    "machine": {
        "chip": os.environ["CHIP"],
        "ram_gb": int(os.environ["RAM"]),
        "macos": os.environ["MACOS"],
        "xcode": os.environ["XCODE"],
        "swift": os.environ["SWIFT"],
    },
}))
PY
