const UPSTREAM_INSTALL_SCRIPT = "https://spmx.io/install.sh";
const GITHUB_RELEASES_BASE = "https://github.com/LuisRibeiroo/spmx/releases";
const ALLOWED_ASSETS = new Set([
  "spmx-macos-universal.tar.gz",
  "spmx-macos-universal.tar.gz.sha256",
]);

interface Env {
  POSTHOG_PROJECT_TOKEN?: string;
  POSTHOG_HOST?: string;
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}

type DownloadMethod = "homebrew" | "curl" | "direct";

function detectDownloadMeta(request: Request, url: URL): {
  method: DownloadMethod;
  arch: "arm64" | "x86_64" | "unknown";
  os: string;
  homebrewVersion?: string;
} {
  const ua = request.headers.get("user-agent") ?? "";
  const sourceParam = url.searchParams.get("source")?.toLowerCase();

  let method: DownloadMethod = "direct";
  if (sourceParam === "homebrew" || /\bHomebrew\b/i.test(ua)) {
    method = "homebrew";
  } else if (
    sourceParam === "curl" ||
    /\bspmx-installer\b/i.test(ua) ||
    /\b(?:curl|wget)\b/i.test(ua)
  ) {
    method = "curl";
  }

  let arch: "arm64" | "x86_64" | "unknown" = "unknown";
  if (/\b(?:arm64|aarch64)\b/i.test(ua)) {
    arch = "arm64";
  } else if (/\b(?:x86_64|amd64|Intel)\b/i.test(ua)) {
    arch = "x86_64";
  }

  const os = /\b(?:Darwin|Macintosh|Mac OS X)\b/i.test(ua) ? "Darwin" : "unknown";
  const brewMatch = /\bHomebrew\/([\d.]+)/i.exec(ua);

  return {
    method,
    arch,
    os,
    ...(brewMatch?.[1] ? { homebrewVersion: brewMatch[1] } : {}),
  };
}

async function captureEdgeEvent(
  env: Env,
  request: Request,
  event: string,
  properties: Record<string, string | boolean | undefined>,
): Promise<void> {
  const token = env.POSTHOG_PROJECT_TOKEN;
  const host = env.POSTHOG_HOST;
  if (!token || !host) {
    return;
  }

  try {
    const ip = request.headers.get("CF-Connecting-IP") ?? undefined;
    const country = (request as Request & { cf?: { country?: string } }).cf?.country;
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
          $lib: "spmx-get-worker",
          ...(ip ? { $ip: ip } : {}),
          ...(country ? { country } : {}),
          ...properties,
        },
      }),
    });
  } catch {
    // Analytics must never fail or stall downloads.
  }
}

function matchReleaseAsset(pathname: string): { version: string; asset: string; githubUrl: string } | null {
  // Matches:
  //   /releases/download/<tag>/<asset>
  //   /releases/latest/download/<asset>
  //   /download/<tag>/<asset>
  const tagged = /^\/(?:releases\/download|download)\/(v[\w.-]+)\/([^/]+)$/.exec(pathname);
  if (tagged) {
    const [, tag, asset] = tagged;
    if (tag && asset && ALLOWED_ASSETS.has(asset)) {
      return {
        version: tag,
        asset,
        githubUrl: `${GITHUB_RELEASES_BASE}/download/${tag}/${asset}`,
      };
    }
  }

  const latest = /^\/(?:releases\/latest\/download|download\/latest)\/([^/]+)$/.exec(pathname);
  if (latest) {
    const [, asset] = latest;
    if (asset && ALLOWED_ASSETS.has(asset)) {
      return {
        version: "latest",
        asset,
        githubUrl: `${GITHUB_RELEASES_BASE}/latest/download/${asset}`,
      };
    }
  }

  return null;
}

const worker = {
  async fetch(request: Request, env: Env = {}, ctx?: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.protocol === "http:") {
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed\n", {
        status: 405,
        headers: { Allow: "GET, HEAD" },
      });
    }

    // 1. Release archive / checksum download route (Homebrew & curl installer)
    const releaseTarget = matchReleaseAsset(url.pathname);
    if (releaseTarget) {
      if (request.method === "GET" && releaseTarget.asset === "spmx-macos-universal.tar.gz") {
        const meta = detectDownloadMeta(request, url);
        ctx?.waitUntil(
          captureEdgeEvent(env, request, "binary_downloaded", {
            method: meta.method,
            version: releaseTarget.version,
            asset: releaseTarget.asset,
            arch: meta.arch,
            os: meta.os,
            homebrew_version: meta.homebrewVersion,
            user_agent: request.headers.get("user-agent") ?? undefined,
          }),
        );
      }

      return Response.redirect(releaseTarget.githubUrl, 302);
    }

    // 2. Root / install.sh route (curl -fsSL https://get.spmx.io | sh)
    if (url.pathname !== "/" && url.pathname !== "/install.sh") {
      return new Response("Not Found\n", { status: 404 });
    }

    const upstream = await fetch(UPSTREAM_INSTALL_SCRIPT);

    if (!upstream.ok) {
      return new Response("Upstream installer unavailable\n", { status: 502 });
    }

    if (request.method === "GET") {
      const meta = detectDownloadMeta(request, url);
      ctx?.waitUntil(
        captureEdgeEvent(env, request, "install_script_downloaded", {
          method: meta.method,
          channel: "get.spmx.io",
          user_agent: request.headers.get("user-agent") ?? undefined,
        }),
      );
    }

    return new Response(request.method === "HEAD" ? null : upstream.body, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
      },
    });
  },
};

export default worker;
