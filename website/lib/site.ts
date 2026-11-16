export const SITE = {
  name: "pspm",
  tagline: "Share SwiftPM packages across Git worktrees",
  description:
    "pspm keeps one APFS copy-on-write store of SwiftPM checkouts, binary artifacts and macro prebuilts, and clones it into every Git worktree. No re-downloads, no duplicated gigabytes.",
  // Domain is still an open question (tasks/prd-site.md §10.1). Set SITE_URL at build time.
  url: (process.env.SITE_URL ?? "http://localhost:3000").replace(/\/$/, ""),
  repo: { owner: "LuisRibeiroo", name: "pspm" },
} as const;

export const REPO_URL = `https://github.com/${SITE.repo.owner}/${SITE.repo.name}`;
export const EDIT_BASE = `${REPO_URL}/edit/main/website/content/docs`;

export const INSTALL = {
  brew: `brew install ${SITE.repo.owner}/tap/pspm`,
  curl: `curl -fsSL https://raw.githubusercontent.com/${SITE.repo.owner}/${SITE.repo.name}/main/scripts/install.sh | sh`,
} as const;
