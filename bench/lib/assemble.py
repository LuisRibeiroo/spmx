#!/usr/bin/python3
"""Builds bench/results JSON (schema 1) from hyperfine exports.

usage: assemble.py <work-dir> <env.json> <fixtures.json> <out.json> <warmup> <runs> [<previous-latest.json>]

When a previous results file from the same chip is given, scenario entries it holds for
(id, fixture) pairs that were not re-run are kept, so partial runs refine latest.json.

<work-dir> holds:  <ID>__<fixture>__{baseline,spmx}.json   (hyperfine --export-json)
                   S4__<fixture>.json                      ({"worktrees", "baseline", "spmx"} in bytes)
"""
import datetime, json, pathlib, sys

work, env_path, fixtures_path, out_path, warmup, default_runs = sys.argv[1:7]
previous_path = sys.argv[7] if len(sys.argv) > 7 else None
work = pathlib.Path(work)
env = json.load(open(env_path))
fixtures = json.load(open(fixtures_path))["fixtures"]

NETWORK = {"S1": True, "S2": True}
ORDER = {f"S{i}": i for i in range(1, 7)}


def stats(path):
    """Reads a hyperfine export. Supports hyperfine 1.x (flat) and 2.x (summary.time_wall_clock)."""
    r = json.load(open(path))["results"][0]
    if "summary" in r:
        w = r["summary"]["time_wall_clock"]
        return {
            "median_s": w["median"], "min_s": w["min"], "max_s": w["max"],
            "stddev_s": w.get("stddev") or 0.0, "runs": int(w["count"]),
        }
    return {
        "median_s": r["median"], "min_s": r["min"], "max_s": r["max"],
        "stddev_s": r["stddev"] or 0.0, "runs": len(r["times"]),
    }


scenarios = []
for base in sorted(work.glob("S*__*__baseline.json")):
    sid, fixture, _ = base.stem.split("__")
    scenarios.append({
        "id": sid, "fixture": fixture, "network_dependent": NETWORK.get(sid, False),
        "baseline": stats(base), "spmx": stats(work / f"{sid}__{fixture}__spmx.json"), "disk_bytes": None,
    })
for disk in sorted(work.glob("S4__*.json")):
    if "__baseline" in disk.stem or "__spmx" in disk.stem:
        continue
    fixture = disk.stem.split("__")[1]
    d = json.load(open(disk))
    scenarios.append({
        "id": "S4", "fixture": fixture, "network_dependent": False, "baseline": None, "spmx": None,
        "disk_bytes": {
            "worktrees": d["worktrees"],
            "baseline_extra_per_worktree": d["baseline"],
            "spmx_extra_per_worktree": d["spmx"],
        },
    })
if not scenarios:
    sys.exit("assemble.py: no scenario results found in " + str(work))
if previous_path and pathlib.Path(previous_path).exists():
    previous = json.load(open(previous_path))
    if previous.get("machine", {}).get("chip") == env["machine"]["chip"] and not previous.get("sample"):
        fresh = {(s["id"], s["fixture"]) for s in scenarios}
        scenarios += [s for s in previous["scenarios"] if (s["id"], s["fixture"]) not in fresh]

scenarios.sort(key=lambda s: (ORDER[s["id"]], s["fixture"]))

used = {s["fixture"] for s in scenarios}
out = {
    "schema": 1,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "spmx": env["spmx"],
    "machine": env["machine"],
    "methodology": {"warmup": int(warmup), "runs": int(default_runs)},
    "fixtures": [{"id": f["id"], "repo": f["repo"], "commit": f["commit"]} for f in fixtures if f["id"] in used],
    "scenarios": scenarios,
}
json.dump(out, open(out_path, "w"), indent=2)
open(out_path, "a").write("\n")
print(f"wrote {out_path} ({len(scenarios)} scenario entries)")
