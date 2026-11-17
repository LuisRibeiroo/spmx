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
      "SITE_URL is not set. Set it to the public origin of the site, e.g. SITE_URL=https://example.com npm run build " +
        "(use SITE_URL=http://localhost:3000 only for a local build you will not deploy).",
    );
  }
  return "http://localhost:3000";
}

export const SITE = {
  name: "spmx",
  tagline: "Share SwiftPM packages across Git worktrees",
  description:
    "spmx keeps one APFS copy-on-write store of SwiftPM checkouts, binary artifacts and macro prebuilts, and clones it into every Git worktree. Works across Swift, Xcode, Flutter, React Native, Expo, Capacitor and Kotlin Multiplatform.",
  /** <= 155 characters so search results do not truncate it. */
  metaDescription:
    "One APFS copy-on-write store for SwiftPM checkouts, artifacts and prebuilts across Git worktrees — works with Xcode, Swift, Flutter, React Native & more.",
  // Domain is still an open question (tasks/prd-site.md §10.1). Set SITE_URL at build time.
  url: resolveSiteUrl(),
  repo: REPO,
} as const;

export { EDIT_BASE, INSTALL, OWNER_URL, REPO_URL } from "./repo";
