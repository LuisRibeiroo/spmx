# pspm benchmarks

A local, reproducible harness that measures pspm against vanilla SwiftPM and Xcode. Every performance number on the website is read from `bench/results/latest.json`; none is written by hand.

## Prerequisites

- macOS with Xcode and its command line tools (`xcode-select --install`)
- [hyperfine](https://github.com/sharkdp/hyperfine): `brew install hyperfine`
- a release build of pspm: `swift build -c release` (or point `PSPM_BIN` at a binary)
- network access for the first run of each fixture
- Flutter on `PATH` for the `flutter-firebase` fixture and the Flutter half of S5

`run.sh` stops with a clear message when `hyperfine` or `pspm` is missing.

## Run

```bash
make bench                              # everything
make bench-quick                        # S3 + S5
bench/run.sh --scenario S3              # one scenario
bench/run.sh --fixture swift-macros     # one fixture
```

Environment: `PSPM_BIN`, `BENCH_RUNS` (default 10), `BENCH_WARMUP` (default 1), `BENCH_RUNS_S5` (default 50, because the shim overhead is measured in milliseconds), `BENCH_KEEP=1` to keep the temporary directory.

Output goes to `bench/results/<date>-<chip>.json` and `bench/results/latest.json`. A partial run (for example `--scenario S3`) keeps the entries that an earlier run on the same chip already produced for other scenarios and fixtures.

The harness runs everything in a temporary directory with its own pspm store (`PSPM_STORE_DIR`), its own compilation cache (`PSPM_COMPILATION_CACHE_DIR`) and its own SwiftPM cache. It never touches `~/.pspm`. Your own pspm shims are removed from `PATH` for the duration of the run.

## Scenarios

| # | Scenario | Baseline | pspm |
| :--- | :--- | :--- | :--- |
| S1 | Cold, no cache of any kind. pspm must not make this worse | `swift package resolve` / `xcodebuild -resolvePackageDependencies` with `PSPM_DISABLE=1` | the same command through the shim |
| S2 | New worktree, only the SwiftPM cache warm | same command, `PSPM_DISABLE=1` | same command through the shim, store empty |
| S3 | **New worktree, pspm store warm (the headline)** | native resolve, SwiftPM cache warm | `pspm hydrate` |
| S4 | Disk: 5 worktrees | extra physical bytes per extra worktree, native | the same, hydrated |
| S5 | Shim overhead on a no-op (`swift --version`, `flutter --version`) | the tool directly | the tool through the shim (target: under 5 ms) |
| S6 | Clean build in a second worktree (LLVM CAS) | `PSPM_NO_COMPILE_CACHE=1` | compilation cache on |

S1 and S2 are marked `network_dependent`. S6 is excluded from `--quick`. S3's baseline deliberately keeps SwiftPM's own cache warm so the comparison is conservative: pspm is not measured against a cold download.

## Physical disk, not `du`

`clonefile()` copies share blocks, and `du` reports their logical size. S4 therefore creates an isolated sparse APFS disk image (`hdiutil create -fs APFS -type SPARSE`), puts the worktrees and the pspm store inside it, and records the drop in free space of that volume (`df -k`) around each extra worktree's resolve or hydrate step. The image is detached and deleted at the end.

## Fixtures

`fixtures.json` pins a repository and commit for each profile; nothing is vendored.

| Id | Profile | Notes |
| :--- | :--- | :--- |
| `swift-macros` | native Swift with macros (swift-syntax prebuilts) | SwiftPM; the only fixture with `build: true`, so it is the one S6 uses |
| `swiftpm-binary-sdk` | heavy binary SDK (Firebase XCFramework artifacts) | SwiftPM |
| `flutter-firebase` | Flutter + SwiftPM with Firebase plugins | Needs Flutter and a full Xcode. The upstream example has no committed `pubspec.lock`, so the dependency set follows the pinned commit's constraints |

The `flutter-firebase` and Xcode-driven paths are the least exercised parts of the harness. Treat their first run as validation of the harness itself.

## Reading results

Each scenario entry has `baseline` and `pspm` blocks with `median_s`, `min_s`, `max_s`, `stddev_s` and `runs`. Compare medians and look at the spread: when the difference is smaller than `stddev_s`, it is noise. S4 reports bytes in `disk_bytes`. Results that miss the targets in `tasks/prd-pspm-cli.md` are still published on the site's `/benchmarks` page; they are simply not promoted to a headline.

## Schema

```json
{
  "schema": 1,
  "date": "…", "pspm": "<version>+<commit>",
  "machine": { "chip": "…", "ram_gb": 0, "macos": "…", "xcode": "…", "swift": "…" },
  "scenarios": [
    { "id": "S3", "fixture": "…", "network_dependent": false,
      "baseline": { "median_s": 0, "min_s": 0, "max_s": 0, "stddev_s": 0, "runs": 10 },
      "pspm":     { "median_s": 0, "min_s": 0, "max_s": 0, "stddev_s": 0, "runs": 10 },
      "disk_bytes": null }
  ]
}
```

`methodology` and `fixtures` are optional additions that the site uses for its methodology block. The schema is validated with Zod when the website builds (`website/lib/benchmark-schema.ts`); an invalid file fails the build.
