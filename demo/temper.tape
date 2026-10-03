# The hero recording for the README: it writes the full mode GIF into docs/assets.
#
# Regenerate from the root of a Temper clone with VHS (https://github.com/charmbracelet/vhs):
#
#     vhs demo/temper.tape
#
# This tape is NOT run in CI and nothing in the repository depends on it. It needs:
#   - an authenticated `claude` session on this machine (Claude Code 2.1.287 or later),
#   - VHS with ttyd and ffmpeg installed.
# It spends real tokens: every take runs a short Temper pipeline. Model output varies, so
# expect to retry and to tune the Sleep times below until each step has finished before
# the next key press. The key presses are the point: 1 approves, so a Sleep that is too
# short presses 1 while Claude is still working and the take drifts.
#
# For the light and dark screenshots in the README, change `Set Theme` and add
# `Screenshot docs/assets/<name>.png` at the moment you want, then run the tape again.

Output docs/assets/temper-full.gif

Set Shell "bash"
Set FontSize 22
Set Width 1500
Set Height 900
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set PlaybackSpeed 1

# Setup the viewer never sees: a throwaway copy of the demo project with its own git.
Hide
Type "export TEMPER_CLONE=$PWD && rm -rf /tmp/pr-demo && cp -R demo/password-reset /tmp/pr-demo && cd /tmp/pr-demo" Enter
Type "git init -q && git add -A && git commit -qm start && clear" Enter
Show

Type "claude --plugin-dir $TEMPER_CLONE" Enter
Sleep 8s

# 1. Intent. Claude drafts the intent; the band shows the six phases.
Type "/temper:temper Add password reset: one time token that expires after one hour" Enter
Sleep 45s

# 2. A denial: no code before the intent is approved.
Type "Skip the planning and edit src/users.js to add resetToken now" Enter
Sleep 20s

# 3. Approve the intent with the hotkey, then the plan.
Type "1"
Sleep 60s
Type "1"
Sleep 5s

# 4. Build. Open the pane to watch the criteria tick.
Type "/temper:temper pane" Enter
Sleep 90s

# 5. Review and Check run; press 1 when the band offers the next step.
Type "1"
Sleep 60s
Type "1"
Sleep 45s

# Done: the run is complete and git commit is allowed.
Sleep 6s
