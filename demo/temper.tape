# The hero recording for the README: it writes the GIF into demo/out (not in git). It shows
# about 15 to 20 seconds and no waiting scene. Copy the result into the README image folder
# yourself when you are happy with it.
#
# Regenerate from the root of a Temper clone with VHS (https://github.com/charmbracelet/vhs):
#
#     vhs demo/temper.tape
#
# This tape is NOT run in CI and nothing in the repository depends on it. It needs:
#   - an authenticated `claude` session on this machine (Claude Code 2.1.287 or later),
#   - VHS with ttyd and ffmpeg installed.
# It spends a few tokens: one short prompt that Claude answers with a refusal, and one follow up
# line after the key press. Model output varies, so tune the Sleep times if a step is not done
# before the next key press. Everything between Hide and Show is real time that the GIF skips.
#
# The setup removes an old /tmp/pr-demo only when it holds the marker file .temper-demo (delete
# /tmp/pr-demo by hand if it is not a demo folder). It copies demo/password-reset to /tmp/pr-demo and seeds a Temper run at the Plan step with
# the intent accepted and the plan written (demo/demo-seed.sh plan). The first key press is
# "1 Continue to Build", so nothing waits on screen. The `claude` function in the setup switches off
# an installed copy of the Temper plugin for this one process.

Output demo/out/temper-full.gif

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
Sleep 8s
Show

# 1. The bar shows "Step 2 of 6: Plan" and "1 Continue to Build." (3 seconds)
Sleep 3s

# 2. Claude is asked to change code before the plan is approved. The edit is refused, with a Next step.
Type "Skip the tasks: edit src/users.js now to add a resetToken function"
Sleep 800ms
Enter
Hide
Sleep 25s
Show
Sleep 5s

# 3. One key press approves the plan. The toast says "Plan approved. Build open." and the bar
# moves to Build with "1 Continue with task 1." (6 seconds)
Type "1"
Sleep 6s
