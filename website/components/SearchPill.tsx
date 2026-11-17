"use client";

import { useSearchContext } from "fumadocs-ui/provider";
import { captureEvent } from "@/lib/analytics";

export function SearchPill() {
  const { setOpenSearch, hotKey } = useSearchContext();
  return (
    <button
      type="button"
      onClick={() => {
        captureEvent("docs_search_opened");
        setOpenSearch(true);
      }}
      className="inline-flex size-10 shrink-0 items-center justify-center gap-2 rounded-full border border-line-strong bg-paper-2 text-sm sm:h-auto sm:min-h-10 sm:w-auto sm:justify-start sm:px-3 text-ink-muted transition-colors duration-200 hover:border-ink-muted hover:text-ink motion-reduce:transition-none sm:min-w-52"
    >
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
        <circle cx="7" cy="7" r="4.5" />
        <path d="M10.5 10.5L14 14" />
      </svg>
      <span className="hidden sm:inline">Search docs</span>
      <span className="sr-only sm:hidden">Search docs</span>
      <span className="ml-auto hidden gap-1 sm:inline-flex" aria-hidden="true">
        {hotKey.map((k, i) => (
          <kbd key={i} className="rounded border border-line px-1.5 text-[11px] leading-5">
            {k.display}
          </kbd>
        ))}
      </span>
    </button>
  );
}
