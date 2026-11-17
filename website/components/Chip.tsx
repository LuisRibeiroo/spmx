import type { ReactNode } from "react";

type Tone = "default" | "ok" | "warn";
type Weight = "medium" | "normal";

interface ChipProps {
  href?: string | null;
  tone?: Tone;
  weight?: Weight;
  className?: string;
  children: ReactNode;
}

const BASE =
  "inline-flex min-h-7 items-center gap-2 rounded-full border border-line-strong px-3 text-xs whitespace-nowrap";

const TONES: Record<Tone, string> = {
  default: "text-ink-muted",
  ok: "text-ok",
  warn: "text-warn",
};

const WEIGHTS: Record<Weight, string> = {
  medium: "font-medium",
  normal: "font-normal",
};

/** Compact pill badge or link with consistent touch target height. */
export function Chip({ href, tone = "default", weight = "medium", className = "", children }: ChipProps) {
  const classes = `${BASE} ${WEIGHTS[weight]} ${TONES[tone]} ${className}`.trim();
  if (href) {
    return (
      <a
        href={href}
        data-chip=""
        className={`${classes} transition-colors duration-200 ease-out hover:border-ink-muted hover:text-ink motion-reduce:transition-none`}
      >
        {children}
      </a>
    );
  }
  return (
    <span data-chip="" className={classes}>
      {children}
    </span>
  );
}
