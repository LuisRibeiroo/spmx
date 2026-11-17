import Image from "next/image";
import type { Metadata } from "next";
import { BenchBars } from "@/components/BenchBars";
import { Button } from "@/components/Button";
import { Chip } from "@/components/Chip";
import { CliSample } from "@/components/CliSample";
import { CodeBlock } from "@/components/CodeBlock";
import { CommandCard } from "@/components/CommandCard";
import { Container } from "@/components/Container";
import { Faq, type FaqItem } from "@/components/Faq";
import { InstallTabs } from "@/components/InstallTabs";
import { StoreDiagram } from "@/components/StoreDiagram";
import { TextLink } from "@/components/TextLink";
import { TARGETS, diskResult, entries, hydrateHeadline, isSample, machine, results, shimResult } from "@/lib/benchmarks";
import { formatDuration, formatPercent } from "@/lib/format";
import { meta, versionBadge } from "@/lib/meta";
import { pageMetadata } from "@/lib/seo";
import { REPO_URL, SITE } from "@/lib/site";

export const metadata: Metadata = pageMetadata({
  title: `${SITE.name} — ${SITE.tagline}`,
  description: SITE.metaDescription,
  path: "/",
  images: [{ url: "/opengraph-image", width: 1200, height: 630, alt: `${SITE.name}: ${SITE.tagline}` }],
});

const FAQ: FaqItem[] = [
  {
    q: "Does it work when I open the project in the Xcode GUI?",
    a: (
      <>
        The Xcode app does not go through your shell <code>PATH</code>, so shims cannot see it. Turn on the
        opt-in Git hook with <code>spmx hooks enable --global</code> and every new worktree is hydrated at{" "}
        <code>git worktree add</code> time, before Xcode opens.
      </>
    ),
  },
  {
    q: "Does it work with React Native, Expo, Capacitor, or KMP?",
    a: (
      <>
        Yes, whenever the iOS or macOS build uses Swift Package Manager. Tools like{" "}
        <code>react-native run-ios</code>, <code>expo run:ios</code>, <code>cap run ios</code>, and Kotlin
        Multiplatform Gradle tasks invoke <code>xcodebuild</code> under the hood, so the <code>xcodebuild</code>{" "}
        shim hydrates <code>SourcePackages</code> and shares the LLVM CAS cache automatically. Projects that use
        only CocoaPods (<code>ios/Pods</code>) are not managed by spmx.
      </>
    ),
  },
  {
    q: "Does it conflict with puro or fvm?",
    a: "No. A shim looks for the real binary further down your PATH, skipping its own directory, so puro, fvm, asdf, mise and xcodes keep working. Set SPMX_DISABLE=1 to bypass spmx for a single command.",
  },
  {
    q: "Is there Linux support?",
    a: "Not in v1. spmx relies on APFS clonefile() and Xcode's DerivedData layout, both macOS-specific.",
  },
  {
    q: "Can I use it in CI?",
    a: "Yes. Point SPMX_STORE_DIR at a cached directory and spmx hydrates from it. If a job passes -clonedSourcePackagesDirPath to xcodebuild explicitly, spmx leaves that directory alone.",
  },
  {
    q: "How do I uninstall it?",
    a: (
      <>
        Run <code>spmx uninstall</code> to remove shims, the binary and the PATH lines. Add <code>--purge</code>{" "}
        to also delete <code>~/.spmx/store</code> and the compilation cache.
      </>
    ),
  },
  {
    q: "Is the shared store safe?",
    a: "Entries are keyed by package identity and revision (artifacts by checksum, prebuilts by toolchain hash). Worktrees receive clones, so editing a file in one worktree never touches the store or another worktree. Writes use file locks and atomic staging. spmx sends no telemetry.",
  },
];

const FEATURES = [
  {
    title: "A content-addressable store",
    description:
      "Checkouts, binary XCFrameworks and macro prebuilts are saved once under ~/.spmx/store and cloned with APFS copy-on-write. Prebuilts are partitioned by toolchain hash so a Xcode update never serves a stale ABI.",
    command: "spmx store status",
    href: "/docs/concepts/global-store",
    span: "md:col-span-4",
  },
  {
    title: "Zero-config shims",
    description:
      "flutter, xcodebuild and swift are intercepted from your PATH — automatically covering Xcode, React Native, Expo, Capacitor and KMP builds that invoke xcodebuild.",
    command: "spmx setup",
    href: "/docs/concepts/shims",
    span: "md:col-span-2",
  },
  {
    title: "Shared compilation cache",
    description: "On Xcode 16+ and Swift 6+, the shims point the LLVM CAS cache at one directory shared by every worktree.",
    command: "SPMX_NO_COMPILE_CACHE=1 xcodebuild build",
    href: "/docs/concepts/llvm-compilation-cache",
    span: "md:col-span-2",
  },
  {
    title: "Git hooks, opt-in",
    description: "Pre-warm SourcePackages the moment you run git worktree add. Off until you ask for it; existing hooks are preserved.",
    command: "spmx hooks enable --global",
    href: "/docs/commands/hooks",
    span: "md:col-span-2",
  },
  {
    title: "Flutter with SwiftPM",
    description: "Runs flutter pub get when the ephemeral FlutterGeneratedPluginSwiftPackage is missing, then hydrates the Runner workspace.",
    command: "flutter run",
    href: "/docs/guides/flutter-spm",
    span: "md:col-span-2",
  },
  {
    title: "A doctor that checks everything",
    description: "APFS, Xcode and Swift versions, PATH order, store integrity and hook state in one report.",
    command: "spmx doctor",
    href: "/docs/commands/doctor",
    span: "md:col-span-6",
  },
];

const STEPS = [
  { n: 1, title: "Install once", command: "spmx setup", note: "Creates ~/.spmx, links the shims and adds them to your shell profile." },
  { n: 2, title: "Add a worktree", command: "git worktree add ../app-feature", note: "Your usual Git workflow. Nothing to change." },
  { n: 3, title: "Hydration runs for you", command: "spmx hydrate", note: "Fired by the shim before the build, or by the opt-in hook at checkout." },
  { n: 4, title: "Build as usual", command: "flutter run", note: "Or xcodebuild, or swift build. New packages are harvested back into the store." },
];

const COMPARISON = [
  ["Package checkouts", "Fetched again in every worktree", "Cloned from the store"],
  ["Binary XCFrameworks", "Downloaded and unpacked per worktree", "Cloned, sharing disk blocks"],
  ["Swift macro prebuilts", "Fetched or rebuilt per worktree", "Cloned, keyed by toolchain"],
  ["Compiler output", "Per-DerivedData, starts empty", "One shared compilation cache"],
  ["Setup per project", "—", "None after spmx setup"],
] as const;

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div className="border-l-2 border-accent pl-4">
      <p className="text-lg font-semibold tracking-tight">{value}</p>
      <p className="text-sm text-ink-muted">{label}</p>
    </div>
  );
}

export default function HomePage() {
  const headline = hydrateHeadline();
  const disk = diskResult();
  const shim = shimResult();
  const benchRows = (["S3", "S4", "S5"] as const).flatMap((id) => entries(id));

  return (
    <>
      {/* 1 · Hero */}
      <section className="hero-glow">
        <Container className="grid items-center gap-10 py-14 md:grid-cols-[1.05fr_1fr] md:gap-12 md:py-24">
          <div className="min-w-0">
            <div className="mb-8 flex items-end gap-4">
              <Image
                src="/icon.svg"
                alt="spmx icon: an open orange pixel-art box"
                width={144}
                height={165}
                priority
                unoptimized
                className="h-auto w-28 [image-rendering:pixelated] md:w-36"
              />
              <Chip href={versionBadge.href} className="mb-2">{versionBadge.label}</Chip>
            </div>
            <h1 className="text-hero font-bold tracking-tight">{SITE.tagline}</h1>
            <p className="mt-5 max-w-[34rem] text-lead text-ink-muted">
              spmx keeps one APFS copy-on-write store of checkouts, artifacts and prebuilts, and clones it into
              every Git worktree. No re-downloads, no duplicated gigabytes.
            </p>
            <div className="mt-8 max-w-[34rem]">
              <InstallTabs idPrefix="hero" />
            </div>
            <div className="mt-6 flex flex-wrap gap-3">
              <Button href="/docs/getting-started/installation" variant="primary">Get started</Button>
              <Button href={REPO_URL}>View on GitHub</Button>
            </div>
          </div>
          <div className="reveal min-w-0 [animation-delay:120ms]">
            <CliSample />
          </div>
        </Container>
      </section>

      {/* 2 · Problem */}
      <Container as="section" className="py-16 md:py-24" aria-labelledby="problem">
        <h2 id="problem" className="max-w-2xl text-h2 font-bold tracking-tight">
          Every worktree starts from zero.
        </h2>
        <div className="mt-10 grid gap-8 md:grid-cols-3">
          <div>
            <h3 className="font-semibold">A new worktree gets a new DerivedData hash</h3>
            <p className="mt-2 text-ink-muted">Xcode derives the build folder name from the workspace path, so a fresh checkout has nothing in it.</p>
          </div>
          <div>
            <h3 className="font-semibold">Every package downloads again</h3>
            <p className="mt-2 text-ink-muted">Source checkouts, binary XCFrameworks and macro prebuilts are fetched per worktree.</p>
          </div>
          <div>
            <h3 className="font-semibold">Gigabytes multiply</h3>
            <p className="mt-2 text-ink-muted">Five worktrees of a project with heavy SDKs means five copies of the same SDKs on your SSD.</p>
          </div>
        </div>
      </Container>

      <Container><div className="pixel-rule" aria-hidden="true" /></Container>

      {/* 3 · How it works (warm band) */}
      <section className="mt-16 border-y border-line bg-surface-warm md:mt-24" aria-labelledby="how">
        <Container className="grid items-center gap-10 py-16 md:grid-cols-2 md:gap-16 md:py-24">
          <StoreDiagram />
          <div>
            <h2 id="how" className="text-h2 font-bold tracking-tight">One store, linked everywhere.</h2>
            <ul className="mt-6 space-y-4 text-ink-muted">
              <li><strong className="text-ink">Saved once.</strong> Packages live under <code className="font-mono text-sm">~/.spmx/store</code>, keyed by identity and revision.</li>
              <li><strong className="text-ink">Cloned, not copied.</strong> APFS <code className="font-mono text-sm">clonefile()</code> creates real files that share disk blocks. Edit one and only the changed blocks are allocated.</li>
              <li><strong className="text-ink">Hands-off.</strong> Shims hydrate before a build and harvest new packages afterwards.</li>
              <li><strong className="text-ink">Safe in parallel.</strong> File locks and atomic staging let several worktrees, or several agents, write at once.</li>
            </ul>
            <TextLink href="/docs/concepts/global-store" className="mt-6 inline-block font-medium">How the store works</TextLink>
          </div>
        </Container>
      </section>

      {/* 4 · Workflow */}
      <Container as="section" className="py-16 md:py-24" aria-labelledby="workflow">
        <h2 id="workflow" className="max-w-2xl text-h2 font-bold tracking-tight">Four steps, one of them yours.</h2>
        <ol className="mt-10 grid gap-5 md:grid-cols-2">
          {STEPS.map((s) => (
            <li key={s.n} className="flex gap-4 rounded-lg border border-line p-5">
              <span className="text-2xl font-semibold tabular-nums text-accent-text" aria-hidden="true">{s.n}</span>
              <div className="min-w-0">
                <h3 className="font-semibold">{s.title}</h3>
                <CodeBlock padding="sm" className="mt-2">
                  <span className="text-ink-muted select-none">$ </span>{s.command}
                </CodeBlock>
                <p className="mt-2 text-sm text-ink-muted">{s.note}</p>
              </div>
            </li>
          ))}
        </ol>
      </Container>

      {/* 5 · Stats + benchmark */}
      <Container as="section" className="pb-16 md:pb-24" aria-labelledby="proof">
        <h2 id="proof" className="max-w-2xl text-h2 font-bold tracking-tight">Measured, not promised.</h2>
        <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <Stat value="1 binary" label="One multicall executable: the CLI and every shim" />
          <Stat value="arm64 + x86_64" label="Universal build for Apple Silicon and Intel" />
          <Stat value="zero-config" label="Shims are active right after spmx setup" />
          <Stat value="no telemetry" label="spmx makes no network calls of its own" />
        </div>
        {meta.tarballBytes ? (
          <p className="mt-4 text-sm text-ink-muted">Release archive: {(meta.tarballBytes / 1_000_000).toFixed(1)} MB.</p>
        ) : null}

        <div className="mt-12 grid gap-10 lg:grid-cols-[1fr_1.2fr]">
          <div>
            {headline?.promoted ? (
              <>
                <p className="text-6xl font-bold tracking-tight tabular-nums text-accent-text">{formatPercent(headline.reduction)}</p>
                <p className="mt-2 text-lg">
                  less time to prepare a new worktree: {formatDuration(headline.baselineSeconds)} →{" "}
                  {formatDuration(headline.spmxSeconds)} (median of {headline.runs} runs, fixture {headline.fixture}).
                </p>
              </>
            ) : (
              <p className="text-lg">
                {headline
                  ? "This run did not reach the warm-store target, so it is published below without a headline claim."
                  : "The warm-store scenario has not been measured in this build."}
              </p>
            )}
            {disk?.promoted ? (
              <p className="mt-4 text-ink-muted">Each extra worktree adds only a few megabytes of physical disk.</p>
            ) : null}
            {shim?.promoted ? <p className="mt-2 text-ink-muted">The shim adds less than {formatDuration(TARGETS.shimOverheadSeconds)} to a no-op command.</p> : null}
            <p className="mt-6 text-xs leading-relaxed text-ink-muted">
              {machine.chip} · {machine.ram_gb} GB · macOS {machine.macos} · Xcode {machine.xcode} · spmx {results.spmx}
              {" · "}{results.date.slice(0, 10)}
            </p>
            {isSample ? (
              <p role="note" className="mt-3 rounded-md border border-warn px-3 py-2 text-sm text-warn">
                Sample data for layout preview only. These are not measurements.
              </p>
            ) : null}
            <TextLink href="/benchmarks" className="mt-4 inline-block font-medium">Methodology and every scenario</TextLink>
          </div>
          <BenchBars scenarios={benchRows} compact />
        </div>
      </Container>

      {/* 6 · Features */}
      <Container as="section" className="pb-16 md:pb-24" aria-labelledby="features">
        <h2 id="features" className="max-w-2xl text-h2 font-bold tracking-tight">What is inside.</h2>
        <div className="mt-10 grid gap-5 md:grid-cols-6">
          {FEATURES.map((f) => (
            <CommandCard key={f.title} title={f.title} description={f.description} command={f.command} href={f.href} className={f.span} />
          ))}
        </div>
      </Container>

      {/* 7 · AI agents */}
      <section className="border-y border-line bg-surface-warm" aria-labelledby="agents">
        <Container className="grid items-center gap-10 py-16 md:grid-cols-2 md:gap-16 md:py-24">
          <div className="min-w-0 md:order-2">
            <p className="text-sm font-medium text-accent-text">For AI coding agents</p>
            <h2 id="agents" className="mt-2 text-h2 font-bold tracking-tight">Parallel agents need cheap worktrees.</h2>
            <ul className="mt-6 space-y-3 text-ink-muted">
              <li>Give every agent its own worktree without paying for its own copy of every SDK.</li>
              <li>Store writes use file locks and atomic staging, so concurrent hydrates and harvests do not collide.</li>
              <li>
                These docs are readable by tools: <TextLink href="/llms.txt">llms.txt</TextLink>,{" "}
                <TextLink href="/llms-full.txt">llms-full.txt</TextLink> and a Copy as Markdown button on every page.
              </li>
            </ul>
            <TextLink href="/docs/guides/ai-agents" className="mt-6 inline-block font-medium">Agents and parallel worktrees</TextLink>
          </div>
          <CodeBlock className="min-w-0 md:order-1">
            <span className="text-ink-muted"># one worktree per agent</span>{"\n"}
            <span className="text-ink-muted">$ </span>for n in 1 2 3; do{"\n"}
            {"    "}git worktree add ../agent-$n{"\n"}
            done{"\n"}
            {"\n"}
            <span className="text-ink-muted"># hydrate automatically on every new worktree</span>{"\n"}
            <span className="text-ink-muted">$ </span>spmx hooks enable --global
          </CodeBlock>
        </Container>
      </section>

      {/* 8 · Comparison */}
      <Container as="section" className="py-16 md:py-24" aria-labelledby="compare">
        <h2 id="compare" className="max-w-2xl text-h2 font-bold tracking-tight">Without spmx, with spmx.</h2>
        <div className="mt-8 overflow-x-auto">
          <table className="w-full min-w-[34rem] border-collapse text-left text-[0.9375rem]">
            <caption className="sr-only">What happens in a new worktree, with and without spmx</caption>
            <thead>
              <tr className="border-b border-line-strong">
                <th scope="col" className="py-3 pr-4 font-semibold">In a new worktree</th>
                <th scope="col" className="px-4 py-3 font-semibold text-ink-muted">Without spmx</th>
                <th scope="col" className="px-4 py-3 font-semibold text-accent-text">With spmx</th>
              </tr>
            </thead>
            <tbody>
              {COMPARISON.map(([row, without, withSpmx]) => (
                <tr key={row} className="border-b border-line">
                  <th scope="row" className="py-3 pr-4 font-medium">{row}</th>
                  <td className="px-4 py-3 text-ink-muted">{without}</td>
                  <td className="px-4 py-3">{withSpmx}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Container>

      {/* 9 · FAQ */}
      <Container as="section" className="pb-16 md:pb-24" aria-labelledby="faq">
        <h2 id="faq" className="text-h2 font-bold tracking-tight">Questions</h2>
        <div className="mt-8 max-w-3xl">
          <Faq items={FAQ} />
        </div>
      </Container>

      {/* 10 · Final CTA */}
      <section className="border-y border-line bg-surface-warm" aria-labelledby="cta">
        <Container className="flex flex-col items-start gap-8 py-16 md:py-20 lg:flex-row lg:items-center lg:justify-between">
          <div className="max-w-md">
            <h2 id="cta" className="text-h2 font-bold tracking-tight">Try it on your next worktree.</h2>
            <Button href="/docs" variant="primary" className="mt-6">Read the docs</Button>
          </div>
          <div className="w-full max-w-xl"><InstallTabs idPrefix="cta" /></div>
        </Container>
      </section>
    </>
  );
}
