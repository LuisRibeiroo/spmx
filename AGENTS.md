# Agent Instructions (`spmx`)

## Context Pointers

- **Analytics (`telemetry-free` CLI, `first-party` `/ingest` proxy, `personless` & `non-blocking` events)** → Read [`docs/analytics-llm.md`](docs/analytics-llm.md) when:
  1. Adding or editing interactive UI components in `website/components/` or `website/app/`.
  2. Modifying CLI distribution or release flows (`scripts/install.sh`, `Formula/spmx.rb`, `website/workers/get-spmx/`, `.github/workflows/release.yml`).
  3. Changing PostHog initialization, reverse proxy, CSP headers, or deploy environment variables (`website/instrumentation-client.ts`, `website/functions/ingest/`, `website/public/_headers`, `.github/workflows/website-deploy.yml`).
