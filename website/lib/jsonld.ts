import { REPO_URL, SITE } from "./site";

export const softwareApplication = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE.name,
  description: SITE.description,
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS",
  url: SITE.url,
  codeRepository: REPO_URL,
  license: "https://opensource.org/license/mit",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export const webSite = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: SITE.name,
  url: SITE.url,
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
