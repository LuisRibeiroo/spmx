import Link from "next/link";
import type { ReactNode } from "react";

interface TextLinkProps {
  href: string;
  className?: string;
  children: ReactNode;
  prefetch?: boolean;
}

const BASE =
  "text-accent-text underline decoration-1 underline-offset-[3px] transition-[text-decoration-color] duration-200 ease-out hover:decoration-2 motion-reduce:transition-none";

const STATIC_FILE_RE = /\.(txt|json|xml|svg|png)$/;

/** Inline accent link using Next Link for app routes and plain anchor for static assets or external URLs. */
export function TextLink({ href, className = "", children, prefetch }: TextLinkProps) {
  const classes = `${BASE} ${className}`.trim();
  if (href.startsWith("/") && !STATIC_FILE_RE.test(href)) {
    return (
      <Link href={href} className={classes} prefetch={prefetch}>
        {children}
      </Link>
    );
  }
  return (
    <a href={href} className={classes}>
      {children}
    </a>
  );
}
