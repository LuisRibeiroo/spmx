// Constants that do not depend on the deploy origin. Safe to import from client components
// (lib/site.ts reads SITE_URL and must stay out of the browser bundle).
const OWNER = "LuisRibeiroo";
const NAME = "spmx";

export const REPO = { owner: OWNER, name: NAME } as const;
export const REPO_URL = `https://github.com/${OWNER}/${NAME}`;
export const OWNER_URL = `https://github.com/${OWNER}`;
export const EDIT_BASE = `${REPO_URL}/edit/main/website/content/docs`;

export const INSTALL = {
  brew: `brew install ${OWNER}/tap/spmx`,
  curl: `curl -fsSL https://raw.githubusercontent.com/${OWNER}/${NAME}/main/scripts/install.sh | sh`,
} as const;
