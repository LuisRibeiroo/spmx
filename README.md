<p align="center">
  <img src="assets/icon.svg" alt="spmx icon" width="96" />
</p>

<h1 align="center">spmx</h1>

<p align="center">
  <strong>Performant Swift Package Manager</strong> — Global APFS copy-on-write store, LLVM CAS compilation cache, and transparent shims for Swift &amp; Flutter on macOS.
</p>

<p align="center">
  <a href="https://spmx.io">Website</a> ·
  <a href="https://spmx.io/docs">Documentation</a> ·
  <a href="https://spmx.io/benchmarks">Benchmarks</a> ·
  <a href="https://github.com/LuisRibeiroo/spmx/releases">Releases</a>
</p>

---

`spmx` eliminates redundant Swift Package Manager downloads, checkouts, and cold builds across repositories, branches, and `git worktree`s. It intercepts `swift`, `xcodebuild`, and `flutter` transparently via lightweight `PATH` shims, hydrates `DerivedData/SourcePackages` from a content-addressable global store using APFS `clonefile()` (zero-copy, instant), and enables native LLVM CAS compilation caching (`~/.spmx/compilation-cache`).

## Key Features

- **Global Content-Addressable Store (`~/.spmx/store`):** Deduplicates `checkouts`, `artifacts`, and `prebuilts` across all projects and worktrees, keyed by package identity, revision/checksum, and toolchain fingerprint.
- **Instant APFS CoW Hydration:** Clones cached packages into project `DerivedData/SourcePackages` (or Flutter's `build/<platform>/SourcePackages`) using `clonefile()` in milliseconds without duplicating disk blocks.
- **Transparent `PATH` Shims (`~/.spmx/shims`):** Wraps `swift`, `xcodebuild`, and `flutter` to pre-hydrate dependencies before resolution/build and harvest newly resolved packages afterward.
- **Native LLVM CAS Compilation Cache:** Configures Xcode/Swift compilation caching (`~/.spmx/compilation-cache`) automatically when supported by the installed toolchain.
- **Flutter SPM Support:** Detects and hydrates `FlutterGeneratedPluginSwiftPackage` and Flutter CLI `build/<platform>/SourcePackages` caches.
- **Opt-In Worktree Git Hooks:** Automatically pre-warms `SourcePackages` on `git worktree add` / `git checkout` via `spmx hooks enable`.
- **Safe Migration:** `spmx migrate` scans existing `DerivedData` and project directories (dry-run by default) to harvest and deduplicate existing caches into `~/.spmx/store`.

## Requirements

- **macOS 13+** on an **APFS** volume
- Xcode / Swift toolchain (`xcodebuild`, `swift`)

## Installation

### One-line installer (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/LuisRibeiroo/spmx/main/scripts/install.sh | sh
```

To skip modifying your shell RC file (`PATH`), pass `--no-modify-path`:

```sh
curl -fsSL https://raw.githubusercontent.com/LuisRibeiroo/spmx/main/scripts/install.sh | sh -s -- --no-modify-path
```

You can also pin a release tag with `SPMX_VERSION=v0.1.0`.

### Homebrew

```sh
brew install LuisRibeiroo/tap/spmx
```

Or install directly from the formula in this repository:

```sh
brew install --formula Formula/spmx.rb
```

### Build from source

Requires Swift 6.0+:

```sh
git clone https://github.com/LuisRibeiroo/spmx.git
cd spmx
swift build -c release
```

The compiled binary will be at `.build/release/spmx`.

## Quick Start

1. **Activate transparent shims and update `PATH`:**

   ```sh
   spmx setup
   ```

2. **Verify your environment (APFS, shims, toolchain, compilation cache):**

   ```sh
   spmx doctor
   ```

3. **Harvest existing `DerivedData` / Flutter caches into the global store:**

   ```sh
   # Dry-run preview (default)
   spmx migrate

   # Apply migration and deduplicate
   spmx migrate --apply
   ```

4. **(Optional) Enable automatic pre-warming on `git worktree add`:**

   ```sh
   spmx hooks enable --global
   ```

5. **Inspect store usage and current project status:**

   ```sh
   spmx status
   spmx store list
   ```

## CLI Commands

| Command | Description |
| :--- | :--- |
| `spmx setup` | Install `~/.spmx/shims` (`swift`, `xcodebuild`, `flutter`) and configure `PATH`. |
| `spmx doctor` | Check macOS/APFS support, shims, `PATH` precedence, toolchain, and CAS cache. |
| `spmx status` | Show cache hit/miss status and store linkage for the current project. |
| `spmx hydrate` (`spmx install`) | Pre-hydrate `SourcePackages` from `~/.spmx/store` using APFS `clonefile()`. |
| `spmx harvest` | Collect resolved `checkouts`, `artifacts`, and `prebuilts` into `~/.spmx/store`. |
| `spmx migrate` | Scan `DerivedData` and directories to harvest and deduplicate existing caches. |
| `spmx store` | Inspect, list, and prune `~/.spmx/store` and `~/.spmx/compilation-cache`. |
| `spmx hooks` | Manage opt-in git `post-checkout` hooks (`enable`, `disable`, `status`). |
| `spmx derived-data-path` | Print the deterministic `DerivedData` path for the current project. |
| `spmx uninstall` | Remove `spmx` shims, hooks, and optionally the store/binary. |

Full command reference and architecture guides are available at **[spmx.io/docs](https://spmx.io/docs)**.

## Benchmarks

Reproducible benchmarks using `hyperfine` live in [`bench/`](bench/README.md), and published results are available at **[spmx.io/benchmarks](https://spmx.io/benchmarks)**.

```sh
# Full benchmark suite
make bench

# Quick smoke benchmark (S3 + S5)
make bench-quick
```

## Development

```sh
# Build
swift build

# Run unit tests
swift test

# Run website locally (http://localhost:3000)
make site-dev

# Production build of the website
make site
```

## Links

- **Official Website:** [https://spmx.io](https://spmx.io)
- **Documentation:** [https://spmx.io/docs](https://spmx.io/docs)
- **Benchmarks:** [https://spmx.io/benchmarks](https://spmx.io/benchmarks)
- **Repository:** [https://github.com/LuisRibeiroo/spmx](https://github.com/LuisRibeiroo/spmx)

## License

MIT — see [`Formula/spmx.rb`](Formula/spmx.rb) for package metadata.
