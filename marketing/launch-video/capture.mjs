// Frame-accurate capture of index.html through the Chrome DevTools Protocol. No npm dependencies.
// Usage: node capture.mjs <outDir> [fps]          -> every frame, f00000.png ...
//        STILLS="3,12.5" node capture.mjs <outDir> -> only those timestamps, still-3.00.png ...
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(process.argv[2] ?? "frames");
const fps = Number(process.argv[3] ?? 30);
const stills = process.env.STILLS ? process.env.STILLS.split(",").map(Number) : null;
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

mkdirSync(outDir, { recursive: true });
const profile = mkdtempSync(path.join(tmpdir(), "spmx-video-chrome-"));
const port = 9300 + Math.floor(Math.random() * 600);
const chrome = spawn(CHROME, [
  "--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--hide-scrollbars", "--no-first-run", "--no-default-browser-check", "--disable-gpu",
  "--window-size=1920,1080", "--force-device-scale-factor=1", "about:blank",
], { stdio: "ignore" });

const cleanup = () => { try { chrome.kill(); } catch {} try { rmSync(profile, { recursive: true, force: true }); } catch {} };
process.on("exit", cleanup);

let page;
for (let i = 0; i < 100 && !page; i++) {
  try { page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === "page"); } catch {}
  if (!page) await sleep(150);
}
if (!page) throw new Error("Chrome did not expose a page target");

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  const p = m.id && pending.get(m.id);
  if (!p) return;
  pending.delete(m.id);
  m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result);
};
const send = (method, params = {}) => new Promise((res, rej) => { const id = ++nextId; pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
await send("Page.navigate", { url: `${pathToFileURL(path.join(here, "index.html")).href}?capture=1` });
for (let i = 0; i < 200 && !(await evaluate("window.__ready === true").catch(() => false)); i++) await sleep(150);
const duration = await evaluate("window.DURATION");
if (!duration) throw new Error("page never became ready");

const shoot = async (t, file) => {
  await evaluate(`window.renderAt(${t.toFixed(5)}); true`);
  const { data } = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
  writeFileSync(path.join(outDir, file), Buffer.from(data, "base64"));
};

if (stills) {
  console.log(await evaluate("scenes.map((s) => `${s.el.id} ${s.start.toFixed(2)}-${s.end.toFixed(2)}`).join('  ')"));
  for (const t of stills) await shoot(t, `still-${t.toFixed(2)}.png`);
  console.log(`duration ${duration.toFixed(2)}s, wrote ${stills.length} stills`);
} else {
  const total = Math.ceil(duration * fps) + 1;
  const started = Date.now();
  for (let i = 0; i < total; i++) {
    await shoot(Math.min(i / fps, duration), `f${String(i).padStart(5, "0")}.png`);
    if (i % (fps * 5) === 0) console.log(`frame ${i}/${total} (${((Date.now() - started) / 1000).toFixed(0)}s)`);
  }
  console.log(`duration ${duration.toFixed(2)}s, wrote ${total} frames`);
}
ws.close();
cleanup();
process.exit(0);
