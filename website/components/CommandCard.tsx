import { CodeBlock } from "./CodeBlock";
import { CopyButton } from "./CopyButton";
import { TextLink } from "./TextLink";

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
        <CodeBlock padding="md" className="min-w-0 flex-1">
          <span className="text-ink-muted select-none">$ </span>
          {command}
        </CodeBlock>
        <CopyButton
          text={command}
          label="Copy command"
          eventName="command_copied"
          eventProps={{ command, title }}
        />
      </div>
      {href ? (
        <TextLink href={href} className="w-fit text-sm font-medium">
          Read the docs
        </TextLink>
      ) : null}
    </article>
  );
}
