import { meta, releases } from "@/lib/meta";
import { TextLink } from "./TextLink";

function majorOf(tag: string): string {
  const major = /^v?(\d+)/.exec(tag)?.[1] ?? "0";
  return `v${major}.x`;
}

/** Built from GitHub releases at build time (scripts/prebuild.mjs), grouped by major version. */
export function Changelog() {
  if (releases.length === 0) {
    return (
      <p>
        No GitHub release has been published yet. The version in the repository is <code>{meta.cliVersion}</code>.
        Release notes will appear here, grouped by major version, once the first tag is released.
      </p>
    );
  }
  const groups = new Map<string, typeof releases>();
  for (const r of releases) groups.set(majorOf(r.tag), [...(groups.get(majorOf(r.tag)) ?? []), r]);
  return (
    <div className="not-prose space-y-10">
      {[...groups.entries()].map(([major, items]) => (
        <section key={major}>
          <h2 className="mb-4 text-xl font-semibold">{major}</h2>
          <ol className="space-y-6">
            {items.map((r) => (
              <li key={r.tag} className="border-l-2 border-line pl-4">
                <h3 className="font-semibold">
                  <TextLink href={r.url}>{r.name}</TextLink>
                  <time className="ml-3 text-xs font-normal tabular-nums text-ink-muted" dateTime={r.date}>
                    {r.date.slice(0, 10)}
                  </time>
                </h3>
                <pre className="mt-2 whitespace-pre-wrap font-sans text-sm leading-relaxed text-ink-muted">{r.body.trim()}</pre>
              </li>
            ))}
          </ol>
        </section>
      ))}
    </div>
  );
}
