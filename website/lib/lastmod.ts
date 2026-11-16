import { execFileSync } from "node:child_process";
import { statSync } from "node:fs";
import { dirname } from "node:path";

/**
 * Last modification time of a file: the last Git commit that touched it, or the file mtime when the file
 * has uncommitted changes or is not tracked (e.g. a shallow CI clone without history).
 * Build-time only (Node APIs).
 */
export function lastModified(...files: string[]): Date {
  let latest = new Date(0);
  for (const file of files) {
    const date = fileDate(file);
    if (date > latest) latest = date;
  }
  return latest.getTime() === 0 ? new Date() : latest;
}

function fileDate(file: string): Date {
  let mtime: Date;
  try {
    mtime = statSync(file).mtime;
  } catch {
    return new Date(0);
  }
  try {
    const cwd = dirname(file);
    const dirty = execFileSync("git", ["status", "--porcelain", "--", file], { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    if (dirty) return mtime;
    const iso = execFileSync("git", ["log", "-1", "--format=%cI", "--", file], { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    const committed = iso ? new Date(iso) : null;
    return committed && !Number.isNaN(committed.getTime()) ? committed : mtime;
  } catch {
    return mtime;
  }
}

/** Parses a benchmark/result date string, returning undefined when it is not a valid date. */
export function parseDate(value: string): Date | undefined {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}
