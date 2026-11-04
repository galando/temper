#!/usr/bin/env python3
"""report.py [RESULTS_DIR]: one table per task and one overall, from every run.json + grade.json. Standard library only.

Columns per arm: runs, the mean hidden test pass rate, how many runs passed every hidden test, how many kept the
original suite green, how many changed a file outside the expected paths, the mean cost and wall time, the mean
lines of code changed. Writes RESULTS_DIR/report.md and prints it.
"""
import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARMS = ["vanilla", "careful", "temper"]


def load(results):
    rows = []
    for d in sorted(os.listdir(results)):
        rp, gp = os.path.join(results, d, "run.json"), os.path.join(results, d, "grade.json")
        if os.path.exists(rp) and os.path.exists(gp):
            r, g = json.load(open(rp)), json.load(open(gp))
            rows.append({**r, **g})
    return rows


def table(rows):
    out = ["| Arm | Runs | Hidden pass rate | All hidden pass | Suite kept green | Outside scope | Cost (mean) | Wall (mean) | Lines changed |",
           "|---|---|---|---|---|---|---|---|---|"]
    for arm in ARMS:
        rs = [r for r in rows if r["arm"] == arm]
        if not rs:
            continue
        m = lambda k: st.mean(r[k] for r in rs)
        out.append("| %s | %d | %.0f%% | %d/%d | %d/%d | %d/%d | $%.2f | %ds | %.0f |" % (
            arm, len(rs), 100 * m("hidden_rate"), sum(r["hidden_all"] for r in rs), len(rs),
            sum(r["suite_ok"] for r in rs), len(rs), sum(bool(r["outside_expected"]) for r in rs), len(rs),
            m("cost_usd"), m("wall_s"), m("code_lines")))
    return out


def main():
    results = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TEMPER_BENCH_RESULTS") or os.path.expanduser("~/temper-bench-results"))
    rows = load(results)
    lines = ["# Temper benchmark results", "", "%d graded runs." % len(rows), ""]
    for task in sorted({r["task"] for r in rows}):
        lines += ["## %s" % task, ""] + table([r for r in rows if r["task"] == task]) + [""]
    lines += ["## All tasks", ""] + table(rows) + [""]
    ended = [r for r in rows if r.get("ended") != "done"]
    if ended:
        lines += ["Runs that did not end cleanly: " + ", ".join("%s/%s/%s (%s)" % (r["task"], r["arm"], r["rep"], r["ended"]) for r in ended), ""]
    text = "\n".join(lines)
    with open(os.path.join(results, "report.md"), "w") as f:
        f.write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
