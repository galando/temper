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
ARMS = ["vanilla", "careful", "careful-ask", "temper-9.7.6", "temper"]
HARD = {"partial-payments", "subscriptions", "cent-mismatch", "tenant-leak"}


def load(results):
    rows = []
    for d in sorted(os.listdir(results)):
        rp, gp = os.path.join(results, d, "run.json"), os.path.join(results, d, "grade.json")
        if os.path.exists(rp) and os.path.exists(gp):
            r, g = json.load(open(rp)), json.load(open(gp))
            mp = os.path.join(results, d, "mutation.json")
            m = json.load(open(mp)) if os.path.exists(mp) else {}
            tj = os.path.join(results, d, "tokens.json")
            tok = json.load(open(tj))["total"] if os.path.exists(tj) else {}
            pj = os.path.join(results, d, "person.jsonl")
            owner = 0
            if os.path.exists(pj):
                for line in open(pj):
                    try:
                        owner += json.loads(line).get("who") == "owner"
                    except ValueError:
                        pass
            rows.append({**r, **g, "mutation": m.get("score"), "regression": m.get("regression_caught"), "owner_questions": owner,
                         "tok_total": tok.get("total"), "tok_output": tok.get("output")})
    return rows


def table(rows):
    out = ["| Arm | Runs | Hidden pass rate | All hidden pass | Suite kept green | Outside scope | Own tests: mutation score | Own tests catch the bug again | Cost (mean) | Wall (mean) | Tokens (mean, all) | Output tokens (mean) | Lines changed |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for arm in ARMS:
        rs = [r for r in rows if r["arm"] == arm]
        if not rs:
            continue
        m = lambda k: st.mean(r[k] for r in rs)
        mut = [r["mutation"] for r in rs if r.get("mutation") is not None]
        reg = [r["regression"] for r in rs if r.get("regression") is not None]
        tt = [r["tok_total"] for r in rs if r.get("tok_total") is not None]
        to = [r["tok_output"] for r in rs if r.get("tok_output") is not None]
        out.append("| %s | %d | %.0f%% | %d/%d | %d/%d | %d/%d | %s | %s | $%.2f | %ds | %s | %s | %.0f |" % (
            arm, len(rs), 100 * m("hidden_rate"), sum(r["hidden_all"] for r in rs), len(rs),
            sum(r["suite_ok"] for r in rs), len(rs), sum(bool(r["outside_expected"]) for r in rs), len(rs),
            ("%.0f%%" % (100 * st.mean(mut))) if mut else "n/a", ("%d/%d" % (sum(reg), len(reg))) if reg else "n/a",
            m("cost_usd"), m("wall_s"), ("%.2fM" % (st.mean(tt) / 1e6)) if tt else "n/a", ("%.0fk" % (st.mean(to) / 1e3)) if to else "n/a",
            m("code_lines")))
    return out


VAGUE_ARMS = ["vanilla", "careful-ask", "careful", "temper-9.7.6", "temper"]


def vague_table(rows):
    out = ["| Arm | Runs | Ticket tests pass | Brief facts met | Brief facts asked for | Questions to the owner | Cost (mean) | Wall (mean) | Tokens (mean, all) |",
           "|---|---|---|---|---|---|---|---|---|"]
    for arm in VAGUE_ARMS:
        rs = [r for r in rows if r["arm"] == arm]
        if not rs:
            continue
        tp, tt = sum(r["ticket_pass"] for r in rs), sum(r["ticket_total"] for r in rs)
        fm, ft = sum(len(r["facts_met"]) for r in rs), sum(len(r["facts_tested"]) for r in rs)
        fa, fz = sum(len(r.get("facts_elicited", [])) for r in rs), sum(r.get("facts_total", 0) for r in rs)
        owner = sum(r.get("owner_questions", 0) for r in rs)
        toks = [r["tok_total"] for r in rs if r.get("tok_total") is not None]
        out.append("| %s | %d | %d/%d (%.0f%%) | %d/%d (%.0f%%) | %d/%d (%.0f%%) | %.1f per run | $%.2f | %ds | %s |" % (
            arm, len(rs), tp, tt, 100 * tp / max(tt, 1), fm, ft, 100 * fm / max(ft, 1), fa, fz, 100 * fa / max(fz, 1),
            owner / len(rs), st.mean(r["cost_usd"] for r in rs), st.mean(r["wall_s"] for r in rs),
            ("%.2fM" % (st.mean(toks) / 1e6)) if toks else "n/a"))
    return out


def main():
    results = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TEMPER_BENCH_RESULTS") or os.path.expanduser("~/temper-bench-results"))
    rows = load(results)
    lines = ["# Temper benchmark results", "", "%d graded runs." % len(rows), ""]
    for task in sorted({r["task"] for r in rows}):
        lines += ["## %s" % task, ""] + table([r for r in rows if r["task"] == task]) + [""]
    hard = [r for r in rows if r.get("size") == "large" or r["task"] in HARD]
    if hard:
        lines += ["## Hard tasks (features and bugs)", ""] + table(hard) + [""]
    vague = [r for r in rows if "facts_tested" in r]
    if vague:
        lines += ["## Vague tasks: what each arm found out and built", ""] + vague_table(vague) + [""]
        for task in sorted({r["task"] for r in vague}):
            lines += ["### %s" % task, ""] + vague_table([r for r in vague if r["task"] == task]) + [""]
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
