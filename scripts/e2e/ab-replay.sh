#!/usr/bin/env bash
# ab-replay.sh [base-ref]: the replay of the measured run (scripts/e2e/replay.ts) on the version before a change and on
# this tree, side by side. base-ref defaults to 7c7a1c1 (9.8.4, the base of the 9.8.5 work). It checks the base out
# into a throwaway worktree, runs the same scripted agents and person against both, prints one table, and removes the
# worktree. Needs bun. Nothing here touches the project's own .temper or branches.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
BASE="${1:-7c7a1c1}"
OUT="$(mktemp -d)"
OLD="$OUT/base"
trap 'git -C "$ROOT" worktree remove --force "$OLD" >/dev/null 2>&1 || true; rm -rf "$OUT"' EXIT
git -C "$ROOT" worktree add -q --detach "$OLD" "$BASE"
# the base runs this tree's replay and harness (the driver is the measuring tool; only the CLI under test differs)
( TEMPER_E2E_ROOT="$OLD" bun "$HERE/replay.ts" base | tail -1 > "$OUT/base.json" ) &
( bun "$HERE/replay.ts" this | tail -1 > "$OUT/this.json" ) &
( REPLAY_POLICY=1 bun "$HERE/replay.ts" this+policy | tail -1 > "$OUT/policy.json" ) &
wait
python3 -I - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
runs = [json.load(open(os.path.join(out, f + ".json"))) for f in ("base", "this", "policy")]
rows = [
    ("version", lambda d: d["version"]),
    ("shipped (committed)", lambda d: "yes" if d["shipped"] else "no (" + d["ended"] + ")"),
    ("defect in the commit", lambda d: "yes" if d["defect_in_commit"] else "no"),
    ("questions to the person", lambda d: d["questions"]),
    ("repairs by hand", lambda d: len(d["manual_repairs"])),
    ("setup clicks", lambda d: d["setup_clicks"]),
    ("agent launches", lambda d: d["agent_launch_total"]),
    ("agent minutes (estimate)", lambda d: d["agent_minutes_estimate"]),
    ("loops recommended", lambda d: len(d["loops_recommended"])),
    ("build tool runs", lambda d: d["mvn_calls"]),
    ("CLI seconds (fake tools)", lambda d: d["cli_seconds"]),
]
w = max(len(r[0]) for r in rows)
print("%-*s  %14s  %14s  %14s" % (w, "", "base", "this", "this + policy"))
for name, f in rows:
    print("%-*s  %14s  %14s  %14s" % ((w, name) + tuple(str(f(d)) for d in runs)))
for d in runs:
    print("\n%s %s agents: %s" % (d["label"], d["version"], d["agent_launches"]))
    print("  repairs by hand: %s" % (d["manual_repairs"] or "none"))
PY
