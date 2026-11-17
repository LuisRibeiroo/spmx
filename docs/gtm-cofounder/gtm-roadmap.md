# GTM Roadmap: spmx

**Last updated:** 2026-11-17

## Diagnosis
Framing `spmx` around `git worktree` alone artificially restricts your addressable audience to a niche workflow, when the underlying APFS copy-on-write store can deduplicate identical `(package, version)` slices across every Swift, Xcode, Flutter, and React Native project on a developer's Mac (just like Puro in Flutter or pnpm in Node).

## Now
- **Execute the Machine-Wide Store Pivot across CLI, README, and Website** (`positioning-and-story`, `value-prop-that-converts`, `the-homepage`, `founder-led-content`, `time-to-first-value`): Close the 5 cross-project engine gaps (partial hydration, `repositories/` bare git cache, dirty-checkout harvest guard, versioned store inspection with per-project and global disk savings, and `spmx link` / `spmx unlink`) and rewrite the README and `spmx.io` around machine-wide cross-project deduplication (`Project A`, `Project B`, `Project C`).
  - **Done when:** `tasks/prd-machine-wide-store.md` is implemented, `spmx status` and `spmx store list` show versioned slices and disk savings per project and globally, and `README.md` + `spmx.io` lead with the machine-wide store pitch.

## Next
- **Talk to 5 to 10 iOS, macOS, and Flutter developers with multiple projects on their Mac** (`talk-to-users`): Validate the machine-wide `DerivedData` / `SourcePackages` duplication pain, watch them run `spmx setup` + `spmx link` (or `spmx migrate`) on their machine, and record real GB-saved numbers and quotes.
- **Turn real user disk-savings numbers into attributed proof** (`value-prop-that-converts`): Add real developer quotes and multi-project disk savings alongside the existing [spmx.io/benchmarks](https://spmx.io/benchmarks) numbers.

## Later (parked on purpose)
- **Get the first 50 users and launch** (`first-50-users`, `launch-it`): Launch on Show HN, r/swift, r/iOSProgramming, and r/FlutterDev once the machine-wide store UX and homepage pivot are live.
- **Pricing and monetization** (`pricing`, `market-to-devs-sell-to-buyers`): Keep 100% free and open-source while building developer adoption.
- **Metrics and analytics** (`know-if-its-working`): Track activation (`time-to-first-value`) once developer traffic starts arriving.

## Log
- **2026-11-17:** Completed initial `founder-brief.md` and `gtm-roadmap.md`.
- **2026-11-17:** Pivoted positioning and GTM roadmap from worktree-only sharing to machine-wide versioned store sharing across all projects on the Mac (`Project A`, `Project B`, `Project C`), aligned with Puro/pnpm mental model.
