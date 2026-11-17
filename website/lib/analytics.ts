import posthog from "posthog-js";

export type AnalyticsProperties = Record<string, string | number | boolean>;

export type AgentBrowserType = "human" | "ai_agent_ua" | "headless_browser" | "webdriver";

export interface AgentBrowserInfo {
  isAgent: boolean;
  isLighthouse: boolean;
  agentType: AgentBrowserType;
  signals: string[];
}

const AI_AGENT_UA_RE =
  /\b(?:ChatGPT-User|OAI-SearchBot|GPTBot|ClaudeBot|Claude-User|Claude-Web|PerplexityBot|Perplexity-User|Anthropic|Browserbase|Stagehand|BrowserUse|Steel|Lightpanda)\b/i;

const HEADLESS_UA_RE = /\b(?:HeadlessChrome|PhantomJS|SlimerJS|Playwright|Puppeteer|Cypress|Electron)\b/i;

const LIGHTHOUSE_UA_RE = /\b(?:Chrome-Lighthouse|Lighthouse|PageSpeed)\b/i;

const AUTOMATION_GLOBALS = [
  "__playwright__binding__",
  "__pwInitScripts",
  "__nightmare",
  "_phantom",
  "callPhantom",
  "_Selenium_IDE_Recorder",
  "__webdriver_evaluate",
  "__driver_evaluate",
  "domAutomation",
  "domAutomationController",
  "Cypress",
] as const;

let cachedAgentInfo: AgentBrowserInfo | null = null;

/** Detects whether the current browser context is driven by an automated/headless browser or AI agent. */
export function detectAgentBrowser(): AgentBrowserInfo {
  if (typeof window === "undefined" || typeof navigator === "undefined") {
    return { isAgent: false, isLighthouse: false, agentType: "human", signals: [] };
  }
  if (cachedAgentInfo) {
    return cachedAgentInfo;
  }

  const ua = navigator.userAgent ?? "";
  if (LIGHTHOUSE_UA_RE.test(ua)) {
    cachedAgentInfo = { isAgent: false, isLighthouse: true, agentType: "human", signals: ["lighthouse"] };
    return cachedAgentInfo;
  }

  const signals: string[] = [];
  const nav = navigator as Navigator & {
    userAgentData?: { brands?: Array<{ brand: string; version: string }> };
  };

  if (nav.webdriver === true) {
    signals.push("navigator.webdriver");
  }
  if (AI_AGENT_UA_RE.test(ua)) {
    signals.push("ai_agent_ua");
  }
  if (HEADLESS_UA_RE.test(ua)) {
    signals.push("headless_ua");
  }
  if (nav.userAgentData?.brands?.some((b) => /HeadlessChrome|Playwright|Chromium_Automation/i.test(b.brand))) {
    signals.push("ua_data_headless");
  }

  const win = window as unknown as Record<string, unknown>;
  for (const key of AUTOMATION_GLOBALS) {
    if (key in win && win[key] !== undefined) {
      signals.push(`global:${key}`);
    }
  }
  if (Object.keys(win).some((k) => k.startsWith("cdc_") || k.startsWith("$cdc_"))) {
    signals.push("global:cdc_chromedriver");
  }

  let agentType: AgentBrowserType = "human";
  if (signals.includes("ai_agent_ua")) {
    agentType = "ai_agent_ua";
  } else if (
    signals.includes("headless_ua") ||
    signals.includes("ua_data_headless") ||
    signals.some((s) => s.startsWith("global:"))
  ) {
    agentType = "headless_browser";
  } else if (signals.includes("navigator.webdriver")) {
    agentType = "webdriver";
  }

  cachedAgentInfo = {
    isAgent: signals.length > 0,
    isLighthouse: false,
    agentType,
    signals,
  };
  return cachedAgentInfo;
}

/** Sends a custom PostHog event when PostHog is configured; also records agent_browser_interaction when driven by a headless/agent browser. */
export function captureEvent(event: string, properties?: AnalyticsProperties): void {
  if (!process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN || !process.env.NEXT_PUBLIC_POSTHOG_HOST) {
    return;
  }
  const agent = detectAgentBrowser();
  if (agent.isLighthouse) {
    return;
  }

  posthog.capture(event, {
    ...properties,
    is_agent_browser: agent.isAgent,
    agent_type: agent.agentType,
  });

  if (agent.isAgent && event !== "agent_browser_session" && event !== "agent_browser_interaction") {
    posthog.capture("agent_browser_interaction", {
      interaction_event: event,
      agent_type: agent.agentType,
      agent_signals: agent.signals.join(","),
      path: typeof window !== "undefined" ? window.location.pathname : "",
      ...properties,
    });
  }
}
