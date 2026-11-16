import { SITE } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";

export async function GET() {
  const parts = await Promise.all(
    source.getPages().map(async (p) => {
      const text = await p.data.getText("processed");
      return `# ${p.data.title}\nURL: ${SITE.url}${p.url}\n\n${text}`;
    }),
  );
  return new Response(`# ${SITE.name} documentation\n\n${parts.join("\n\n---\n\n")}\n`, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
