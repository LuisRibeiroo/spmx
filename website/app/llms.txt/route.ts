import { SITE } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";

interface PointerMeta {
  section: "getting-started" | "guides" | "commands" | "concepts" | "optional";
  pointer: string;
}

/**
 * Context pointers authored with writing-for-agents principles:
 * - Front-load the leading word / branch trigger.
 * - One trigger per distinct branch.
 * - Cut identity the link title already carries.
 */
const POINTERS: Record<string, PointerMeta> = {
  "/docs": {
    section: "getting-started",
    pointer: "Overview — read when evaluating whether a project's SwiftPM / DerivedData setup fits spmx.",
  },
  "/docs/getting-started/installation": {
    section: "getting-started",
    pointer: "Install & PATH setup — read when installing via Homebrew or curl, or configuring ~/.zshrc / ~/.bashrc / fish.",
  },
  "/docs/getting-started/quick-start": {
    section: "getting-started",
    pointer: "End-to-end command sequence — read when bootstrapping a repo and its first worktree.",
  },
  "/docs/troubleshooting": {
    section: "getting-started",
    pointer: "Diagnostics — read when a new worktree still downloads packages, shims are bypassed, or Xcode GUI misses cache hits.",
  },
  "/docs/faq": {
    section: "getting-started",
    pointer: "Edge cases & constraints — read when checking OS/filesystem requirements, CocoaPods scope, or store safety.",
  },
  "/docs/getting-started/uninstall": {
    section: "getting-started",
    pointer: "Teardown — read when removing shims, PATH entries, or purging ~/.spmx/store.",
  },

  "/docs/guides/ai-agents": {
    section: "guides",
    pointer: "Parallel agent worktrees — read when spawning multiple coding agents across concurrent git worktrees.",
  },
  "/docs/guides/xcode-native": {
    section: "guides",
    pointer: "Native Xcode & SwiftPM — read when building with xcodebuild, swift build, or opening worktrees in Xcode.app.",
  },
  "/docs/guides/flutter-spm": {
    section: "guides",
    pointer: "Flutter iOS/macOS SwiftPM — read when hydrating FlutterGeneratedPluginSwiftPackage and build/<platform>/SourcePackages.",
  },
  "/docs/guides/cross-platform-spm": {
    section: "guides",
    pointer: "React Native, Expo, Capacitor & KMP — read when accelerating iOS/macOS builds that invoke xcodebuild under the hood.",
  },
  "/docs/guides/puro-fvm": {
    section: "guides",
    pointer: "Flutter version managers — read when chaining ~/.spmx/shims ahead of puro, fvm, asdf, or mise on PATH.",
  },
  "/docs/guides/ci": {
    section: "guides",
    pointer: "CI pipelines — read when caching SPMX_STORE_DIR across jobs or bypassing shims with SPMX_DISABLE=1.",
  },
  "/docs/guides/reproduce-the-benchmarks": {
    section: "guides",
    pointer: "Benchmark harness — read when running or verifying the hyperfine and APFS physical-disk measurements.",
  },

  "/docs/commands/setup": {
    section: "commands",
    pointer: "Shim & PATH installer — read for --no-modify-path flags and shell profile idempotency.",
  },
  "/docs/commands/doctor": {
    section: "commands",
    pointer: "Environment verifier — read when checking APFS support, PATH order, toolchain hashes, and LLVM CAS availability.",
  },
  "/docs/commands/hydrate": {
    section: "commands",
    pointer: "Worktree pre-warmer (alias: spmx install) — read for --force and explicit workspace/package path flags.",
  },
  "/docs/commands/harvest": {
    section: "commands",
    pointer: "Store populator — read when manually capturing resolved checkouts, artifacts, and prebuilts into ~/.spmx/store.",
  },
  "/docs/commands/migrate": {
    section: "commands",
    pointer: "Existing cache harvester — read when scanning ~/Library/Developer/Xcode/DerivedData (dry-run by default; --apply to execute).",
  },
  "/docs/commands/status": {
    section: "commands",
    pointer: "Project cache inspector — read when checking pin hit/miss rates and resolved DerivedData paths for the current directory.",
  },
  "/docs/commands/store": {
    section: "commands",
    pointer: "Store & CAS manager — read when listing cached packages, inspecting disk size, or running prune.",
  },
  "/docs/commands/hooks": {
    section: "commands",
    pointer: "Git post-checkout hook — read when enabling or disabling automatic hydration on git worktree add.",
  },
  "/docs/commands/derived-data-path": {
    section: "commands",
    pointer: "DerivedData hash resolver — read when scripting against Xcode's deterministic workspace build folder.",
  },
  "/docs/commands/uninstall": {
    section: "commands",
    pointer: "CLI & shim remover — read for --purge and hook cleanup flags.",
  },

  "/docs/concepts/global-store": {
    section: "concepts",
    pointer: "Content-addressable layout — read for ~/.spmx/store keying by package identity, revision, checksum, and toolchain hash.",
  },
  "/docs/concepts/apfs-clonefile": {
    section: "concepts",
    pointer: "Copy-on-write mechanics — read for why clonefile(2) beats cp -R and symlinks in Xcode and SwiftPM.",
  },
  "/docs/concepts/shims": {
    section: "concepts",
    pointer: "Shim execution lifecycle — read for how swift, xcodebuild, and flutter intercept, hydrate, inject CAS flags, and harvest.",
  },
  "/docs/concepts/llvm-compilation-cache": {
    section: "concepts",
    pointer: "Shared compiler cache — read for Xcode 16+ / Swift 6+ CAS flags and SPMX_NO_COMPILE_CACHE=1 override.",
  },
  "/docs/concepts/worktrees": {
    section: "concepts",
    pointer: "Worktree DerivedData isolation — read for why Xcode derives a fresh hash per worktree path and how spmx bridges it.",
  },

  "/docs/changelog": {
    section: "optional",
    pointer: "Version history — read when checking release tags and feature availability.",
  },
};

const SECTION_ORDER: ReadonlyArray<{
  key: PointerMeta["section"];
  heading: string;
}> = [
  { key: "getting-started", heading: "Getting Started & Diagnostics" },
  { key: "guides", heading: "Stack & Workflow Guides" },
  { key: "commands", heading: "CLI Command Reference" },
  { key: "concepts", heading: "Architecture & Internals" },
  { key: "optional", heading: "Optional" },
];

export function GET() {
  const pages = source.getPages();
  const grouped = new Map<PointerMeta["section"], string[]>();
  for (const s of SECTION_ORDER) {
    grouped.set(s.key, []);
  }

  // Sort pages by their order in POINTERS so high-priority entry points come first.
  const pointerKeys = Object.keys(POINTERS);
  const sortedPages = [...pages].sort((a, b) => {
    const ia = pointerKeys.indexOf(a.url);
    const ib = pointerKeys.indexOf(b.url);
    if (ia !== -1 && ib !== -1) return ia - ib;
    if (ia !== -1) return -1;
    if (ib !== -1) return 1;
    return a.url.localeCompare(b.url);
  });

  for (const page of sortedPages) {
    const meta = POINTERS[page.url];
    const section = meta?.section ?? "guides";
    const summary = meta?.pointer ?? page.data.description ?? "";
    grouped.get(section)?.push(`- [${page.data.title}](${SITE.url}${page.url}): ${summary}`.trimEnd());
  }

  grouped.get("optional")?.push(
    `- [Benchmarks](${SITE.url}/benchmarks): Methodology & hyperfine results — read when citing warm-store hydration speedups, physical APFS disk delta, or shim overhead.`,
    `- [Full documentation as one file](${SITE.url}/llms-full.txt): Single-file corpus — read when loading the entire spmx documentation into a large context window at once.`,
  );

  const lines: string[] = [
    `# ${SITE.name}`,
    "",
    `> ${SITE.description}`,
    "",
    "## Workflow Steps (In-File Quick Start)",
    "",
    "1. **Install & activate shims**: Run `curl -fsSL https://get.spmx.io | sh` (or `brew install LuisRibeiroo/tap/spmx && spmx setup`).",
    "   - **Done when**: `spmx doctor` exits `0` with APFS, shims, and `PATH` precedence passing.",
    "2. **Seed the global store from existing caches**: Run `spmx migrate --apply` once to harvest existing `DerivedData` checkouts, artifacts, and prebuilts into `~/.spmx/store`.",
    "   - **Done when**: `spmx store status` reports populated entries in `~/.spmx/store`.",
    "3. **Pre-warm parallel worktrees**: Run `spmx hooks enable --global` so every `git worktree add` auto-hydrates, or run `spmx hydrate` inside any worktree before building.",
    "   - **Done when**: `spmx status` in the worktree reports resolved pins linked from `~/.spmx/store`.",
    "",
    "## Core Invariants",
    "",
    "- **_Copy-on-write_ (`~/.spmx/store`)**: Packages are cloned into `DerivedData/SourcePackages` (or Flutter's `build/<platform>/SourcePackages`) via APFS `clonefile(2)`. Editing a file in one worktree allocates new blocks locally and leaves `~/.spmx/store` and sibling worktrees untouched.",
    "- **_Transparent shims_ (`~/.spmx/shims`)**: Intercept `swift`, `xcodebuild`, and `flutter` on `PATH`—hydrating before builds, enabling the shared `~/.spmx/compilation-cache` LLVM CAS cache, and harvesting newly resolved packages afterward. Set `SPMX_DISABLE=1` to bypass shims for one command, or `SPMX_NO_COMPILE_CACHE=1` to skip CAS flags.",
    "- **_Concurrency-safe_**: Store writes acquire per-package `flock` locks and stage atomically, so parallel coding agents building in separate `git worktree` checkouts never collide.",
    "",
  ];

  for (const { key, heading } of SECTION_ORDER) {
    const items = grouped.get(key) ?? [];
    if (items.length === 0) continue;
    lines.push(`## ${heading}`, "", ...items, "");
  }

  return new Response(lines.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
