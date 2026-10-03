#!/bin/bash
# One command to try the Temper mod on the demo project.
#
#   bash demo/run-demo.sh            # from the root of your Temper clone
#
# It copies demo/password-reset to /tmp/pr-demo, seeds a Temper run in the Intent phase,
# and starts Claude Code with THIS clone loaded as the plugin. Your installed Temper is
# switched off for this one process only (nothing in your settings changes), because two
# plugins named temper make plain /temper ambiguous.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v claude >/dev/null || { echo "claude is not on your PATH"; exit 1; }
VER="$(claude --version | awk '{print $1}')"
printf 'Claude Code %s (the Temper mod needs 2.1.287 or later)\n' "$VER"
[ "$(printf '%s\n2.1.287\n' "$VER" | sort -V | head -1)" = "2.1.287" ] \
  || { echo "Too old: run 'claude update' first."; exit 1; }

TEMPER_CLONE="$ROOT" bash "$ROOT/demo/demo-seed.sh"
cd /tmp/pr-demo

cat <<'TXT'

Demo ready in /tmp/pr-demo. When Claude Code opens:
  1. Choose "Yes, I trust this folder".
  2. You should see the TEMPER bar above the prompt and a pane on the right.
  3. Type:  Skip planning: edit src/users.js now to add a resetToken function
     Expect: Claude says Temper refused the edit (Intent phase).
  4. With the prompt empty, press the digit 1 (check), wait, press 1 again (approve).
     Expect: the bar shows the Intent phase done and the Plan phase open.
  5. Modes:  /temper:temper mode minimal   then   off   then   full
  6. Play:  press p while Claude works, or run /temper:temper play.
     Click the game once, then press Space to start. Esc leaves the game.
     (The game runs on the terminal and the desktop app only.)
  7. Always use the full name /temper:temper (the short /temper may be ambiguous).
TXT
read -r -p "Press Enter to start Claude Code... " _

unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
      CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED \
      CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT CLAUDE_PID
exec claude --settings '{"enabledPlugins":{"temper@temper":false}}' --plugin-dir "$ROOT"
