import { OG_SIZE, renderOg } from "@/lib/og";

export const dynamic = "force-static";
export const size = OG_SIZE;
export const contentType = "image/png";
export const alt = "pspm benchmarks: worktree clone time and disk use";

export default function Image() {
  return renderOg("Benchmarks", "Methodology, raw data and reproduction steps for every scenario.");
}
