# The game recording for the README: it writes the GIF into demo/out (not in git).
#
#     vhs demo/game.tape
#
# This tape is NOT run in CI. It needs an authenticated `claude` session (Claude Code 2.1.287
# or later) and VHS with ttyd and ffmpeg. It sends no prompt to Claude. The game opens with the
# /temper:temper play command (while Claude works, the digit 8 opens it too), and the pane takes the keyboard. The tape plays with the keys
# s (start), w (jump) and q (quit) only. It never clicks and never presses Tab or Space.
# The Sleep times are estimates: a jump has to come before a block reaches the runner.

Output demo/out/game.gif

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
Sleep 9s
Show

# Open the game. The line "The game is open. Press s to start, w to jump, q or Esc to leave." shows.
Type "/temper:temper play"
Sleep 500ms
Enter
Sleep 3s

# Start, then jump over the blocks. Each w is one jump.
Type "s"
Sleep 2s
Type "w"
Sleep 1500ms
Type "w"
Sleep 1500ms
Type "w"
Sleep 1800ms
Type "w"
Sleep 1500ms
Type "w"
Sleep 1800ms
Type "w"
Sleep 1500ms
Type "w"
Sleep 1500ms

# Stop jumping: the next block ends the game and the Start button says Again.
Sleep 8s

# Leave with q. The prompt is back.
Type "q"
Sleep 3s
