#!/usr/bin/env bash
#
# run-fixture.sh <fixture-name> — runs a seeded-defect fixture's designated /temper
# stage headlessly against a throwaway copy of the fixture, then checks whether the
# defect was actually caught: via the evidence ledger `scripts/temper` writes first,
# falling back to a keyword match on the transcript only if no evidence exists.
#
# This is Move 3 of docs/plans/v7-deterministic-spine.md: proof, not narration, that
# the pipeline catches what it claims to catch.
#
# Requires: the `claude` CLI on PATH, authenticated. Runs with
# --dangerously-skip-permissions — only ever point this at the throwaway copy this
# script makes, never at a real project. IS_SANDBOX=1 is set on the invocation because
# --dangerously-skip-permissions refuses to run as root otherwise (common on
# Docker-based CI runners) — safe here specifically because the target is always the
# disposable mktemp -d copy made above, never a real checkout.
#
# TEMPER_PLUGIN_DIR overrides which plugin checkout is loaded via --plugin-dir — used
# to baseline-run this same harness (fixtures + expect.json) against a different
# plugin version/commit (e.g. a pre-diet checkout) without duplicating the script.
#
# Exit 0 + "CAUGHT" if the seeded defect was flagged; exit 1 + "MISSED" otherwise.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="${TEMPER_PLUGIN_DIR:-$REPO_ROOT}"
FIXTURE="${1:?usage: run-fixture.sh <fixture-name>}"
FIXTURE_DIR="$REPO_ROOT/evals/fixtures/$FIXTURE"
[[ -d "$FIXTURE_DIR" ]] || { echo "FAIL: no such fixture: $FIXTURE" >&2; exit 2; }

EXPECT="$FIXTURE_DIR/expect.json"
[[ -f "$EXPECT" ]] || { echo "FAIL: $FIXTURE_DIR/expect.json missing" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "FAIL: claude CLI not on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required" >&2; exit 2; }

STAGE=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['stage'])" "$EXPECT")
COMMAND=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['command'])" "$EXPECT")
KEYWORDS=$(python3 -c "import json, sys; print('|'.join(json.load(open(sys.argv[1]))['catch_keywords']))" "$EXPECT")

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cp -r "$FIXTURE_DIR"/. "$WORKDIR"/
# Don't leak the answer key into the agent's context — it must find the defect itself.
rm -f "$WORKDIR/expect.json" "$WORKDIR/SEEDED_DEFECT.md"
cd "$WORKDIR"
git init -q . 2>/dev/null || true

TIMEOUT_BIN="timeout"
command -v timeout >/dev/null 2>&1 || TIMEOUT_BIN="gtimeout"
if ! command -v "$TIMEOUT_BIN" >/dev/null 2>&1; then
  echo "WARN: no timeout/gtimeout on PATH — running without a wall-clock cap" >&2
  TIMEOUT_BIN=""
fi

echo "Running: claude -p \"$COMMAND\" in $WORKDIR (fixture: $FIXTURE, stage: $STAGE, plugin: $PLUGIN_DIR)"
IS_SANDBOX=1 $TIMEOUT_BIN 600 claude -p "$COMMAND" \
  --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  > run.log 2>&1
CLAUDE_EXIT=$?

FOUND="no"
EVIDENCE_FILE=".temper/evidence/$STAGE.json"
if [[ -f "$EVIDENCE_FILE" ]]; then
  if python3 -c "
import json, re, sys
evidence_path, keywords = sys.argv[1], sys.argv[2]
entries = json.load(open(evidence_path))
pat = re.compile(keywords, re.I)
sys.exit(0 if any(pat.search(e.get('claim') or '') for e in entries) else 1)
" "$EVIDENCE_FILE" "$KEYWORDS" 2>/dev/null; then
    FOUND="evidence-ledger"
  fi
fi
if [[ "$FOUND" == "no" ]] && grep -qEi "$KEYWORDS" run.log 2>/dev/null; then
  FOUND="transcript-fallback"
fi

if [[ "$FOUND" != "no" ]]; then
  echo "CAUGHT: $FIXTURE ($STAGE) — defect flagged (source: $FOUND)"
  exit 0
else
  echo "MISSED: $FIXTURE ($STAGE) — defect NOT flagged (claude exit $CLAUDE_EXIT)"
  echo "--- run.log tail ---"
  tail -40 run.log
  exit 1
fi
