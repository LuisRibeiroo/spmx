import { z } from "zod";

/** Schema `1` produced by `bench/run.sh`. Shared by the build script and the site. */
export const statsSchema = z.object({
  median_s: z.number().nonnegative(),
  min_s: z.number().nonnegative(),
  max_s: z.number().nonnegative(),
  stddev_s: z.number().nonnegative(),
  runs: z.number().int().positive(),
});

export const scenarioIds = ["S1", "S2", "S3", "S4", "S5", "S6"] as const;

export const diskSchema = z.object({
  worktrees: z.number().int().positive(),
  baseline_extra_per_worktree: z.number().nonnegative(),
  pspm_extra_per_worktree: z.number().nonnegative(),
});

export const scenarioSchema = z.object({
  id: z.enum(scenarioIds),
  fixture: z.string().min(1),
  network_dependent: z.boolean(),
  baseline: statsSchema.nullable(),
  pspm: statsSchema.nullable(),
  disk_bytes: diskSchema.nullable(),
});

export const benchmarkSchema = z.object({
  schema: z.literal(1),
  date: z.string().min(1),
  pspm: z.string().min(1),
  /** Set only on the layout-preview sample. Real runs never carry it. */
  sample: z.boolean().optional(),
  machine: z.object({
    chip: z.string().min(1),
    ram_gb: z.number().positive(),
    macos: z.string().min(1),
    xcode: z.string().min(1),
    swift: z.string().min(1),
  }),
  methodology: z
    .object({
      warmup: z.number().int().nonnegative(),
      runs: z.number().int().positive(),
    })
    .optional(),
  fixtures: z
    .array(z.object({ id: z.string(), repo: z.string(), commit: z.string() }))
    .optional(),
  scenarios: z.array(scenarioSchema).min(1),
});

export type BenchmarkResults = z.infer<typeof benchmarkSchema>;
export type Scenario = z.infer<typeof scenarioSchema>;
export type Stats = z.infer<typeof statsSchema>;
