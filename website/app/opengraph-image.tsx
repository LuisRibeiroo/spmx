import { OG_SIZE, renderOg } from "@/lib/og";
import { SITE } from "@/lib/site";

export const dynamic = "force-static";
export const size = OG_SIZE;
export const contentType = "image/png";
export const alt = `${SITE.name}: ${SITE.tagline}`;

export default function Image() {
  return renderOg(SITE.tagline, "One APFS copy-on-write store. Cloned into every worktree.", "macOS CLI · SwiftPM");
}
