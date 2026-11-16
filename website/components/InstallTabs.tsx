"use client";

import { useEffect, useId, useState } from "react";
import { INSTALL } from "@/lib/repo";
import { CopyButton } from "./CopyButton";

type Tab = keyof typeof INSTALL;
const TABS: { id: Tab; label: string }[] = [
  { id: "brew", label: "Homebrew" },
  { id: "curl", label: "curl" },
];
const STORAGE_KEY = "pspm-install-tab";

export function InstallTabs({ idPrefix = "install" }: { idPrefix?: string }) {
  const uid = useId();
  const [tab, setTab] = useState<Tab>("brew");
  const [notMac, setNotMac] = useState(false);

  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "brew" || saved === "curl") setTab(saved);
    } catch {
      /* storage blocked: default tab */
    }
    const nav = navigator as Navigator & { userAgentData?: { platform?: string } };
    const platform = nav.userAgentData?.platform ?? navigator.platform ?? "";
    if (platform && !/mac|iphone|ipad/i.test(platform)) setNotMac(true);
  }, []);

  function select(next: Tab) {
    setTab(next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      /* ignore */
    }
  }

  function onKeyDown(event: React.KeyboardEvent, index: number) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const next = TABS[(index + (event.key === "ArrowRight" ? 1 : TABS.length - 1)) % TABS.length]!;
    select(next.id);
    document.getElementById(`${uid}-${idPrefix}-${next.id}`)?.focus();
  }

  return (
    <div className="w-full">
      <div role="tablist" aria-label="Install method" className="flex gap-1 border-b border-line">
        {TABS.map((t, i) => (
          <button
            key={t.id}
            id={`${uid}-${idPrefix}-${t.id}`}
            role="tab"
            type="button"
            aria-selected={tab === t.id}
            aria-controls={`${uid}-${idPrefix}-panel`}
            tabIndex={tab === t.id ? 0 : -1}
            onClick={() => select(t.id)}
            onKeyDown={(e) => onKeyDown(e, i)}
            className={`-mb-px min-h-11 border-b-2 px-4 text-sm font-medium transition-colors duration-200 motion-reduce:transition-none ${
              tab === t.id
                ? "border-accent text-ink"
                : "border-transparent text-ink-muted hover:text-ink"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div
        id={`${uid}-${idPrefix}-panel`}
        role="tabpanel"
        aria-labelledby={`${uid}-${idPrefix}-${tab}`}
        className="mt-3 flex items-center gap-2"
      >
        <pre className="codeblock min-w-0 flex-1 !py-3 max-sm:!text-xs">
          <code>
            <span className="c-muted select-none">$ </span>
            {INSTALL[tab]}
          </code>
        </pre>
        <CopyButton text={INSTALL[tab]} label="Copy install command" />
      </div>
      {notMac ? (
        <p className="mt-2 text-sm text-ink-muted" role="note">
          pspm runs on macOS (Apple Silicon and Intel). Linux is not supported yet.
        </p>
      ) : null}
    </div>
  );
}
