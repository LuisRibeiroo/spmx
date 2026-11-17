<p align="center">
  <img src="assets/icon.svg" alt="spmx icon" width="96" />
</p>

<h1 align="center">spmx</h1>

<p align="center">
  <strong>One global Swift Package Manager store for your entire Mac.</strong>
  <br />
  Like Puro for Flutter or pnpm for Node.js, shared via APFS copy-on-write across every project, branch, and worktree.
</p>

<p align="center">
  <a href="https://spmx.io">Website</a> ·
  <a href="https://spmx.io/docs">Documentation</a> ·
  <a href="https://spmx.io/benchmarks">Benchmarks</a> ·
  <a href="https://github.com/LuisRibeiroo/spmx/releases">Releases</a>
</p>

---

Every Xcode and SwiftPM project on your Mac creates its own isolated `DerivedData/<App>-<Hash>/SourcePackages` folder. Open three apps, two client branches, or a few Git worktrees, and you download and store the same multi-gigabyte SDKs (`Firebase`, `Stripe`, `gRPC`, `SwiftSyntax`) over and over again.

`spmx` gives your Mac one shared `~/.spmx/store` (plus one shared LLVM CAS compilation cache at `~/.spmx/compilation-cache`). It intercepts `swift`, `xcodebuild`, and `flutter` transparently via `PATH` shims, clones matching package versions into `SourcePackages` in milliseconds using APFS `clonefile()`, and harvests newly resolved packages back into the global store.

## How Cross-Project Deduplication Works

`spmx` stores each `(package, version)` slice once in `~/.spmx/store`, alongside bare Git repositories in `~/.spmx/store/repositories/`. Different projects keep their exact `Package.resolved` versions without forcing upgrades:

- **`c-137`** (`~/dimension/c-137`) uses `firebase 1.0.0`, `stripe 3.4.5`, `xyz 4.0.0`
- **`prime`** (`~/dimension/prime`) uses `xyz 4.0.0`, `abc 1.0.0`
- **`c-131`** (`~/dimension/c-131`) uses `firebase 1.0.1`, `stripe 3.4.5`

`~/.spmx/store` keeps a single physical copy of each slice:

```text
~/.spmx/store/
├── checkouts/
│   ├── firebase-ios-sdk-<rev-1.0.0>/   # used by c-137
│   ├── firebase-ios-sdk-<rev-1.0.1>/   # used by c-131
│   ├── stripe-ios-<rev-3.4.5>/         # cloned to c-137 & c-131 via clonefile()
│   ├── xyz-<rev-4.0.0>/                # cloned to c-137 & prime via clonefile()
│   └── abc-<rev-1.0.0>/                # used by prime
└── repositories/
    ├── firebase-ios-sdk/               # bare Git history shared between 1.0.0 & 1.0.1
    ├── stripe-ios/
    ├── xyz/
    └── abc/
```

When you open `prime`, `xyz 4.0.0` is cloned locally in milliseconds and SwiftPM resolves only `abc 1.0.0`. When `c-131` moves from `firebase 1.0.0` to `1.0.1`, the shared bare repository lets SwiftPM fetch only the delta commits.

## Quick Start (< 2 minutes)

### 1. Install

```sh
curl -fsSL https://get.spmx.io | sh
```

Or via Homebrew:

```sh
brew install LuisRibeiroo/tap/spmx
```

### 2. Activate global shims

```sh
spmx setup
spmx doctor
```

### 3. Link existing projects on your Mac

Scan your machine (or a specific folder) to harvest existing `DerivedData`, `.build`, and Flutter caches and replace duplicates with APFS clones. `spmx link` shows the full plan and estimated disk savings and asks for confirmation before touching disk:

```sh
# Scan your Mac and review estimated GB saved before confirming
spmx link

# Or target a specific workspace folder
spmx link ~/dimension
```

## Full Control: `link`, `unlink`, and Space Savings

All projects invoked through `swift`, `xcodebuild`, or `flutter` use the global store by default.

- **Isolate a project (`spmx unlink`):** Exclude any project so it uses only Xcode's or SwiftPM's local cache. Shims, Git hooks, and machine scans skip it cleanly:

  ```sh
  spmx unlink ~/dimension/c-131
  ```

- **Re-link anytime:**

  ```sh
  spmx link ~/dimension/c-131
  ```

- **Inspect versions and disk saved per project and across your Mac:**

  ```sh
  # Per-project link status, semantic versions, and estimated disk saved
  spmx status

  # Every (package, version) in ~/.spmx/store and which projects use it
  spmx store list

  # Per-project breakdown and total GB saved across your Mac
  spmx store status
  ```

## Supported Frameworks & Toolchains

- **Swift & Xcode:** Native `swift` CLI, `xcodebuild`, and Xcode GUI (via `spmx hooks enable --global`).
- **Flutter:** Dedicated handling for `FlutterGeneratedPluginSwiftPackage`, `build/<platform>/SourcePackages`, and cross-project pre-warming from `.flutter-plugins-dependencies`.
- **React Native & Expo:** Accelerated automatically via the `xcodebuild` shim whenever the iOS/macOS app uses Swift Package Manager.
- **Capacitor / Ionic & Kotlin Multiplatform (KMP):** Any toolchain that invokes `xcodebuild` with SwiftPM shares `~/.spmx/store` and `~/.spmx/compilation-cache`.

> **Scope note:** `spmx` manages **Swift Package Manager** (`SourcePackages`) and Swift/Clang LLVM CAS compilation caches. It does not manage CocoaPods (`ios/Pods`) or `node_modules`.

## Requirements

- **macOS 13+** on an **APFS** volume
- Xcode / Swift toolchain (`xcodebuild`, `swift`)

## CLI Commands

| Command | Description |
| :--- | :--- |
| `spmx setup` | Install `~/.spmx/shims` (`swift`, `xcodebuild`, `flutter`) and configure `PATH`. |
| `spmx link [path]` | Scan a path or the whole Mac, show estimated savings, and link/deduplicate after confirmation. |
| `spmx unlink [path]` | Exclude a project from the global store so shims pass through to its local cache. |
| `spmx status` | Show project link state, package semantic versions, and estimated disk saved in this project. |
| `spmx store list` | List every `(package, version)` in `~/.spmx/store` and its linked projects. |
| `spmx store status` | Show store entries, per-project breakdown, and total disk saved across the machine. |
| `spmx store prune` | Remove missing projects, unreferenced store entries, and old compilation cache files. |
| `spmx doctor` | Check macOS/APFS support, shims, `PATH` precedence, toolchain, and CAS cache. |
| `spmx hydrate` (`spmx install`) | Pre-hydrate `SourcePackages` from `~/.spmx/store` using APFS `clonefile()`. |
| `spmx harvest` | Collect clean `checkouts`, `repositories`, `artifacts`, and `prebuilts` into `~/.spmx/store`. |
| `spmx migrate [path]` | Alias for scanning and migrating existing caches into `~/.spmx/store`. |
| `spmx hooks` | Manage opt-in Git `post-checkout` hooks (`enable`, `disable`, `status`). |
| `spmx derived-data-path` | Print the deterministic `DerivedData` path for the current project. |
| `spmx uninstall` | Remove `spmx` shims, hooks, and optionally the store/binary. |

Full documentation is available at **[spmx.io/docs](https://spmx.io/docs)**.

## Benchmarks

Reproducible benchmarks using `hyperfine` live in [`bench/`](bench/README.md), and published results are available at **[spmx.io/benchmarks](https://spmx.io/benchmarks)**.

```sh
# Full benchmark suite
make bench

# Quick smoke benchmark (S3 + S5)
make bench-quick
```

## License

MIT
