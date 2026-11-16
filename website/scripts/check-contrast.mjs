// Verifies WCAG AA contrast of the design tokens in app/globals.css, in dark and light.
// Text >= 4.5:1, focus ring / UI boundary >= 3:1. Exits non-zero on failure.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "app", "globals.css"), "utf8");

function block(selector) {
  const start = css.indexOf(selector);
  const open = css.indexOf("{", start);
  return css.slice(open + 1, css.indexOf("\n}", open));
}
function tokens(body) {
  const out = {};
  for (const m of body.matchAll(/--color-([\w-]+):\s*oklch\(([\d.]+)\s+([\d.]+)\s+([\d.]+)\)/g)) out[m[1]] = [+m[2], +m[3], +m[4]];
  return out;
}

function oklchToLinear([L, C, H]) {
  const h = (H * Math.PI) / 180, a = C * Math.cos(h), b = C * Math.sin(h);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ].map((v) => Math.min(1, Math.max(0, v)));
}
const luminance = (c) => { const [r, g, b] = oklchToLinear(c); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const ratio = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

const light = tokens(block("@theme {"));
const dark = { ...light, ...tokens(block(".dark {")) };

const CHECKS = [
  // [foreground, background, min, label]
  ["ink", "paper", 4.5, "body text"],
  ["ink", "paper-2", 4.5, "text on code surface"],
  ["ink-muted", "paper", 4.5, "secondary text"],
  ["ink-muted", "paper-2", 4.5, "secondary text on code surface"],
  ["ink-muted", "surface-warm", 4.5, "secondary text on warm band"],
  ["accent-text", "paper", 4.5, "links"],
  ["accent-text", "surface-warm", 4.5, "links on warm band"],
  ["accent-text", "paper-2", 4.5, "links on code surface"],
  ["on-accent", "accent", 4.5, "primary button label"],
  ["ok", "paper-2", 4.5, "success text"],
  ["warn", "paper", 4.5, "warning text"],
  ["err", "paper", 4.5, "error text"],
  ["accent-text", "paper", 3, "focus ring"],
  ["line-strong", "paper", 3, "input / chip boundary"],
];

let failed = 0;
for (const [name, set] of [["dark", dark], ["light", light]]) {
  for (const [fg, bg, min, label] of CHECKS) {
    const r = ratio(set[fg], set[bg]);
    const ok = r >= min;
    if (!ok) failed++;
    console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(5)} ${label.padEnd(34)} ${fg} on ${bg}: ${r.toFixed(2)} (min ${min})`);
  }
}
if (failed) {
  console.error(`\n${failed} contrast check(s) failed`);
  process.exit(1);
}
console.log("\nAll contrast checks passed");
