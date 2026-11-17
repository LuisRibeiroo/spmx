import type { Scenario } from "@/lib/benchmark-schema";
import { SCENARIO_TITLES, targetStatus } from "@/lib/benchmarks";
import { formatBytes, formatDuration } from "@/lib/format";
import { Chip } from "./Chip";

interface Row {
  label: string;
  median: number;
  min?: number;
  max?: number;
  text: string;
  range?: string;
  tone: "base" | "spmx";
}

function rowsFor(s: Scenario): Row[] {
  if (s.disk_bytes) {
    const d = s.disk_bytes;
    return [
      { label: "Without spmx", median: d.baseline_extra_per_worktree, text: formatBytes(d.baseline_extra_per_worktree), tone: "base" },
      { label: "With spmx", median: d.spmx_extra_per_worktree, text: formatBytes(d.spmx_extra_per_worktree), tone: "spmx" },
    ];
  }
  const out: Row[] = [];
  const mk = (label: string, st: NonNullable<Scenario["baseline"]>, tone: Row["tone"]): Row => ({
    label,
    median: st.median_s,
    min: st.min_s,
    max: st.max_s,
    text: formatDuration(st.median_s),
    range: `${formatDuration(st.min_s)} – ${formatDuration(st.max_s)} · ${st.runs} runs`,
    tone,
  });
  if (s.baseline) out.push(mk(s.id === "S5" ? "Direct binary" : s.id === "S6" ? "Cache off" : "Without spmx", s.baseline, "base"));
  if (s.spmx) out.push(mk(s.id === "S5" ? "spmx shim" : s.id === "S6" ? "Cache on" : "With spmx", s.spmx, "spmx"));
  return out;
}

const STATUS_LABEL = { met: "Target met", missed: "Target not met", informational: "" } as const;

/** Static SVG bars (no chart library): median bar, min–max whisker. */
export function BenchBars({ scenarios, compact = false }: { scenarios: Scenario[]; compact?: boolean }) {
  return (
    <div className="space-y-8">
      {scenarios.map((s) => {
        const rows = rowsFor(s);
        if (rows.length === 0) return null;
        const scaleMax = Math.max(...rows.map((r) => r.max ?? r.median));
        const info = SCENARIO_TITLES[s.id];
        const status = targetStatus(s);
        const tipId = `bench-tip-${s.id}-${s.fixture}`;
        return (
          <section key={`${s.id}-${s.fixture}`} aria-labelledby={`bench-${s.id}-${s.fixture}`}>
            <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1">
              <span className="group/tip relative inline-flex">
                <button
                  type="button"
                  aria-describedby={tipId}
                  className="cursor-help rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
                >
                  <Chip>{s.id}</Chip>
                </button>
                <span
                  id={tipId}
                  role="tooltip"
                  className="pointer-events-none invisible absolute bottom-full left-0 z-20 mb-2 w-64 rounded-md border border-line-strong bg-paper-2 px-3 py-2 text-left text-xs leading-relaxed text-ink opacity-0 shadow-sm transition-opacity duration-150 group-hover/tip:visible group-hover/tip:opacity-100 group-focus-within/tip:visible group-focus-within/tip:opacity-100 motion-reduce:transition-none"
                >
                  <span className="font-semibold text-accent-text">Scenario {s.id}:</span> {info.title} ({info.detail}).
                </span>
              </span>
              <h3 id={`bench-${s.id}-${s.fixture}`} className="text-base font-semibold">{info.title}</h3>
              <Chip weight="normal" className="font-mono">{s.fixture}</Chip>
              {s.network_dependent ? <Chip>network-dependent</Chip> : null}
              {status !== "informational" ? (
                <Chip tone={status === "met" ? "ok" : "warn"}>{STATUS_LABEL[status]}</Chip>
              ) : null}
            </div>
            {compact ? null : <p className="mb-3 text-sm text-ink-muted">{info.detail}</p>}
            <div className="grid grid-cols-[6.5rem_1fr] items-center gap-x-3 gap-y-2 sm:grid-cols-[8rem_1fr_12rem]">
              {rows.map((r) => {
                const w = (r.median / scaleMax) * 100;
                const lo = r.min !== undefined ? (r.min / scaleMax) * 100 : null;
                const hi = r.max !== undefined ? (r.max / scaleMax) * 100 : null;
                const aria = `${r.label}: median ${r.text}${r.range ? `, range ${r.range}` : ""}`;
                return (
                  <div key={r.label} className="contents">
                    <span className="text-sm text-ink-muted">{r.label}</span>
                    <svg
                      role="img"
                      aria-label={aria}
                      viewBox="0 0 100 14"
                      preserveAspectRatio="none"
                      className="h-4 w-full overflow-visible"
                    >
                      <rect x="0" y="0" width="100" height="14" className="fill-paper-2" />
                      <rect x="0" y="0" width={Math.max(w, 0.6)} height="14" className={r.tone === "spmx" ? "fill-accent" : "fill-line-strong"} />
                      {lo !== null && hi !== null ? (
                        <g className="stroke-ink" strokeWidth="1.5" vectorEffect="non-scaling-stroke">
                          <line x1={lo} x2={hi} y1="7" y2="7" vectorEffect="non-scaling-stroke" />
                          <line x1={lo} x2={lo} y1="3" y2="11" vectorEffect="non-scaling-stroke" />
                          <line x1={hi} x2={hi} y1="3" y2="11" vectorEffect="non-scaling-stroke" />
                        </g>
                      ) : null}
                    </svg>
                    <span className="col-span-2 -mt-1 mb-1 text-sm tabular-nums sm:col-span-1 sm:mt-0 sm:mb-0">
                      <span className="font-semibold">{r.text}</span>
                      {!compact && r.range ? <span className="block text-xs text-ink-muted">{r.range}</span> : null}
                    </span>
                  </div>
                );
              })}
            </div>
          </section>
        );
      })}
    </div>
  );
}
