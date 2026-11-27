#!/usr/bin/env python3
"""replay_compare.py: the table of the A/B replay, and the gate on it (9.8.5, WP32; done.md rows D58 and D59).

  python3 scripts/e2e/replay_compare.py BASE.json THIS.json

BASE.json and THIS.json each hold the last line `bun scripts/e2e/replay.ts <label>` printed: one JSON object of the
replay of the measured run, the first on the version before (the base), the second on this tree. It prints the table
`scripts/e2e/ab-replay.sh` printed before this file held its code, then the agents and the repairs by hand of each side,
then one line `replay_compare: PASS` or `replay_compare: FAIL (<n>)` after one `WORSE:` line a row.

Counted, each lower or equal on this tree: `questions`, the length of `manual_repairs`, `agent_launch_total`,
`agent_minutes_estimate`, the length of `loops_recommended`, `setup_clicks`. Must hold on this tree: `shipped` is true
and `defect_in_commit` is false. Printed only, never compared: `version`, `mvn_calls` (the baseline of the suite on the
base adds a run of the build tool on purpose) and `cli_seconds` (machine time, which follows the load of the machine).

Exit 0 when no counted number of THIS is above BASE and both must rows hold, 1 when one is worse, 2 for a wrong call
(a file that is missing or holds no JSON object, or a key either side lacks). Standard library only.
"""
import json
import sys

# (row, key, how the cell is printed); a counted row is compared by the number its function gives
COUNTED = [
    ("questions to the person", "questions", lambda d: d["questions"]),
    ("repairs by hand", "manual_repairs", lambda d: len(d["manual_repairs"])),
    ("setup clicks", "setup_clicks", lambda d: d["setup_clicks"]),
    ("agent launches", "agent_launch_total", lambda d: d["agent_launch_total"]),
    ("agent minutes (estimate)", "agent_minutes_estimate", lambda d: d["agent_minutes_estimate"]),
    ("loops recommended", "loops_recommended", lambda d: len(d["loops_recommended"])),
]
ROWS = [
    ("version", "version", lambda d: d["version"]),
    ("shipped (committed)", "shipped", lambda d: "yes" if d["shipped"] else "no (%s)" % d.get("ended", "not committed")),
    ("defect in the commit", "defect_in_commit", lambda d: "yes" if d["defect_in_commit"] else "no"),
] + COUNTED + [
    ("build tool runs", "mvn_calls", lambda d: d["mvn_calls"]),
    ("CLI seconds (fake tools)", "cli_seconds", lambda d: d["cli_seconds"]),
]


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit("replay_compare: %s holds no result line of replay.ts (%s)" % (path, e))
    if not isinstance(d, dict):
        raise SystemExit("replay_compare: %s holds no JSON object" % path)
    return d


def table(base, this):
    w = max(len(r[0]) for r in ROWS)
    out = ["%-*s  %14s  %14s" % (w, "", "base", "this")]
    for name, _, f in ROWS:
        out.append("%-*s  %14s  %14s" % (w, name, f(base), f(this)))
    for d in (base, this):
        out.append("")
        out.append("%s %s agents: %s" % (d.get("label", ""), d["version"], d.get("agent_launches", {})))
        out.append("  repairs by hand: %s" % (d["manual_repairs"] or "none"))
    return out


def worse(base, this):
    """The lines that say how THIS is worse than BASE; none when it is not."""
    out = []
    for name, key, f in COUNTED:
        if f(this) > f(base):
            out.append("WORSE: %s (%s) is %s on this tree and %s on the base" % (name, key, f(this), f(base)))
    if this["shipped"] is not True:
        out.append("WORSE: shipped (shipped) is false on this tree: the change was not committed (%s)"
                   % this.get("ended", "no end recorded"))
    if this["defect_in_commit"] is not False:
        out.append("WORSE: defect in the commit (defect_in_commit) is true on this tree: the High defect was committed")
    return out


def main(argv):
    if len(argv) != 2:
        print("usage: python3 scripts/e2e/replay_compare.py BASE.json THIS.json", file=sys.stderr)
        return 2
    base, this = load(argv[0]), load(argv[1])
    keys = [k for _, k, _ in ROWS]
    lack = ["%s lacks %s" % (p, k) for p, d in zip(argv, (base, this)) for k in keys if k not in d]
    if lack:
        print("replay_compare: %s" % "; ".join(lack), file=sys.stderr)
        return 2
    for line in table(base, this):
        print(line)
    bad = worse(base, this)
    print("")
    for line in bad:
        print(line)
    print("replay_compare: %s" % ("FAIL (%d)" % len(bad) if bad else "PASS: no counted number is above the base"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
