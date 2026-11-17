import type { ReactNode } from "react";

interface ContainerProps {
  as?: "div" | "section";
  className?: string;
  children?: ReactNode;
  "aria-labelledby"?: string;
}

/** Centered page-width wrapper respecting horizontal safe-area insets. */
export function Container({ as: Tag = "div", className = "", children, ...rest }: ContainerProps) {
  return (
    <Tag
      className={`mx-auto w-full max-w-[1080px] px-[max(1rem,env(safe-area-inset-left))] ${className}`.trim()}
      {...rest}
    >
      {children}
    </Tag>
  );
}
