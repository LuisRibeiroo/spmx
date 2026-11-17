// Full-page screenshots + mobile checks through headless Chrome (DevTools protocol, no extra dependencies).
//   node scripts/screenshots.mjs [baseUrl] [outDir]
// Reports horizontal overflow and links/buttons that wrap onto two lines at 320/375/414/768 px.
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const base = (process.argv[2] ?? "http://localhost:4310").replace(/\/$/, "");
const out = process.argv[3] ?? "screenshots";
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9400 + Math.floor(Math.random() * 400);
mkdirSync(out, { recursive: true });

const proc = spawn(chrome, [
  "--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "spmx-shot-"))}`,
  "--no-first-run", "--no-default-browser-check", "--hide-scrollbars", "--disable-gpu", "about:blank",
], { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function connect() {
  for (let i = 0; i < 50; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find((t) => t.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(200);
  }
  throw new Error("Chrome did not start");
}

const ws = new WebSocket(await connect());
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, (m) => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)));
  ws.send(JSON.stringify({ id: n, method, params }));
});
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;

const CHECK = `(() => {
  const overflow = document.documentElement.scrollWidth - window.innerWidth;
  const wrapped = [];
  for (const el of document.querySelectorAll("a, button, [data-chip], summary")) {
    if (!el.textContent.trim() || el.querySelector("p, div, h1, h2, h3, h4") || el.closest("p, li, [data-faq], .prose, td, th, dd, figcaption, h1, h2, h3, article")) continue;
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (!n.textContent.trim()) continue;
      const r = document.createRange(); r.selectNodeContents(n);
      const tops = new Set([...r.getClientRects()].filter((x) => x.width > 1).map((x) => Math.round(x.top)));
      if (tops.size > 1) { wrapped.push(n.textContent.trim().slice(0, 50)); break; }
    }
  }
  return { overflow, wrapped };
})()`;

const pages = [
  ["home", "/"],
  ["docs-quick-start", "/docs/getting-started/quick-start"],
  ["docs-global-store", "/docs/concepts/global-store"],
  ["docs-hydrate", "/docs/commands/hydrate"],
  ["benchmarks", "/benchmarks"],
];
const shots = [];
for (const [name, path] of pages) shots.push({ name: `${name}-dark-1280`, path, w: 1280, scheme: "dark", full: true });
shots.push({ name: "home-light-1280", path: "/", w: 1280, scheme: "light", full: true });
shots.push({ name: "benchmarks-light-1280", path: "/benchmarks", w: 1280, scheme: "light", full: true });
for (const w of [320, 375, 414, 768]) for (const [name, path] of [["home", "/"], ["benchmarks", "/benchmarks"], ["docs-global-store", "/docs/concepts/global-store"]])
  shots.push({ name: `${name}-dark-${w}`, path, w, scheme: "dark", full: w <= 414 ? name === "home" : false, mobile: w < 768 });

const report = [];
await send("Page.enable");
for (const s of shots) {
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: s.scheme }] });
  await send("Emulation.setDeviceMetricsOverride", { width: s.w, height: 900, deviceScaleFactor: 1, mobile: !!s.mobile });
  await send("Page.navigate", { url: base + s.path });
  await sleep(1800); // load + the single reveal / diagram-draw animations
  const check = await evaluate(CHECK);
  let clip;
  if (s.full) {
    const { cssContentSize } = await send("Page.getLayoutMetrics");
    clip = { x: 0, y: 0, width: s.w, height: Math.min(Math.ceil(cssContentSize.height), 14000), scale: 1 };
  }
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: !!clip, ...(clip ? { clip } : {}) });
  writeFileSync(join(out, `${s.name}.png`), Buffer.from(shot.data, "base64"));
  report.push({ name: s.name, ...check });
  console.log(`${s.name.padEnd(28)} overflow=${check.overflow} wrapped=${JSON.stringify(check.wrapped)}`);
}
ws.close(); proc.kill();
const bad = report.filter((r) => r.overflow > 0 || r.wrapped.length > 0);
console.log(bad.length ? `\n${bad.length} page(s) with layout problems` : "\nNo horizontal overflow, no wrapped links/buttons");
process.exit(bad.length ? 1 : 0);
