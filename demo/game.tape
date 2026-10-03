# The game recording for the README: it writes the GIF into demo/out (not in git).
#
#     vhs demo/game.tape
#
# This tape is NOT run in CI. It needs an authenticated `claude` session (Claude Code 2.1.287
# or later) and VHS with ttyd and ffmpeg. It sends no prompt to Claude: the game opens with
# the /temper:temper play command. A click gives the game its keys, so the tape does not
# press keys at the game until the mouse has clicked it. If your VHS cannot click, press Tab
# to move the focus. Tune the Sleep times for your machine.

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

Type "/temper:temper play" Enter
Sleep 3s
Tab
Sleep 1s
Space
Sleep 2s
Space
Sleep 1500ms
Space
Sleep 2s
Space
Sleep 8s
Escape
Sleep 3s
