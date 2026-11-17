import sample from "@/content/cli-samples/hydrate.json";
import { CodeBlock } from "./CodeBlock";

interface Segment {
  t: string;
  c?: string;
  b?: boolean;
}

const CLASS: Record<string, string> = { accent: "text-accent-text", muted: "text-ink-muted", ok: "text-ok" };

/** Renders output captured from the real CLI (see content/cli-samples). Never hand-edited copy. */
export function CliSample() {
  const lines = sample.lines as Segment[][];
  return (
    <figure>
      <CodeBlock wrap aria-label={`Output of ${sample.command}`}>
        <span className="text-ink-muted select-none">$ </span>
        {sample.command}
        {"\n"}
        {lines.map((line, i) => (
          <span key={i}>
            {line.map((seg, j) => (
              <span key={j} className={`${seg.c ? CLASS[seg.c] : ""} ${seg.b ? "font-semibold" : ""}`.trim() || undefined}>
                {seg.t}
              </span>
            ))}
            {"\n"}
          </span>
        ))}
      </CodeBlock>
      <figcaption className="mt-3 text-xs text-ink-muted">
        Captured from <code className="font-mono">spmx hydrate</code> v{sample.cliVersion} on a small SwiftPM project.
        Paths shortened.
      </figcaption>
    </figure>
  );
}
