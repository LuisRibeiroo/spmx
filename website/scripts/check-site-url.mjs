// Post-build guard: a production export must not contain a localhost origin
// (canonical, sitemap, robots, llms.txt, Open Graph and JSON-LD all derive from SITE_URL).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const out = resolve(dirname(fileURLToPath(import.meta.url)), "..", "out");
const siteUrl = process.env.SITE_URL ?? "";

if (/^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?\/?$/.test(siteUrl)) {
  console.log("[check-site-url] SITE_URL is a local origin: skipping (never deploy this build).");
  process.exit(0);
}

const TEXT = /\.(html|txt|xml|json|js|css|map)$/;
const bad = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path);
    else if (TEXT.test(name) && /https?:\/\/localhost[:/"'\s]/.test(readFileSync(path, "utf8"))) bad.push(path.replace(out + "/", ""));
  }
})(out);

if (bad.length > 0) {
  console.error(`\n[check-site-url] ERROR: localhost origin found in ${bad.length} file(s):\n  ${bad.slice(0, 15).join("\n  ")}\n`);
  process.exit(1);
}
console.log("[check-site-url] no localhost origins in out/ OK");
