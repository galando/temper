#!/usr/bin/env bash
#
# run-wiring-smoke.sh — proves /temper:plan and /temper:build actually call
# `temper evidence add` / `temper gate <stage>` when a real model runs them
# standalone. Unlike run-fixture.sh, there's no seeded defect and no CAUGHT/MISSED
# verdict — this only checks that each stage's gate was actually invoked for real
# (`.temper/gates.json` has a real verdict, not MISSING) and that evidence/state was
# actually recorded. `review`/`check` wiring is already covered live by
# evals/run-fixture.sh's seeded-defect fixtures; this fills the remaining gap —
# see "Known limitations" in evals/README.md.
# (v8.0.0: the Eval stage was removed from the pipeline; this probe no longer runs
# /temper:eval or asserts an eval gate verdict — see CHANGELOG.md's v8.0.0 migration
# note. plan/build wiring coverage is unchanged.)
#
# Requires: the `claude` CLI on PATH, authenticated. IS_SANDBOX=1 is set for the same
# --dangerously-skip-permissions-refuses-root reason as run-fixture.sh — safe here only
# because the target is always the disposable mktemp -d copy made below.
#
# Exit 0 if plan/build are wired correctly; exit 1 if any gap is found.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="${TEMPER_PLUGIN_DIR:-$REPO_ROOT}"
FIXTURE_DIR="$REPO_ROOT/evals/wiring-smoke"
[[ -d "$FIXTURE_DIR" ]] || { echo "FAIL: no wiring-smoke fixture at $FIXTURE_DIR" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "FAIL: claude CLI not on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required" >&2; exit 2; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cp -r "$FIXTURE_DIR"/. "$WORKDIR"/
rm -f "$WORKDIR/WIRING_CHECK.md"
cd "$WORKDIR"
git init -q . 2>/dev/null || true

TIMEOUT_BIN="timeout"
command -v timeout >/dev/null 2>&1 || TIMEOUT_BIN="gtimeout"
if ! command -v "$TIMEOUT_BIN" >/dev/null 2>&1; then
  echo "WARN: no timeout/gtimeout on PATH — running without a wall-clock cap" >&2
  TIMEOUT_BIN=""
fi

run_stage() { # run_stage <label> <slash-command>
  local label="$1" cmd="$2"
  echo "Running: claude -p \"$cmd\" in $WORKDIR (wiring-smoke, stage: $label, plugin: $PLUGIN_DIR)"
  IS_SANDBOX=1 $TIMEOUT_BIN 600 claude -p "$cmd" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    > "run.$label.log" 2>&1
  echo "  claude exit: $? (see run.$label.log in $WORKDIR if inspecting before cleanup)"
}

FEATURE='add a version() function to src/app.js returning the package.json version string, with a test'

run_stage plan "/temper:plan $FEATURE"

run_stage build "/temper:build"

echo ""
echo "=== gates.json wiring check (was temper gate <stage> actually invoked?) ==="
python3 -c "
import json, sys
try:
    gates = json.load(open('.temper/gates.json'))
except Exception:
    gates = {}
missing = []
for s in ('plan', 'build'):
    v = gates.get(s, {}).get('verdict', 'MISSING')
    print(f'  {s}: {v}')
    if v == 'MISSING':
        missing.append(s)
sys.exit(1 if missing else 0)
"
GATES_OK=$?

echo ""
echo "=== evidence wiring check (was temper evidence add actually called?) ==="
python3 -c "
import json, os, sys
missing = []
for s in ('build',):
    p = f'.temper/evidence/{s}.json'
    if not os.path.exists(p):
        print(f'  {s}: no evidence file at all')
        missing.append(s)
        continue
    try:
        entries = json.load(open(p))
    except Exception:
        entries = []
    print(f'  {s}: {len(entries)} entr' + ('y' if len(entries) == 1 else 'ies'))
    if not entries:
        missing.append(s)
sys.exit(1 if missing else 0)
"
EVIDENCE_OK=$?

echo ""
COMPLEXITY="$("$PLUGIN_DIR/scripts/temper" state get complexity 2>/dev/null)"
if [[ -n "$COMPLEXITY" ]]; then
  echo "  plan: temper state set complexity was called (complexity=$COMPLEXITY)"
  COMPLEXITY_OK=0
else
  echo "  plan: temper state set complexity was NEVER called"
  COMPLEXITY_OK=1
fi

echo ""
if [[ "$GATES_OK" -eq 0 && "$EVIDENCE_OK" -eq 0 && "$COMPLEXITY_OK" -eq 0 ]]; then
  echo "WIRED: plan/build both called temper evidence add / temper gate for real"
  exit 0
else
  echo "GAP: one or more stages never called the CLI — inspect run.plan.log / run.build.log before this workdir is cleaned up"
  exit 1
fi
