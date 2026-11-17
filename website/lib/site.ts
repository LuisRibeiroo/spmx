import { REPO } from "./repo";

/**
 * Canonical origin of the deployed site. There is no safe default for a production build: a wrong origin
 * ends up in canonical tags, the sitemap, robots.txt, llms.txt, Open Graph URLs and JSON-LD.
 * Only server/build code reads SITE_URL (it is not NEXT_PUBLIC_), so the guard skips the browser bundle.
 */
function resolveSiteUrl(): string {
  const raw = process.env.SITE_URL?.trim();
  if (raw) {
    let parsed: URL;
    try {
      parsed = new URL(raw);
    } catch {
      throw new Error(`SITE_URL is not a valid absolute URL: "${raw}"`);
    }
    return parsed.origin;
  }
  if (process.env.NODE_ENV === "production" && typeof window === "undefined") {
    throw new Error(
      "SITE_URL is not set. Set it to the public origin of the site, e.g. SITE_URL=https://example.com pnpm run build " +
        "(use SITE_URL=http://localhost:3000 only for a local build you will not deploy).",
    );
  }
  return "http://localhost:3000";
}

export const SITE = {
  name: "spmx",
  tagline: "One package store for every Swift project on your Mac.",
  description:
    "spmx shares one APFS copy-on-write package store and LLVM CAS build cache across every Swift, Xcode, Flutter, React Native, Expo, Capacitor and KMP project on your Mac.",
  /** <= 155 characters so search results do not truncate it. */
  metaDescription:
    "One APFS copy-on-write SwiftPM store and build cache for every Swift, Xcode, Flutter, React Native and KMP project on your Mac.",
  // Domain is still an open question (tasks/prd-site.md §10.1). Set SITE_URL at build time.
  url: resolveSiteUrl(),
  repo: REPO,
} as const;

export { EDIT_BASE, INSTALL, OWNER_URL, REPO_URL } from "./repo";
