import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { DocsBody, DocsDescription, DocsPage, DocsTitle } from "fumadocs-ui/page";
import { CopyMarkdown } from "@/components/CopyMarkdown";
import { breadcrumbs } from "@/lib/jsonld";
import { EDIT_BASE } from "@/lib/site";
import { source } from "@/lib/source";
import { getMDXComponents } from "@/mdx-components";

interface Props {
  params: Promise<{ slug?: string[] }>;
}

export default async function Page({ params }: Props) {
  const { slug } = await params;
  const page = source.getPage(slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdown = await page.data.getText("processed");
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
        dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbs(crumbs)) }}
      />
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <div className="not-prose -mt-4 mb-6 flex flex-wrap gap-2">
        <CopyMarkdown markdown={`# ${page.data.title}\n\n${markdown}`} />
      </div>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
      <div className="mt-12 border-t border-line pt-4">
        <a className="link text-sm" href={`${EDIT_BASE}/${page.path}`}>
          Edit this page on GitHub
        </a>
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
  const path = `/docs${slug?.length ? `/${slug.join("/")}` : ""}`;
  return {
    title: page.data.title,
    description: page.data.description,
    alternates: { canonical: path },
    openGraph: {
      title: page.data.title,
      description: page.data.description,
      url: path,
      images: [{ url: `/og/docs${slug?.length ? `/${slug.join("/")}` : ""}/image.png`, width: 1200, height: 630, alt: page.data.title }],
    },
  };
}
