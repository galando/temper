# The hero recording for the README: it writes the full mode GIF into docs/assets.
#
# Regenerate from the root of a Temper clone with VHS (https://github.com/charmbracelet/vhs):
#
#     vhs demo/temper.tape
#
# This tape is NOT run in CI and nothing in the repository depends on it. It needs:
#   - an authenticated `claude` session on this machine (Claude Code 2.1.287 or later),
#   - VHS with ttyd and ffmpeg installed.
# It spends real tokens: each take sends three short prompts to Claude. Model output varies,
# so expect to retry and to tune the Sleep times until each step has finished before the next
# key press. Everything between Hide and Show is real time that the GIF skips.
#
# The setup copies demo/password-reset to /tmp/pr-demo and seeds a Temper run in the Intent
# phase (scripts/demo-seed.sh). The `claude` function in the setup switches off an installed
# copy of the Temper plugin for this one process, so the branch in this clone is the only one.

Output docs/assets/temper-full.gif

Set Shell "bash"
Set FontSize 18
Set Width 1800
Set Height 1000
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms
Set Framerate 12

Hide
Type "unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT CLAUDE_PID" Enter
Type "export TEMPER_CLONE=$PWD && bash demo/demo-seed.sh && cd /tmp/pr-demo && clear" Enter
Sleep 6s
Type `claude() { command claude --settings '{"enabledPlugins":{"temper@temper":false}}' "$@"; }` Enter
Type "claude --plugin-dir $TEMPER_CLONE" Enter
Sleep 7s
Down
Enter
Sleep 8s
Show

# 1. Claude is asked to skip the planning. The Intent phase refuses the edit.
Sleep 2s
Type "Skip planning: edit src/users.js now to add a resetToken function"
Sleep 1s
Enter
Hide
Sleep 40s
Show
Sleep 5s

# 2. One key press lints the intent, a second one approves it. The bar moves to Plan.
Type "1"
Hide
Sleep 35s
Show
Sleep 3s
Type "1"
Hide
Sleep 40s
Show
Sleep 6s
