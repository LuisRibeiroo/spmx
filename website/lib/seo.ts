import type { Metadata } from "next";
import { SITE } from "./site";

/** Appends the brand unless the title already starts with it ("pspm doctor" stays "pspm doctor"). */
export function brandTitle(title: string): string {
  return /^pspm\b/i.test(title) ? title : `${title} · ${SITE.name}`;
}

interface PageMetadataOptions {
  /** Final title, already branded. */
  title: string;
  description: string;
  /** Path starting with "/", resolved against metadataBase. */
  path: string;
  images?: { url: string; width: number; height: number; alt: string }[];
}

/**
 * Next replaces (not merges) `openGraph` and `twitter` when a page sets them, so every page spells out the
 * full set here: type, site name, locale, url, title, description and images.
 */
export function pageMetadata({ title, description, path, images }: PageMetadataOptions): Metadata {
  return {
    title: { absolute: title },
    description,
    alternates: { canonical: path },
    openGraph: {
      type: "website",
      siteName: SITE.name,
      locale: "en_US",
      title,
      description,
      url: path,
      ...(images ? { images } : {}),
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      ...(images ? { images: images.map((image) => image.url) } : {}),
    },
  };
}
