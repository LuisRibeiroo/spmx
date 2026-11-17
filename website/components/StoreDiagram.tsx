const PROJECTS = [
  { name: "project-a", deps: "firebase 1.0.0 · stripe 3.4.5 · xyz 4.0.0", y: 204 },
  { name: "project-b", deps: "xyz 4.0.0 · abc 1.0.0", y: 290 },
  { name: "project-c", deps: "firebase 1.0.1 · stripe 3.4.5", y: 376 },
];

/**
 * Hand-drawn SVG: one global store cloned into N projects/worktrees with clonefile().
 * Colours come from tokens only. The single draw animation is disabled under
 * prefers-reduced-motion (see globals.css).
 */
export function StoreDiagram({ className = "" }: { className?: string }) {
  return (
    <figure className={`not-prose my-0 ${className}`}>
      <svg
        viewBox="0 0 420 452"
        role="img"
        aria-labelledby="store-diagram-title store-diagram-desc"
        className="mx-auto h-auto w-full max-w-[27rem]"
      >
        <title id="store-diagram-title">One global store cloned into every project on your Mac</title>
        <desc id="store-diagram-desc">
          The global store at ~/.spmx/store keeps one physical copy of each package version: firebase 1.0.0,
          firebase 1.0.1, stripe 3.4.5, xyz 4.0.0, and abc 1.0.0. APFS clonefile() clones them into
          project-a, project-b, and project-c (plus any Git worktrees), sharing disk blocks until modified.
        </desc>

        <rect x="20" y="8" width="380" height="136" rx="10" className="fill-paper-2 stroke-accent" strokeWidth="2" />
        <text x="38" y="38" className="fill-ink font-mono" fontSize="16" fontWeight="600">
          ~/.spmx/store
        </text>
        <text x="38" y="64" className="fill-ink-muted font-mono" fontSize="12">
          firebase @ 1.0.0   firebase @ 1.0.1
        </text>
        <text x="38" y="84" className="fill-ink-muted font-mono" fontSize="12">
          stripe @ 3.4.5     xyz @ 4.0.0     abc @ 1.0.0
        </text>
        <text x="38" y="106" className="fill-ink-muted font-mono" fontSize="11">
          repositories/ · checkouts/ · artifacts/ · prebuilts/
        </text>
        <text x="38" y="128" className="fill-accent-text font-mono" fontSize="11" fontWeight="600">
          1 physical copy per (package, version)
        </text>

        {PROJECTS.map((p) => (
          <path
            key={p.name}
            d={`M40 144 C 40 ${p.y + 18}, 44 ${p.y + 32}, 80 ${p.y + 32}`}
            pathLength={1}
            fill="none"
            strokeWidth="2"
            strokeLinecap="square"
            className="diagram-line stroke-accent"
          />
        ))}
        <text x="58" y="174" className="diagram-label fill-accent-text font-mono" fontSize="13" fontWeight="600">
          clonefile()
        </text>

        {PROJECTS.map((p) => (
          <g key={p.name}>
            <rect x="80" y={p.y} width="320" height="64" rx="8" className="fill-paper stroke-line-strong" strokeWidth="1.5" />
            <text x="98" y={p.y + 26} className="fill-ink font-mono" fontSize="14" fontWeight="600">
              {p.name}
              <tspan className="fill-ink-muted" fontWeight="400" fontSize="12">{"  SourcePackages/"}</tspan>
            </text>
            <text x="98" y={p.y + 48} className="fill-ink-muted font-mono" fontSize="11.5">
              {p.deps}
            </text>
          </g>
        ))}
      </svg>
      <figcaption className="sr-only">
        Diagram: ~/.spmx/store clones shared package versions into project-a, project-b, and project-c with APFS copy-on-write.
      </figcaption>
    </figure>
  );
}
