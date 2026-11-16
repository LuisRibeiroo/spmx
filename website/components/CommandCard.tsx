import Link from "next/link";
import { CopyButton } from "./CopyButton";

interface Props {
  title: string;
  command: string;
  description: string;
  href?: string;
  className?: string;
  children?: React.ReactNode;
}

/** Feature card that always carries a real command. */
export function CommandCard({ title, command, description, href, className = "", children }: Props) {
  return (
    <article className={`not-prose flex flex-col gap-3 rounded-lg border border-line bg-paper p-5 ${className}`}>
      <h3 className="text-lg font-semibold tracking-tight">{title}</h3>
      <p className="text-[0.9375rem] leading-relaxed text-ink-muted">{description}</p>
      {children}
      <div className="mt-auto flex items-center gap-2 pt-1">
        <pre className="codeblock min-w-0 flex-1 !py-2.5">
          <code>
            <span className="c-muted select-none">$ </span>
            {command}
          </code>
        </pre>
        <CopyButton text={command} label="Copy command" />
      </div>
      {href ? (
        <Link href={href} className="link w-fit text-sm font-medium">
          Read the docs
        </Link>
      ) : null}
    </article>
  );
}
