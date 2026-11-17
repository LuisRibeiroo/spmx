import Link from "next/link";
import type { ReactNode } from "react";

type Variant = "primary" | "secondary";

interface ButtonProps {
  href?: string;
  variant?: Variant;
  className?: string;
  children: ReactNode;
  type?: "button" | "submit" | "reset";
  disabled?: boolean;
  onClick?: () => void;
}

const BASE =
  "inline-flex min-h-11 items-center justify-center gap-2 rounded-md border px-6 text-[0.9375rem] font-semibold leading-none whitespace-nowrap cursor-pointer transition-[background-color,border-color,transform] duration-200 ease-out active:translate-y-px disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none aria-disabled:opacity-50 aria-disabled:cursor-not-allowed aria-disabled:transform-none motion-reduce:transition-none";

const VARIANTS: Record<Variant, string> = {
  primary:
    "border-accent bg-accent text-on-accent hover:border-[color-mix(in_oklch,var(--color-accent)_88%,white)] hover:bg-[color-mix(in_oklch,var(--color-accent)_88%,white)]",
  secondary: "border-line-strong bg-transparent text-ink hover:border-ink-muted hover:bg-paper-2",
};

/** Primary or secondary call-to-action button, rendered as Next Link, anchor, or button. */
export function Button({ href, variant = "secondary", className = "", children, type = "button", ...rest }: ButtonProps) {
  const classes = `${BASE} ${VARIANTS[variant]} ${className}`.trim();
  if (href) {
    return href.startsWith("/") ? (
      <Link href={href} className={classes}>
        {children}
      </Link>
    ) : (
      <a href={href} className={classes}>
        {children}
      </a>
    );
  }
  return (
    <button type={type} className={classes} {...rest}>
      {children}
    </button>
  );
}
