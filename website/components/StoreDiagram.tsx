const WORKTREES = [
  { name: "worktree-a", y: 176 },
  { name: "worktree-b", y: 262 },
  { name: "worktree-c", y: 348 },
];

/**
 * Hand-drawn SVG: one global store cloned into N worktrees with clonefile().
 * Colours come from tokens only. The single draw animation is disabled under
 * prefers-reduced-motion (see globals.css).
 */
export function StoreDiagram({ className = "" }: { className?: string }) {
  return (
    <figure className={`not-prose my-0 ${className}`}>
      <svg
        viewBox="0 0 400 424"
        role="img"
        aria-labelledby="store-diagram-title store-diagram-desc"
        className="mx-auto h-auto w-full max-w-[26rem]"
      >
        <title id="store-diagram-title">One global store cloned into many worktrees</title>
        <desc id="store-diagram-desc">
          The global store at ~/.spmx/store holds checkouts, artifacts and prebuilts once. The clonefile
          system call clones them into the SourcePackages folder of each Git worktree, sharing disk blocks
          until a file is modified.
        </desc>

        <rect x="20" y="8" width="360" height="108" rx="10" className="fill-paper-2 stroke-accent" strokeWidth="2" />
        <text x="38" y="38" className="fill-ink font-mono" fontSize="16" fontWeight="600">
          ~/.spmx/store
        </text>
        <text x="38" y="64" className="fill-ink-muted font-mono" fontSize="12">
          checkouts/&lt;identity&gt;-&lt;revision&gt;
        </text>
        <text x="38" y="84" className="fill-ink-muted font-mono" fontSize="12">
          artifacts/&lt;identity&gt;/&lt;target&gt;
        </text>
        <text x="38" y="104" className="fill-ink-muted font-mono" fontSize="12">
          prebuilts/&lt;toolchain&gt;/&lt;package&gt;
        </text>

        {WORKTREES.map((w) => (
          <path
            key={w.name}
            d={`M40 116 C 40 ${w.y + 18}, 44 ${w.y + 32}, 80 ${w.y + 32}`}
            pathLength={1}
            fill="none"
            strokeWidth="2"
            strokeLinecap="square"
            className="diagram-line stroke-accent"
          />
        ))}
        <text x="58" y="146" className="diagram-label fill-accent-text font-mono" fontSize="13" fontWeight="600">
          clonefile()
        </text>

        {WORKTREES.map((w) => (
          <g key={w.name}>
            <rect x="80" y={w.y} width="300" height="64" rx="8" className="fill-paper stroke-line-strong" strokeWidth="1.5" />
            <text x="98" y={w.y + 26} className="fill-ink font-mono" fontSize="14" fontWeight="600">
              {w.name}
              <tspan className="fill-ink-muted" fontWeight="400" fontSize="12">{"  SourcePackages/"}</tspan>
            </text>
            <text x="98" y={w.y + 48} className="fill-ink-muted font-mono" fontSize="12">
              checkouts · artifacts · prebuilts
            </text>
          </g>
        ))}
      </svg>
      <figcaption className="sr-only">
        Diagram: the global store is cloned into every worktree with APFS copy-on-write.
      </figcaption>
    </figure>
  );
}
