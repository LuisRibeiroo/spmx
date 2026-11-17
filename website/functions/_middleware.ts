interface Env {
  POSTHOG_PROJECT_TOKEN?: string;
  NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN?: string;
  POSTHOG_HOST?: string;
  NEXT_PUBLIC_POSTHOG_HOST?: string;
}

interface PagesContext {
  request: Request;
  env: Env;
  next: () => Promise<Response>;
  waitUntil: (promise: Promise<unknown>) => void;
}

type EdgeAgentCategory = "ai_agent" | "headless_browser" | "http_client" | "search_crawler" | "unknown";

const STATIC_ASSET_EXT_RE = /\.(?:js|css|png|svg|ico|woff2?|ttf|map|webmanifest)$/i;
const LIGHTHOUSE_RE = /\b(?:Chrome-Lighthouse|Lighthouse|PageSpeed)\b/i;

const AGENT_PATTERNS: ReadonlyArray<{
  pattern: RegExp;
  name: string;
  category: EdgeAgentCategory;
}> = [
  { pattern: /\b(?:ClaudeBot|Claude-User|Claude-Web|Anthropic)\b/i, name: "Claude", category: "ai_agent" },
  { pattern: /\b(?:ChatGPT-User|OAI-SearchBot|GPTBot|OpenAI)\b/i, name: "OpenAI / ChatGPT", category: "ai_agent" },
  { pattern: /\b(?:PerplexityBot|Perplexity-User)\b/i, name: "Perplexity", category: "ai_agent" },
  { pattern: /\b(?:Google-Extended|GoogleOther)\b/i, name: "Google AI", category: "ai_agent" },
  { pattern: /\bApplebot-Extended\b/i, name: "Apple AI", category: "ai_agent" },
  { pattern: /\b(?:Cursor|Antigravity|Windsurf|Codeium|Copilot)\b/i, name: "Coding Agent", category: "ai_agent" },
  { pattern: /\b(?:Browserbase|Stagehand|BrowserUse|Steel|Lightpanda)\b/i, name: "AI Browser Agent", category: "headless_browser" },
  { pattern: /\b(?:HeadlessChrome|Playwright|Puppeteer|PhantomJS|SlimerJS|Cypress)\b/i, name: "Headless Browser", category: "headless_browser" },
  { pattern: /\b(?:Googlebot|Bingbot|DuckDuckBot|YandexBot|Baiduspider)\b/i, name: "Search Crawler", category: "search_crawler" },
  { pattern: /\b(?:curl|wget|HTTPie)\b/i, name: "CLI HTTP Client", category: "http_client" },
  { pattern: /\b(?:python-requests|httpx|aiohttp|urllib|node-fetch|undici|axios|got|Go-http-client|okhttp)\b/i, name: "Programmatic HTTP Client", category: "http_client" },
];

function classifyUserAgent(ua: string): { isAutomated: boolean; name: string; category: EdgeAgentCategory } {
  for (const entry of AGENT_PATTERNS) {
    if (entry.pattern.test(ua)) {
      return { isAutomated: true, name: entry.name, category: entry.category };
    }
  }
  return { isAutomated: false, name: "unknown", category: "unknown" };
}

async function sendPostHogEdgeEvent(
  env: Env,
  request: Request,
  event: string,
  properties: Record<string, string | boolean | undefined>,
): Promise<void> {
  const token = env.POSTHOG_PROJECT_TOKEN || env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN;
  const host = env.POSTHOG_HOST || env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com";
  if (!token) {
    return;
  }

  try {
    const ip = request.headers.get("CF-Connecting-IP") ?? undefined;
    const country =
      request.headers.get("CF-IPCountry") ??
      (request as Request & { cf?: { country?: string } }).cf?.country;
    const endpoint = `${host.replace(/\/$/, "")}/i/v0/e/`;

    await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: token,
        event,
        distinct_id: crypto.randomUUID(),
        properties: {
          $process_person_profile: false,
          $lib: "spmx-pages-edge",
          ...(ip ? { $ip: ip } : {}),
          ...(country ? { country } : {}),
          ...properties,
        },
      }),
    });
  } catch {
    // Non-blocking: never fail or delay page serving.
  }
}

export async function onRequest(context: PagesContext): Promise<Response> {
  const { request, env, next, waitUntil } = context;
  const url = new URL(request.url);

  // Skip reverse proxy and internal build assets
  if (
    url.pathname.startsWith("/ingest") ||
    url.pathname.startsWith("/_next/") ||
    STATIC_ASSET_EXT_RE.test(url.pathname)
  ) {
    return next();
  }

  const response = await next();

  if (request.method === "GET") {
    const ua = request.headers.get("user-agent") ?? "";
    if (!LIGHTHOUSE_RE.test(ua)) {
      const agent = classifyUserAgent(ua);

      if (url.pathname === "/llms.txt" || url.pathname === "/llms-full.txt") {
        waitUntil(
          sendPostHogEdgeEvent(env, request, "llms_txt_fetched", {
            path: url.pathname,
            variant: url.pathname === "/llms-full.txt" ? "full" : "index",
            agent_category: agent.category,
            agent_name: agent.name,
            user_agent: ua || undefined,
          }),
        );
      } else if (agent.isAutomated) {
        waitUntil(
          sendPostHogEdgeEvent(env, request, "agent_site_access", {
            path: url.pathname,
            agent_category: agent.category,
            agent_name: agent.name,
            user_agent: ua || undefined,
          }),
        );
      }
    }
  }

  return response;
}
