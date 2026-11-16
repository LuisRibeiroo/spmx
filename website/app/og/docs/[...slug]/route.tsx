import { notFound } from "next/navigation";
import { renderOg } from "@/lib/og";
import { source } from "@/lib/source";

export const dynamic = "force-static";

/** Static per-page OG images at /og/docs/<page>/image.png (the docs index is /og/docs/image.png). */
export function generateStaticParams() {
  return source.getPages().map((p) => ({ slug: [...p.slugs, "image.png"] }));
}

export async function GET(_req: Request, { params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();
  return renderOg(page.data.title, page.data.description ?? "spmx documentation");
}
