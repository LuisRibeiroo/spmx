import Link from "next/link";
import { REPO_URL } from "@/lib/site";
import { Logo } from "./Logo";
import { SearchPill } from "./SearchPill";
import { ThemeToggle } from "./ThemeToggle";

const linkClass =
  "min-h-10 items-center whitespace-nowrap rounded-md px-2.5 text-sm text-ink-muted transition-colors duration-200 hover:text-ink motion-reduce:transition-none";

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-line bg-paper/90 backdrop-blur supports-[backdrop-filter]:bg-paper/75">
      <div className="container-page flex h-16 items-center gap-1 sm:gap-2">
        <Logo />
        <nav aria-label="Main" className="ml-1 flex items-center sm:ml-4">
          <Link href="/docs" className={`${linkClass} inline-flex`}>
            Docs
          </Link>
          <Link href="/benchmarks" className={`${linkClass} hidden min-[420px]:inline-flex`}>
            Benchmarks
          </Link>
          <a href={REPO_URL} className={`${linkClass} hidden md:inline-flex`}>
            GitHub
          </a>
        </nav>
        <div className="ml-auto flex items-center gap-1">
          <SearchPill />
          <ThemeToggle />
        </div>
      </div>
    </header>
  );
}
