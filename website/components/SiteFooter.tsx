import Link from "next/link";
import { REPO_URL } from "@/lib/site";
import { meta } from "@/lib/meta";

const link =
  "inline-flex min-h-10 items-center whitespace-nowrap text-ink-muted transition-colors duration-200 hover:text-ink motion-reduce:transition-none";

export function SiteFooter() {
  return (
    <footer className="band-warm mt-auto">
      <div className="container-page flex flex-wrap items-center justify-between gap-x-6 gap-y-1 py-4 text-sm">
        <p className="whitespace-nowrap text-ink-muted">
          pspm v{meta.cliVersion} · MIT
        </p>
        <nav aria-label="Footer" className="flex flex-wrap gap-x-5">
          <Link href="/docs" className={link}>Docs</Link>
          <Link href="/benchmarks" className={link}>Benchmarks</Link>
          <Link href="/docs/changelog" className={link}>Changelog</Link>
          <a href={REPO_URL} className={link}>GitHub</a>
          <a href="/llms.txt" className={link}>llms.txt</a>
        </nav>
      </div>
    </footer>
  );
}
