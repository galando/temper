#!/usr/bin/env python3
"""bench_lines.py: the bench step of `verify.sh final`, the lines of part H of docs/plans/one-go/done.md read from the
scorecard of the bench round (bench/scorecard.py --gate), 9.8.5.

  python3 -I scripts/bench_lines.py SCORECARD [ACCEPTED]

Every line of the scorecard must pass. A line that missed passes this step only when ACCEPTED (a JSON file the owner
keeps, docs/evidence/bench-accepted-9.8.5.json) holds an entry for it whose measured numbers are the very numbers of
the scorecard and that gives a reason: the owner accepted that measure, and a later round that measures worse is not
accepted by it. Each line is printed as it was measured: pass, MISS, MISS accepted, or no data.
Exit 0 when every line passes or is accepted, else 1. Standard library only.
"""
import json
import sys

# the measured numbers of a line that an acceptance must name, as the scorecard writes them
KEYS = ("cost_ratio", "time_ratio", "runs_over_dialogs", "rate", "share", "mean")


def load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def measured(line):
    out = {k: line[k] for k in KEYS if k in line}
    med = (line.get("dialogs") or {}).get("median") if isinstance(line.get("dialogs"), dict) else None
    if med is not None:
        out["dialogs_median"] = med
    return out


def accepted(acc, name, line):
    """The reason of the owner's entry for the line, when it names the line's very numbers; else ''."""
    for e in (acc.get("accepted") or []) if isinstance(acc, dict) else []:
        if (isinstance(e, dict) and e.get("line") == name and str(e.get("reason") or "").strip()
                and e.get("measured") == measured(line)):
            return str(e["reason"]).strip()
    return ""


def main(argv):
    if len(argv) not in (1, 2):
        print("usage: bench_lines.py SCORECARD [ACCEPTED]", file=sys.stderr)
        return 2
    lines = (load(argv[0], {}) or {}).get("lines") or {}
    acc = load(argv[1], {}) if len(argv) > 1 else {}
    bad, took = [], []
    for k, v in sorted(lines.items()):
        p = v.get("pass") if isinstance(v, dict) else None
        if p is True:
            print("%-10s pass" % k)
        elif p is False and accepted(acc, k, v):
            took.append(k)
            print("%-10s MISS accepted by the owner: %s" % (k, accepted(acc, k, v)))
        else:
            bad.append(k)
            print("%-10s %s" % (k, "MISS" if p is False else "no data"))
    if lines and not bad:
        print("bench: every line of part H passes" if not took else
              "bench: no line outside part H but %s, missed as measured and accepted by the owner" % ", ".join(took))
        return 0
    print("bench: outside the lines of part H: %s" % (", ".join(bad) or "no line"))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
