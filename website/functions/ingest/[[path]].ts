interface Env {
  NEXT_PUBLIC_POSTHOG_HOST?: string;
  POSTHOG_HOST?: string;
}

interface PagesContext {
  request: Request;
  env: Env;
  waitUntil: (promise: Promise<unknown>) => void;
}

const DEFAULT_API_HOST = "us.i.posthog.com";

function resolveHosts(env: Env): { apiHost: string; assetHost: string } {
  const raw = env.POSTHOG_HOST || env.NEXT_PUBLIC_POSTHOG_HOST || `https://${DEFAULT_API_HOST}`;
  let apiHost = DEFAULT_API_HOST;
  try {
    apiHost = new URL(raw.startsWith("http") ? raw : `https://${raw}`).hostname;
  } catch {
    apiHost = DEFAULT_API_HOST;
  }
  const assetHost = apiHost.includes(".i.posthog.com")
    ? apiHost.replace(".i.posthog.com", "-assets.i.posthog.com")
    : "us-assets.i.posthog.com";
  return { apiHost, assetHost };
}

async function retrieveAsset(request: Request, assetHost: string, pathWithSearch: string, waitUntil: PagesContext["waitUntil"]): Promise<Response> {
  const cache = (caches as unknown as { default: Cache }).default;
  let response = await cache.match(request);
  if (!response) {
    response = await fetch(`https://${assetHost}${pathWithSearch}`);
    if (response.ok) {
      waitUntil(cache.put(request, response.clone()));
    }
  }
  return response;
}

async function forwardRequest(request: Request, apiHost: string, pathWithSearch: string): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") || "";
  const originHeaders = new Headers(request.headers);
  originHeaders.delete("cookie");
  originHeaders.delete("host");

  if (!/^Bearer ph[csx]_/.test(originHeaders.get("authorization") ?? "")) {
    originHeaders.delete("authorization");
  }
  if (ip) {
    originHeaders.set("X-Forwarded-For", ip);
  }

  const body =
    request.method !== "GET" && request.method !== "HEAD" ? await request.arrayBuffer() : null;

  const originRequest = new Request(`https://${apiHost}${pathWithSearch}`, {
    method: request.method,
    headers: originHeaders,
    body,
    redirect: request.redirect,
  });

  return fetch(originRequest);
}

export async function onRequest(context: PagesContext): Promise<Response> {
  const { request, env, waitUntil } = context;
  const { apiHost, assetHost } = resolveHosts(env);
  const url = new URL(request.url);
  const subPath = url.pathname.replace(/^\/ingest(?=\/|$)/, "") || "/";
  const pathWithSearch = `${subPath}${url.search}`;

  if (subPath.startsWith("/static/") || subPath.startsWith("/array/")) {
    return retrieveAsset(request, assetHost, pathWithSearch, waitUntil);
  }

  return forwardRequest(request, apiHost, pathWithSearch);
}
