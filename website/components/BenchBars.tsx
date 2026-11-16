import type { Scenario } from "@/lib/benchmark-schema";
import { SCENARIO_TITLES, targetStatus } from "@/lib/benchmarks";
import { formatBytes, formatDuration } from "@/lib/format";

interface Row {
  label: string;
  median: number;
  min?: number;
  max?: number;
  text: string;
  range?: string;
  tone: "base" | "pspm";
}

function rowsFor(s: Scenario): Row[] {
  if (s.disk_bytes) {
    const d = s.disk_bytes;
    return [
      { label: "Without pspm", median: d.baseline_extra_per_worktree, text: formatBytes(d.baseline_extra_per_worktree), tone: "base" },
      { label: "With pspm", median: d.pspm_extra_per_worktree, text: formatBytes(d.pspm_extra_per_worktree), tone: "pspm" },
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
  if (s.baseline) out.push(mk(s.id === "S5" ? "Direct binary" : s.id === "S6" ? "Cache off" : "Without pspm", s.baseline, "base"));
  if (s.pspm) out.push(mk(s.id === "S5" ? "pspm shim" : s.id === "S6" ? "Cache on" : "With pspm", s.pspm, "pspm"));
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
        return (
          <section key={`${s.id}-${s.fixture}`} aria-labelledby={`bench-${s.id}-${s.fixture}`}>
            <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1">
              <span className="chip">{s.id}</span>
              <h3 id={`bench-${s.id}-${s.fixture}`} className="text-base font-semibold">{info.title}</h3>
              <span className="chip font-mono !font-normal">{s.fixture}</span>
              {s.network_dependent ? <span className="chip">network-dependent</span> : null}
              {status !== "informational" ? (
                <span className={`chip ${status === "met" ? "!text-ok" : "!text-warn"}`}>{STATUS_LABEL[status]}</span>
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
                      <rect x="0" y="0" width={Math.max(w, 0.6)} height="14" className={r.tone === "pspm" ? "fill-accent" : "fill-line-strong"} />
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
