import raw from "@/content/benchmarks/latest.json";
import { benchmarkSchema, type BenchmarkResults, type Scenario } from "./benchmark-schema";

// Parsed at module load: an invalid or missing JSON fails the build (FR-2 / US-003).
export const results: BenchmarkResults = benchmarkSchema.parse(raw);

/** Targets from tasks/prd-spmx-cli.md §7. Thresholds, not measurements. */
export const TARGETS = {
  hydrateReduction: 0.9,
  diskBytesPerWorktree: 5_000_000,
  shimOverheadSeconds: 0.005,
  coldRegressionTolerance: 1.05,
} as const;

export const SCENARIO_TITLES: Record<Scenario["id"], { title: string; detail: string }> = {
  S1: { title: "Cold, no cache", detail: "spmx must not make a cold resolve slower" },
  S2: { title: "New worktree, SwiftPM cache warm", detail: "same command in both modes" },
  S3: { title: "New worktree, spmx store warm", detail: "native resolve vs spmx hydrate" },
  S4: { title: "Disk per extra worktree", detail: "physical bytes on an isolated APFS volume" },
  S5: { title: "Shim overhead", detail: "direct binary vs spmx shim, no-op command" },
  S6: { title: "Clean build in 2nd worktree", detail: "LLVM CAS compilation cache off vs on" },
};

/** A scenario can have several entries, one per fixture. */
export function entries(id: Scenario["id"]): Scenario[] {
  return results.scenarios.filter((s) => s.id === id);
}

export function scenario(id: Scenario["id"]): Scenario | undefined {
  return entries(id)[0];
}

export const isSample = results.sample === true;
export const machine = results.machine;

export interface Headline {
  baselineSeconds: number;
  spmxSeconds: number;
  reduction: number;
  runs: number;
  fixture: string;
  /** Only a met target is promoted to a headline claim. */
  promoted: boolean;
}

export function hydrateHeadline(): Headline | null {
  const s = scenario("S3");
  if (!s?.baseline || !s.spmx) return null;
  const reduction = 1 - s.spmx.median_s / s.baseline.median_s;
  return {
    baselineSeconds: s.baseline.median_s,
    spmxSeconds: s.spmx.median_s,
    reduction,
    runs: s.spmx.runs,
    fixture: s.fixture,
    promoted: reduction >= TARGETS.hydrateReduction,
  };
}

export function diskResult() {
  const s = scenario("S4");
  if (!s?.disk_bytes) return null;
  return {
    ...s.disk_bytes,
    promoted: s.disk_bytes.spmx_extra_per_worktree < TARGETS.diskBytesPerWorktree,
  };
}

/** Worst case across S5 entries, so a headline never hides the slowest tool. */
export function shimResult() {
  const measured = entries("S5").filter((e) => e.baseline && e.spmx);
  if (measured.length === 0) return null;
  const s = measured.reduce((worst, e) =>
    e.spmx!.median_s - e.baseline!.median_s > worst.spmx!.median_s - worst.baseline!.median_s ? e : worst,
  );
  const overheadSeconds = s.spmx!.median_s - s.baseline!.median_s;
  return {
    baselineSeconds: s.baseline!.median_s,
    spmxSeconds: s.spmx!.median_s,
    overheadSeconds,
    promoted: overheadSeconds < TARGETS.shimOverheadSeconds,
  };
}

export function targetStatus(s: Scenario): "met" | "missed" | "informational" {
  if (s.id === "S3" && s.baseline && s.spmx)
    return 1 - s.spmx.median_s / s.baseline.median_s >= TARGETS.hydrateReduction ? "met" : "missed";
  if (s.id === "S4" && s.disk_bytes)
    return s.disk_bytes.spmx_extra_per_worktree < TARGETS.diskBytesPerWorktree ? "met" : "missed";
  if (s.id === "S5" && s.baseline && s.spmx)
    return s.spmx.median_s - s.baseline.median_s < TARGETS.shimOverheadSeconds ? "met" : "missed";
  if (s.id === "S1" && s.baseline && s.spmx)
    return s.spmx.median_s <= s.baseline.median_s * TARGETS.coldRegressionTolerance ? "met" : "missed";
  return "informational";
}
