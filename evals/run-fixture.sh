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
# Two keyword sets, both required (AND, not OR): anchor_keywords are specific enough to
# identify THIS defect uniquely (a scenario name, a symbol, a component name);
# signal_keywords are generic descriptive terms ("missing", "unused") that are only
# meaningful once co-occurring with an anchor. Either alone is a false-positive risk —
# an anchor can appear in unrelated boilerplate, a signal word matches almost anything.
ANCHOR_KEYWORDS=$(python3 -c "import json, sys; print('|'.join(json.load(open(sys.argv[1]))['anchor_keywords']))" "$EXPECT")
SIGNAL_KEYWORDS=$(python3 -c "import json, sys; print('|'.join(json.load(open(sys.argv[1]))['signal_keywords']))" "$EXPECT")

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

# Tier 1 (strongest): the recorded evidence carries the SPECIFIC property that makes
# `temper gate <stage>` actually FAIL for it — not just text matching the keywords.
# review: severity must be in the default block-on list (critical). check: the row
# must be a --scenario entry with a nonzero exit_code (uncovered). This directly
# mirrors gate_review()/gate_check() in scripts/temper — a keyword match alone proves
# nothing about whether the gate would have blocked a commit, only that matching text
# exists somewhere in a claim string. Requiring BOTH an anchor and a signal match (not
# either alone) narrows a claim like "coverage looks fine, nothing missing" from
# falsely matching a lone "missing" signal word with no anchor identifying this defect.
if [[ -f "$EVIDENCE_FILE" ]]; then
  if python3 -c "
import json, re, sys
evidence_path, anchor_kw, signal_kw, stage = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
entries = json.load(open(evidence_path))
anchor_pat = re.compile(anchor_kw, re.I)
signal_pat = re.compile(signal_kw, re.I)
def blocks_gate(e):
    claim = e.get('claim') or ''
    if not (anchor_pat.search(claim) and signal_pat.search(claim)):
        return False
    if stage == 'review':
        return e.get('severity') == 'critical'
    if stage == 'check':
        return e.get('scenario') and e.get('exit_code') not in (0, None)
    return e.get('exit_code') not in (0, None)
sys.exit(0 if any(blocks_gate(e) for e in entries) else 1)
" "$EVIDENCE_FILE" "$ANCHOR_KEYWORDS" "$SIGNAL_KEYWORDS" "$STAGE" 2>/dev/null; then
    FOUND="gate-blocking-evidence"
  fi
fi

# Tier 2: evidence exists and its claim text matches both anchor and signal, but not
# in a way that would have failed the gate (e.g. recorded at a non-blocking severity)
# — worth knowing separately from tier 1, not the same claim strength.
if [[ "$FOUND" == "no" && -f "$EVIDENCE_FILE" ]]; then
  if python3 -c "
import json, re, sys
entries = json.load(open(sys.argv[1]))
anchor_pat = re.compile(sys.argv[2], re.I)
signal_pat = re.compile(sys.argv[3], re.I)
def matches(e):
    claim = e.get('claim') or ''
    return bool(anchor_pat.search(claim) and signal_pat.search(claim))
sys.exit(0 if any(matches(e) for e in entries) else 1)
" "$EVIDENCE_FILE" "$ANCHOR_KEYWORDS" "$SIGNAL_KEYWORDS" 2>/dev/null; then
    FOUND="evidence-non-blocking"
  fi
fi

# Tier 3 (weakest): only the raw transcript mentions it — no evidence was ever
# recorded, so `temper gate` never saw this at all. Real for v6.0.1 (no CLI exists);
# a warning sign for v7 (the agent found it but never called `temper evidence add`).
# Same anchor+signal co-occurrence requirement — a transcript is long free text where a
# lone generic word like "missing" or "unused" is even more likely to false-positive
# than a structured evidence claim.
if [[ "$FOUND" == "no" ]] && grep -qEi "$ANCHOR_KEYWORDS" run.log 2>/dev/null && grep -qEi "$SIGNAL_KEYWORDS" run.log 2>/dev/null; then
  FOUND="transcript-fallback"
fi

# Pass bar: STRICT by default (tier 1 only — "would this have mechanically blocked a
# commit"), which is the actual guarantee v7 makes and what CI should enforce on every
# prompt change. Set TEMPER_EVAL_ACCEPT_ANY_TIER=1 to accept tiers 2-3 too — needed
# for a v6.0.1 baseline comparison, since v6.0.1 has no CLI and tier 1 is structurally
# unreachable there; NOT for judging v7 itself, where accepting a weaker tier would
# let a real regression (found the bug, stopped recording it as blocking) pass silently.
PASS_BAR_MET="no"
if [[ "$FOUND" == "gate-blocking-evidence" ]]; then
  PASS_BAR_MET="yes"
elif [[ "$FOUND" != "no" && "${TEMPER_EVAL_ACCEPT_ANY_TIER:-0}" == "1" ]]; then
  PASS_BAR_MET="yes"
fi

if [[ "$PASS_BAR_MET" == "yes" ]]; then
  echo "CAUGHT: $FIXTURE ($STAGE) — defect flagged (source: $FOUND)"
  exit 0
elif [[ "$FOUND" != "no" ]]; then
  echo "MISSED: $FIXTURE ($STAGE) — defect noticed but NOT gate-blocking (source: $FOUND) — set TEMPER_EVAL_ACCEPT_ANY_TIER=1 to accept this tier (e.g. for a pre-CLI baseline comparison)"
  echo "--- run.log tail ---"
  tail -40 run.log
  exit 1
else
  echo "MISSED: $FIXTURE ($STAGE) — defect NOT flagged at all (claude exit $CLAUDE_EXIT)"
  echo "--- run.log tail ---"
  tail -40 run.log
  exit 1
fi
