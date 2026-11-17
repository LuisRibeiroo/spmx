# Analytics Specification for Agents

Authoritative workflow and reference for modifying analytics, interactive UI components, or CLI download routes in `spmx`.

## Workflow Steps

1. **Classify the target surface**:
   - `Sources/spmx/**`: **Telemetry-free**. Make zero network or analytics calls in the Swift CLI binary.
   - `website/**` (Browser): Client-side product and web analytics routed through the _first-party_ `/ingest` proxy.
   - `website/workers/get-spmx/**`, `scripts/install.sh`, `Formula/spmx.rb` (Edge distribution): Server-side _personless_ download counting at `get.spmx.io`.
   - **Done when**: The target file is mapped to `browser` or `edge`, and `Sources/spmx/**` remains untouched by telemetry.

2. **Align with the Canonical Event Catalog**:
   - Reuse existing event names (`noun_past_verb` in `snake_case`) and property keys (`method`, `version`, `arch`, `id_prefix`, `command`) from the catalog below so funnel joins between web intent (`install_command_copied`) and edge downloads (`binary_downloaded`) stay intact.
   - When adding a new event, add its row to both this file and `docs/analytics.md` in the same change.
   - **Done when**: Every emitted event name and property key matches the catalog and only scalar values (`string | number | boolean`) are passed as properties.

3. **Instrument as _non-blocking_ and _personless_**:
   - **Browser**: Import `captureEvent` from `@/lib/analytics` (or pass `eventName` and `eventProps` to `<CopyButton>`). Initialize `posthog-js` solely in `website/instrumentation-client.ts` with `api_host` set to `/ingest` in production (`NEXT_PUBLIC_POSTHOG_PROXY_PATH || "/ingest"`), `host` in `development`, and `ui_host` set to `https://us.posthog.com` (or `https://eu.posthog.com`).
   - **Edge (`get.spmx.io`)**: Dispatch PostHog `POST /i/v0/e/` inside `ctx.waitUntil(captureEdgeEvent(...))` with a `try/catch` that swallows errors, `distinct_id: crypto.randomUUID()`, and `$process_person_profile: false`. Count `binary_downloaded` only on `GET` requests for `spmx-macos-universal.tar.gz` (skip `HEAD` and `.sha256` requests).
   - **Installer (`scripts/install.sh` & `Formula/spmx.rb`)**: Point archive URLs at `https://get.spmx.io/releases/...`, send `-A "spmx-installer/1.0 (${OS}; ${ARCH})"` in `scripts/install.sh`, and keep `FALLBACK_URL` (`https://github.com/LuisRibeiroo/spmx/releases/...`) in `scripts/install.sh`.
   - **Done when**: Missing PostHog env vars leave production builds and downloads working with zero thrown errors, and `development` logs the missing `<VAR>` error on the client.

4. **Verify build, lint, types, and checks**:
   - Run `pnpm --dir website run typecheck`.
   - Run `pnpm --dir website exec eslint <modified-files>`.
   - Run `pnpm --dir website run build && pnpm --dir website run check`.
   - **Done when**: All four commands exit `0` and `website/scripts/check-hardcoded-numbers.mjs` reports zero hardcoded measurements.

---

## Core Concepts (Leading Words)

- **_Telemetry-free_ (`Sources/spmx/`)**: The compiled `spmx` binary makes zero network requests. All measurement happens on `spmx.io` (browser) or `get.spmx.io` (download edge).
- **_First-party_ (`website/functions/ingest/[[path]].ts`)**: Browser SDK traffic on `spmx.io` routes through `/ingest/*` on the same origin (`/ingest/static/*` and `/ingest/array/*` → `us-assets.i.posthog.com`; all other `/ingest/*` → `us.i.posthog.com`) with `X-Forwarded-For` set from `CF-Connecting-IP` and `ui_host: "https://us.posthog.com"`.
- **_Non-blocking_**: Analytics never stalls or fails user work. Browser calls guard on env presence inside `captureEvent()`; edge worker calls run inside `ctx.waitUntil()` with swallowed errors; `scripts/install.sh` falls back to GitHub Releases if `get.spmx.io` fails.
- **_Personless_**: Edge events (`install_script_downloaded`, `binary_downloaded`) set `$process_person_profile: false` with an ephemeral UUID `distinct_id`. Event properties across all surfaces carry technical metadata only—zero PII or file contents.

---

## Canonical Event Catalog

| Event | Surface | Source File | Required Properties | What It Is & Why We Have It |
| :--- | :--- | :--- | :--- | :--- |
| `install_script_downloaded` | Edge (`get.spmx.io`) | `website/workers/get-spmx/src/index.ts` | `method` (`"curl" \| "direct"`), `channel` (`"get.spmx.io"`), `$process_person_profile: false` | `GET /` or `GET /install.sh` served the shell installer. Measures top-of-funnel `curl \| sh` starts. |
| `binary_downloaded` | Edge (`get.spmx.io`) | `website/workers/get-spmx/src/index.ts` | `method` (`"homebrew" \| "curl" \| "direct"`), `version` (`"v0.1.1"` \| `"latest"`), `arch` (`"arm64" \| "x86_64" \| "unknown"`), `os`, `asset` (`"spmx-macos-universal.tar.gz"`), `$process_person_profile: false` | `GET` for the release archive before `302` redirect to GitHub Releases. Counts actual Homebrew (`Formula/spmx.rb`) and `curl` (`scripts/install.sh`) installations by version and CPU architecture. |
| `llms_txt_fetched` | Edge (`spmx.io`) | `website/functions/_middleware.ts` | `path`, `variant` (`"index" \| "full"`), `agent_category`, `agent_name`, `$process_person_profile: false` | `GET /llms.txt` or `GET /llms-full.txt`. Counts AI agents and LLM tools reading machine-readable docs. |
| `agent_site_access` | Edge (`spmx.io`) | `website/functions/_middleware.ts` | `path`, `agent_category` (`"ai_agent" \| "headless_browser" \| "http_client" \| "search_crawler"`), `agent_name`, `$process_person_profile: false` | `GET` on site pages with an automated/AI `User-Agent`. Counts non-JS and headless agent traffic at the Cloudflare Pages edge. |
| `agent_browser_session` | Browser (`spmx.io`) | `website/instrumentation-client.ts` | `agent_type` (`"ai_agent_ua" \| "headless_browser" \| "webdriver"`), `agent_signals`, `path`, `user_agent` | Fired once per session when a headless or automated browser initializes `posthog-js` (`opt_out_useragent_filter: true`). |
| `agent_browser_interaction` | Browser (`spmx.io`) | `website/lib/analytics.ts` | `interaction_event`, `agent_type`, `agent_signals`, `path`, plus underlying event props | Fired whenever a headless/automated browser triggers `captureEvent()` on any interactive UI element. |
| `install_tab_selected` | Browser (`spmx.io`) | `website/components/InstallTabs.tsx` | `method` (`"brew" \| "curl"`), `id_prefix` (`"hero" \| "cta"`) | User switched install method tab. Measures Homebrew vs `curl` preference. |
| `install_command_copied` | Browser (`spmx.io`) | `website/components/InstallTabs.tsx` | `label`, `method` (`"brew" \| "curl"`), `id_prefix` (`"hero" \| "cta"`), `command` | User copied the install command. Primary web conversion event; joins with `binary_downloaded` via `method`. |
| `command_copied` | Browser (`spmx.io`) | `website/components/CommandCard.tsx` | `label`, `command`, `title` | User copied a feature card CLI command. Measures feature-level interest. |
| `cta_clicked` | Browser (`spmx.io`) | `website/components/Button.tsx` | `label`, `href`, `variant` (`"primary" \| "secondary"`), `external` (`boolean`) | User clicked a CTA button (`Get started`, `View on GitHub`, `Read the docs`). Tracks landing-page funnel progression. |
| `docs_search_opened` | Browser (`spmx.io`) | `website/components/SearchPill.tsx` | *(none)* | User opened the Fumadocs search dialog. |
| `docs_markdown_copied` | Browser (`spmx.io`) | `website/components/CopyMarkdown.tsx` | `label` (`"Copy as Markdown"`) | User copied a docs page as Markdown for an LLM/agent. |
| `faq_opened` | Browser (`spmx.io`) | `website/components/Faq.tsx` | `question` | User expanded an FAQ `<details>` row. Surfaces top pre-install questions. |
| `theme_toggled` | Browser (`spmx.io`) | `website/components/ThemeToggle.tsx` | `to_theme` (`"dark" \| "light"`) | User toggled light/dark theme. |

---

## Configuration & Secrets Reference

- **Browser (`website/.env`, `website/.env.local`, `website/.env.example`, `.github/workflows/website-deploy.yml`)**:
  - `NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN`: PostHog project API key (`phc_...`).
  - `NEXT_PUBLIC_POSTHOG_HOST`: Regional ingestion origin (`https://us.i.posthog.com`).
  - `NEXT_PUBLIC_POSTHOG_PROXY_PATH`: First-party Pages Function proxy path (`/ingest`).
- **Edge Worker (`website/workers/get-spmx/.dev.vars`, `.dev.vars.example`)**:
  - `POSTHOG_PROJECT_TOKEN`: PostHog project API key (`phc_...`).
  - `POSTHOG_HOST`: Regional ingestion origin (`https://us.i.posthog.com`).
- **CSP (`website/public/_headers`)**:
  - Keep `'self'` and `https://*.posthog.com` in `script-src` and `connect-src`, and `worker-src 'self' blob: data:`.
