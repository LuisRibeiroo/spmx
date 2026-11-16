import { meta } from "./meta";
import { OWNER_URL, REPO_URL, SITE } from "./site";

const author = {
  "@type": "Person",
  name: SITE.repo.owner,
  url: OWNER_URL,
  sameAs: [OWNER_URL],
};

export const softwareApplication = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE.name,
  description: SITE.description,
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS",
  softwareVersion: meta.cliVersion,
  url: SITE.url,
  downloadUrl: meta.latestRelease?.url ?? `${REPO_URL}/releases`,
  installUrl: `${SITE.url}/docs/getting-started/installation`,
  codeRepository: REPO_URL,
  sameAs: [REPO_URL],
  license: "https://opensource.org/license/mit",
  isAccessibleForFree: true,
  author,
  publisher: author,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export const webSite = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: SITE.name,
  url: SITE.url,
  inLanguage: "en",
  publisher: author,
  potentialAction: {
    "@type": "SearchAction",
    target: { "@type": "EntryPoint", urlTemplate: `${SITE.url}/docs?q={search_term_string}` },
    "query-input": "required name=search_term_string",
  },
};

export function breadcrumbs(items: { name: string; path: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: item.name,
      item: `${SITE.url}${item.path}`,
    })),
  };
}

export function techArticle({ title, description, path, modified }: { title: string; description?: string; path: string; modified: Date }) {
  return {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: title,
    ...(description ? { description } : {}),
    url: `${SITE.url}${path}`,
    mainEntityOfPage: `${SITE.url}${path}`,
    inLanguage: "en",
    dateModified: modified.toISOString(),
    author,
    publisher: author,
    isPartOf: { "@type": "WebSite", name: SITE.name, url: SITE.url },
  };
}
