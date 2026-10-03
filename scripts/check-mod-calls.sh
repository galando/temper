#!/usr/bin/env bash
# check-mod-calls.sh: the Temper mod's `$` surface is a reviewed list, enforced here.
#
# Runs `claude plugin validate` on the manifest, takes the `calls:` line it prints for
# hooks/temper-mod/register.tsx, and FAILS when
#   - any call is process.*, http.* or env.* (the mod never spawns, fetches or reads the
#     environment: tests, lint, git and CLI calls are prompts to Claude), or
#   - any call is not on the reviewed list below.
# A new call is a reviewed change: add it here AND to docs/mods-plan.md section 2.7 with a
# one line reason.
#
# Test hook: CHECK_MOD_CALLS_LINE="<a calls: line>" checks that line without running claude.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The reviewed list: one `noun.method` per line, with why the mod needs it.
ALLOWED='
config.list      /temper mode and enforcement read the row to see whether an administrator locked it
config.set       the same commands change the row the way /config does (key temper.uiMode, temper.enforcement)
fs.list          lists .temper/specs/{slug}/events/ to rebuild the run
fs.read          reads build-state, gates, status, evidence, intent, plan, tasks, temper.config and event files
fs.stat          resolves "." to the project root so absolute tool paths can be made relative
fs.write         the one write: Temper event files and .temper/report.md
prompt.submit    a pressed band or pane Button sends its action to Claude (never from a hook)
prompt.suggest   offers the next action as a suggestion after a turn (Tab to take, never submitted)
session.version  the version guard: the mod stays inert below 2.1.287
state.get        the drawing hooks read the run view and the live mode, so a write redraws them
state.set        publishes the run view and the live mode
store.get        own event ids (forgery guard), consumed human decisions, "mode already asked"
store.set        records those
ui.ask           scope drift choices, the first run mode question, reasons for override and accept
ui.close         closes the pane (leaving full mode, a toggle, a pane that would not dock)
ui.focus         key 9 on the band moves the focus into the override reason field
ui.invalidate    redraws the render sites after a mode or enforcement change
ui.open          opens the pane
ui.resolve       the element table of the surface being drawn (Box, Text, Button, Markdown)
ui.toast         one toast per phase transition and on enforcement changes
'

allowed_names() { printf '%s\n' "$ALLOWED" | awk 'NF { print $1 }'; }

if [[ -n "${CHECK_MOD_CALLS_LINE:-}" ]]; then
  LINE="$CHECK_MOD_CALLS_LINE"
else
  command -v claude >/dev/null 2>&1 || { echo "FAIL: claude is not installed (need Claude Code 2.1.287 or later)"; exit 1; }
  OUT="$(claude plugin validate "$REPO_ROOT/.claude-plugin/plugin.json" </dev/null 2>&1)" || {
    echo "$OUT"
    echo "FAIL: claude plugin validate failed"
    exit 1
  }
  LINE="$(printf '%s\n' "$OUT" | grep -E 'register\.tsx calls:' | head -1 || true)"
  [[ -n "$LINE" ]] || { echo "$OUT"; echo "FAIL: no 'calls:' line for the mod in the validate output"; exit 1; }
fi

# "...calls: $.fs.list (via makeIo), $.store.get (via a, b), ..." -> one name per line.
CALLS="$(printf '%s\n' "$LINE" \
  | sed -E 's/.*calls: //' \
  | sed -E 's/ \([^)]*\)//g' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]*\$\.//; s/[[:space:]]+$//' \
  | awk 'NF')"
[[ -n "$CALLS" ]] || { echo "FAIL: the calls: line names no calls (is the mod scanned?)"; exit 1; }

FAIL=0
while IFS= read -r call; do
  case "$call" in
    process.*|http.*|env.*)
      echo "FAIL: forbidden call \$.$call (the mod never spawns, fetches or reads the environment)"
      FAIL=1
      continue
      ;;
  esac
  if ! allowed_names | grep -qx -- "$call"; then
    echo "FAIL: \$.$call is not on the reviewed list (scripts/check-mod-calls.sh, docs/mods-plan.md 2.7)"
    FAIL=1
  fi
done <<< "$CALLS"

# The surface modules (the game) run on the drawing thread and have no engine at all: any dollar
# sign followed by a dot in one fails. CHECK_MOD_CLIENT_DIR lets the test script point at fixtures.
CLIENT_DIR="${CHECK_MOD_CLIENT_DIR:-$REPO_ROOT/hooks/temper-mod/ui}"
for f in "$CLIENT_DIR"/*-client.tsx; do
  [[ -e "$f" ]] || continue
  if grep -nE '(^|[^A-Za-z0-9_])\$\.' "$f" >/dev/null; then
    echo "FAIL: $(basename "$f") makes a \$. call; a surface module has no engine (it posts to the hooks module instead)"
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "OK: $(printf '%s\n' "$CALLS" | wc -l | tr -d ' ') calls, all on the reviewed list, none process/http/env; surface modules make no \$. call"
fi
exit $FAIL
