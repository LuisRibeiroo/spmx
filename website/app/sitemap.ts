import { join } from "node:path";
import type { MetadataRoute } from "next";
import { results } from "@/lib/benchmarks";
import { lastModified, parseDate } from "@/lib/lastmod";
import { SITE } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";

const site = process.cwd();

export default function sitemap(): MetadataRoute.Sitemap {
  const docs = source.getPages().map((p) => ({
    url: `${SITE.url}${p.url}`,
    lastModified: lastModified(join(site, "content", "docs", p.path)),
  }));
  const benchmarks = lastModified(join(site, "app", "benchmarks", "page.tsx"));
  const measured = parseDate(results.date);
  return [
    { url: SITE.url, lastModified: lastModified(join(site, "app", "(home)", "page.tsx")), priority: 1 },
    {
      url: `${SITE.url}/benchmarks`,
      lastModified: measured && measured > benchmarks ? measured : benchmarks,
      priority: 0.8,
    },
    ...docs,
  ];
}
