import type { MetadataRoute } from "next";
import { SITE } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  const pages = source.getPages().map((p) => ({ url: `${SITE.url}${p.url}`, lastModified: now }));
  return [
    { url: SITE.url, lastModified: now, priority: 1 },
    { url: `${SITE.url}/benchmarks`, lastModified: now, priority: 0.8 },
    ...pages,
  ];
}
