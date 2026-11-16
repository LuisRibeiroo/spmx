// CI guard (US-003): no performance number may be hardcoded in components, pages or MDX.
// Numbers must come from content/benchmarks/latest.json via lib/benchmarks.ts.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCAN = ["app", "components", "content/docs"];
// lib/benchmarks.ts holds the PRD targets (thresholds, not measurements); lib/og.tsx has no numbers of this kind.
const EXTENSIONS = new Set([".tsx", ".ts", ".mdx", ".md"]);
// A number glued to a performance unit: 12 ms, 3.4 s, 90%, 1.9 MB, 5x faster, 2 GB.
const PATTERN = /(?<![\w.#-])\d+(?:[.,]\d+)?\s?(?:ms|s|sec|seconds|min|%|KB|MB|GB|TB|x faster|× faster)(?![\w-])/g;

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) yield* walk(full);
    else if (EXTENSIONS.has(full.slice(full.lastIndexOf(".")))) yield full;
  }
}

let hits = 0;
for (const dir of SCAN) {
  for (const file of walk(join(root, dir))) {
    let inFence = false;
    readFileSync(file, "utf8").split("\n").forEach((line, i) => {
      if (/^\s*```/.test(line)) inFence = !inFence;
      // Sample CLI output in fenced blocks is documentation of format, not a claim; Tailwind sizes are not numbers either.
      if (inFence || /className=|class=|clamp\(|viewBox|<path|strokeWidth/.test(line)) return;
      for (const m of line.matchAll(PATTERN)) {
        hits++;
        console.error(`${relative(root, file)}:${i + 1}: hardcoded measurement "${m[0]}"`);
      }
    });
  }
}
if (hits) {
  console.error(`\n${hits} hardcoded measurement(s). Read numbers from lib/benchmarks.ts instead.`);
  process.exit(1);
}
console.log("No hardcoded performance numbers found.");
