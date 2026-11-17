"use client";

import { useEffect, useRef, useState } from "react";
import { captureEvent, type AnalyticsProperties } from "@/lib/analytics";

type State = "idle" | "copied" | "error";

interface Props {
  text: string;
  label?: string;
  className?: string;
  variant?: "icon" | "text";
  eventName?: string;
  eventProps?: AnalyticsProperties;
}

/** States: default, hover, focus-visible, active, success (copied), error (clipboard blocked). */
export function CopyButton({
  text,
  label = "Copy",
  className = "",
  variant = "icon",
  eventName = "content_copied",
  eventProps,
}: Props) {
  const [state, setState] = useState<State>("idle");
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setState("copied");
      captureEvent(eventName, { label, ...eventProps });
    } catch {
      setState("error");
    }
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setState("idle"), 1800);
  }

  const text_ = state === "copied" ? "Copied" : state === "error" ? "Copy failed" : label;
  const color =
    state === "copied" ? "text-ok" : state === "error" ? "text-err" : "text-ink-muted hover:text-ink";

  return (
    <button
      type="button"
      onClick={copy}
      aria-label={`${label}: ${text}`}
      className={`inline-flex min-h-9 min-w-9 shrink-0 items-center justify-center gap-1.5 rounded-md border border-line px-2 text-xs transition-colors duration-200 hover:border-line-strong active:translate-y-px motion-reduce:transition-none ${color} ${className}`}
    >
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
        {state === "copied" ? (
          <path d="M3 8.5l3.2 3L13 4.5" />
        ) : (
          <>
            <rect x="5.5" y="5.5" width="8" height="8" rx="1.5" />
            <path d="M10.5 5.5v-2a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2" />
          </>
        )}
      </svg>
      {variant === "text" || state !== "idle" ? <span>{text_}</span> : null}
      <span className="sr-only" role="status" aria-live="polite">
        {state === "copied" ? "Copied to clipboard" : state === "error" ? "Copy failed" : ""}
      </span>
    </button>
  );
}
