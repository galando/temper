#!/usr/bin/env bash
#
# verify-stage-gate.sh — Stop half of the standalone-stage gate guarantee.
#
# If stage-marker.sh recorded a pending stage for this session, refuse to let the
# session end (exit 2, reason on stderr) until .temper/gates.json carries a verdict
# for that stage. Any verdict satisfies it — PASS or FAIL — because what this enforces
# is that `temper gate <stage>` was actually invoked, not that it succeeded; a FAIL
# verdict is the interactive gate's problem, not this hook's. Appends one line per
# firing to .temper/hooks.log so a live run leaves a checkable trace.
#
# Loop guard, two layers: after MAX_BLOCKS refusals (counted in the marker itself) the
# hook fails open — a model that cannot satisfy the gate (broken CLI, read-only disk)
# must not be trapped in an infinite stop loop. Independently, if the harness reports
# stop_hook_active with the marker's counter at 0 — meaning our own count never
# persisted — fail open rather than trust a counter that isn't counting.
#
# DEGRADATION CONTRACT:
#   - No marker file                        => exit 0 (nothing owed)
#   - Verdict present for the stage         => exit 0 (marker cleared — debt paid)
#   - python3 absent / marker unreadable    => exit 0 (fail-open, marker cleared)
#   - Verdict missing, blocks < MAX_BLOCKS  => exit 2 (BLOCK: the one fail-closed path)
#   - Verdict missing, blocks >= MAX_BLOCKS => exit 0 (fail-open, marker cleared)
set -uo pipefail

MAX_BLOCKS=2

_log() { # append-only trace; never fails the hook
  local dir="$1" line="$2"
  printf '%s verify-stage-gate %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo -)" "$line" \
    >> "$dir/.temper/hooks.log" 2>/dev/null || true
}

_main() {
  local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  local marker="$dir/.temper/pending-stage.json"
  local stdin_json=""
  stdin_json="$(cat 2>/dev/null || true)"
  [[ -f "$marker" ]] || return 0
  command -v python3 >/dev/null 2>&1 || { rm -f "$marker" 2>/dev/null; return 0; }

  # One python pass: read marker + gates.json + harness input, decide, update the
  # marker in place. Prints "CLEAR", "OPEN" (fail-open), or "BLOCK <stage>". The
  # harness JSON travels as argv, NOT piped to stdin — `python3 -` takes its program
  # from stdin (the heredoc), so anything piped there would be silently discarded.
  local decision
  decision=$(python3 - "$marker" "$dir/.temper/gates.json" "$MAX_BLOCKS" "$stdin_json" <<'PY' 2>/dev/null
import json, sys
marker_path, gates_path, max_blocks = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    hook_input = json.loads(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else {}
except Exception:
    hook_input = {}
try:
    m = json.load(open(marker_path))
    stage, blocks = m["stage"], int(m.get("blocks", 0))
    since = m.get("since", "")
except Exception:
    print("OPEN"); sys.exit(0)
try:
    g = json.load(open(gates_path)).get(stage, {})
    verdict, verdict_ts = g.get("verdict"), g.get("ts", "")
except Exception:
    verdict, verdict_ts = None, ""
# The verdict must postdate the marker: a verdict left behind by a previous run does
# not pay this session's debt. ISO-8601 UTC strings compare lexicographically; if
# either timestamp is missing (old marker format, hand-edited gates.json), degrade to
# the weaker any-verdict check rather than blocking on unknowable state.
if verdict and (not since or not verdict_ts or verdict_ts >= since):
    print("CLEAR"); sys.exit(0)
if blocks >= max_blocks:
    print("OPEN"); sys.exit(0)
if hook_input.get("stop_hook_active") and blocks == 0:
    # The harness says a stop hook is already re-blocking this session, yet our own
    # counter never moved — the marker isn't persisting. Don't loop on a broken counter.
    print("OPEN"); sys.exit(0)
m["blocks"] = blocks + 1
json.dump(m, open(marker_path, "w"))
print(f"BLOCK {stage}")
PY
  ) || decision="OPEN"

  case "$decision" in
    CLEAR)
      _log "$dir" "cleared (verdict recorded)"
      rm -f "$marker" 2>/dev/null
      return 0
      ;;
    BLOCK*)
      local stage="${decision#BLOCK }"
      _log "$dir" "blocked stop (stage=$stage, no verdict)"
      cat >&2 <<EOF
temper: this session ran /temper:$stage but 'temper gate $stage' was never invoked, so
no verdict exists in .temper/gates.json and 'temper gate commit' cannot see that the
stage happened. Before finishing: record the stage's evidence as agents/$stage.md
specifies (e.g. 'temper state set complexity <tier>' for plan, 'temper evidence add'
for build/review/check), then run:
  \$CLAUDE_PLUGIN_ROOT/scripts/temper gate $stage --spec-path .temper/specs/<feature-slug>
A FAIL verdict is fine to finish on if the user chose to stop — the requirement is that
the gate ran, not that it passed.
EOF
      return 2
      ;;
    *)
      _log "$dir" "fail-open (marker unreadable or block budget spent)"
      rm -f "$marker" 2>/dev/null
      return 0
      ;;
  esac
}

_main
exit $?
