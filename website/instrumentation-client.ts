import posthog from "posthog-js";
import { detectAgentBrowser } from "@/lib/analytics";

const token = process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN;
const host = process.env.NEXT_PUBLIC_POSTHOG_HOST;
const proxyPath = process.env.NEXT_PUBLIC_POSTHOG_PROXY_PATH;
const AGENT_SESSION_STORAGE_KEY = "spmx-agent-session-tracked";

if (token && host) {
  const isDev = process.env.NODE_ENV === "development";
  const apiHost = isDev ? host : proxyPath || "/ingest";
  const uiHost = host.includes("eu.") ? "https://eu.posthog.com" : "https://us.posthog.com";
  const agent = detectAgentBrowser();

  if (!agent.isLighthouse) {
    posthog.init(token, {
      api_host: apiHost,
      ui_host: uiHost,
      defaults: "2026-08-30",
      // Allow headless browsers & AI agents through client-side filter; PostHog tags $browser_type = "bot" | "browser".
      opt_out_useragent_filter: true,
      capture_exceptions: true,
      debug: isDev,
      loaded(ph) {
        ph.register({
          is_agent_browser: agent.isAgent,
          agent_type: agent.agentType,
          ...(agent.signals.length > 0 ? { agent_signals: agent.signals.join(",") } : {}),
        });

        if (agent.isAgent && typeof window !== "undefined") {
          let alreadyTracked = false;
          try {
            alreadyTracked = sessionStorage.getItem(AGENT_SESSION_STORAGE_KEY) === "1";
            sessionStorage.setItem(AGENT_SESSION_STORAGE_KEY, "1");
          } catch {
            /* sessionStorage unavailable */
          }
          if (!alreadyTracked) {
            ph.capture("agent_browser_session", {
              agent_type: agent.agentType,
              agent_signals: agent.signals.join(","),
              path: window.location.pathname,
              user_agent: navigator.userAgent,
            });
          }
        }
      },
    });
  }
} else if (process.env.NODE_ENV === "development") {
  for (const [name, value] of [
    ["NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN", token],
    ["NEXT_PUBLIC_POSTHOG_HOST", host],
  ] as const) {
    if (!value) {
      console.error(
        `${name} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once ${name} is configured`,
      );
    }
  }
}
