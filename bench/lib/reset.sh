#!/bin/bash
# hyperfine --prepare hook. Brings the world back to the state a scenario starts from.
# Environment (set by run.sh): BENCH_SCENARIO, BENCH_MODE (baseline|spmx), BENCH_REPO,
# BENCH_COMMIT, BENCH_WT, BENCH_SPM_CACHE, BENCH_STORE, BENCH_CC
set -euo pipefail

: "${BENCH_SCENARIO:?}" "${BENCH_MODE:?}" "${BENCH_REPO:?}" "${BENCH_COMMIT:?}" "${BENCH_WT:?}"

new_worktree() {
  rm -rf "$BENCH_WT"
  git -C "$BENCH_REPO" worktree prune
  git -C "$BENCH_REPO" worktree add --quiet --detach "$BENCH_WT" "$BENCH_COMMIT"
}

case "$BENCH_SCENARIO" in
  S1) # cold: no SwiftPM cache, no spmx store
      rm -rf "$BENCH_SPM_CACHE" "$BENCH_STORE"; mkdir -p "$BENCH_SPM_CACHE" "$BENCH_STORE"
      new_worktree ;;
  S2) # new worktree, SwiftPM cache warm (primed by run.sh), spmx store empty
      rm -rf "$BENCH_STORE"; mkdir -p "$BENCH_STORE"
      new_worktree ;;
  S3) # new worktree, spmx store warm (primed by run.sh). Baseline keeps the SwiftPM cache warm too.
      new_worktree ;;
  S6) # clean build in a new worktree: store warm, compilation cache state decided by run.sh
      new_worktree ;;
  *)  echo "reset.sh: no reset defined for $BENCH_SCENARIO" >&2; exit 1 ;;
esac
