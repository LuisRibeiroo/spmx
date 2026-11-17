import type { ReactNode } from "react";

type Padding = "sm" | "md" | "lg" | "base";

interface CodeBlockProps {
  children: ReactNode;
  padding?: Padding;
  wrap?: boolean;
  responsiveText?: boolean;
  className?: string;
  "aria-label"?: string;
}

const PADDINGS: Record<Padding, string> = {
  sm: "px-4 py-2",
  md: "px-4 py-2.5",
  lg: "px-4 py-3",
  base: "p-4",
};

/** Preformatted CLI/code block outside MDX without fake window chrome. */
export function CodeBlock({
  children,
  padding = "base",
  wrap = false,
  responsiveText = false,
  className = "",
  ...rest
}: CodeBlockProps) {
  const ws = wrap ? "whitespace-pre-wrap [overflow-wrap:anywhere]" : "whitespace-pre";
  const textSize = responsiveText ? "text-xs sm:text-[0.8125rem]" : "text-[0.8125rem]";
  return (
    <pre
      className={`overflow-x-auto rounded-md border border-line bg-paper-2 font-mono leading-[1.65] [tab-size:2] ${PADDINGS[padding]} ${ws} ${textSize} ${className}`.trim()}
      {...rest}
    >
      <code>{children}</code>
    </pre>
  );
}
