import { SITE } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";

export function GET() {
  const lines = [
    `# ${SITE.name}`,
    "",
    `> ${SITE.description}`,
    "",
    "## Docs",
    "",
    ...source.getPages().map((p) => `- [${p.data.title}](${SITE.url}${p.url}): ${p.data.description ?? ""}`.trimEnd()),
    "",
    "## Optional",
    "",
    `- [Benchmarks](${SITE.url}/benchmarks): methodology and measured results`,
    `- [Full documentation as one file](${SITE.url}/llms-full.txt)`,
    "",
  ];
  return new Response(lines.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
