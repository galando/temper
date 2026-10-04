#!/bin/bash
# One command to try the Temper mod on the demo project.
#
#   bash demo/run-demo.sh            # starts at the Plan step, ready to approve (the smooth demo)
#   bash demo/run-demo.sh intent     # starts at the Intent step, from a draft intent
#
# Run it from the root of your Temper clone. It copies demo/password-reset to /tmp/pr-demo,
# seeds a Temper run, and starts Claude Code with THIS clone loaded as the plugin. Your installed
# Temper is switched off for this one process only (nothing in your settings changes), because
# two plugins named temper make plain /temper ambiguous.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-plan}"
case "$MODE" in intent | plan) ;; *) echo "usage: bash demo/run-demo.sh [plan|intent]"; exit 1 ;; esac

command -v claude >/dev/null || { echo "claude is not on your PATH"; exit 1; }
VER="$(claude --version | awk '{print $1}')"
printf 'Claude Code %s (the Temper mod needs 2.1.287 or later)\n' "$VER"
[ "$(printf '%s\n2.1.287\n' "$VER" | sort -V | head -1)" = "2.1.287" ] \
  || { echo "Too old: run 'claude update' first."; exit 1; }

TEMPER_CLONE="$ROOT" bash "$ROOT/demo/demo-seed.sh" "$MODE"
cd /tmp/pr-demo

if [ "$MODE" = "plan" ]; then
  cat <<'TXT'

Demo ready in /tmp/pr-demo, at Step 2 of 6: Plan. When Claude Code opens:
  1. Choose "Yes, I trust this folder".
  2. You see the TEMPER bar above the prompt: "1 Approve the plan." and a pane on the right.
  3. Type:  Skip the tasks: edit src/users.js now to add a resetToken function
     Expect: Claude says Temper refused the edit, with a "Next:" step. The plan is not approved yet.
  4. With the prompt empty, press the digit 1.
     Expect: the toast "Plan approved. Build open." and the bar moves to Build: "1 Start the next task."
  5. Play:  while Claude works, press 8 on an empty prompt ("Play while you wait"), or
     run /temper:temper play. Press r to run, w to jump, s to duck, q or Esc to leave.
     (The game runs on the terminal and the desktop app only.)
  6. Modes:  /temper:temper mode minimal   then   off   then   full
  7. Always use the full name /temper:temper (the short /temper may be ambiguous).
TXT
else
  cat <<'TXT'

Demo ready in /tmp/pr-demo, at Step 1 of 6: Intent. When Claude Code opens:
  1. Choose "Yes, I trust this folder".
  2. You see the TEMPER bar above the prompt and a pane on the right.
  3. Type:  Skip planning: edit src/users.js now to add a resetToken function
     Expect: Claude says Temper refused the edit (Intent step), with a "Next:" step.
  4. With the prompt empty, press the digit 1 ("Check the intent"), wait, press 1 again ("Approve the intent").
     Expect: the toast "Intent approved. Plan open." and the bar moves to Plan.
  5. Play:  while Claude works, press 8 on an empty prompt, or run /temper:temper play.
  6. Modes:  /temper:temper mode minimal   then   off   then   full
  7. Always use the full name /temper:temper (the short /temper may be ambiguous).
TXT
fi
read -r -p "Press Enter to start Claude Code... " _

unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
      CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED \
      CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT CLAUDE_PID
exec claude --settings '{"enabledPlugins":{"temper@temper":false}}' --plugin-dir "$ROOT"
