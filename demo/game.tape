# The game recording for the README: it writes the GIF into demo/out (not in git).
#
#     vhs demo/game.tape
#
# This tape is NOT run in CI. It needs an authenticated `claude` session (Claude Code 2.1.287
# or later) and VHS with ttyd and ffmpeg. It sends one short prompt to Claude (it costs a few
# tokens), because the game is offered only while Claude works. The digit 8 opens the game (the
# command /temper:temper play opens it too), and the pane takes the keyboard. The game is
# Temper Merge, a turn based puzzle, so no key needs exact timing. The tape plays with the keys
# 8, w, a, s, d and q only. It never clicks and never presses Tab or Space.

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
Type "export TEMPER_CLONE=$PWD && bash demo/demo-seed.sh plan && cd /tmp/pr-demo && clear" Enter
Sleep 6s
Type `claude() { command claude --settings '{"enabledPlugins":{"temper@temper":false}}' "$@"; }` Enter
Type "claude --plugin-dir $TEMPER_CLONE" Enter
Sleep 7s
Down
Enter
Sleep 9s
Show

# Send a short prompt. While Claude works, the band says "8: Play while you wait" and the hint under
# the prompt says "Press 8 to play while you wait."
Type "Write a 300 word essay about forges"
Sleep 500ms
Enter
Sleep 4s

# Press 8 with the prompt empty: the game pane opens and takes the keyboard.
Type "8"
Sleep 3s

# Slide the pieces with w a s d. Equal pieces merge and get hotter. Take your time: the game waits.
Type "a"
Sleep 900ms
Type "w"
Sleep 900ms
Type "d"
Sleep 900ms
Type "s"
Sleep 900ms
Type "a"
Sleep 900ms
Type "w"
Sleep 900ms
Type "a"
Sleep 900ms
Type "s"
Sleep 900ms
Type "d"
Sleep 900ms
Type "w"
Sleep 900ms
Type "a"
Sleep 900ms
Type "s"
Sleep 2s

# Leave with q. The prompt is back, and the board waits for the next time.
Type "q"
Sleep 3s
