# Analytics Guide (Human Reference)

## What It Is & Why We Have It

`spmx` uses **PostHog** (project `spmx`, US Cloud) across two surfaces—the documentation/marketing website (`spmx.io`) and the distribution edge worker (`get.spmx.io`)—to answer three questions without putting any telemetry inside the `spmx` CLI binary itself:

1. **Acquisition & Content Utility**: Which pages, guides, and benchmark results bring developers in, and where do they search or copy docs for AI coding agents?
2. **Evaluation Intent**: Do visitors prefer Homebrew (`brew install LuisRibeiroo/tap/spmx`) or the one-line installer (`curl -fsSL https://get.spmx.io | sh`), which CLI commands resonate on the landing page, and which FAQ questions do they expand before installing?
3. **Actual Installations & Upgrades**: How many real binary downloads happen via **Homebrew** vs **direct `curl` execution**, broken down by release version (`v0.1.1`, `latest`) and macOS architecture (`arm64` vs `x86_64`)?

> **Hard boundary:** The Swift CLI (`Sources/spmx/`) makes zero network calls of its own. All analytics live exclusively in the website (`website/`) and the edge installer worker (`website/workers/get-spmx/`).

---

## Architecture

### 1. Website (`spmx.io`) + First-Party Reverse Proxy (`/ingest`)
- **Client SDK Initialization**: [website/instrumentation-client.ts](../website/instrumentation-client.ts) initializes `posthog-js` once using Next.js 15.3+ client instrumentation (`defaults: "2026-08-30"`, `capture_exceptions: true`).
- **First-Party Reverse Proxy**:
  - In production builds, `api_host` points to `/ingest` (configured via `NEXT_PUBLIC_POSTHOG_PROXY_PATH=/ingest`) and `ui_host` points to `https://us.posthog.com`.
  - [website/functions/ingest/[[path]].ts](../website/functions/ingest/[[path]].ts) is a Cloudflare Pages Function deployed alongside the static export (`out/`). It routes `/ingest/static/*` and `/ingest/array/*` to `https://us-assets.i.posthog.com` (cached at the Cloudflare edge) and forwards all other `/ingest/*` requests to `https://us.i.posthog.com` while preserving client geolocation (`CF-Connecting-IP` → `X-Forwarded-For`) and stripping non-PostHog cookies/credentials.
  - In local development (`pnpm dev`), `instrumentation-client.ts` sends events directly to `NEXT_PUBLIC_POSTHOG_HOST` (`https://us.i.posthog.com`) so `next dev` works without running Wrangler locally.
- **Safe Event Helper**: [website/lib/analytics.ts](../website/lib/analytics.ts) exports `captureEvent(event, properties)`, which safely no-ops whenever PostHog environment variables are unset (such as in unconfigured CI runs).

### 2. Homebrew & Direct `curl` Download Counting (`get.spmx.io`)
Because GitHub Releases does not expose per-request telemetry or distinguish Homebrew from `curl`, download counting happens at the Cloudflare Worker edge in [website/workers/get-spmx/src/index.ts](../website/workers/get-spmx/src/index.ts):

1. **Direct `curl` Script Fetch (`GET https://get.spmx.io/`)**:
   - Serves `install.sh` and asynchronously dispatches `install_script_downloaded` (`method: "curl"`) inside `ctx.waitUntil()`.
2. **Release Tarball Download (`GET https://get.spmx.io/releases/download/<tag>/spmx-macos-universal.tar.gz` or `/releases/latest/download/...`)**:
   - **Homebrew (`method: "homebrew"`)**: [Formula/spmx.rb](../Formula/spmx.rb) points `url` at `https://get.spmx.io/releases/download/v#{version}/spmx-macos-universal.tar.gz`. When `brew install` runs, Homebrew sends `User-Agent: Homebrew/<ver> (Macintosh; <arch> Mac OS X <ver>) curl/<ver>`.
   - **Direct `curl` Installer (`method: "curl"`)**: [scripts/install.sh](../scripts/install.sh) downloads the archive from `https://get.spmx.io/releases/...` with `User-Agent: spmx-installer/1.0 (<OS>; <ARCH>)`. If `get.spmx.io` is ever unreachable, `install.sh` automatically falls back to `https://github.com/LuisRibeiroo/spmx/releases/...`.
   - **Zero-Latency Redirect**: The worker inspects the `User-Agent` (and optional `?source=` query), dispatches `binary_downloaded` in `ctx.waitUntil()`, and immediately returns `302 Found` to the canonical GitHub Release asset. Both `brew` and `install.sh` verify the exact SHA-256 checksum after download.

---

## Event Catalog

### Edge Distribution & Agent Access Events (Server-Side, Personless)

| Event | Trigger | Properties | What It Is & Why We Have It |
| :--- | :--- | :--- | :--- |
| `install_script_downloaded` | `GET /` or `GET /install.sh` on `get.spmx.io` | `method` (`"curl" \| "direct"`), `channel` (`"get.spmx.io"`), `country`, `user_agent`, `$process_person_profile: false` | Counts top-of-funnel executions of `curl -fsSL https://get.spmx.io \| sh`. Compare against `binary_downloaded` (`method: "curl"`) to verify installer completion rate. |
| `binary_downloaded` | `GET /releases/download/:tag/spmx-macos-universal.tar.gz` or `/releases/latest/download/spmx-macos-universal.tar.gz` | `method` (`"homebrew" \| "curl" \| "direct"`), `version` (`"v0.1.1"`, `"latest"`), `arch` (`"arm64" \| "x86_64" \| "unknown"`), `os` (`"Darwin" \| "unknown"`), `homebrew_version` (optional), `asset`, `country`, `user_agent`, `$process_person_profile: false` | Core adoption metric. Counts real binary downloads split by Homebrew vs `curl`, release version, and Apple Silicon (`arm64`) vs Intel (`x86_64`). Checksum (`.sha256`) and `HEAD` requests are excluded to prevent double-counting. |
| `llms_txt_fetched` | `GET /llms.txt` or `GET /llms-full.txt` on `spmx.io` ([_middleware.ts](../website/functions/_middleware.ts)) | `path`, `variant` (`"index" \| "full"`), `agent_category`, `agent_name`, `country`, `user_agent`, `$process_person_profile: false` | Counts AI coding agents and LLM tools reading `/llms.txt` or `/llms-full.txt` (even when they do not execute JavaScript). |
| `agent_site_access` | `GET` on `spmx.io` pages with an automated/AI `User-Agent` ([_middleware.ts](../website/functions/_middleware.ts)) | `path`, `agent_category` (`"ai_agent" \| "headless_browser" \| "http_client" \| "search_crawler"`), `agent_name`, `country`, `user_agent`, `$process_person_profile: false` | Server-side count of non-human visits (Claude, ChatGPT/OpenAI, Perplexity, Playwright/HeadlessChrome, `curl`, Python/Node HTTP clients) across docs and landing pages. |

### Website & Headless Browser Events (`spmx.io` — Client-Side)

> **Headless Browser Support**: `website/instrumentation-client.ts` sets `opt_out_useragent_filter: true` so `posthog-js` does not drop Playwright, Puppeteer, or `HeadlessChrome` sessions (tagging `$browser_type: "bot"` vs `"browser"`). Every client event is also enriched with super-properties `is_agent_browser` (`boolean`) and `agent_type` (`"human" \| "ai_agent_ua" \| "headless_browser" \| "webdriver"`).

| Event | Component | Properties | What It Is & Why We Have It |
| :--- | :--- | :--- | :--- |
| `agent_browser_session` | [instrumentation-client.ts](../website/instrumentation-client.ts) | `agent_type`, `agent_signals`, `path`, `user_agent` | Fired once per session when a headless or automated browser (`navigator.webdriver`, `HeadlessChrome`, Playwright/Puppeteer globals, AI agent UA) loads the site and executes JS. |
| `agent_browser_interaction` | [analytics.ts](../website/lib/analytics.ts) | `interaction_event`, `agent_type`, `agent_signals`, `path`, plus the underlying event's properties | Fired whenever a headless/automated browser interacts with any tracked UI component (copying commands, clicking CTAs, toggling tabs, copying docs as Markdown). |
| `install_tab_selected` | [InstallTabs.tsx](../website/components/InstallTabs.tsx) | `method` (`"brew" \| "curl"`), `id_prefix` (`"hero" \| "cta"`) | Visitor switched between Homebrew and `curl` tabs. Measures package manager preference on the site. |
| `install_command_copied` | [InstallTabs.tsx](../website/components/InstallTabs.tsx) | `label`, `method` (`"brew" \| "curl"`), `id_prefix` (`"hero" \| "cta"`), `command` | Visitor copied the install command from the hero or bottom CTA. Primary web-to-CLI conversion signal. |
| `command_copied` | [CommandCard.tsx](../website/components/CommandCard.tsx) | `label`, `command`, `title` | Visitor copied a CLI command from the feature bento grid (`spmx setup`, `spmx store status`, `spmx doctor`, etc.). Shows which features drive interest. |
| `cta_clicked` | [Button.tsx](../website/components/Button.tsx) | `label`, `href`, `variant` (`"primary" \| "secondary"`), `external` (`boolean`) | Visitor clicked a primary or secondary CTA button (`Get started`, `View on GitHub`, `Read the docs`). Tracks landing-page funnel progression. |
| `docs_search_opened` | [SearchPill.tsx](../website/components/SearchPill.tsx) | *(none)* | Visitor opened the documentation search modal. Measures docs navigation engagement. |
| `docs_markdown_copied` | [CopyMarkdown.tsx](../website/components/CopyMarkdown.tsx) | `label` (`"Copy as Markdown"`) | Visitor copied a documentation page as Markdown. Tracks AI coding agent / LLM context usage. |
| `faq_opened` | [Faq.tsx](../website/components/Faq.tsx) | `question` | Visitor expanded an FAQ `<details>` item. Highlights which technical questions or objections matter most. |
| `theme_toggled` | [ThemeToggle.tsx](../website/components/ThemeToggle.tsx) | `to_theme` (`"dark" \| "light"`) | Visitor manually switched between dark and light themes. |
| `$pageview` / `$pageleave` / `$web_vitals` | Automatic (`posthog-js`) | Standard PostHog web analytics properties | Automatic pageview, session attribution, and Core Web Vitals (LCP, INP, CLS, FCP) tracking. |

---

## Main Items to Follow

1. **Keep the `spmx` CLI binary telemetry-free**:
   - Never add PostHog or network calls inside `Sources/spmx/`. The CLI's "no telemetry" guarantee is a core product promise.
2. **Always keep analytics non-blocking and failure-safe**:
   - **Browser**: Call `captureEvent()` from `website/lib/analytics.ts`. Missing env vars must never break `next build` or Lighthouse CI in production builds, and must log a clear `console.error` in `next dev`.
   - **Edge Worker (`get.spmx.io`)**: Wrap all PostHog `fetch` calls in `ctx.waitUntil()` with `try/catch` so analytics adds 0 ms to download latency and never fails an install.
   - **Shell Installer (`scripts/install.sh`)**: Keep the `FALLBACK_URL` (`https://github.com/LuisRibeiroo/spmx/releases/...`) whenever downloading through `get.spmx.io`.
3. **Respect privacy & personless edge events**:
   - Edge worker events must set `$process_person_profile: false` with a fresh `crypto.randomUUID()` `distinct_id`.
   - Never send PII (emails, names, local file paths, or raw markdown content) in event properties.
4. **Maintain Reverse Proxy & CSP parity**:
   - When `api_host` uses `/ingest`, `ui_host` must remain `https://us.posthog.com` so the PostHog toolbar and app links resolve properly.
   - `/ingest/static/*` and `/ingest/array/*` must route to `us-assets.i.posthog.com`; all other `/ingest/*` paths route to `us.i.posthog.com`.
   - Keep `'self'` and `https://*.posthog.com` in `script-src` and `connect-src` (plus `worker-src 'self' blob: data:`) in [website/public/_headers](../website/public/_headers).
5. **Environment Variables & Secrets**:
   - **Website (`website/.env`, `website/.env.local`, GitHub Actions)**:
     - `NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN`
     - `NEXT_PUBLIC_POSTHOG_HOST` (`https://us.i.posthog.com`)
     - `NEXT_PUBLIC_POSTHOG_PROXY_PATH` (`/ingest`)
   - **Worker (`website/workers/get-spmx/.dev.vars`, Cloudflare Worker secrets)**:
     - `POSTHOG_PROJECT_TOKEN`
     - `POSTHOG_HOST` (`https://us.i.posthog.com`)
