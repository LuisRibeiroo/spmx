#!/bin/bash
# spmx benchmark harness. Measures spmx against vanilla SwiftPM/Xcode with hyperfine and
# writes bench/results/<date>-<chip>.json plus bench/results/latest.json (schema 1).
#
#   ./run.sh                       all scenarios, all fixtures
#   ./run.sh --quick               S3 + S5 only (no S6, no network-bound S1/S2)
#   ./run.sh --scenario S3         one scenario (S1..S6)
#   ./run.sh --fixture swift-macros   restrict to one fixture id from fixtures.json
#
# Env: SPMX_BIN (default: .build/release/spmx), BENCH_RUNS (10), BENCH_WARMUP (1),
#      BENCH_RUNS_S5 (50), BENCH_KEEP=1 (keep the temp directory for debugging)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

die() { echo "bench: $*" >&2; exit 1; }

QUICK=0; ONLY_SCENARIO=""; ONLY_FIXTURE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --scenario) ONLY_SCENARIO="${2:?--scenario needs an id}"; shift ;;
    --fixture) ONLY_FIXTURE="${2:?--fixture needs an id}"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

# ---- prerequisites -------------------------------------------------------
command -v hyperfine >/dev/null 2>&1 || die "hyperfine is not installed. Install it with: brew install hyperfine"
[ -x /usr/bin/python3 ] || die "/usr/bin/python3 is required (install the Xcode command line tools: xcode-select --install)"
command -v git >/dev/null 2>&1 || die "git is required"
command -v xcrun >/dev/null 2>&1 || die "Xcode command line tools are required (xcode-select --install)"
[ "$(uname -s)" = "Darwin" ] || die "spmx benchmarks run on macOS only"

SPMX_BIN="${SPMX_BIN:-$ROOT/.build/release/spmx}"
if [ ! -x "$SPMX_BIN" ]; then
  SPMX_BIN="$(command -v spmx 2>/dev/null || true)"
fi
[ -n "$SPMX_BIN" ] && [ -x "$SPMX_BIN" ] || die "spmx binary not found. Build it with: swift build -c release  (or set SPMX_BIN)"
export SPMX_BIN

RUNS="${BENCH_RUNS:-10}"; WARMUP="${BENCH_WARMUP:-1}"; RUNS_S5="${BENCH_RUNS_S5:-50}"

if [ -n "$ONLY_SCENARIO" ]; then
  case "$ONLY_SCENARIO" in S1|S2|S3|S4|S5|S6) SCENARIOS="$ONLY_SCENARIO" ;; *) die "unknown scenario $ONLY_SCENARIO (S1..S6)" ;; esac
elif [ "$QUICK" = 1 ]; then SCENARIOS="S3 S5"
else SCENARIOS="S1 S2 S3 S4 S5 S6"; fi

# Real tools must be reachable without the user's own spmx shims in the way.
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/\.spmx/shims' | paste -sd: -)"
export PATH
SWIFT_BIN="$(xcrun --find swift)"

# shellcheck source=lib/disk.sh
. "$HERE/lib/disk.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/spmx-bench.XXXXXX")"
RESULTS_TMP="$WORK/results"; mkdir -p "$RESULTS_TMP" "$WORK/repos"
SHIMS="$WORK/shims"; mkdir -p "$SHIMS"
for tool in swift xcodebuild flutter; do ln -sf "$SPMX_BIN" "$SHIMS/$tool"; done
MOUNTS=""

cleanup() {
  for m in $MOUNTS; do disk_destroy "${m%%|*}" "${m##*|}" || true; done
  if [ "${BENCH_KEEP:-0}" = 1 ]; then echo "bench: kept $WORK" >&2; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

# ---- fixtures ------------------------------------------------------------
fx_ids() { /usr/bin/python3 -c 'import json,sys; [print(f["id"]) for f in json.load(open(sys.argv[1]))["fixtures"]]' "$HERE/fixtures.json"; }
fx() { /usr/bin/python3 -c 'import json,sys; f=[x for x in json.load(open(sys.argv[1]))["fixtures"] if x["id"]==sys.argv[2]][0]; v=f.get(sys.argv[3],""); print(str(v).lower() if isinstance(v,bool) else v)' "$HERE/fixtures.json" "$1" "$2"; }

clone_fixture() { # <id> <dir>
  local id="$1" dir="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$(fx "$id" repo)"
  git -C "$dir" fetch -q --depth 1 origin "$(fx "$id" commit)"
}

# ---- per-fixture command builders ---------------------------------------
setup_fixture_env() { # sets F_* globals for fixture $1 and a worktree dir $2
  F_ID="$1"; F_TYPE="$(fx "$1" type)"; F_SUB="$(fx "$1" subpath)"; F_WS="$(fx "$1" workspace)"; F_SCHEME="$(fx "$1" scheme)"
  F_BUILD="$(fx "$1" build)"; WT="$2"
}

native_resolve_cmd() { # baseline: vanilla toolchain, spmx disabled
  if [ "$F_TYPE" = swiftpm ]; then
    echo "cd '$WT/$F_SUB' && SPMX_DISABLE=1 '$SWIFT_BIN' package resolve --cache-path '$BENCH_SPM_CACHE' >/dev/null 2>&1"
  else
    echo "cd '$WT/$F_SUB' && SPMX_DISABLE=1 xcodebuild -resolvePackageDependencies -workspace '$F_WS' -scheme '$F_SCHEME' -derivedDataPath '$WT/DerivedData' >/dev/null 2>&1"
  fi
}

shim_resolve_cmd() { # spmx: same command through the shim (hydrates, runs, harvests)
  local env="SPMX_STORE_DIR='$BENCH_STORE' SPMX_SHIMS_DIR='$SHIMS' PATH='$SHIMS':\"\$PATH\""
  if [ "$F_TYPE" = swiftpm ]; then
    echo "cd '$WT/$F_SUB' && $env swift package resolve --cache-path '$BENCH_SPM_CACHE' >/dev/null 2>&1"
  else
    echo "cd '$WT/$F_SUB' && $env xcodebuild -resolvePackageDependencies -workspace '$F_WS' -scheme '$F_SCHEME' -derivedDataPath '$WT/DerivedData' >/dev/null 2>&1"
  fi
}

hydrate_cmd() { # spmx hydrate, store warm
  if [ "$F_TYPE" = swiftpm ]; then
    echo "SPMX_STORE_DIR='$BENCH_STORE' '$SPMX_BIN' hydrate '$WT/$F_SUB' --quiet"
  else
    echo "SPMX_STORE_DIR='$BENCH_STORE' '$SPMX_BIN' hydrate '$WT/$F_SUB' --workspace '$WT/$F_SUB/$F_WS' --source-packages '$WT/DerivedData/SourcePackages' --quiet"
  fi
}

harvest_cmd() {
  if [ "$F_TYPE" = swiftpm ]; then
    echo "SPMX_STORE_DIR='$BENCH_STORE' '$SPMX_BIN' harvest '$WT/$F_SUB' --quiet"
  else
    echo "SPMX_STORE_DIR='$BENCH_STORE' '$SPMX_BIN' harvest '$WT/$F_SUB' --workspace '$WT/$F_SUB/$F_WS' --source-packages '$WT/DerivedData/SourcePackages' --quiet"
  fi
}

flutter_bootstrap() { # flutter fixtures need pub get before Xcode can resolve
  if [ "$F_TYPE" = flutter ]; then (cd "$WT/$F_SUB" && SPMX_DISABLE=1 flutter pub get >/dev/null 2>&1) || die "flutter pub get failed for $F_ID"; fi
}

new_worktree() { # <repo> <dir> <commit>
  rm -rf "$2"; git -C "$1" worktree prune
  git -C "$1" worktree add --quiet --detach "$2" "$3"
}

hf_prepared() { # same, with the reset.sh prepare hook
  local out="$1" name="$2" cmd="$3"
  hyperfine --shell=default --warmup "$WARMUP" --runs "$RUNS" --prepare "$HERE/lib/reset.sh" --export-json "$out" --command-name "$name" "$cmd" >&2
}

export_bench_env() { # <scenario> <mode> <repo> <commit>
  export BENCH_SCENARIO="$1" BENCH_MODE="$2" BENCH_REPO="$3" BENCH_COMMIT="$4" BENCH_WT="$WORK/wt"
  export BENCH_SPM_CACHE="$WORK/spm-cache" BENCH_STORE="$WORK/store" BENCH_CC="$WORK/compilation-cache"
  export SPMX_COMPILATION_CACHE_DIR="$BENCH_CC"
}

prime_native_cache() { # warm the SwiftPM cache and (optionally) the spmx store with a primer worktree
  local repo="$1" commit="$2" with_store="$3"
  mkdir -p "$BENCH_SPM_CACHE" "$BENCH_STORE"
  WT="$WORK/primer"; new_worktree "$repo" "$WT" "$commit"; flutter_bootstrap
  eval "$(native_resolve_cmd)" || die "native resolve failed while priming $F_ID"
  if [ "$with_store" = 1 ]; then eval "$(harvest_cmd)" || die "harvest failed while priming $F_ID"; fi
}

# ---- scenarios -----------------------------------------------------------
run_network_scenario() { # S1|S2
  local sid="$1" id="$2" repo="$WORK/repos/$2" commit; commit="$(fx "$id" commit)"
  [ -d "$repo/.git" ] || clone_fixture "$id" "$repo"
  WT="$WORK/wt"; export_bench_env "$sid" baseline "$repo" "$commit"
  [ "$sid" = S2 ] && { prime_native_cache "$repo" "$commit" 0; WT="$WORK/wt"; }
  hf_prepared "$RESULTS_TMP/${sid}__${id}__baseline.json" "$id baseline" "$(native_resolve_cmd)"
  export_bench_env "$sid" spmx "$repo" "$commit"
  hf_prepared "$RESULTS_TMP/${sid}__${id}__spmx.json" "$id spmx" "$(shim_resolve_cmd)"
}

run_s3() {
  local id="$1" repo="$WORK/repos/$1" commit; commit="$(fx "$id" commit)"
  [ -d "$repo/.git" ] || clone_fixture "$id" "$repo"
  export_bench_env S3 baseline "$repo" "$commit"
  prime_native_cache "$repo" "$commit" 1; WT="$WORK/wt"
  hf_prepared "$RESULTS_TMP/S3__${id}__baseline.json" "$id native resolve" "$(native_resolve_cmd)"
  export_bench_env S3 spmx "$repo" "$commit"
  hf_prepared "$RESULTS_TMP/S3__${id}__spmx.json" "$id spmx hydrate" "$(hydrate_cmd)"
}

run_s4() {
  local id="$1" n=5 commit; commit="$(fx "$id" commit)"
  local mode result_baseline=0 result_spmx=0
  for mode in baseline spmx; do
    local image="$WORK/disk-$mode" mnt
    mnt="$(disk_create "$image" 60g)"; [ -n "$mnt" ] || die "could not create APFS test volume"
    MOUNTS="$MOUNTS $image|$mnt"
    local repo="$mnt/repo"; clone_fixture "$id" "$repo"
    export BENCH_SPM_CACHE="$mnt/spm-cache" BENCH_STORE="$mnt/store" SPMX_COMPILATION_CACHE_DIR="$mnt/cc"
    mkdir -p "$BENCH_SPM_CACHE" "$BENCH_STORE"
    local total=0 i
    for i in $(seq 1 "$n"); do
      WT="$mnt/wt$i"; new_worktree "$repo" "$WT" "$commit"; flutter_bootstrap
      local before after
      before="$(disk_free_bytes "$mnt")"
      if [ "$i" = 1 ]; then
        eval "$(native_resolve_cmd)" || die "native resolve failed (S4 $id)"
        [ "$mode" = spmx ] && { eval "$(harvest_cmd)" || die "harvest failed (S4 $id)"; }
      elif [ "$mode" = baseline ]; then eval "$(native_resolve_cmd)" || die "native resolve failed (S4 $id)"
      else eval "$(hydrate_cmd)" || die "hydrate failed (S4 $id)"; fi
      after="$(disk_free_bytes "$mnt")"
      [ "$i" -gt 1 ] && total=$(( total + before - after ))
    done
    local avg=$(( total / (n - 1) ))
    if [ "$mode" = baseline ]; then result_baseline="$avg"; else result_spmx="$avg"; fi
    disk_destroy "$image" "$mnt"; MOUNTS="${MOUNTS/ $image|$mnt/}"
  done
  printf '{"worktrees": %s, "baseline": %s, "spmx": %s}\n' "$n" "$result_baseline" "$result_spmx" > "$RESULTS_TMP/S4__${id}.json"
}

run_s5() {
  local tools="swift"; command -v flutter >/dev/null 2>&1 && tools="swift flutter"
  local t real
  for t in $tools; do
    real="$(command -v "$t")"
    echo "bench: S5 $t: direct $real vs shim $SHIMS/$t" >&2
    export SPMX_SHIMS_DIR="$SHIMS"
    hyperfine -N --warmup 3 --runs "$RUNS_S5" --export-json "$RESULTS_TMP/S5__shim-$t-version__baseline.json" --command-name "$t direct" "$real --version" >&2
    hyperfine -N --warmup 3 --runs "$RUNS_S5" --export-json "$RESULTS_TMP/S5__shim-$t-version__spmx.json" --command-name "$t shim" "$SHIMS/$t --version" >&2
  done
}

run_s6() {
  local id="$1" repo="$WORK/repos/$1" commit; commit="$(fx "$id" commit)"
  [ "$(fx "$id" build)" = true ] || return 0
  [ -d "$repo/.git" ] || clone_fixture "$id" "$repo"
  export_bench_env S6 baseline "$repo" "$commit"
  mkdir -p "$BENCH_SPM_CACHE" "$BENCH_STORE" "$BENCH_CC"
  # Prime: store warm and compilation cache warm via the shims.
  WT="$WORK/primer"; new_worktree "$repo" "$WT" "$commit"
  (cd "$WT/$F_SUB" && SPMX_STORE_DIR="$BENCH_STORE" SPMX_SHIMS_DIR="$SHIMS" PATH="$SHIMS:$PATH" swift build >/dev/null 2>&1) || die "priming build failed for $id"
  WT="$WORK/wt"
  local shim="SPMX_STORE_DIR='$BENCH_STORE' SPMX_SHIMS_DIR='$SHIMS' PATH='$SHIMS':\"\$PATH\""
  hf_prepared "$RESULTS_TMP/S6__${id}__baseline.json" "$id cache off" "cd '$WT/$F_SUB' && SPMX_NO_COMPILE_CACHE=1 $shim swift build >/dev/null 2>&1"
  export_bench_env S6 spmx "$repo" "$commit"
  hf_prepared "$RESULTS_TMP/S6__${id}__spmx.json" "$id cache on" "cd '$WT/$F_SUB' && $shim swift build >/dev/null 2>&1"
}

# ---- main ----------------------------------------------------------------
FIXTURE_IDS="$(fx_ids)"
[ -z "$ONLY_FIXTURE" ] || { printf '%s\n' "$FIXTURE_IDS" | grep -qx "$ONLY_FIXTURE" || die "unknown fixture $ONLY_FIXTURE"; FIXTURE_IDS="$ONLY_FIXTURE"; }

for sid in $SCENARIOS; do
  echo "bench: === $sid ===" >&2
  case "$sid" in
    S5) run_s5 ;;
    *)
      for id in $FIXTURE_IDS; do
        setup_fixture_env "$id" "$WORK/wt"
        echo "bench: $sid on $id" >&2
        case "$sid" in
          S1|S2) run_network_scenario "$sid" "$id" ;;
          S3) run_s3 "$id" ;;
          S4) run_s4 "$id" ;;
          S6) run_s6 "$id" ;;
        esac
      done ;;
  esac
done

mkdir -p "$HERE/results"
"$HERE/lib/env.sh" > "$WORK/env.json"
CHIP_SLUG="$(sysctl -n machdep.cpu.brand_string | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-' )"
OUT="$HERE/results/$(date -u +%Y-%m-%d)-$CHIP_SLUG.json"
/usr/bin/python3 "$HERE/lib/assemble.py" "$RESULTS_TMP" "$WORK/env.json" "$HERE/fixtures.json" "$OUT" "$WARMUP" "$RUNS" "$HERE/results/latest.json"
cp "$OUT" "$HERE/results/latest.json"
echo "bench: wrote $OUT and results/latest.json" >&2
