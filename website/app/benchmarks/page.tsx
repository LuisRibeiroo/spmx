import type { Metadata } from "next";
import { BenchBars } from "@/components/BenchBars";
import { Container } from "@/components/Container";
import { TextLink } from "@/components/TextLink";
import { isSample, machine, results, TARGETS } from "@/lib/benchmarks";
import { formatBytes, formatDuration, formatPercent } from "@/lib/format";
import { breadcrumbs } from "@/lib/jsonld";
import { brandTitle, pageMetadata } from "@/lib/seo";
import { REPO_URL } from "@/lib/site";

export const metadata: Metadata = pageMetadata({
  title: brandTitle("Benchmarks: worktree clone time and disk use"),
  description: "Methodology, raw data and reproduction steps for every spmx benchmark scenario.",
  path: "/benchmarks",
  images: [{ url: "/benchmarks/opengraph-image", width: 1200, height: 630, alt: "spmx benchmarks: worktree clone time and disk use" }],
});

export default function BenchmarksPage() {
  const m = results.methodology;
  return (
    <Container className="py-14 md:py-20">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(breadcrumbs([{ name: "Home", path: "/" }, { name: "Benchmarks", path: "/benchmarks" }])),
        }}
      />
      <h1 className="max-w-3xl text-hero font-bold tracking-tight">Benchmarks</h1>
      <p className="mt-5 max-w-2xl text-lead text-ink-muted">
        Every number on this site is read from one JSON file produced by a local, reproducible harness. Scenarios
        that miss their target are published here too; they are just not promoted to a headline.
      </p>
      <p className="mt-3 text-sm text-ink-muted">
        Last measured <time dateTime={results.date}>{results.date.slice(0, 10)}</time> with spmx {results.spmx}.
      </p>
      {isSample ? (
        <p role="note" className="mt-6 max-w-2xl rounded-md border border-warn px-4 py-3 text-warn">
          This build uses sample data for layout preview only. These are not measurements.
        </p>
      ) : null}

      <div className="mt-12 grid gap-12 lg:grid-cols-[1fr_20rem]">
        <div className="min-w-0">
          <h2 className="mb-6 text-h2 font-bold tracking-tight">Results</h2>
          <figure>
            <BenchBars scenarios={results.scenarios} />
            <figcaption className="mt-8 text-sm text-ink-muted">
              Bars show the median; the whisker spans the fastest and slowest run. Scenarios marked
              network-dependent include download time and vary with your connection.
            </figcaption>
          </figure>
        </div>

        <aside aria-labelledby="method" className="min-w-0 space-y-8 text-[0.9375rem]">
          <section>
            <h2 id="method" className="text-lg font-semibold">Methodology</h2>
            <dl className="mt-3 space-y-3">
              {m ? (
                <div>
                  <dt className="text-ink-muted">Runs</dt>
                  <dd>hyperfine, {m.warmup} warmup. Each result lists its own run count (default {m.runs}).</dd>
                </div>
              ) : null}
              <div>
                <dt className="text-ink-muted">Machine</dt>
                <dd className="tabular-nums">{machine.chip} · {machine.ram_gb} GB</dd>
              </div>
              <div>
                <dt className="text-ink-muted">Software</dt>
                <dd>macOS {machine.macos} · Xcode {machine.xcode} · {machine.swift}</dd>
              </div>
              <div>
                <dt className="text-ink-muted">spmx</dt>
                <dd className="break-all tabular-nums">{results.spmx}</dd>
              </div>
              <div>
                <dt className="text-ink-muted">Date</dt>
                <dd className="tabular-nums">{results.date.slice(0, 10)}</dd>
              </div>
            </dl>
          </section>

          <section>
            <h2 className="text-lg font-semibold">Disk is measured physically</h2>
            <p className="mt-2 text-ink-muted">
              Worktrees and the store live on an isolated, sparse APFS disk image. Cost per worktree is the drop in
              free space of that volume, because <code>du</code> reports the logical size of clones and overstates
              the real cost. The image is unmounted and deleted at the end.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-semibold">Targets</h2>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-ink-muted">
              <li>S3: at least {formatPercent(TARGETS.hydrateReduction)} less time</li>
              <li>S4: under {formatBytes(TARGETS.diskBytesPerWorktree)} per worktree</li>
              <li>S5: under {formatDuration(TARGETS.shimOverheadSeconds)} overhead</li>
              <li>S1: no slower than the baseline</li>
            </ul>
          </section>

          {results.fixtures?.length ? (
            <section>
              <h2 className="text-lg font-semibold">Fixtures</h2>
              <ul className="mt-2 space-y-2 text-ink-muted">
                {results.fixtures.map((f) => (
                  <li key={f.id} className="break-words">
                    <span className="font-mono text-ink">{f.id}</span>
                    <br />
                    <span className="font-mono text-xs">{f.repo} @ {f.commit.slice(0, 12)}</span>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <section className="flex flex-col gap-2">
            <TextLink className="w-fit" href="/benchmarks/latest.json">Raw results (JSON)</TextLink>
            <TextLink className="w-fit" href="/docs/guides/reproduce-the-benchmarks">Reproduce the benchmarks</TextLink>
            <TextLink className="w-fit" href={`${REPO_URL}/tree/main/bench`}>Harness source</TextLink>
          </section>
        </aside>
      </div>
    </Container>
  );
}
