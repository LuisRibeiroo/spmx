# Founder Brief: spmx

**Last updated:** 2026-11-17

## Strongest Asset
- Local benchmarks and published benchmarks at [spmx.io/benchmarks](https://spmx.io/benchmarks) proving millisecond APFS copy-on-write hydration and near-zero extra physical disk usage across cloned `SourcePackages` `[validated]`

## Core Five

1. **What it does (plain sentence):**
   A machine-wide store for Swift Package Manager (like Puro in Flutter or pnpm in Node) where every package version is downloaded and saved once in `~/.spmx/store` and shared via APFS copy-on-write across all your projects, branches, and worktrees. `[assumption]` (Built to solve the founder's own problem; pivoting primary pitch from worktrees-only to machine-wide cross-project deduplication.)

2. **Who it is for (ICP):**
   iOS, macOS, Flutter, and React Native developers on macOS who maintain two or more SwiftPM-based projects on the same machine (multi-app company engineers, mobile consultancies and agencies, indie developers with several apps, and engineers using multiple branches, worktrees, or AI coding agents). `[assumption]`

3. **What they use today instead, and why spmx:**
   They let Xcode create isolated `DerivedData/<App>-<Hash>/SourcePackages` directories per project, re-downloading and duplicating gigabytes of identical SDKs (`firebase-ios-sdk`, `stripe-ios`, `grpc-swift`, `swift-syntax`), and manually delete `DerivedData` when the SSD fills up. `spmx` links every project on the Mac to one global versioned store and shared LLVM CAS compilation cache automatically via transparent `PATH` shims, with zero workflow changes and per-project opt-out (`spmx unlink`). `[assumption]`

4. **Stage and traction:**
   - **Users:** 0 `[validated]`
   - **Retention:** N/A (0 users) `[validated]`
   - **Real users interviewed (non-friends):** 0 `[validated]`
   - **Origin:** Built to solve the founder's own problem. `[validated]`

## Positioning & Story (`positioning-and-story` + `value-prop-that-converts`)
- **Pain in the user's words:** "Every new iOS or Flutter project on my Mac downloads and compiles the same multi-gigabyte SDKs from scratch, and my SSD is choked with duplicate `DerivedData` folders." `[assumption]`
- **Villain (undeniable trend):** Modern iOS and macOS SDKs (`firebase-ios-sdk`, `stripe-ios`, `webrtc`, `grpc-swift`) and Swift macro dependencies (`swift-syntax`) have grown to several gigabytes per project, while Xcode still isolates `DerivedData/<Project>-<Hash>/SourcePackages` per project and worktree. Five projects sharing common dependencies mean five physical copies and five cold resolutions on the same SSD. `[validated]`
- **Who says no (exclusions):** Developers on Linux or Windows, projects that use only CocoaPods (`ios/Pods`) without Swift Package Manager, or developers with a single tiny project and no heavy dependencies. `[validated]`
- **Job to be done (`who-is-this-for`):** "When I clone, create, or build another project on my Mac that uses Firebase, Stripe, or dozens of Swift packages, I want to pull the exact package versions already on my machine in milliseconds, so I can build immediately without re-downloading or duplicating gigabytes on my SSD." `[assumption]`
- **Three-dimension Value Prop (`value-prop-that-converts`):**
  - **What it is:** A machine-wide, versioned APFS copy-on-write package store and LLVM compilation cache for Swift Package Manager (pnpm / Puro for Swift and Xcode).
  - **For whom:** macOS developers working across multiple iOS, macOS, Flutter, or React Native projects, branches, and worktrees.
  - **Why spmx over status quo:** Zero workflow changes after `spmx setup`. Identical `(package, version)` slices across Project A, Project B, and Project C live once in `~/.spmx/store`, clone in milliseconds via `clonefile()`, report exact disk space saved per project and globally, and allow per-project opt-out via `spmx unlink`.

## Product & Repo Facts (from codebase scan)
- **Version:** `v0.1.1` `[validated]`
- **Stack & Requirements:** Swift 6.0+ CLI, macOS 13+ on APFS, Xcode / Swift toolchain (`xcodebuild`, `swift`). `[validated]`
- **Supported Toolchains:** Swift CLI, `xcodebuild`, Xcode GUI, Flutter (`FlutterGeneratedPluginSwiftPackage`), and any toolchain invoking `xcodebuild` with SwiftPM (React Native, Expo, Capacitor, KMP). `[validated]`
- **Distribution:** `curl -fsSL https://get.spmx.io | sh`, Homebrew (`LuisRibeiroo/tap/spmx`), and build from source. `[validated]`
- **Web presence:** `spmx.io`, `spmx.io/docs`, `spmx.io/benchmarks`. `[validated]`
