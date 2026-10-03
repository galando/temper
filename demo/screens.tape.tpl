# Template for the mode screenshots. demo/make-screens.sh fills in THEME_NAME and SUFFIX and
# runs VHS once per theme. No model calls happen here: only slash commands the mod answers.
# NOT run in CI. Needs VHS with ttyd and ffmpeg and an authenticated claude session.

Set Shell "bash"
Set FontSize 18
Set Width 1800
Set Height 1000
Set Padding 20
Set Theme "THEME_NAME"
Set TypingSpeed 30ms

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
Type "/temper:temper mode full" Enter
Sleep 8s
Show
Sleep 2s
Screenshot demo/out/mode-full-SUFFIX.png
Type "/temper:temper mode minimal" Enter
Sleep 8s
Screenshot demo/out/mode-minimal-SUFFIX.png
Type "/temper:temper mode off" Enter
Sleep 8s
Screenshot demo/out/mode-off-SUFFIX.png
Type "/temper:temper mode full" Enter
Sleep 6s
