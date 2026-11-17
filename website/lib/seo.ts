import type { Metadata } from "next";
import { OWNER_URL, SITE } from "./site";

/** Appends the brand unless the title already starts with it ("spmx doctor" stays "spmx doctor"). */
export function brandTitle(title: string): string {
  return /^spmx\b/i.test(title) ? title : `${title} · ${SITE.name}`;
}

export interface OgImageDescriptor {
  url: string;
  width: number;
  height: number;
  alt: string;
  type?: string;
}

interface PageMetadataOptions {
  /** Final title, already branded. */
  title: string;
  description: string;
  /** Path starting with "/", resolved against metadataBase. */
  path: string;
  images?: OgImageDescriptor[];
  ogType?: "website" | "article";
  modifiedTime?: string;
}

/**
 * Next replaces (not merges) `openGraph` and `twitter` when a page sets them, so every page spells out the
 * full set here: type, site name, locale, url, title, description and images.
 */
export function pageMetadata({ title, description, path, images, ogType = "website", modifiedTime }: PageMetadataOptions): Metadata {
  const ogImages = images?.map((image) => ({
    url: image.url,
    width: image.width,
    height: image.height,
    alt: image.alt,
    type: image.type ?? "image/png",
  }));

  const twitterImages = images?.map((image) => ({
    url: image.url,
    alt: image.alt,
    width: image.width,
    height: image.height,
  }));

  return {
    title: { absolute: title },
    description,
    alternates: { canonical: path },
    openGraph:
      ogType === "article"
        ? {
            type: "article",
            siteName: SITE.name,
            locale: "en_US",
            title,
            description,
            url: path,
            authors: [OWNER_URL],
            ...(modifiedTime ? { modifiedTime } : {}),
            ...(ogImages ? { images: ogImages } : {}),
          }
        : {
            type: "website",
            siteName: SITE.name,
            locale: "en_US",
            title,
            description,
            url: path,
            ...(ogImages ? { images: ogImages } : {}),
          },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      ...(twitterImages ? { images: twitterImages } : {}),
    },
  };
}
