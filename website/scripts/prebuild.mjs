// Pre-build: copies shared assets and validates generated content.
//  - assets/icon.{svg,png}          -> public/   (single source of truth, never versioned twice)
//  - bench/results/latest.json      -> content/benchmarks/latest.json (validated with Zod; fails the build)
//  - GitHub release + CLI version   -> content/generated/meta.json, releases.json
import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, "..");
const root = resolve(site, "..");
const REPO = "LuisRibeiroo/pspm";

function fail(message) {
  console.error(`\n[prebuild] ERROR: ${message}\n`);
  process.exit(1);
}

mkdirSync(join(site, "public"), { recursive: true });
mkdirSync(join(site, "content", "generated"), { recursive: true });
mkdirSync(join(site, "content", "benchmarks"), { recursive: true });

// 1. Icon -------------------------------------------------------------------
for (const file of ["icon.svg", "icon.png"]) {
  const src = join(root, "assets", file);
  if (!existsSync(src)) fail(`missing ${src}`);
  cpSync(src, join(site, "public", file));
}

// 2. Benchmarks -------------------------------------------------------------
const { benchmarkSchema } = await import("../lib/benchmark-schema.ts");
const real = join(root, "bench", "results", "latest.json");
const sample = join(site, "content", "benchmarks", "sample.json");
let source = real;
if (!existsSync(real)) {
  if (process.env.PSPM_SITE_SAMPLE_BENCH === "1") {
    console.warn("[prebuild] bench/results/latest.json not found — using SAMPLE data (PSPM_SITE_SAMPLE_BENCH=1). Never ship this.");
    source = sample;
  } else {
    fail(
      "bench/results/latest.json not found.\n" +
        "  Run `make bench` first (see bench/README.md), or for a local layout preview only:\n" +
        "  PSPM_SITE_SAMPLE_BENCH=1 npm run build",
    );
  }
}
let parsed;
try {
  parsed = JSON.parse(readFileSync(source, "utf8"));
} catch (error) {
  fail(`${source} is not valid JSON: ${error.message}`);
}
const result = benchmarkSchema.safeParse(parsed);
if (!result.success) fail(`${source} failed schema validation:\n${result.error.message}`);
if (result.data.sample && process.env.PSPM_SITE_SAMPLE_BENCH !== "1") fail("sample benchmark data cannot be used without PSPM_SITE_SAMPLE_BENCH=1");
writeFileSync(join(site, "content", "benchmarks", "latest.json"), JSON.stringify(result.data, null, 2) + "\n");
mkdirSync(join(site, "public", "benchmarks"), { recursive: true });
writeFileSync(join(site, "public", "benchmarks", "latest.json"), JSON.stringify(result.data, null, 2) + "\n");
console.log(`[prebuild] benchmarks: ${source.replace(root + "/", "")} OK`);

// 3. Version + GitHub releases ---------------------------------------------
const cliSource = readFileSync(join(root, "Sources", "pspm", "PSPMCommand.swift"), "utf8");
const cliVersion = /version:\s*"([^"]+)"/.exec(cliSource)?.[1] ?? "0.0.0";
let releases = [];
let latest = null;
if (process.env.PSPM_SITE_OFFLINE !== "1") {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "pspm-site-build" },
      signal: AbortSignal.timeout(8000),
    });
    if (res.ok) {
      const data = await res.json();
      releases = data
        .filter((r) => !r.draft)
        .map((r) => ({
          tag: r.tag_name,
          name: r.name ?? r.tag_name,
          date: r.published_at,
          url: r.html_url,
          body: r.body ?? "",
          prerelease: r.prerelease,
          assets: (r.assets ?? []).map((a) => ({ name: a.name, size: a.size })),
        }));
      latest = releases.find((r) => !r.prerelease) ?? null;
    } else {
      console.warn(`[prebuild] GitHub releases: HTTP ${res.status} (no release yet?)`);
    }
  } catch (error) {
    console.warn(`[prebuild] GitHub releases unavailable: ${error.message}`);
  }
}
const tarball = latest?.assets.find((a) => a.name === "pspm-macos-universal.tar.gz");
const meta = {
  cliVersion,
  latestRelease: latest ? { tag: latest.tag, url: latest.url, date: latest.date } : null,
  tarballBytes: tarball?.size ?? null,
  generatedAt: new Date().toISOString(),
};
writeFileSync(join(site, "content", "generated", "meta.json"), JSON.stringify(meta, null, 2) + "\n");
writeFileSync(join(site, "content", "generated", "releases.json"), JSON.stringify(releases, null, 2) + "\n");
console.log(`[prebuild] cli ${cliVersion}; releases: ${releases.length}${latest ? `; latest ${latest.tag}` : ""}`);
