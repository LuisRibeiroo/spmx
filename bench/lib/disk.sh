#!/bin/bash
# Physical-disk helpers. `du` reports the logical size of APFS clones and overstates
# their cost, so cost is measured as the drop in free space of an isolated volume.
#
#   disk_create <image-path> <size>   -> prints mount point
#   disk_free_bytes <mount-point>
#   disk_destroy <image-path> <mount-point>
set -euo pipefail

disk_create() {
  local image="$1" size="${2:-60g}"
  rm -f "$image" "$image.sparseimage"
  hdiutil create -quiet -size "$size" -fs APFS -type SPARSE -volname spmxbench "$image" >&2
  local attached
  attached="$(hdiutil attach -nobrowse -noverify "${image}.sparseimage" 2>/dev/null)"
  printf '%s\n' "$attached" | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1 | sed 's/[[:space:]]*$//'
}

disk_free_bytes() {
  # Sync first so delayed allocations do not hide in the next sample.
  sync
  df -k "$1" | awk 'NR==2 {print $4 * 1024}'
}

disk_destroy() {
  local image="$1" mount="$2"
  hdiutil detach -quiet -force "$mount" >/dev/null 2>&1 || true
  rm -f "$image" "${image}.sparseimage"
}
