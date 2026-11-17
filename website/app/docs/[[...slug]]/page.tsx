import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { DocsBody, DocsDescription, DocsPage, DocsTitle } from "fumadocs-ui/page";
import { CopyMarkdown } from "@/components/CopyMarkdown";
import { TextLink } from "@/components/TextLink";
import { join } from "node:path";
import { breadcrumbs, techArticle } from "@/lib/jsonld";
import { lastModified } from "@/lib/lastmod";
import { brandTitle, pageMetadata } from "@/lib/seo";
import { EDIT_BASE, OWNER_URL, SITE } from "@/lib/site";
import { source } from "@/lib/source";
import { getMDXComponents } from "@/mdx-components";

interface Props {
  params: Promise<{ slug?: string[] }>;
}

/** The docs index is titled "Introduction" in the sidebar; search results get a descriptive title. */
const INDEX_SEO_TITLE = "What is spmx? Introduction";

function docPath(slug?: string[]) {
  return `/docs${slug?.length ? `/${slug.join("/")}` : ""}`;
}

function docModified(pagePath: string) {
  return lastModified(join(process.cwd(), "content", "docs", pagePath));
}

export default async function Page({ params }: Props) {
  const { slug } = await params;
  const page = source.getPage(slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdown = await page.data.getText("processed");
  const modified = docModified(page.path);
  const crumbs = [
    { name: "Home", path: "/" },
    { name: "Docs", path: "/docs" },
    ...(slug ?? []).map((part, i) => ({
      name: part.replace(/-/g, " "),
      path: `/docs/${(slug ?? []).slice(0, i + 1).join("/")}`,
    })),
  ];

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify([
            breadcrumbs(crumbs),
            techArticle({ title: page.data.title, description: page.data.description, path: docPath(slug), modified }),
          ]),
        }}
      />
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <div className="not-prose -mt-4 mb-6 flex flex-wrap gap-2">
        <CopyMarkdown markdown={`# ${page.data.title}\n\n${markdown}`} />
      </div>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
      <div className="mt-12 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-line pt-4 text-sm text-ink-muted">
        <span>
          Maintained by{" "}
          <TextLink href={OWNER_URL}>
            {SITE.repo.owner}
          </TextLink>
        </span>
        <span>
          Last updated <time dateTime={modified.toISOString()}>{modified.toISOString().slice(0, 10)}</time>
        </span>
        <TextLink href={`${EDIT_BASE}/${page.path}`}>
          Edit this page on GitHub
        </TextLink>
      </div>
    </DocsPage>
  );
}

export function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const page = source.getPage(slug);
  if (!page) notFound();
  const path = docPath(slug);
  const title = brandTitle(slug?.length ? page.data.title : INDEX_SEO_TITLE);
  return pageMetadata({
    title,
    description: page.data.description ?? SITE.metaDescription,
    path,
    ogType: "article",
    modifiedTime: docModified(page.path).toISOString(),
    images: [{ url: `/og/docs${slug?.length ? `/${slug.join("/")}` : ""}/image.png`, width: 1200, height: 630, alt: page.data.title }],
  });
}
