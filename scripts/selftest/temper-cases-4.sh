# shellcheck shell=bash
# Part 4 of the temper CLI test suite: the guard scripts, validators and the installer refusals.
# Sourced in order by test-temper.sh, which sets up the helpers, WORKDIR and the counters;
# not meant to run on its own.

# --- block-protected-paths.sh and block-uncommitted-gate.sh: the CLI next to the script ---
setup
cat >> .claude/temper.config <<'EOF'
protect:
  paths: ["**/frozen/**"]
EOF
assert_exit "protected-paths finds its CLI next to it, with an empty environment" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/frozen/a.ts\"}}' | env -i HOME='$HOME' PATH='$PATH' CLAUDE_PROJECT_DIR='$WORKDIR' bash '$REPO_ROOT/scripts/guards/block-protected-paths.sh'"
UG="$REPO_ROOT/scripts/guards/block-uncommitted-gate.sh"
echo 'x' > gate-file.txt
git add gate-file.txt >/dev/null 2>&1
assert_exit "uncommitted-gate: a git commit on a red gate is BLOCKED, with an empty environment" 2 \
  bash -c "echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | env -i HOME='$HOME' PATH='$PATH' bash '$UG'"
assert_exit "uncommitted-gate: any other command passes" 0 \
  bash -c "echo '{\"tool_input\": {\"command\": \"git status\"}}' | env -i HOME='$HOME' PATH='$PATH' bash '$UG'"
git rm -q --cached gate-file.txt >/dev/null 2>&1 || true
rm -f gate-file.txt

# --- pack-discover.py: named folders, no wildcard; hidden, nested and non-.md entries left out; a
# symlink that leaves its folder is never read, one that stays inside is kept ---
setup
PD_OUTSIDE="$WORKDIR/outside-pd"
rm -rf "$PD_OUTSIDE"
mkdir -p "$PD_OUTSIDE/skill" .claude/commands/nested .claude/skills/real-skill .claude/skills/.hidden-skill \
  .claude/skills/no-skill-file
printf -- '---\ndescription: outside\n---\n' > "$PD_OUTSIDE/cmd.md"
printf -- '---\ndescription: outside skill\n---\n' > "$PD_OUTSIDE/skill/SKILL.md"
printf -- '---\ndescription: local\n---\n' > .claude/commands/local-cmd.md
printf -- '---\ndescription: hidden local\n---\n' > .claude/commands/.hidden-cmd.md
printf -- '---\ndescription: nested\n---\n' > .claude/commands/nested/inner.md
printf 'not a command\n' > .claude/commands/notes.txt
printf -- '---\ndescription: real skill\n---\n' > .claude/skills/real-skill/SKILL.md
printf -- '---\ndescription: hidden skill\n---\n' > .claude/skills/.hidden-skill/SKILL.md
printf 'x\n' > .claude/skills/no-skill-file/README.md
ln -s "$PD_OUTSIDE/cmd.md" .claude/commands/escape.md
ln -s "$PD_OUTSIDE/skill" .claude/skills/escape-skill
ln -s local-cmd.md .claude/commands/alias.md
PD_OUT="$(python3 "$REPO_ROOT/scripts/pack-discover.py")"
assert_eq "pack-discover lists the project's own commands: hidden, nested, non-.md and escaping ones left out" "alias|local-cmd" \
  "$(printf '%s\n' "$PD_OUT" | awk -F'|' '$1 == "LOCAL_CMD" {print $2}' | sort | paste -sd'|' -)"
assert_eq "pack-discover lists each project skill folder's SKILL.md: hidden, empty and escaping folders left out" "real-skill" \
  "$(printf '%s\n' "$PD_OUT" | awk -F'|' '$1 == "LOCAL_SKILL" {print $2}' | sort | paste -sd'|' -)"
assert_eq "pack-discover never prints a path outside the project's own folders" "0" "$(printf '%s\n' "$PD_OUT" | grep -c 'outside')"
# A skills folder that is itself a link is listed while it stays inside the project, and not when
# it links out of it (to a home skills folder, say). The project here is a folder of its own.
PD_PROJ="$WORKDIR/pd-proj"
rm -rf "$PD_PROJ"
mkdir -p "$PD_PROJ/.claude" "$PD_PROJ/kept-skills/linked-skill" "$PD_OUTSIDE/skills/linked-skill"
printf -- '---\ndescription: linked\n---\n' > "$PD_PROJ/kept-skills/linked-skill/SKILL.md"
printf -- '---\ndescription: linked\n---\n' > "$PD_OUTSIDE/skills/linked-skill/SKILL.md"
ln -s "$PD_PROJ/kept-skills" "$PD_PROJ/.claude/skills"
assert_eq "pack-discover lists a skill through a skills folder linked inside the project" "1" \
  "$(cd "$PD_PROJ" && python3 "$REPO_ROOT/scripts/pack-discover.py" | grep -c '^LOCAL_SKILL|linked-skill|')"
rm -f "$PD_PROJ/.claude/skills"
ln -s "$PD_OUTSIDE/skills" "$PD_PROJ/.claude/skills"
assert_eq "pack-discover lists no skill through a skills folder that links out of the project" "0" \
  "$(cd "$PD_PROJ" && python3 "$REPO_ROOT/scripts/pack-discover.py" | grep -c 'LOCAL_SKILL')"
rm -rf "$PD_OUTSIDE" "$PD_PROJ" .claude/commands .claude/skills

# --- version-stamp drift: every visible version string matches plugin.json ---
# plugin.json is the single source of truth; the CLAUDE.md stamp and the top
# CHANGELOG entry must never disagree with it (version-bump.sh keeps them in
# sync — this test catches a hand-bump that misses one). Resolved from the
# script's own location so it works from any cwd.
VR_ROOT="$REPO_ROOT"   # captured before setup() cds into WORKDIR
PLUGIN_VERSION="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['version'])" "$VR_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo MISSING)"
assert_eq "plugin.json version is readable" "yes" "$([[ "$PLUGIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)"
CLAUDE_MD_VERSION="$(sed -n 's/^\*\*Version:\*\* \([0-9.]*\).*/\1/p' "$VR_ROOT/.claude/CLAUDE.md" | head -1)"
assert_eq ".claude/CLAUDE.md version stamp matches plugin.json" "$PLUGIN_VERSION" "${CLAUDE_MD_VERSION:-MISSING}"
CHANGELOG_VERSION="$(grep -m1 -oE '^## v[0-9]+\.[0-9]+\.[0-9]+' "$VR_ROOT/CHANGELOG.md" | sed 's/^## v//')"
assert_eq "CHANGELOG top entry matches plugin.json" "$PLUGIN_VERSION" "${CHANGELOG_VERSION:-MISSING}"

# --- the CLI refuses a link only on its own run state, and refuses the home folder; every guard
# script follows its own symlinks and does nothing outside a plugin's scripts/guards folder ---
# A throwaway plugin folder (an installed copy, with no .git of its own) holds copies of the CLI
# and every guard script. The projects are folders outside it.
setup
CL_PLUG="$WORKDIR/cl-plugin"
CL_PROJ="$WORKDIR/cl-project"
CL_BIN="$WORKDIR/cl-bin"
CL_LOOSE="$WORKDIR/cl-loose"
CL_HOME="$WORKDIR/cl-home"
rm -rf "$CL_PLUG" "$CL_PROJ" "$CL_BIN" "$CL_LOOSE" "$CL_HOME" "$WORKDIR/cl-guards-link" "$WORKDIR/cl-scripts-link" \
  "$WORKDIR/cl-home-link"
mkdir -p "$CL_PLUG/scripts/guards" "$CL_BIN" "$CL_LOOSE/scripts" "$CL_HOME/project"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$CL_PLUG/scripts/"
cp -R "$REPO_ROOT/scripts/guards/." "$CL_PLUG/scripts/guards/"
cp -R "$REPO_ROOT/agents" "$CL_PLUG/agents"
CL_T="$CL_PLUG/scripts/temper"
CL_G="$CL_PLUG/scripts/guards"
CL_T_REAL="$(cd -P "$CL_PLUG" && pwd)/scripts/temper"
cl_project() { # a fresh git project with one commit and an active run whose gates are all missing
  rm -rf "$CL_PROJ"
  mkdir -p "$CL_PROJ"
  git init -q "$CL_PROJ"
  git -C "$CL_PROJ" config user.email "test@example.com"
  git -C "$CL_PROJ" config user.name "test"
  echo a > "$CL_PROJ/a.txt"
  git -C "$CL_PROJ" add a.txt
  git -C "$CL_PROJ" commit -qm init
  (cd "$CL_PROJ" && "$CL_T" state init demo-run >/dev/null)
  mkdir -p "$CL_PROJ/.temper/specs/demo-run" "$CL_PROJ/.temper/specs/other-run"
}

# A link inside a spec folder is not run state: the commit gate still computes its verdict, and
# a red run stays blocked by the CLI, the native pre-commit hook and the in-agent hook alike.
cl_project
ln -s "$WORKDIR" "$CL_PROJ/.temper/specs/demo-run/notes"
ln -s "$WORKDIR/cl-no-such-target" "$CL_PROJ/.temper/specs/other-run/dangling"
OUT=$(cd "$CL_PROJ" && "$CL_T" gate commit 2>&1); CL_RC=$?
assert_eq "a link inside a spec folder leaves the commit gate to fail a red run (exit 1, never 3)" "1|yes|0" \
  "$CL_RC|$(printf '%s\n' "$OUT" | grep -q 'temper gate commit -> FAIL' && echo yes || echo no)|$(printf '%s\n' "$OUT" | grep -c 'unsafe .temper')"
(cd "$CL_PROJ" && bash "$CL_G/install.sh" >/dev/null 2>&1)
echo b > "$CL_PROJ/b.txt"
git -C "$CL_PROJ" add b.txt
OUT=$(cd "$CL_PROJ" && git commit -qm 'code with red gates' 2>&1); CL_RC=$?
assert_eq "the native pre-commit hook blocks that red run, link and all" "blocked|yes|1" \
  "$([[ $CL_RC -ne 0 ]] && echo blocked || echo committed)|$(printf '%s\n' "$OUT" | grep -q 'temper gate commit -> FAIL' && echo yes || echo no)|$(git -C "$CL_PROJ" rev-list --count HEAD)"
assert_exit "the in-agent commit gate blocks it too" 2 \
  bash -c "cd '$CL_PROJ' && echo '{\"tool_input\": {\"command\": \"git commit -m y\"}}' | bash '$CL_G/block-uncommitted-gate.sh'"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_G/stage-marker.sh"
assert_eq "stage-marker records the debt there, since the CLI runs" "yes" \
  "$([[ -f "$CL_PROJ/.temper/pending-stage.json" ]] && echo yes || echo no)"
# The spec folder of a run that is not the active one is not run state either.
cl_project
rm -rf "$CL_PROJ/.temper/specs/other-run"
ln -s "$WORKDIR" "$CL_PROJ/.temper/specs/other-run"
assert_exit "a spec folder of another run that is a link does not stop the active run" 0 \
  bash -c "cd '$CL_PROJ' && '$CL_T' evidence add --stage build --claim x"
# A link on any path the CLI writes or reads as run state is refused (exit 3) and named, and
# nothing is written through it.
for p in .temper/specs .temper/archive .temper/build-state.json .temper/overrides.json .temper/status.json \
         .temper/metrics.json .temper/bands.json .temper/feedback-loops.json .temper/evidence/build.json \
         .temper/evidence/fix.json .temper/specs/demo-run/gate-ledger.json; do
  cl_project
  rm -rf "${CL_PROJ:?}/$p"
  ln -s "$WORKDIR/cl-no-such-target" "$CL_PROJ/$p"
  OUT=$(cd "$CL_PROJ" && "$CL_T" gate commit 2>&1); CL_RC=$?
  assert_eq "a link at $p is refused with exit 3 and named" "3|yes" \
    "$CL_RC|$(printf '%s\n' "$OUT" | grep -qF "unsafe .temper: '$p' is a symlink" && echo yes || echo no)"
done
cl_project
mv "$CL_PROJ/.temper/specs/demo-run" "$WORKDIR/cl-spec-real"
ln -s "$WORKDIR/cl-spec-real" "$CL_PROJ/.temper/specs/demo-run"
assert_exit "the active run's spec folder that is a link is refused (exit 3)" 3 \
  bash -c "cd '$CL_PROJ' && '$CL_T' evidence add --stage build --claim x"
assert_eq "no refused command created a link target or wrote through a link" "no|" \
  "$([[ -e "$WORKDIR/cl-no-such-target" ]] && echo yes || echo no)|$(ls "$WORKDIR/cl-spec-real")"
rm -rf "$WORKDIR/cl-spec-real"

# The CLI reached through a link to its scripts folder resolves that folder: it finds its plugin
# folder and still guards it.
ln -s "$CL_PLUG/scripts" "$WORKDIR/cl-scripts-link"
assert_eq "a CLI reached through a link to its scripts folder resolves a model from its plugin folder" \
  "$("$TEMPER" model plan)" "$("$WORKDIR/cl-scripts-link/temper" model plan 2>/dev/null)"
assert_exit "it still refuses a folder inside that plugin folder" 1 \
  bash -c "cd '$CL_PLUG/agents' && '$WORKDIR/cl-scripts-link/temper' init"
assert_eq "and wrote nothing there" "no" "$([[ -e "$CL_PLUG/agents/.temper" ]] && echo yes || echo no)"

# Every guard script reached through a symlink (a link in a bin folder, a chain of relative links,
# or a link to the guards folder) finds its plugin folder and works. A copy outside a
# scripts/guards folder does nothing, even with a CLI where the failed suffix strip would look.
cl_project
mkdir -p "$CL_PROJ/.claude" "$CL_PROJ/src/frozen"
printf 'protect:\n  paths: ["**/frozen/**"]\nformat:\n  cmd: "touch {file}.formatted"\n' > "$CL_PROJ/.claude/temper.config"
echo x > "$CL_PROJ/src/a.ts"
echo 'const cp = require("child_process.exec")' > "$CL_PROJ/risky.js"
for g in stage-marker verify-stage-gate run-formatter block-protected-paths confirm-override block-forbidden-imports; do
  ln -s "$CL_G/$g.sh" "$CL_BIN/$g.sh"
  cp "$CL_G/$g.sh" "$CL_LOOSE/$g.sh"
done
cp "$TEMPER" "$CL_LOOSE/scripts/temper"
ln -s block-protected-paths.sh "$CL_BIN/chain-one.sh"
ln -s chain-one.sh "$CL_BIN/chain-two.sh"
ln -s "$CL_G" "$WORKDIR/cl-guards-link"
CL_FROZEN='{"tool_input": {"file_path": "src/frozen/a.ts"}}'
for s in "$CL_BIN/block-protected-paths.sh" "$CL_BIN/chain-two.sh" "$WORKDIR/cl-guards-link/block-protected-paths.sh"; do
  assert_exit "block-protected-paths reached as $s blocks a frozen path" 2 \
    bash -c "echo '$CL_FROZEN' | CLAUDE_PROJECT_DIR='$CL_PROJ' bash '$s'"
done
assert_exit "block-protected-paths copied outside a scripts/guards folder does nothing" 0 \
  bash -c "echo '$CL_FROZEN' | CLAUDE_PROJECT_DIR='$CL_PROJ' bash '$CL_LOOSE/block-protected-paths.sh'"
echo "{\"tool_input\": {\"file_path\": \"$CL_PROJ/src/a.ts\"}}" | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_LOOSE/run-formatter.sh"
assert_eq "run-formatter copied outside a scripts/guards folder formats nothing" "no" \
  "$([[ -e "$CL_PROJ/src/a.ts.formatted" ]] && echo yes || echo no)"
echo "{\"tool_input\": {\"file_path\": \"$CL_PROJ/src/a.ts\"}}" | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_BIN/run-formatter.sh"
assert_eq "run-formatter reached through a symlink runs the project's formatter" "yes" \
  "$([[ -e "$CL_PROJ/src/a.ts.formatted" ]] && echo yes || echo no)"
OUT=$(echo '{"tool_input": {"command": "temper override plan --reason y"}}' | bash "$CL_BIN/confirm-override.sh")
assert_eq "confirm-override reached through a symlink asks" "yes" \
  "$(printf '%s\n' "$OUT" | grep -q '"permissionDecision": "ask"' && echo yes || echo no)"
OUT=$(echo '{"tool_input": {"command": "temper override plan --reason y"}}' | bash "$CL_LOOSE/confirm-override.sh")
assert_eq "confirm-override copied outside a scripts/guards folder does nothing" "" "$OUT"
CL_RISKY="{\"tool_input\": {\"file_path\": \"$CL_PROJ/risky.js\"}}"
assert_exit "block-forbidden-imports reached through a symlink blocks a denylisted import" 2 \
  bash -c "cd '$CL_PROJ' && echo '$CL_RISKY' | TEMPER_FORBIDDEN_IMPORTS='child_process.exec' bash '$CL_BIN/block-forbidden-imports.sh'"
assert_exit "block-forbidden-imports copied outside a scripts/guards folder does nothing" 0 \
  bash -c "cd '$CL_PROJ' && echo '$CL_RISKY' | TEMPER_FORBIDDEN_IMPORTS='child_process.exec' bash '$CL_LOOSE/block-forbidden-imports.sh'"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_LOOSE/stage-marker.sh"
assert_eq "stage-marker copied outside a scripts/guards folder marks nothing" "no" \
  "$([[ -e "$CL_PROJ/.temper/pending-stage.json" ]] && echo yes || echo no)"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$CL_PLUG" bash "$CL_BIN/stage-marker.sh"
assert_eq "stage-marker reached through a symlink still skips the installed plugin folder" "no" \
  "$([[ -e "$CL_PLUG/.temper" ]] && echo yes || echo no)"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_BIN/stage-marker.sh"
assert_eq "stage-marker reached through a symlink marks the project" "plan" \
  "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['stage'])" "$CL_PROJ/.temper/pending-stage.json" 2>/dev/null)"
assert_exit "verify-stage-gate copied outside a scripts/guards folder does nothing" 0 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$CL_PROJ' bash '$CL_LOOSE/verify-stage-gate.sh'"
OUT=$(echo '{}' | CLAUDE_PROJECT_DIR="$CL_PROJ" bash "$CL_BIN/verify-stage-gate.sh" 2>&1); CL_RC=$?
assert_eq "verify-stage-gate reached through a symlink blocks and names its real CLI" "2|yes" \
  "$CL_RC|$(printf '%s\n' "$OUT" | grep -qF "$(printf '%q' "$CL_T_REAL") gate plan" && echo yes || echo no)"

# The home folder is never a project: every subcommand that keeps run state is refused there
# (exit 1), decided by identity, and nothing is written. config and model still answer, and a
# project folder inside the home folder runs as usual.
ln -s "$CL_HOME" "$WORKDIR/cl-home-link"
for sub in "init" "state init foo" "state set stage x" "state get" "state archive" "state clear" \
           "evidence add --stage build --claim x" "evidence list --stage build" "gate intent" "status" "report" \
           "bands" "metrics append coverage 42" "override plan --reason x"; do
  assert_exit "the CLI refuses '$sub' in the home folder" 1 bash -c "cd '$CL_HOME' && HOME='$CL_HOME' '$CL_T' $sub"
done
ERR=$(cd "$CL_HOME" && HOME="$CL_HOME" "$CL_T" status 2>&1 >/dev/null; true)
assert_eq "the home refusal is one line that says why" "1|yes" \
  "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')|$(printf '%s\n' "$ERR" | grep -q 'not from the home folder' && echo yes || echo no)"
assert_exit "the home folder entered through a symlink is refused too" 1 \
  bash -c "cd '$WORKDIR/cl-home-link' && HOME='$CL_HOME' '$CL_T' init"
assert_exit "a HOME spelled through a symlink names the same folder" 1 \
  bash -c "cd '$CL_HOME' && HOME='$WORKDIR/cl-home-link' '$CL_T' init"
echo '{"prompt": "/temper:plan x"}' | HOME="$CL_HOME" CLAUDE_PROJECT_DIR="$CL_HOME" bash "$CL_G/stage-marker.sh"
assert_eq "nothing was written in the home folder, by the CLI or by stage-marker" "no" \
  "$([[ -e "$CL_HOME/.temper" ]] && echo yes || echo no)"
assert_eq "config get and model still answer in the home folder" "auto|$("$TEMPER" model plan)" \
  "$(cd "$CL_HOME" && HOME="$CL_HOME" TEMPER_CONFIG="$WORKDIR/.claude/temper.config" "$CL_T" config get stack)|$(cd "$CL_HOME" && HOME="$CL_HOME" "$CL_T" model plan)"
assert_exit "a project folder inside the home folder runs as usual" 0 \
  bash -c "cd '$CL_HOME/project' && HOME='$CL_HOME' '$CL_T' init"
rm -rf "$CL_PLUG" "$CL_PROJ" "$CL_BIN" "$CL_LOOSE" "$CL_HOME" "$WORKDIR/cl-guards-link" "$WORKDIR/cl-scripts-link" \
  "$WORKDIR/cl-home-link"

# --- install.sh never writes into a folder named hooks: it keeps the hook in .git/temper-gate and
# points core.hooksPath there only when that stops no hook of the user's. Otherwise (a hook in git's
# default folder, husky v8 under sh, husky v9, lefthook, the pre-commit framework, a team's tracked
# folder, an outside core.hooksPath) it prints a FAIL line, the one line that runs the kept hook,
# and a hint. The line keeps the host hook's own result at its start or its end, and a re-run finds
# it, as it finds the line Temper 9.6.5 printed. An older Temper hook in the default folder is left
# with a note, an old installer's backup is named, and an older Temper hook that git still runs is
# named with its stale path and the hint to replace it. --global does what the default does. The
# folders an older Temper set in core.hooksPath, and the temper-gate folder of where a repository
# used to be, are pointed at the temper-gate folder unless they hold other hooks git runs. Both
# commit hooks block on the CLI's exit 3 while a run is active. block-secrets --staged scans the
# staged content. The guard scripts follow their own symlinks and do nothing outside a
# scripts/guards folder.
# No case writes into a folder named hooks (see _dg_plugin in test-temper.sh). A case about hooks of
# the user's in git's default folder runs the copy of install.sh that _dg_plugin makes, which reads
# <git folder>/default-gate in that folder's place; a case where git must run a hook of the user's
# on a real commit sets core.hooksPath to a folder of the case's own, .git/user-gate ---
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-pre-commit .git/temper-gate .git/default-gate .git/user-gate
L_PLUG="$WORKDIR/l1-plugin"
rm -rf "$L_PLUG"
mkdir -p "$L_PLUG/scripts/guards"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$L_PLUG/scripts/"
for g in install.sh block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh protect-regression-test.sh; do
  cp "$REPO_ROOT/scripts/guards/$g" "$L_PLUG/scripts/guards/$g"
done
L_INSTALL="$L_PLUG/scripts/guards/install.sh"
L_CLI_LINE="TEMPER_CLI=$(printf '%q' "$L_PLUG/scripts/temper")"
# The copy whose install.sh reads <git folder>/default-gate as git's default folder. The hook it
# keeps in <git folder>/temper-gate names that copy's CLI.
L_DG="$WORKDIR/l1-dg-plugin"
_dg_plugin "$L_DG"
L_DG_INSTALL="$L_DG/scripts/guards/install.sh"
L_DG_CLI_LINE="TEMPER_CLI=$(printf '%q' "$L_DG/scripts/temper")"
L_LINES="$WORKDIR/l1-hook-lines.sh"
# The one line the installer prints once it keeps the hook (the text the docs quote), and the line
# Temper 9.6.5 printed, which still counts.
L_CALL='_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1'
L_CALL_965='_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1'
L_KEPT_TEXT="(in the repository's git folder, never committed). Nothing else was written. To use the Temper commit gate, add the line between the BEGIN and END lines below to your pre-commit hook."
L_HINT_END="at its start or its end. It keeps your hook's own result. Create that file, executable, if it does not exist."
# A PATH folder whose sh is dash when there is one (as on Debian and Ubuntu), so the hooks that
# husky runs with sh meet a shell that knows no bash-only syntax.
L_DASH="$(command -v dash 2>/dev/null || true)"
L_BIN="$WORKDIR/l1-bin"
rm -rf "$L_BIN"
mkdir -p "$L_BIN"
[[ -z "$L_DASH" ]] || ln -s "$L_DASH" "$L_BIN/sh"
_l_lines() { # _l_lines <installer output>: writes the lines between BEGIN and END to $L_LINES
  printf '%s\n' "$1" | sed -n '/^----- BEGIN Temper pre-commit hook lines -----$/,/^----- END Temper pre-commit hook lines -----$/p' | sed '1d;$d' > "$L_LINES"
}
_l_red() { # _l_red <repository>: an active run there whose check gate failed
  mkdir -p "$1/.temper"
  echo '{"command": "temper", "run_mode": "interactive"}' > "$1/.temper/build-state.json"
  python3 -c '
import json, sys
json.dump({s: {"verdict": "FAIL" if s == "check" else "PASS", "requirements": [], "ts": "x"}
           for s in ("plan", "build", "review", "check")}, open(sys.argv[1], "w"))' "$1/.temper/gates.json"
  echo '[]' > "$1/.temper/overrides.json"
}
_l_green() { # _l_green <repository>: the same active run, with every gate passed
  _l_red "$1"
  python3 -c '
import json, sys
json.dump({s: {"verdict": "PASS", "requirements": [], "ts": "x"}
           for s in ("plan", "build", "review", "check")}, open(sys.argv[1], "w"))' "$1/.temper/gates.json"
}
_l_repo() { # _l_repo <folder>: a new repository with one commit
  rm -rf "$1"
  git init -q "$1"
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "test"
  git -C "$1" commit -q --allow-empty -m init
}
# grep reads a here-string, not a pipe: under pipefail, grep -q leaving early could end a writer
# with SIGPIPE and turn a match into a miss.
_l_has() { # _l_has <text> <fixed string>: yes when a line of the text holds the string
  grep -qF -- "$2" <<< "$1" && echo yes || echo no
}
_l_line() { # _l_line <text> <exact line>: yes when a whole line of the text is that line
  grep -qxF -- "$2" <<< "$1" && echo yes || echo no
}
_l_last() { # _l_last <text> <exact line>: yes when the last line of the text is that line
  [[ "$(printf '%s\n' "$1" | tail -1)" == "$2" ]] && echo yes || echo no
}
_l_kept() { # _l_kept <repository> [CLI line]: yes when its git folder keeps the current hook of
            # this plugin, or of the plugin whose CLI line is given
  grep -qxF "${2:-$L_CLI_LINE}" "$1/.git/temper-gate/pre-commit" 2>/dev/null && [[ "$(sed -n 2p "$1/.git/temper-gate/pre-commit")" == "# Temper native pre-commit hook"* ]] && echo yes || echo no
}
_l_dg_kept() { # _l_dg_kept <repository>: yes when its git folder keeps the hook of the copy that
               # reads default-gate
  _l_kept "$1" "$L_DG_CLI_LINE"
}
_l_older() { # _l_older <installer output> <hook file> <embedded path> <current CLI>: yes or no for
             # each line a refusal prints over an older Temper hook that git runs: the warning, the
             # stale path, the embedded and the current path, the line that says the embedded path
             # does not exist, and the hint to replace the hook, as the last line
  printf '%s|%s|%s|%s|%s|%s' \
    "$(_l_line "$1" "Warning: $2 is a hook from an older Temper, and git runs it in place of the kept hook. This installer does not write it.")" \
    "$(_l_line "$1" "Warning: the Temper hook $2 points at a stale plugin path:")" \
    "$(_l_line "$1" "  embedded: $3")" \
    "$(_l_line "$1" "  current:  $4")" \
    "$(_l_line "$1" "  (That path does not exist, so the hook has been failing open: its gate checks did nothing.)")" \
    "$(_l_last "$1" "Hint: $2 is a hook from an older Temper. Replace all of its lines with two: #!/bin/sh and the line.")"
}
_l_path() { # _l_path <repository>: its core.hooksPath, or none
  git -C "$1" config --get core.hooksPath 2>/dev/null || echo none
}
_l_commits() { # _l_commits <repository>: how many commits it has
  git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0
}

# A hook of the user's in the default folder: git would stop running it once core.hooksPath is set,
# so core.hooksPath stays unset and the hook is left as it was, with no backup; FAIL first, the kept
# hook named, exactly the one line, a hint last. The line added at the end of that hook is found by
# a second run, which writes nothing else.
mkdir -p .git/default-gate
printf '#!/bin/sh\necho mine\n' > .git/default-gate/pre-commit
chmod +x .git/default-gate/pre-commit
L_SUM="$(cksum < .git/default-gate/pre-commit)"
OUT=$(bash "$L_DG_INSTALL" 2>&1); L_RC=$?
_l_lines "$OUT"
assert_eq "install.sh refuses over a hook of the user's in the default folder: FAIL first, the kept hook, the one line, a hint last" "1|yes|yes|$L_CALL|yes" \
  "$L_RC|$(printf '%s\n' "$OUT" | head -1 | grep -qxF "FAIL: $WORKDIR/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: pre-commit." && echo yes || echo no)|$(_l_line "$OUT" "The Temper hook is kept in $WORKDIR/.git/temper-gate/pre-commit $L_KEPT_TEXT")|$(cat "$L_LINES")|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF "Hint: add the line to your own pre-commit hook ($WORKDIR/.git/default-gate/pre-commit), $L_HINT_END" && echo yes || echo no)"
assert_eq "the refused hook is left as it was, no backup is made, core.hooksPath stays unset, and the full hook is kept" "yes|0|none|yes|no" \
  "$([[ "$(cksum < .git/default-gate/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)|$(find .git/default-gate -maxdepth 1 -name 'pre-commit.bak.*' | wc -l | tr -d ' ')|$(_l_path "$WORKDIR")|$(_l_dg_kept "$WORKDIR")|$(_l_has "$OUT" "$L_DG_CLI_LINE")"
cat "$L_LINES" >> .git/default-gate/pre-commit
L_SUM="$(cksum < .git/default-gate/pre-commit)"
OUT=$(bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a hook of the user's in the default folder that holds the line is reported as calling the Temper hook and left as it was" "0|yes|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $WORKDIR/.git/default-gate/pre-commit calls the Temper hook ($WORKDIR/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$([[ "$(cksum < .git/default-gate/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)|$(_l_path "$WORKDIR")"
# The same hook in .git/user-gate, which core.hooksPath names, so git runs it: the installer
# refuses with the hook kept, the line added at the end of that hook gates a real commit, and a
# second run then finds it and writes nothing else.
git config core.hooksPath .git/user-gate
mkdir -p .git/user-gate
printf '#!/bin/sh\necho mine\n' > .git/user-gate/pre-commit
chmod +x .git/user-gate/pre-commit
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
_l_lines "$OUT"
assert_eq "over a hook of the user's in .git/user-gate, install.sh refuses with the hook kept, the one line and a hint last" "1|yes|yes|$L_CALL|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '.git/user-gate', a folder that is not Temper's, and this installer never writes into it.")|$(_l_kept "$WORKDIR")|$(cat "$L_LINES")|$(_l_last "$OUT" "Hint: add the line to your own pre-commit hook (.git/user-gate/pre-commit), $L_HINT_END")"
cat "$L_LINES" >> .git/user-gate/pre-commit
L_SUM="$(cksum < .git/user-gate/pre-commit)"
_l_red "$WORKDIR"
echo l1 > l1-file.txt
git add l1-file.txt >/dev/null 2>&1
assert_exit "with the line added at the end of a hook of the user's, a real commit on a red gate is blocked" 1 git commit -q -m l1
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a hook of the user's that holds the line is reported as calling the Temper hook and left as it was" "0|yes|yes|.git/user-gate" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .git/user-gate/pre-commit calls the Temper hook ($WORKDIR/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$([[ "$(cksum < .git/user-gate/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)|$(_l_path "$WORKDIR")"
# A stale kept hook (a moved plugin path) is rewritten by that re-run; so is a kept hook that is a
# symlink, which is replaced and never written through.
python3 - <<'EOF'
import re
p = '.git/temper-gate/pre-commit'
s = open(p).read()
open(p, 'w').write(re.sub(r'(?m)^TEMPER_CLI=.*$', 'TEMPER_CLI=/moved/plugin/scripts/temper', s))
EOF
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a re-run with the line in place says it calls the Temper hook and rewrites a stale kept hook" "0|yes|yes|yes|yes" \
  "$L_RC|$(_l_has "$OUT" 'calls the Temper hook')|$(_l_has "$OUT" 'embedded: /moved/plugin/scripts/temper')|$(_l_kept "$WORKDIR")|$([[ "$(cksum < .git/user-gate/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (another file)\n' > "$WORKDIR/l1-keep-target"
L_KT_SUM="$(cksum < "$WORKDIR/l1-keep-target")"
rm -f .git/temper-gate/pre-commit
ln -s "$WORKDIR/l1-keep-target" .git/temper-gate/pre-commit
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a kept hook that is a symlink is replaced by a regular file; the file it pointed at is untouched" "0|yes|yes|yes" \
  "$L_RC|$([[ -f .git/temper-gate/pre-commit && ! -L .git/temper-gate/pre-commit ]] && echo yes || echo no)|$(_l_kept "$WORKDIR")|$([[ "$(cksum < "$WORKDIR/l1-keep-target")" == "$L_KT_SUM" ]] && echo yes || echo no)"
rm -f "$WORKDIR/l1-keep-target"
# The line Temper 9.6.5 printed still counts, in the default folder and in .git/user-gate alike: its
# temper-pre-commit is made current, and it gates a real commit.
git config --unset core.hooksPath
printf '#!/bin/sh\necho mine\n%s\n' "$L_CALL_965" > .git/default-gate/pre-commit
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by 9.6.5)\nTEMPER_CLI=/old/plugin/scripts/temper\n' > .git/temper-pre-commit
OUT=$(bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a hook in the default folder that holds the line of Temper 9.6.5 counts, and its temper-pre-commit is made current" "0|yes|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $WORKDIR/.git/default-gate/pre-commit calls the Temper hook ($WORKDIR/.git/temper-pre-commit), which is now current, so nothing else was written.")|$(grep -qxF "$L_DG_CLI_LINE" .git/temper-pre-commit && echo yes || echo no)|$(_l_path "$WORKDIR")"
git config core.hooksPath .git/user-gate
printf '#!/bin/sh\necho mine\n%s\n' "$L_CALL_965" > .git/user-gate/pre-commit
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "so does that hook in .git/user-gate, and its temper-pre-commit gets this plugin's path" "0|yes|yes|.git/user-gate" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .git/user-gate/pre-commit calls the Temper hook ($WORKDIR/.git/temper-pre-commit), which is now current, so nothing else was written.")|$(grep -qxF "$L_CLI_LINE" .git/temper-pre-commit && echo yes || echo no)|$(_l_path "$WORKDIR")"
assert_exit "through the line of Temper 9.6.5, a real commit on a red gate is blocked" 1 git commit -q -m l1
rm -f .git/temper-pre-commit
# A temper-gate/pre-commit that is a folder cannot be replaced, and a temper-gate folder that is a
# symlink is never written through: each refusal writes nothing there and prints the whole hook.
git config --unset core.hooksPath
rm -rf .git/temper-gate
mkdir -p .git/temper-gate/pre-commit
printf '#!/bin/sh\necho mine\n' > .git/default-gate/pre-commit
OUT=$(bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a temper-gate/pre-commit folder is left empty and the refusal prints the whole hook" "1||yes|yes" \
  "$L_RC|$(ls -A .git/temper-gate/pre-commit)|$(_l_line "$OUT" 'Nothing was written. To use the Temper commit gate, add the lines between the BEGIN and END lines below to your pre-commit hook.')|$(_l_has "$OUT" "$L_DG_CLI_LINE")"
rm -rf .git/temper-gate "$WORKDIR/l1-gate-target"
mkdir -p "$WORKDIR/l1-gate-target"
ln -s "$WORKDIR/l1-gate-target" .git/temper-gate
OUT=$(bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a temper-gate folder that is a symlink is refused and nothing is written through it" "1|yes||none" \
  "$L_RC|$(_l_has "$OUT" "FAIL: $WORKDIR/.git/temper-gate is a symlink. This installer writes the hook only into a real folder there.")|$(ls -A "$WORKDIR/l1-gate-target")|$(_l_path "$WORKDIR")"
rm -rf .git/temper-gate .git/default-gate .git/user-gate "$WORKDIR/l1-gate-target"
git rm -q --cached l1-file.txt >/dev/null 2>&1 || true
rm -f l1-file.txt .git/temper-pre-commit
if [[ -n "$L_DASH" ]]; then
  assert_exit "the line is plain sh: dash reads it without a syntax error" 0 "$L_DASH" -n "$L_LINES"
fi

# The call line keeps the result of the hook it is added to: a hook whose last command fails still
# blocks with the line at its end or at its start, and a hook that passes still lets a commit with
# no run through. The whole hook an early refusal prints, in its subshell, does the same. Git runs
# each of these hooks from .git/user-gate, which core.hooksPath names.
L_FL="$WORKDIR/l1-failing"
_l_repo "$L_FL"
printf '.temper/\n' > "$L_FL/.gitignore"
git -C "$L_FL" add .gitignore >/dev/null 2>&1
git -C "$L_FL" commit -q -m ignore
mkdir -p "$L_FL/.git/user-gate"
git -C "$L_FL" config core.hooksPath .git/user-gate
printf '#!/bin/sh\necho "lint: 3 errors" >&2\nfalse\n' > "$L_FL/.git/user-gate/pre-commit"
chmod +x "$L_FL/.git/user-gate/pre-commit"
echo f > "$L_FL/f.txt"
git -C "$L_FL" add f.txt >/dev/null 2>&1
L_N="$(_l_commits "$L_FL")"
assert_exit "a hook of the user's whose last command fails blocks a commit" 1 git -C "$L_FL" commit -q -m f
OUT=$(cd "$L_FL" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "that hook is refused, with the hook kept" "1|yes" "$L_RC|$(_l_kept "$L_FL")"
printf '%s\n' "$L_CALL" >> "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the line at its end, the failing hook still blocks a commit" 1 git -C "$L_FL" commit -q -m f
printf '#!/bin/sh\n%s\necho "lint: 3 errors" >&2\nfalse\n' "$L_CALL" > "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the line at its start, the failing hook still blocks a commit" 1 git -C "$L_FL" commit -q -m f
assert_eq "no commit landed" "$L_N" "$(_l_commits "$L_FL")"
OUT=$(cd "$L_FL" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the line at the start of the hook is found by a re-run" "0|yes" "$L_RC|$(_l_has "$OUT" 'calls the Temper hook')"
printf '#!/bin/sh\n%s\necho "lint: clean" >&2\n' "$L_CALL" > "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the line at the start of a hook that passes, a commit with no run passes" 0 git -C "$L_FL" commit -q -m f
_l_red "$L_FL"
echo g > "$L_FL/g.txt"
git -C "$L_FL" add g.txt >/dev/null 2>&1
assert_exit "with the line at the start of a hook that passes, a commit on a red gate is blocked" 1 git -C "$L_FL" commit -q -m g
rm -rf "$L_FL/.temper"
# The whole hook an early refusal prints (here: the CLI does not run yet), in its subshell.
chmod -x "$L_PLUG/scripts/temper"
OUT=$(cd "$L_FL" && bash "$L_INSTALL" 2>&1)
chmod +x "$L_PLUG/scripts/temper"
_l_lines "$OUT"
cp "$L_LINES" "$WORKDIR/l1-wrapped-lines.sh"
if [[ -n "$L_DASH" ]]; then
  assert_exit "the whole hook in its subshell is plain sh: dash reads it without a syntax error" 0 "$L_DASH" -n "$WORKDIR/l1-wrapped-lines.sh"
fi
{ printf '#!/bin/sh\necho "lint: 3 errors" >&2\nfalse\n'; cat "$WORKDIR/l1-wrapped-lines.sh"; } > "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the whole hook in its subshell at its end, the failing hook still blocks a commit" 1 git -C "$L_FL" commit -q -m g
{ printf '#!/bin/sh\n'; cat "$WORKDIR/l1-wrapped-lines.sh"; printf 'echo "lint: 3 errors" >&2\nfalse\n'; } > "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the whole hook in its subshell at its start, the failing hook still blocks a commit" 1 git -C "$L_FL" commit -q -m g
{ printf '#!/bin/sh\n'; cat "$WORKDIR/l1-wrapped-lines.sh"; printf 'echo "lint: clean" >&2\n'; } > "$L_FL/.git/user-gate/pre-commit"
assert_exit "with the whole hook in its subshell at the start of a hook that passes, a commit with no run passes" 0 git -C "$L_FL" commit -q -m g
_l_red "$L_FL"
echo h > "$L_FL/h.txt"
git -C "$L_FL" add h.txt >/dev/null 2>&1
assert_exit "with the whole hook in its subshell at the start of a hook that passes, a commit on a red gate is blocked" 1 git -C "$L_FL" commit -q -m h
rm -rf "$L_FL" "$WORKDIR/l1-wrapped-lines.sh"

# A lefthook-shaped hook (lefthook writes its hook with an early 'exit 0' for LEFTHOOK=0 and no
# set -e): refused with the lefthook hint in the default folder and in .git/user-gate, and a failing
# lefthook run that git runs from .git/user-gate still blocks with the line at the end or at the
# start.
L_LH="$WORKDIR/l1-lefthook"
_l_repo "$L_LH"
printf '#!/bin/sh\necho "lefthook: eslint failed" >&2\nexit 1\n' > "$WORKDIR/l1-lefthook-bin"
chmod +x "$WORKDIR/l1-lefthook-bin"
cat > "$WORKDIR/l1-lefthook-hook" <<EOF
#!/bin/sh

if [ "\$LEFTHOOK_VERBOSE" = "1" -o "\$LEFTHOOK_VERBOSE" = "true" ]; then
  set -x
fi

if [ "\$LEFTHOOK" = "0" ]; then
  exit 0
fi

call_lefthook()
{
  "$WORKDIR/l1-lefthook-bin" "\$@"
}

call_lefthook run "pre-commit" "\$@"
EOF
mkdir -p "$L_LH/.git/default-gate"
cp "$WORKDIR/l1-lefthook-hook" "$L_LH/.git/default-gate/pre-commit"
chmod +x "$L_LH/.git/default-gate/pre-commit"
OUT=$(cd "$L_LH" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "the lefthook-shaped hook in the default folder is refused with the lefthook hint, with the hook kept" "1|yes|yes" \
  "$L_RC|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF 'Hint: lefthook writes this hook again. Add a pre-commit command to lefthook.yml that runs the line.' && echo yes || echo no)|$(_l_dg_kept "$L_LH")"
rm -rf "$L_LH/.git/default-gate"
mkdir -p "$L_LH/.git/user-gate"
cp "$WORKDIR/l1-lefthook-hook" "$L_LH/.git/user-gate/pre-commit"
chmod +x "$L_LH/.git/user-gate/pre-commit"
git -C "$L_LH" config core.hooksPath .git/user-gate
echo l > "$L_LH/l.txt"
git -C "$L_LH" add l.txt >/dev/null 2>&1
L_N="$(_l_commits "$L_LH")"
assert_exit "a lefthook-shaped hook whose lefthook run fails blocks a commit" 1 git -C "$L_LH" commit -q -m l
OUT=$(cd "$L_LH" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the lefthook-shaped hook in .git/user-gate is refused with the lefthook hint, with the hook kept" "1|yes|yes" \
  "$L_RC|$(_l_last "$OUT" 'Hint: lefthook writes this hook again. Add a pre-commit command to lefthook.yml that runs the line.')|$(_l_kept "$L_LH")"
printf '%s\n' "$L_CALL" >> "$L_LH/.git/user-gate/pre-commit"
assert_exit "with the line at its end, the failing lefthook-shaped hook still blocks a commit" 1 git -C "$L_LH" commit -q -m l
{ sed -n 1p "$WORKDIR/l1-lefthook-hook"; printf '%s\n' "$L_CALL"; sed 1d "$WORKDIR/l1-lefthook-hook"; } > "$L_LH/.git/user-gate/pre-commit"
assert_exit "with the line at its start, the failing lefthook-shaped hook still blocks a commit" 1 git -C "$L_LH" commit -q -m l
assert_eq "no commit landed in the lefthook-shaped repository" "$L_N" "$(_l_commits "$L_LH")"
OUT=$(cd "$L_LH" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the line at the start of the lefthook-shaped hook is found by a re-run" "0|yes" "$L_RC|$(_l_has "$OUT" 'calls the Temper hook')"
rm -rf "$L_LH" "$WORKDIR/l1-lefthook-bin" "$WORKDIR/l1-lefthook-hook"

# The line after an exit or exec line never runs: refused, and the hook (here in the default folder)
# is left as it was. A line that only starts with the letters of exit (exit_code=...) does not
# count.
L_EX="$WORKDIR/l1-exit"
_l_repo "$L_EX"
mkdir -p "$L_EX/.git/default-gate"
printf '#!/bin/sh\necho mine\nexit 0\n%s\n' "$L_CALL" > "$L_EX/.git/default-gate/pre-commit"
chmod +x "$L_EX/.git/default-gate/pre-commit"
L_SUM="$(cksum < "$L_EX/.git/default-gate/pre-commit")"
OUT=$(cd "$L_EX" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "the line after an 'exit 0' line is refused, and the hook is left as it was" "1|yes|yes|none" \
  "$L_RC|$(_l_line "$OUT" "FAIL: the Temper line in $L_EX/.git/default-gate/pre-commit comes after an exit or exec line, so it never runs. Move it above that line.")|$([[ "$(cksum < "$L_EX/.git/default-gate/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(_l_path "$L_EX")"
printf '#!/bin/sh\n  exec "$(dirname "$0")/other-hook" "$@"\n%s\n' "$L_CALL" > "$L_EX/.git/default-gate/pre-commit"
OUT=$(cd "$L_EX" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "the line after an indented exec line is refused" "1|yes" \
  "$L_RC|$(_l_has "$OUT" 'comes after an exit or exec line, so it never runs')"
printf '#!/bin/sh\nexit_code=0\nexecutable=yes\n%s\n' "$L_CALL" > "$L_EX/.git/default-gate/pre-commit"
OUT=$(cd "$L_EX" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "lines that only start with the letters of exit or exec do not count" "0|yes" \
  "$L_RC|$(_l_has "$OUT" 'calls the Temper hook')"
rm -rf "$L_EX"

# A linked worktree runs the same kept hook through the line in the repository's hook: the
# default-gate copy finds that hook in the main checkout's default folder, and git runs it from
# the main checkout's .git/user-gate, which core.hooksPath names by its absolute path.
L_WM="$WORKDIR/l1-wmain"
L_WF="$WORKDIR/l1-wfeat"
_l_repo "$L_WM"
rm -rf "$L_WF"
printf '.temper/\n' > "$L_WM/.gitignore"
git -C "$L_WM" add .gitignore >/dev/null 2>&1
git -C "$L_WM" commit -q -m ignore
git -C "$L_WM" worktree add -q "$L_WF" >/dev/null 2>&1
L_WM_REAL="$(cd -P "$L_WM" && pwd)"
mkdir -p "$L_WM/.git/default-gate"
printf '#!/bin/sh\necho mine\n%s\n' "$L_CALL" > "$L_WM/.git/default-gate/pre-commit"
chmod +x "$L_WM/.git/default-gate/pre-commit"
OUT=$(cd "$L_WF" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "in a linked worktree, the repository's hook in the default folder that holds the line calls the one kept hook" "0|yes|yes|no|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_WM_REAL/.git/default-gate/pre-commit calls the Temper hook ($L_WM_REAL/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_dg_kept "$L_WM")|$([[ -e "$L_WM/.git/worktrees/${L_WF##*/}/temper-gate" ]] && echo yes || echo no)|$(_l_path "$L_WF")"
mkdir -p "$L_WM/.git/user-gate"
cp "$L_WM/.git/default-gate/pre-commit" "$L_WM/.git/user-gate/pre-commit"
git -C "$L_WM" config core.hooksPath "$L_WM_REAL/.git/user-gate"
OUT=$(cd "$L_WF" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "in a linked worktree, that hook in the main checkout's .git/user-gate calls the one kept hook" "0|yes|yes|no|$L_WM_REAL/.git/user-gate" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_WM_REAL/.git/user-gate/pre-commit calls the Temper hook ($L_WM_REAL/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_kept "$L_WM")|$([[ -e "$L_WM/.git/worktrees/${L_WF##*/}/temper-gate" ]] && echo yes || echo no)|$(_l_path "$L_WF")"
echo w > "$L_WF/w.txt"
git -C "$L_WF" add w.txt >/dev/null 2>&1
assert_exit "in the linked worktree, a commit with no run passes through the line" 0 git -C "$L_WF" commit -q -m w
_l_red "$L_WF"
echo v > "$L_WF/v.txt"
git -C "$L_WF" add v.txt >/dev/null 2>&1
assert_exit "in the linked worktree, a commit on a red gate is blocked through the line" 1 git -C "$L_WF" commit -q -m v
rm -rf "$L_WM" "$L_WF"

# A core.hooksPath outside the repository: refused with the hook kept and the hint naming the hook
# there; once that hook holds the line, a re-run finds it and a red commit is blocked.
L_OUT="$WORKDIR/l1-outrepo"
L_OUTG="$WORKDIR/l1-outside-gate"
_l_repo "$L_OUT"
rm -rf "$L_OUTG"
mkdir -p "$L_OUTG"
printf '#!/bin/sh\necho outside\n' > "$L_OUTG/pre-commit"
chmod +x "$L_OUTG/pre-commit"
git -C "$L_OUT" config core.hooksPath "$L_OUTG"
L_SUM="$(cksum < "$L_OUTG/pre-commit")"
OUT=$(cd "$L_OUT" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "an outside core.hooksPath is refused with the hook kept and the hint naming the hook there" "1|yes|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '$L_OUTG', a folder that is not Temper's, and this installer never writes into it.")|$(_l_kept "$L_OUT")|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF "Hint: add the line to your own pre-commit hook ($L_OUTG/pre-commit), $L_HINT_END" && echo yes || echo no)"
assert_eq "the outside folder is left as it was, and core.hooksPath too" "yes|pre-commit|$L_OUTG" \
  "$([[ "$(cksum < "$L_OUTG/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(ls -A "$L_OUTG")|$(_l_path "$L_OUT")"
printf '%s\n' "$L_CALL" >> "$L_OUTG/pre-commit"
OUT=$(cd "$L_OUT" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "once the outside hook holds the line, a re-run says it calls the Temper hook" "0|yes" "$L_RC|$(_l_has "$OUT" "calls the Temper hook ($(cd -P "$L_OUT" && pwd)/.git/temper-gate/pre-commit)")"
printf '.temper/\n' > "$L_OUT/.gitignore"
_l_red "$L_OUT"
git -C "$L_OUT" add .gitignore >/dev/null 2>&1
assert_exit "through the outside hook, a commit on a red gate is blocked" 1 git -C "$L_OUT" commit -q -m red
rm -rf "$L_OUT" "$L_OUTG"

# husky v5 to v8: core.hooksPath is .husky, .husky/pre-commit is tracked and sources husky.sh,
# which runs the hook again with sh -e.
L_H8="$WORKDIR/l1-husky8"
_l_repo "$L_H8"
mkdir -p "$L_H8/.husky/_"
cat > "$L_H8/.husky/_/husky.sh" <<'EOF'
#!/usr/bin/env sh
if [ -z "$husky_skip_init" ]; then
  readonly husky_skip_init=1
  export husky_skip_init
  sh -e "$0" "$@"
  exitCode="$?"
  if [ $exitCode != 0 ]; then
    echo "husky - $(basename -- "$0") hook exited with code $exitCode (error)"
  fi
  exit $exitCode
fi
EOF
printf '*\n' > "$L_H8/.husky/_/.gitignore"
printf '#!/usr/bin/env sh\n. "$(dirname -- "$0")/_/husky.sh"\n\necho husky-ran >> husky.log\n' > "$L_H8/.husky/pre-commit"
chmod +x "$L_H8/.husky/pre-commit"
printf 'husky.log\n.temper/\n' > "$L_H8/.gitignore"
git -C "$L_H8" config core.hooksPath .husky
git -C "$L_H8" add .gitignore .husky/pre-commit >/dev/null 2>&1
env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m husky >/dev/null 2>&1
L_SUM="$(cksum < "$L_H8/.husky/pre-commit")"
L_LIST="$(cd "$L_H8/.husky" && ls -A . _)"
OUT=$(cd "$L_H8" && env PATH="$L_BIN:$PATH" bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v8: install.sh never writes into .husky, keeps the hook, and gives the husky hint" "1|yes|yes|$L_CALL|yes" \
  "$L_RC|$(_l_has "$OUT" "FAIL: core.hooksPath is set to '.husky', a folder that is not Temper's, and this installer never writes into it.")|$(_l_kept "$L_H8")|$(_l_lines "$OUT"; cat "$L_LINES")|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF 'Hint: add the line to .husky/pre-commit. It holds no path of this machine, so it is safe to commit.' && echo yes || echo no)"
assert_eq "husky v8: the refusal leaves .husky and core.hooksPath as they were and adds no file to the work tree" "yes|yes|.husky|" \
  "$([[ "$(cksum < "$L_H8/.husky/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$([[ "$(cd "$L_H8/.husky" && ls -A . _)" == "$L_LIST" ]] && echo yes || echo no)|$(_l_path "$L_H8")|$(git -C "$L_H8" status --short)"
rm -f "$L_H8/husky.log"
echo a > "$L_H8/a.txt"
git -C "$L_H8" add a.txt >/dev/null 2>&1
assert_exit "husky v8: after the refusal a commit still works under sh" 0 env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m a
_l_lines "$OUT"
cat "$L_LINES" >> "$L_H8/.husky/pre-commit"
rm -f "$L_H8/husky.log"
echo b > "$L_H8/b.txt"
git -C "$L_H8" add b.txt .husky/pre-commit >/dev/null 2>&1
assert_exit "husky v8: with the line at the end of .husky/pre-commit, a green commit (no run) passes under sh" 0 \
  env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m b
assert_eq "husky v8: husky's own line ran once" "husky-ran" "$(cat "$L_H8/husky.log" 2>/dev/null)"
assert_eq "husky v8: the committed .husky/pre-commit holds the line and no path of this machine" "yes|0" \
  "$(git -C "$L_H8" show HEAD:.husky/pre-commit | grep -qxF "$L_CALL" && echo yes || echo no)|$(git -C "$L_H8" show HEAD:.husky/pre-commit | grep -cF "$WORKDIR")"
_l_red "$L_H8"
echo c > "$L_H8/c.txt"
git -C "$L_H8" add c.txt >/dev/null 2>&1
assert_exit "husky v8: with the line at the end of .husky/pre-commit, a commit on a red gate is blocked under sh" 1 \
  env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m c
OUT=$(cd "$L_H8" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v8: once .husky/pre-commit holds the line, install.sh says it calls the Temper hook and writes nothing else" "0|yes|" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .husky/pre-commit calls the Temper hook ($L_H8/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(git -C "$L_H8" status --short -- .husky)"
rm -rf "$L_H8"

# husky v9: core.hooksPath is .husky/_, where husky's generated hook runs .husky/pre-commit with sh -e.
L_H9="$WORKDIR/l1-husky9"
_l_repo "$L_H9"
mkdir -p "$L_H9/.husky/_"
printf '#!/usr/bin/env sh\n. "${0%%/*}/h"\n' > "$L_H9/.husky/_/pre-commit"
printf '#!/usr/bin/env sh\nn=$(basename "$0")\ns=$(dirname "$(dirname "$0")")/$n\n[ -f "$s" ] || exit 0\nsh -e "$s" "$@"\n' > "$L_H9/.husky/_/h"
printf '*\n' > "$L_H9/.husky/_/.gitignore"
chmod +x "$L_H9/.husky/_/pre-commit" "$L_H9/.husky/_/h"
printf 'echo husky-ran >> husky.log\n' > "$L_H9/.husky/pre-commit"
printf 'husky.log\n.temper/\n' > "$L_H9/.gitignore"
git -C "$L_H9" config core.hooksPath .husky/_
git -C "$L_H9" add .gitignore .husky/pre-commit >/dev/null 2>&1
env PATH="$L_BIN:$PATH" git -C "$L_H9" commit -q -m husky >/dev/null 2>&1
L_SUM="$(cksum < "$L_H9/.husky/_/pre-commit")"
L_LIST="$(cd "$L_H9/.husky" && ls -A . _)"
OUT=$(cd "$L_H9" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v9: install.sh never writes into husky's generated folder, keeps the hook, and gives the husky hint" "1|yes|yes|yes|yes|$L_CALL|yes" \
  "$L_RC|$(_l_has "$OUT" "FAIL: core.hooksPath is set to '.husky/_', a folder that is not Temper's, and this installer never writes into it.")|$([[ "$(cksum < "$L_H9/.husky/_/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$([[ "$(cd "$L_H9/.husky" && ls -A . _)" == "$L_LIST" ]] && echo yes || echo no)|$(_l_kept "$L_H9")|$(_l_lines "$OUT"; cat "$L_LINES")|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF 'Hint: add the line to .husky/pre-commit. It holds no path of this machine, so it is safe to commit.' && echo yes || echo no)"
_l_lines "$OUT"
cat "$L_LINES" >> "$L_H9/.husky/pre-commit"
rm -f "$L_H9/husky.log"
echo a > "$L_H9/a.txt"
git -C "$L_H9" add a.txt .husky/pre-commit >/dev/null 2>&1
assert_exit "husky v9: with the line at the end of .husky/pre-commit, a green commit (no run) passes under sh" 0 \
  env PATH="$L_BIN:$PATH" git -C "$L_H9" commit -q -m a
assert_eq "husky v9: husky's own line ran once" "husky-ran" "$(cat "$L_H9/husky.log" 2>/dev/null)"
assert_eq "husky v9: the committed .husky/pre-commit holds the line and no path of this machine" "yes|0" \
  "$(git -C "$L_H9" show HEAD:.husky/pre-commit | grep -qxF "$L_CALL" && echo yes || echo no)|$(git -C "$L_H9" show HEAD:.husky/pre-commit | grep -cF "$WORKDIR")"
_l_red "$L_H9"
echo b > "$L_H9/b.txt"
git -C "$L_H9" add b.txt >/dev/null 2>&1
assert_exit "husky v9: with the line at the end of .husky/pre-commit, a commit on a red gate is blocked under sh" 1 \
  env PATH="$L_BIN:$PATH" git -C "$L_H9" commit -q -m b
OUT=$(cd "$L_H9" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v9: once .husky/pre-commit holds the line, install.sh says it calls the Temper hook and writes nothing else" "0|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .husky/pre-commit calls the Temper hook ($L_H9/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$([[ "$(cksum < "$L_H9/.husky/_/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)"
rm -rf "$L_H9"

# The pre-commit framework: its hook in the default folder is refused with the local-hook hint, and
# core.hooksPath stays unset (the framework refuses to install while it is set). The entry the hint
# gives splits, as the framework splits it, into sh, -c and the line, and reads back from YAML as
# it is written. A local hook with that entry (here the framework's hook in .git/user-gate runs it
# the way such an entry does) lets a commit with no run through after the framework's own checks,
# and a red gate still blocks.
L_PC="$WORKDIR/l1-precommit"
_l_repo "$L_PC"
cat > "$WORKDIR/l1-framework-hook" <<'EOF'
#!/usr/bin/env bash
# File generated by pre-commit
if [ -n "${PRE_COMMIT_RUNNING_LEGACY:-}" ]; then
  echo "bug: pre-commit's script is installed in migration mode" >&2
  exit 1
fi
if [ -x "${0%/*}/pre-commit.legacy" ]; then
  PRE_COMMIT_RUNNING_LEGACY=1 "${0%/*}/pre-commit.legacy" "$@" || exit 1
fi
echo framework-ran >> framework.log
EOF
mkdir -p "$L_PC/.git/default-gate"
cp "$WORKDIR/l1-framework-hook" "$L_PC/.git/default-gate/pre-commit"
chmod +x "$L_PC/.git/default-gate/pre-commit"
L_PC_HINT="Hint: the pre-commit framework owns this hook. Add a local hook to .pre-commit-config.yaml (repo: local, language: system, pass_filenames: false, always_run: true) with this entry: sh -c '$L_CALL'"
OUT=$(cd "$L_PC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "the pre-commit framework's hook in the default folder is refused with the local-hook hint, and core.hooksPath stays unset" "1|yes|yes|none|yes" \
  "$L_RC|$(_l_has "$OUT" "FAIL: $L_PC/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: pre-commit.")|$(_l_last "$OUT" "$L_PC_HINT")|$(_l_path "$L_PC")|$(_l_dg_kept "$L_PC")"
L_PC_ENTRY="$(printf '%s\n' "$OUT" | tail -1)"
L_PC_ENTRY="${L_PC_ENTRY#*with this entry: }"
assert_eq "the entry in that hint splits, as the framework splits it, into sh, -c and the line" "True" \
  "$(python3 -c 'import shlex, sys; print(shlex.split(sys.argv[1]) == ["sh", "-c", sys.argv[2]])' "$L_PC_ENTRY" "$L_CALL")"
# The framework reads the entry from YAML. That check needs PyYAML, so it is skipped when PyYAML
# does not import.
if python3 -c 'import yaml' >/dev/null 2>&1; then
  assert_eq "the entry in that hint reads back from YAML as it is written" "True" \
    "$(python3 -c 'import sys, yaml; print(yaml.safe_load("entry: " + sys.argv[1])["entry"] == sys.argv[1])' "$L_PC_ENTRY")"
fi
rm -rf "$L_PC/.git/default-gate"
mkdir -p "$L_PC/.git/user-gate"
cp "$WORKDIR/l1-framework-hook" "$L_PC/.git/user-gate/pre-commit"
chmod +x "$L_PC/.git/user-gate/pre-commit"
git -C "$L_PC" config core.hooksPath .git/user-gate
OUT=$(cd "$L_PC" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the framework's hook in .git/user-gate is refused with the same hint, with the hook kept" "1|yes|yes" \
  "$L_RC|$(_l_last "$OUT" "$L_PC_HINT")|$(_l_kept "$L_PC")"
{ printf '#!/usr/bin/env bash\n# File generated by pre-commit\n'; printf '%s || exit 1\n' "$L_PC_ENTRY"; printf 'echo framework-ran >> framework.log\n'; } > "$L_PC/.git/user-gate/pre-commit"
printf 'framework.log\n.temper/\n' > "$L_PC/.gitignore"
git -C "$L_PC" add .gitignore >/dev/null 2>&1
assert_exit "the framework running the line from a local hook entry: a commit with no run passes" 0 git -C "$L_PC" commit -q -m framework
assert_eq "the framework's own checks ran" "framework-ran" "$(cat "$L_PC/framework.log" 2>/dev/null)"
_l_red "$L_PC"
echo x > "$L_PC/x.txt"
git -C "$L_PC" add x.txt >/dev/null 2>&1
assert_exit "the framework running the line from a local hook entry: a commit on a red gate is blocked" 1 git -C "$L_PC" commit -q -m red
rm -rf "$L_PC" "$WORKDIR/l1-framework-hook"

# A team's folder (.team-gate here stands for a team's tracked folder of hooks): a tracked
# pre-commit, even an older Temper hook, is never written; neither is an empty folder git does not
# ignore, nor one that cannot be made. An older Temper hook there (Temper 9.6.4 and 9.6.5 wrote into
# such a folder) is named as the hook git runs, with its stale path, and the hint to replace it. For
# an empty folder the hint says to create the hook there, and once it holds the line a re-run finds
# it.
L_TR="$WORKDIR/l1-tracked"
_l_repo "$L_TR"
mkdir -p "$L_TR/.team-gate"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_TR/.team-gate/pre-commit"
chmod +x "$L_TR/.team-gate/pre-commit"
git -C "$L_TR" add .team-gate/pre-commit >/dev/null 2>&1
git -C "$L_TR" commit -q -m team-gate
git -C "$L_TR" config core.hooksPath .team-gate
L_SUM="$(cksum < "$L_TR/.team-gate/pre-commit")"
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a tracked pre-commit (here an older Temper hook) is refused and left as it was" "1|yes|yes|" \
  "$L_RC|$(_l_has "$OUT" "FAIL: core.hooksPath is set to '.team-gate', a folder that is not Temper's, and this installer never writes into it.")|$([[ "$(cksum < "$L_TR/.team-gate/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(git -C "$L_TR" status --short)"
assert_eq "that older Temper hook is named as the hook git runs, with its stale path that does not exist, and the hint to replace it is last" \
  "yes|yes|yes|yes|yes|yes" "$(_l_older "$OUT" .team-gate/pre-commit /old/plugin/scripts/temper "$L_PLUG/scripts/temper")"
git -C "$L_TR" config core.hooksPath team-gate
mkdir -p "$L_TR/team-gate"
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "an empty team folder git does not ignore gets nothing, and the hint says to create the hook there" "1||yes" \
  "$L_RC|$(ls -A "$L_TR/team-gate")|$(printf '%s\n' "$OUT" | tail -1 | grep -qxF "Hint: add the line to your own pre-commit hook (team-gate/pre-commit), $L_HINT_END" && echo yes || echo no)"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_TR/team-gate/pre-commit"
chmod +x "$L_TR/team-gate/pre-commit"
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "once that hook is created with the line, a re-run says it calls the Temper hook" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook team-gate/pre-commit calls the Temper hook ($L_TR/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")"
# A folder that cannot be made (a file is in the way) is never made: a FAIL line and the hook
# lines, never a bare shell error.
echo x > "$L_TR/blocked"
git -C "$L_TR" config core.hooksPath blocked/gate
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a core.hooksPath folder that cannot be made gives a FAIL line and the hook lines, no shell error" "1|yes|yes|0" \
  "$L_RC|$(_l_has "$OUT" "FAIL: core.hooksPath is set to 'blocked/gate', a folder that is not Temper's, and this installer never writes into it.")|$(_l_has "$OUT" "$L_CALL")|$(printf '%s\n' "$OUT" | grep -c 'mkdir:')"
rm -rf "$L_TR"

# An older Temper hook (9.6.4 and earlier embedded a scripts folder, here that of a fake older
# plugin) next to the backup the old installer made of the user's hook, which it never ran, in the
# default folder: core.hooksPath stays unset (moved back, that hook would run from there), the older
# hook is left as it was, and the backup is named as set aside, with how to restore it, never as a
# hook git would stop running. The older hook is named as the hook git runs, with its stale path,
# and the hint to replace it.
L_OLD="$WORKDIR/l1-old"
_l_repo "$L_OLD"
mkdir -p "$WORKDIR/l1-old-plugin/scripts/old-guards" "$L_OLD/.git/default-gate"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_HOOKS_DIR="${TEMPER_HOOKS_DIR:-%s}"\n' "$WORKDIR/l1-old-plugin/scripts/old-guards" > "$L_OLD/.git/default-gate/pre-commit"
printf '#!/bin/sh\necho user-hook\n' > "$L_OLD/.git/default-gate/pre-commit.bak.20260101000000"
chmod +x "$L_OLD/.git/default-gate/pre-commit" "$L_OLD/.git/default-gate/pre-commit.bak.20260101000000"
L_SUM="$(cksum < "$L_OLD/.git/default-gate/pre-commit")"
OUT=$(cd "$L_OLD" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "an older Temper hook next to an old installer's backup in the default folder: refused naming the backup as set aside, the older hook left, core.hooksPath unset" "1|yes|yes|none" \
  "$L_RC|$(_l_line "$OUT" "FAIL: $L_OLD/.git/default-gate holds a hook an older Temper installer set aside (pre-commit.bak.20260101000000). Moved back, git would run it, but not once core.hooksPath pointed at Temper's folder.")|$([[ "$(cksum < "$L_OLD/.git/default-gate/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(_l_path "$L_OLD")"
assert_eq "the old installer's backup is named, with how to move it back and the line to add" "yes|$L_CALL|yes" \
  "$(_l_line "$OUT" "Warning: $L_OLD/.git/default-gate/pre-commit.bak.20260101000000 is a pre-commit hook that an older Temper installer set aside, and git does not run it. To run it again, move it back to $L_OLD/.git/default-gate/pre-commit and add the line between the BEGIN and END lines below to it.")|$(_l_lines "$OUT"; cat "$L_LINES")|$(_l_dg_kept "$L_OLD")"
assert_eq "no hook is said to run first, and no hook is listed as one git would stop running" "no|no" \
  "$(_l_has "$OUT" 'runs it first')|$(_l_has "$OUT" 'holds hooks git would stop running')"
assert_eq "the older hook is named as the hook git runs, with its stale scripts folder (which exists, so not failing open), and the hint to replace it is last" \
  "yes|yes|yes|yes|no|yes" "$(_l_older "$OUT" "$L_OLD/.git/default-gate/pre-commit" "$WORKDIR/l1-old-plugin/scripts/old-guards" "$L_DG/scripts/temper")"
# Moved back with the line added, the user's hook runs the kept hook, and a re-run finds the line;
# in .git/user-gate, where git runs it, it blocks a commit on a red gate.
mv "$L_OLD/.git/default-gate/pre-commit.bak.20260101000000" "$L_OLD/.git/default-gate/pre-commit"
cat "$L_LINES" >> "$L_OLD/.git/default-gate/pre-commit"
OUT=$(cd "$L_OLD" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a re-run finds the line in the hook moved back" "0|yes" "$L_RC|$(_l_has "$OUT" 'calls the Temper hook')"
mkdir -p "$L_OLD/.git/user-gate"
cp "$L_OLD/.git/default-gate/pre-commit" "$L_OLD/.git/user-gate/pre-commit"
git -C "$L_OLD" config core.hooksPath .git/user-gate
OUT=$(cd "$L_OLD" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the hook moved back, in .git/user-gate, calls the Temper hook too" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .git/user-gate/pre-commit calls the Temper hook ($L_OLD/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")"
printf '.temper/\n' > "$L_OLD/.gitignore"
_l_red "$L_OLD"
git -C "$L_OLD" add .gitignore >/dev/null 2>&1
assert_exit "the backup moved back with the line added, in .git/user-gate, blocks a commit on a red gate" 1 git -C "$L_OLD" commit -q -m red
rm -rf "$L_OLD"
# A hook of the user's that git runs (a commit-msg) next to such a backup: the reason lists the
# commit-msg only and names the backup in a sentence of its own.
L_BK="$WORKDIR/l1-both"
_l_repo "$L_BK"
mkdir -p "$L_BK/.git/default-gate"
printf '#!/bin/sh\necho commit-msg-ran >&2\n' > "$L_BK/.git/default-gate/commit-msg"
printf '#!/bin/sh\necho user-hook\n' > "$L_BK/.git/default-gate/pre-commit.bak.20260101000000"
chmod +x "$L_BK/.git/default-gate/commit-msg" "$L_BK/.git/default-gate/pre-commit.bak.20260101000000"
L_SUM="$(cksum < "$L_BK/.git/default-gate/commit-msg")|$(cksum < "$L_BK/.git/default-gate/pre-commit.bak.20260101000000")"
L_LIST="$(ls -A "$L_BK/.git/default-gate")"
OUT=$(cd "$L_BK" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a commit-msg next to an old installer's backup in the default folder: the commit-msg listed, the backup named apart, core.hooksPath unset" "1|yes|yes|none|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: $L_BK/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: commit-msg. It also holds a hook an older Temper installer set aside (pre-commit.bak.20260101000000).")|$(_l_line "$OUT" "Warning: $L_BK/.git/default-gate/pre-commit.bak.20260101000000 is a pre-commit hook that an older Temper installer set aside, and git does not run it. To run it again, move it back to $L_BK/.git/default-gate/pre-commit and add the line between the BEGIN and END lines below to it.")|$(_l_path "$L_BK")|$(_l_dg_kept "$L_BK")"
assert_eq "that folder is left as it was, and the hint says to create its pre-commit with the line" "yes|yes|yes" \
  "$([[ "$(cksum < "$L_BK/.git/default-gate/commit-msg")|$(cksum < "$L_BK/.git/default-gate/pre-commit.bak.20260101000000")" == "$L_SUM" ]] && echo yes || echo no)|$([[ "$(ls -A "$L_BK/.git/default-gate")" == "$L_LIST" ]] && echo yes || echo no)|$(_l_last "$OUT" "Hint: add the line to your own pre-commit hook ($L_BK/.git/default-gate/pre-commit), $L_HINT_END")"
rm -rf "$L_BK"
# An older Temper pre-commit with a stale plugin path next to a commit-msg hook in the default
# folder: core.hooksPath stays unset, so git keeps running that older hook in place of the kept
# hook. The reason lists the commit-msg only, the older hook is named as the hook git runs, with
# its stale path, the hint to replace it is last, and nothing in that folder is written.
L_OC="$WORKDIR/l1-old-commit-msg"
_l_repo "$L_OC"
mkdir -p "$L_OC/.git/default-gate"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_OC/.git/default-gate/pre-commit"
printf '#!/bin/sh\necho commit-msg-ran >&2\n' > "$L_OC/.git/default-gate/commit-msg"
chmod +x "$L_OC/.git/default-gate/pre-commit" "$L_OC/.git/default-gate/commit-msg"
L_SUM="$(cksum < "$L_OC/.git/default-gate/pre-commit")|$(cksum < "$L_OC/.git/default-gate/commit-msg")"
OUT=$(cd "$L_OC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "an older Temper pre-commit next to a commit-msg in the default folder: refused naming commit-msg only, the files as they were, core.hooksPath unset" "1|yes|yes|none|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: $L_OC/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: commit-msg.")|$([[ "$(cksum < "$L_OC/.git/default-gate/pre-commit")|$(cksum < "$L_OC/.git/default-gate/commit-msg")" == "$L_SUM" ]] && echo yes || echo no)|$(_l_path "$L_OC")|$(_l_dg_kept "$L_OC")"
assert_eq "the older Temper pre-commit is named as the hook git runs, with its stale path that does not exist, and the hint to replace it is last" \
  "yes|yes|yes|yes|yes|yes" "$(_l_older "$OUT" "$L_OC/.git/default-gate/pre-commit" /old/plugin/scripts/temper "$L_DG/scripts/temper")"
rm -rf "$L_OC"

# An upgrade over a 9.6.5 install (a Temper hook as the default folder's pre-commit, and nothing
# else there that git runs): core.hooksPath is set to the temper-gate folder, nothing in the default
# folder changes, and a note says the old hook can be deleted. A red commit is blocked through the
# kept hook, which git runs from the temper-gate folder.
L_UP="$WORKDIR/l1-upgrade"
_l_repo "$L_UP"
mkdir -p "$L_UP/.git/default-gate"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by scripts/guards/install.sh).\nTEMPER_CLI=%s\n' "$WORKDIR/l1-old-plugin/scripts/temper" > "$L_UP/.git/default-gate/pre-commit"
chmod +x "$L_UP/.git/default-gate/pre-commit"
L_SUM="$(cksum < "$L_UP/.git/default-gate/pre-commit")"
L_LIST="$(ls -A "$L_UP/.git/default-gate")"
OUT=$(cd "$L_UP" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "over a 9.6.5 install, core.hooksPath points at the temper-gate folder and the kept hook is current" "0|$L_UP/.git/temper-gate|yes" \
  "$L_RC|$(_l_path "$L_UP")|$(_l_dg_kept "$L_UP")"
assert_eq "the 9.6.5 hook is left as it was, the default folder is unchanged, and the note says it can be deleted" "yes|yes|yes" \
  "$([[ "$(cksum < "$L_UP/.git/default-gate/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$([[ "$(ls -A "$L_UP/.git/default-gate")" == "$L_LIST" ]] && echo yes || echo no)|$(_l_line "$OUT" "Note: git no longer runs $L_UP/.git/default-gate/pre-commit, a hook from an older Temper; you can delete it.")"
printf '.temper/\n' > "$L_UP/.gitignore"
_l_red "$L_UP"
git -C "$L_UP" add .gitignore >/dev/null 2>&1
assert_exit "after the upgrade, a commit on a red gate is blocked" 1 git -C "$L_UP" commit -q -m red
# A kept hook whose plugin path is stale: a path that still exists is reported but not called
# failing open; a path that is gone is reported as failing open. Both are rewritten.
mkdir -p "$WORKDIR/l1-old-plugin/scripts"
printf '#!/bin/sh\n' > "$WORKDIR/l1-old-plugin/scripts/temper"
sed "s|^TEMPER_CLI=.*|TEMPER_CLI=$WORKDIR/l1-old-plugin/scripts/temper|" "$L_UP/.git/temper-gate/pre-commit" > "$WORKDIR/l1-stale-hook"
cp "$WORKDIR/l1-stale-hook" "$L_UP/.git/temper-gate/pre-commit"
OUT=$(cd "$L_UP" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a stale path that still exists is reported, not called failing open, and the kept hook is rewritten" "0|yes|no|yes|yes" \
  "$L_RC|$(_l_has "$OUT" 'stale plugin path')|$(_l_has "$OUT" 'failing open')|$(_l_kept "$L_UP")|$(_l_line "$OUT" "The Temper pre-commit hook $L_UP/.git/temper-gate/pre-commit was updated to the current plugin paths.")"
sed "s|^TEMPER_CLI=.*|TEMPER_CLI=$WORKDIR/l1-gone-plugin/scripts/temper|" "$L_UP/.git/temper-gate/pre-commit" > "$WORKDIR/l1-stale-hook"
cp "$WORKDIR/l1-stale-hook" "$L_UP/.git/temper-gate/pre-commit"
OUT=$(cd "$L_UP" && bash "$L_INSTALL" 2>&1)
assert_eq "a stale path that is gone is reported as failing open" "yes|yes" "$(_l_has "$OUT" 'failing open')|$(_l_kept "$L_UP")"
rm -rf "$L_UP" "$WORKDIR/l1-old-plugin" "$WORKDIR/l1-stale-hook"

# --global does what the default does (with a note): refused over hooks of the user's in the
# default folder (git would skip them once core.hooksPath is set), where a pre-commit that holds the
# line is then found next to them; otherwise it sets an absolute core.hooksPath, which a linked
# worktree uses, so its commits are gated too. The same hooks in .git/user-gate, where git runs
# them, keep running after a refusal, and a pre-commit there with the line gates commits next to
# them.
L_GM="$WORKDIR/l1-gmain"
L_GW="$WORKDIR/l1-gwt"
_l_repo "$L_GM"
rm -rf "$L_GW"
git -C "$L_GM" worktree add -q "$L_GW" >/dev/null 2>&1
L_GM_REAL="$(cd -P "$L_GM" && pwd)"
mkdir -p "$L_GM/.git/default-gate"
printf '#!/bin/sh\necho mine\n' > "$L_GM/.git/default-gate/pre-commit"
chmod +x "$L_GM/.git/default-gate/pre-commit"
OUT=$(cd "$L_GM" && bash "$L_DG_INSTALL" --global 2>&1); L_RC=$?
assert_eq "--global refuses when the default folder holds a pre-commit hook that is not Temper's, as the default does" "1|yes|yes|$L_CALL|none" \
  "$L_RC|$(_l_line "$OUT" 'Note: the default install now does what --global did.')|$(_l_line "$OUT" "FAIL: $L_GM_REAL/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: pre-commit.")|$(_l_lines "$OUT"; cat "$L_LINES")|$(_l_path "$L_GM")"
rm -f "$L_GM/.git/default-gate/pre-commit"
# A commit-msg hook (and any of git's other hook names) counts too; a hook that is not executable,
# a sample and an older Temper pre-commit do not, since git would not run them anyway or no longer
# needs them.
printf '#!/bin/sh\necho commit-msg-ran >&2\n' > "$L_GM/.git/default-gate/commit-msg"
printf '#!/bin/sh\necho lfs\n' > "$L_GM/.git/default-gate/pre-push"
printf '#!/bin/sh\necho off\n' > "$L_GM/.git/default-gate/post-commit"
chmod +x "$L_GM/.git/default-gate/commit-msg" "$L_GM/.git/default-gate/pre-push"
chmod -x "$L_GM/.git/default-gate/post-commit"
printf '#!/bin/sh\necho sample\n' > "$L_GM/.git/default-gate/post-merge.sample"
chmod +x "$L_GM/.git/default-gate/post-merge.sample"
L_LIST="$(ls -A "$L_GM/.git/default-gate")"
OUT=$(cd "$L_GM" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a commit-msg and a pre-push hook in the default folder are refused and named; core.hooksPath stays unset" "1|yes|none" \
  "$L_RC|$(_l_line "$OUT" "FAIL: $L_GM_REAL/.git/default-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: commit-msg pre-push.")|$(_l_path "$L_GM")"
assert_eq "the hint says to create the default folder's pre-commit with the line, and nothing in that folder was written" "yes|yes" \
  "$(printf '%s\n' "$OUT" | tail -1 | grep -qxF "Hint: add the line to your own pre-commit hook ($L_GM_REAL/.git/default-gate/pre-commit), $L_HINT_END" && echo yes || echo no)|$([[ "$(ls -A "$L_GM/.git/default-gate")" == "$L_LIST" ]] && echo yes || echo no)"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_GM/.git/default-gate/pre-commit"
chmod +x "$L_GM/.git/default-gate/pre-commit"
OUT=$(cd "$L_GM" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "with the line in a new pre-commit in the default folder next to them, a re-run says it calls the Temper hook" "0|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_GM_REAL/.git/default-gate/pre-commit calls the Temper hook ($L_GM_REAL/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_path "$L_GM")"
# The same four files in .git/user-gate: the refusal leaves core.hooksPath as it was, so git still
# runs the commit-msg. The line in a new pre-commit there, next to those hooks: a re-run finds it,
# a red commit is blocked, and a failing hook keeps its own result.
mkdir -p "$L_GM/.git/user-gate"
cp -p "$L_GM/.git/default-gate/commit-msg" "$L_GM/.git/default-gate/pre-push" "$L_GM/.git/default-gate/post-commit" \
  "$L_GM/.git/default-gate/post-merge.sample" "$L_GM/.git/user-gate/"
git -C "$L_GM" config core.hooksPath .git/user-gate
L_LIST="$(ls -A "$L_GM/.git/user-gate")"
OUT=$(cd "$L_GM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with a commit-msg and a pre-push hook in .git/user-gate, the refusal leaves core.hooksPath as it was, and commit-msg still runs" "1|yes|.git/user-gate|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '.git/user-gate', a folder that is not Temper's, and this installer never writes into it.")|$(_l_path "$L_GM")|$(_l_has "$(git -C "$L_GM" commit -q --allow-empty -m cm 2>&1)" commit-msg-ran)"
assert_eq "the hint says to create .git/user-gate/pre-commit with the line, and nothing in that folder was written" "yes|yes" \
  "$(_l_last "$OUT" "Hint: add the line to your own pre-commit hook (.git/user-gate/pre-commit), $L_HINT_END")|$([[ "$(ls -A "$L_GM/.git/user-gate")" == "$L_LIST" ]] && echo yes || echo no)"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_GM/.git/user-gate/pre-commit"
chmod +x "$L_GM/.git/user-gate/pre-commit"
OUT=$(cd "$L_GM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with the line in a new .git/user-gate/pre-commit next to them, a re-run says it calls the Temper hook" "0|yes|.git/user-gate" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook .git/user-gate/pre-commit calls the Temper hook ($L_GM_REAL/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_path "$L_GM")"
printf '.temper/\n' > "$L_GM/.gitignore"
_l_red "$L_GM"
echo g > "$L_GM/g.txt"
git -C "$L_GM" add .gitignore g.txt >/dev/null 2>&1
L_N="$(_l_commits "$L_GM")"
assert_exit "through that line, a commit on a red gate is blocked" 1 git -C "$L_GM" commit -q -m red
rm -rf "$L_GM/.temper"
printf '#!/bin/sh\necho "lint: 3 errors" >&2\nfalse\n%s\n' "$L_CALL" > "$L_GM/.git/user-gate/pre-commit"
assert_exit "a failing pre-commit with the line at its end still blocks a commit with no run" 1 git -C "$L_GM" commit -q -m lint
assert_eq "no commit landed" "$L_N" "$(_l_commits "$L_GM")"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_GM/.git/user-gate/pre-commit"
OUT=$(git -C "$L_GM" commit -q -m green 2>&1); L_RC=$?
assert_eq "with that hook passing and no run, the commit lands, and commit-msg runs" "0|yes|$((L_N + 1))" \
  "$L_RC|$(_l_has "$OUT" commit-msg-ran)|$(_l_commits "$L_GM")"
git -C "$L_GM" config --unset core.hooksPath
rm -rf "$L_GM/.git/user-gate"
rm -f "$L_GM/.git/default-gate/commit-msg" "$L_GM/.git/default-gate/pre-push" "$L_GM/.git/default-gate/post-commit" "$L_GM/.git/default-gate/post-merge.sample"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_GM/.git/default-gate/pre-commit"
assert_exit "--global installs in the main checkout (an older Temper pre-commit in the default folder does not count)" 0 bash -c "cd '$L_GM' && bash '$L_DG_INSTALL' --global"
assert_eq "--global sets core.hooksPath to the absolute path of the repository's temper-gate folder" \
  "$L_GM_REAL/.git/temper-gate|$L_GM_REAL/.git/temper-gate/pre-commit" \
  "$(_l_path "$L_GM")|$(git -C "$L_GW" config --get core.hooksPath)/pre-commit"
OUT=$(cd "$L_GW" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "in a linked worktree the default mode accepts that core.hooksPath and finds the hook there" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The Temper pre-commit hook is already installed: $L_GM_REAL/.git/temper-gate/pre-commit (core.hooksPath points at its folder).")"
_l_red "$L_GW"
printf '.temper/\n' > "$L_GW/.gitignore"
echo w > "$L_GW/w.txt"
git -C "$L_GW" add .gitignore w.txt >/dev/null 2>&1
assert_exit "after --global in the main checkout, a commit on a red gate in a linked worktree is blocked" 1 git -C "$L_GW" commit -q -m wt
# The relative value an earlier --global wrote names no folder in a linked worktree: a run there
# points core.hooksPath at the temper-gate folder by its absolute path, with a note and no mkdir
# error. So does the absolute value an earlier --global wrote, and so do the relative and the
# absolute value that --global wrote from 5.5.0 to 9.6.4 (.git/hooks-temper, a folder no case
# makes), with the note on stderr.
git -C "$L_GM" config core.hooksPath .git/temper-git-hooks
OUT=$(cd "$L_GW" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the relative value of an older --global is replaced from a linked worktree, with a note" "0|yes|$L_GM_REAL/.git/temper-gate|0" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder (.git/temper-git-hooks); it now points at $L_GM_REAL/.git/temper-gate.")|$(_l_path "$L_GM")|$(printf '%s\n' "$OUT" | grep -c 'mkdir:')"
git -C "$L_GM" config core.hooksPath "$L_GM_REAL/.git/temper-git-hooks"
OUT=$(cd "$L_GM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the absolute value of an older --global is replaced, with a note" "0|yes|$L_GM_REAL/.git/temper-gate" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder ($L_GM_REAL/.git/temper-git-hooks); it now points at $L_GM_REAL/.git/temper-gate.")|$(_l_path "$L_GM")"
git -C "$L_GM" config core.hooksPath .git/hooks-temper
ERR=$(cd "$L_GM" && bash "$L_INSTALL" 2>&1 >/dev/null); L_RC=$?
assert_eq "the relative value --global wrote from 5.5.0 to 9.6.4 is replaced, with the note on stderr and no folder made" "0|$L_GM_REAL/.git/temper-gate|yes|no" \
  "$L_RC|$(_l_path "$L_GM")|$(_l_line "$ERR" "Note: core.hooksPath held Temper's older folder (.git/hooks-temper); it now points at $L_GM_REAL/.git/temper-gate.")|$([[ -e "$L_GM/.git/hooks-temper" ]] && echo yes || echo no)"
git -C "$L_GM" config core.hooksPath "$L_GM_REAL/.git/hooks-temper"
ERR=$(cd "$L_GM" && bash "$L_INSTALL" 2>&1 >/dev/null); L_RC=$?
assert_eq "so is its absolute form, with the note on stderr and no folder made" "0|$L_GM_REAL/.git/temper-gate|yes|no" \
  "$L_RC|$(_l_path "$L_GM")|$(_l_line "$ERR" "Note: core.hooksPath held Temper's older folder ($L_GM_REAL/.git/hooks-temper); it now points at $L_GM_REAL/.git/temper-gate.")|$([[ -e "$L_GM/.git/hooks-temper" ]] && echo yes || echo no)"
assert_exit "after that, a commit on a red gate in the linked worktree is still blocked" 1 git -C "$L_GW" commit -q -m wt
rm -rf "$L_GM" "$L_GW"

# The repository is moved after an install: core.hooksPath still names a folder where it used to
# be (an older --global folder, or the temper-gate folder). Git runs no hook from there, so a run
# points it at the temper-gate folder here, with a note, and commits are gated again.
L_MV1="$WORKDIR/l1-moved-from"
L_MV2="$WORKDIR/l1-moved-to"
_l_repo "$L_MV1"
rm -rf "$L_MV2"
printf '.temper/\n' > "$L_MV1/.gitignore"
git -C "$L_MV1" add .gitignore >/dev/null 2>&1
git -C "$L_MV1" commit -q -m ignore
bash -c "cd '$L_MV1' && bash '$L_INSTALL'" >/dev/null 2>&1
_l_red "$L_MV1"
echo m > "$L_MV1/m.txt"
git -C "$L_MV1" add m.txt >/dev/null 2>&1
assert_exit "after the install, a commit on a red gate is blocked" 1 git -C "$L_MV1" commit -q -m m
mv "$L_MV1" "$L_MV2"
OUT=$(cd "$L_MV2" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "after a move, the temper-gate folder of where the repository used to be is replaced, with a note" "0|yes|$L_MV2/.git/temper-gate" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder ($L_MV1/.git/temper-gate); it now points at $L_MV2/.git/temper-gate.")|$(_l_path "$L_MV2")"
assert_exit "after the move and a run again, a commit on a red gate is blocked" 1 git -C "$L_MV2" commit -q -m m
OUT=$(cd "$L_MV2" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a further run gives no note and says the hook is already installed" "0|no|yes" \
  "$L_RC|$(_l_has "$OUT" "Temper's older folder")|$(_l_has "$OUT" 'is already installed')"
git -C "$L_MV2" config core.hooksPath "$L_MV1/.git/temper-git-hooks"
OUT=$(cd "$L_MV2" && bash "$L_INSTALL" --global 2>&1); L_RC=$?
assert_eq "an older --global folder from where the repository used to be is replaced too, with a note" "0|yes|$L_MV2/.git/temper-gate" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder ($L_MV1/.git/temper-git-hooks); it now points at $L_MV2/.git/temper-gate.")|$(_l_path "$L_MV2")"
rm -rf "$L_MV1" "$L_MV2"

# The temper-gate folder of where a repository used to be, still there and holding only an older
# Temper pre-commit, is pointed at the temper-gate folder with a note. When it also holds another
# hook git runs (git lfs writes its hooks into the folder core.hooksPath names), core.hooksPath
# stays as it is: the refusal names that hook, the older Temper pre-commit as the hook git runs
# with its stale path, and the hint to replace it, and nothing in that folder is written. Once its
# pre-commit is #!/bin/sh and the line, a re-run finds it, and git runs it from there to gate a real
# commit.
L_OP="$WORKDIR/l1-old-place/.git/temper-gate"
L_OR="$WORKDIR/l1-old-place-repo"
rm -rf "$WORKDIR/l1-old-place"
mkdir -p "$L_OP"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_OP/pre-commit"
chmod +x "$L_OP/pre-commit"
L_SUM="$(cksum < "$L_OP/pre-commit")"
_l_repo "$L_OR"
git -C "$L_OR" config core.hooksPath "$L_OP"
OUT=$(cd "$L_OR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "an older temper-gate folder that holds only an older Temper pre-commit is replaced, with a note, and left as it was" "0|yes|$L_OR/.git/temper-gate|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder ($L_OP); it now points at $L_OR/.git/temper-gate.")|$(_l_path "$L_OR")|$(_l_kept "$L_OR")|$([[ "$(cksum < "$L_OP/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)"
printf '#!/bin/sh\ncommand -v git-lfs >/dev/null 2>&1 || { echo "git lfs is missing" >&2; exit 2; }\ngit lfs pre-push "$@"\n' > "$L_OP/pre-push"
chmod +x "$L_OP/pre-push"
L_SUM="$(cksum < "$L_OP/pre-commit")|$(cksum < "$L_OP/pre-push")"
_l_repo "$L_OR"
git -C "$L_OR" config core.hooksPath "$L_OP"
OUT=$(cd "$L_OR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "an older temper-gate folder that also holds an LFS pre-push is refused naming it, core.hooksPath stays, the hook is kept here, and that folder is left as it was" "1|yes|$L_OP|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '$L_OP', a folder an older Temper set. $L_OP holds hooks git would stop running if core.hooksPath pointed at Temper's folder: pre-push.")|$(_l_path "$L_OR")|$(_l_kept "$L_OR")|$([[ "$(cksum < "$L_OP/pre-commit")|$(cksum < "$L_OP/pre-push")" == "$L_SUM" ]] && echo yes || echo no)"
assert_eq "the older Temper pre-commit there is named as the hook git runs, with its stale path that does not exist, and the hint to replace it is last" \
  "yes|yes|yes|yes|yes|yes" "$(_l_older "$OUT" "$L_OP/pre-commit" /old/plugin/scripts/temper "$L_PLUG/scripts/temper")"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_OP/pre-commit"
OUT=$(cd "$L_OR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "once that pre-commit is #!/bin/sh and the line, a re-run says it calls the Temper hook, and core.hooksPath and the pre-push stay" "0|yes|$L_OP|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_OP/pre-commit calls the Temper hook ($L_OR/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_path "$L_OR")|$([[ "$(cksum < "$L_OP/pre-push")" == "${L_SUM#*|}" ]] && echo yes || echo no)"
printf '.temper/\n' > "$L_OR/.gitignore"
git -C "$L_OR" add .gitignore >/dev/null 2>&1
L_N="$(_l_commits "$L_OR")"
_l_red "$L_OR"
assert_exit "git runs that pre-commit from the older folder: a commit on a red gate is blocked" 1 git -C "$L_OR" commit -q -m red
_l_green "$L_OR"
assert_exit "and a commit on a green gate lands" 0 git -C "$L_OR" commit -q -m green
assert_eq "exactly that one commit landed" "$((L_N + 1))" "$(_l_commits "$L_OR")"
# With the pre-push gone, that pre-commit only runs the kept hook, so the folder is Temper's older
# folder again: core.hooksPath is pointed at the temper-gate folder, and nothing there is written.
rm -f "$L_OP/pre-push"
L_SUM="$(cksum < "$L_OP/pre-commit")"
OUT=$(cd "$L_OR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with only #!/bin/sh and the line left in the older folder, core.hooksPath is pointed at the temper-gate folder, with the note" "0|yes|$L_OR/.git/temper-gate|yes" \
  "$L_RC|$(_l_line "$OUT" "Note: core.hooksPath held Temper's older folder ($L_OP); it now points at $L_OR/.git/temper-gate.")|$(_l_path "$L_OR")|$([[ "$(cksum < "$L_OP/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)"
rm -rf "$L_OR" "$WORKDIR/l1-old-place"

# A pre-commit that only runs the kept hook (#!/bin/sh and the line, as the hint makes of an older
# Temper hook) is not a hook that would stop running. Next to a commit-msg in the default folder it
# calls the Temper hook and core.hooksPath stays unset; once the commit-msg is gone, core.hooksPath
# is pointed at the temper-gate folder. A pre-commit with a line of its own still counts.
L_CO="$WORKDIR/l1-call-only"
_l_repo "$L_CO"
mkdir -p "$L_CO/.git/default-gate"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_CO/.git/default-gate/pre-commit"
printf '#!/bin/sh\nexit 0\n' > "$L_CO/.git/default-gate/commit-msg"
chmod +x "$L_CO/.git/default-gate/pre-commit" "$L_CO/.git/default-gate/commit-msg"
OUT=$(cd "$L_CO" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a pre-commit of #!/bin/sh and the line next to a commit-msg in the default folder calls the Temper hook, and core.hooksPath stays unset" "0|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_CO/.git/default-gate/pre-commit calls the Temper hook ($L_CO/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_path "$L_CO")"
rm -f "$L_CO/.git/default-gate/commit-msg"
OUT=$(cd "$L_CO" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "with the commit-msg gone, core.hooksPath is pointed at the temper-gate folder, and a note says the pre-commit only ran the kept hook" "0|$L_CO/.git/temper-gate|yes|yes" \
  "$L_RC|$(_l_path "$L_CO")|$(_l_dg_kept "$L_CO")|$(_l_line "$OUT" "Note: git no longer runs $L_CO/.git/default-gate/pre-commit, which only ran the kept hook; you can delete it.")"
git -C "$L_CO" config --unset core.hooksPath
printf '#!/bin/sh\necho mine\n%s\n' "$L_CALL" > "$L_CO/.git/default-gate/pre-commit"
OUT=$(cd "$L_CO" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a pre-commit with a line of its own next to the line still counts: it calls the Temper hook, and core.hooksPath stays unset" "0|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_CO/.git/default-gate/pre-commit calls the Temper hook ($L_CO/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")|$(_l_path "$L_CO")"
# A hook an older installer set aside, next to a pre-commit of the user's that git runs: the warning
# says to add its lines to that file, never to move it over it.
printf '#!/bin/sh\necho mine\n' > "$L_CO/.git/default-gate/pre-commit"
printf '#!/bin/sh\necho older-mine\n' > "$L_CO/.git/default-gate/pre-commit.bak.20260101000000"
chmod +x "$L_CO/.git/default-gate/pre-commit" "$L_CO/.git/default-gate/pre-commit.bak.20260101000000"
OUT=$(cd "$L_CO" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "next to a pre-commit of the user's, the warning for a set-aside hook says to add its lines to it, not to move it over it" "1|yes|no|none" \
  "$L_RC|$(_l_line "$OUT" "Warning: $L_CO/.git/default-gate/pre-commit.bak.20260101000000 is a pre-commit hook that an older Temper installer set aside, and git does not run it. To run it again, add its lines to $L_CO/.git/default-gate/pre-commit, a hook git runs now (do not move it over that file), and add the line between the BEGIN and END lines below to that file.")|$(_l_has "$OUT" "move it back to")|$(_l_path "$L_CO")"
rm -rf "$L_CO"

# A relative value of Temper's older folder that must stay (it holds another hook git runs): git
# takes it from each worktree's top, so a linked worktree runs nothing there. The installer sets
# the same folder by its absolute path, says so, and then refuses as for any older folder; once
# that folder's pre-commit is #!/bin/sh and the line, a commit in the linked worktree is gated. The
# older folder names both hold the word hooks, so this case runs a copy of the default-gate plugin
# whose installer takes .git/older-gate as the older value .git/hooks-temper.
L_RV="$WORKDIR/l1-relative-older"
L_RV_WT="$WORKDIR/l1-relative-older-wt"
L_RV_PLUG="$WORKDIR/l1-rv-plugin"
_dg_plugin "$L_RV_PLUG"
sed 's/hooks-temper/older-gate/g' "$L_RV_PLUG/scripts/guards/install.sh" > "$L_RV_PLUG/install.new"
mv "$L_RV_PLUG/install.new" "$L_RV_PLUG/scripts/guards/install.sh"
assert_eq "the older-gate copy names .git/older-gate where install.sh names its 5.5.0 to 9.6.4 older folder" "yes|0" \
  "$(grep -qF '"$v" == ".git/older-gate"' "$L_RV_PLUG/scripts/guards/install.sh" && echo yes || echo no)|$(grep -c 'hooks-temper' "$L_RV_PLUG/scripts/guards/install.sh")"
_l_repo "$L_RV"
rm -rf "$L_RV_WT"
git -C "$L_RV" worktree add -q "$L_RV_WT" >/dev/null 2>&1
mkdir -p "$L_RV/.git/older-gate"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_RV/.git/older-gate/pre-commit"
printf '#!/bin/sh\necho lfs-pre-push\n' > "$L_RV/.git/older-gate/pre-push"
chmod +x "$L_RV/.git/older-gate/pre-commit" "$L_RV/.git/older-gate/pre-push"
git -C "$L_RV" config core.hooksPath .git/older-gate
OUT=$(cd "$L_RV_WT" && bash "$L_RV_PLUG/scripts/guards/install.sh" 2>&1); L_RC=$?
assert_eq "a relative older folder that must stay is set by its absolute path, with a note, and then refused naming its other hook" "1|$L_RV/.git/older-gate|yes|yes" \
  "$L_RC|$(_l_path "$L_RV")|$(_l_line "$OUT" "Note: core.hooksPath held '.git/older-gate'; it now holds $L_RV/.git/older-gate, the same older Temper folder in this repository's git folder by its absolute path, which every worktree reaches.")|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '$L_RV/.git/older-gate', a folder an older Temper set. $L_RV/.git/older-gate holds hooks git would stop running if core.hooksPath pointed at Temper's folder: pre-push.")"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_RV/.git/older-gate/pre-commit"
OUT=$(cd "$L_RV_WT" && bash "$L_RV_PLUG/scripts/guards/install.sh" 2>&1); L_RC=$?
assert_eq "once its pre-commit is #!/bin/sh and the line, a run from the linked worktree says it calls the Temper hook" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_RV/.git/older-gate/pre-commit calls the Temper hook ($L_RV/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")"
(cd "$L_RV_WT" && printf '.temper/\n' > .gitignore && git add .gitignore)
_l_red "$L_RV_WT"
assert_exit "a commit on a red gate in the linked worktree is blocked: it reaches the older folder by its absolute path" 1 git -C "$L_RV_WT" commit -q -m red
rm -rf "$L_RV" "$L_RV_WT" "$L_RV_PLUG"

# A copy of a repository whose core.hooksPath still names the original's temper-gate folder, where
# another tool also wrote a hook: that folder is another repository's, and its pre-commit is that
# repository's own current hook. The installer refuses with no hook lines and no hint to change
# that file (the line there would make the hook run itself); the hint is to point core.hooksPath at
# this repository's own folder.
L_CA="$WORKDIR/l1-copy-a"
L_CB="$WORKDIR/l1-copy-b"
_l_repo "$L_CA"
(cd "$L_CA" && bash "$L_INSTALL" >/dev/null 2>&1)
printf '#!/bin/sh\necho lfs-pre-push\n' > "$L_CA/.git/temper-gate/pre-push"
chmod +x "$L_CA/.git/temper-gate/pre-push"
rm -rf "$L_CB"
cp -a "$L_CA" "$L_CB"
L_SUM="$(cksum < "$L_CA/.git/temper-gate/pre-commit")"
OUT=$(cd "$L_CB" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a copy pointed at the original's temper-gate folder is refused as another repository's folder, with no hook lines and no older Temper warning" "1|yes|no|no|$L_CA/.git/temper-gate" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '$L_CA/.git/temper-gate', the Temper folder of another repository ($L_CA/.git), which also holds other hooks: pre-push.")|$(_l_has "$OUT" 'BEGIN Temper pre-commit hook lines')|$(_l_has "$OUT" 'a hook from an older Temper')|$(_l_path "$L_CB")"
assert_eq "its hint says to point core.hooksPath at this repository's own folder, the original's hook is left as it was, and this one's hook is kept" "yes|yes|yes" \
  "$(_l_last "$OUT" "Hint: point core.hooksPath at this repository's own folder (git config --local core.hooksPath $L_CB/.git/temper-gate), then copy those hooks into it, or install them again with their tool (git lfs install --local writes into the folder core.hooksPath names).")|$([[ "$(cksum < "$L_CA/.git/temper-gate/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(_l_kept "$L_CB")"
rm -rf "$L_CA" "$L_CB"

# husky's _ folder holding a pre-commit from an older Temper (9.6.4 wrote over husky's own there):
# git runs that hook, not husky's, so .husky/pre-commit never runs, even with the line in it. The
# installer refuses, names the older hook with its stale path, and says to have husky write its own.
L_HO="$WORKDIR/l1-husky-older"
_l_repo "$L_HO"
mkdir -p "$L_HO/.husky/_"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_HO/.husky/_/pre-commit"
printf '#!/bin/sh\necho husky-own\n' > "$L_HO/.husky/_/pre-commit.bak.20260101000000"
printf '%s\n' "$L_CALL" > "$L_HO/.husky/pre-commit"
chmod +x "$L_HO/.husky/_/pre-commit"
git -C "$L_HO" config core.hooksPath .husky/_
L_SUM="$(cksum < "$L_HO/.husky/_/pre-commit")"
OUT=$(cd "$L_HO" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky's _ folder holding an older Temper pre-commit is refused even with the line in .husky/pre-commit, naming the older hook" "1|yes|yes|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: core.hooksPath is set to '.husky/_', and git runs .husky/_/pre-commit there, a hook from an older Temper in place of husky's.")|$(_l_line "$OUT" "Warning: .husky/_/pre-commit is a hook from an older Temper, and git runs it in place of husky's own hook, so .husky/pre-commit does not run. This installer does not write it.")|$(_l_line "$OUT" "  embedded: /old/plugin/scripts/temper")|$([[ "$(cksum < "$L_HO/.husky/_/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)"
assert_eq "its hint says to have husky write its own hooks there again, then add the line to .husky/pre-commit" "yes" \
  "$(_l_last "$OUT" "Hint: run npx husky, which writes husky's own hooks there again (or move the pre-commit.bak.<timestamp> file there back over it), then add the line to .husky/pre-commit.")"
rm -rf "$L_HO"

# A host hook that holds the line but is not executable: git does not run it, so it does not count.
# husky's _ folder runs .husky/pre-commit with sh, so there the execute bit is not needed.
L_NX="$WORKDIR/l1-not-exec"
_l_repo "$L_NX"
mkdir -p "$L_NX/.git/default-gate"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_NX/.git/default-gate/pre-commit"
printf '#!/bin/sh\nexit 0\n' > "$L_NX/.git/default-gate/commit-msg"
chmod +x "$L_NX/.git/default-gate/commit-msg"
OUT=$(cd "$L_NX" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a pre-commit in the default folder that holds the line but is not executable is refused, with the chmod hint" "1|yes|yes|none" \
  "$L_RC|$(_l_line "$OUT" "FAIL: the pre-commit hook $L_NX/.git/default-gate/pre-commit is not executable, so git does not run it, and the Temper hook with it.")|$(_l_last "$OUT" "Hint: run chmod +x $L_NX/.git/default-gate/pre-commit, then run this installer again.")|$(_l_path "$L_NX")"
chmod +x "$L_NX/.git/default-gate/pre-commit"
OUT=$(cd "$L_NX" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "made executable, it calls the Temper hook" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_NX/.git/default-gate/pre-commit calls the Temper hook ($L_NX/.git/temper-gate/pre-commit), which is now current, so nothing else was written.")"
rm -rf "$L_NX/.git/default-gate"
mkdir -p "$L_NX/.git/user-gate"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_NX/.git/user-gate/pre-commit"
git -C "$L_NX" config core.hooksPath .git/user-gate
OUT=$(cd "$L_NX" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the same in another tool's folder: refused with the chmod hint" "1|yes" \
  "$L_RC|$(_l_last "$OUT" "Hint: run chmod +x .git/user-gate/pre-commit, then run this installer again.")"
git -C "$L_NX" config --unset core.hooksPath
mkdir -p "$L_NX/.husky/_"
printf '#!/bin/sh\n. "$(dirname "$0")/h"\n' > "$L_NX/.husky/_/pre-commit"
chmod +x "$L_NX/.husky/_/pre-commit"
printf '%s\n' "$L_CALL" > "$L_NX/.husky/pre-commit"
git -C "$L_NX" config core.hooksPath .husky/_
OUT=$(cd "$L_NX" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky's .husky/pre-commit, which husky runs with sh, counts without the execute bit" "0|yes" \
  "$L_RC|$(_l_has "$OUT" "The pre-commit hook .husky/pre-commit calls the Temper hook")"
rm -rf "$L_NX"

# The pre-commit framework and lefthook keep the line in their config file, not in the hook they
# write: once that file at the repository's top holds the line, a run counts it as installed.
L_FC="$WORKDIR/l1-framework-config"
_l_repo "$L_FC"
mkdir -p "$L_FC/.git/default-gate"
printf '#!/usr/bin/env bash\n# File generated by pre-commit\nexec pre-commit hook-impl --hook-type=pre-commit -- "$@"\n' > "$L_FC/.git/default-gate/pre-commit"
chmod +x "$L_FC/.git/default-gate/pre-commit"
OUT=$(cd "$L_FC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "the framework's hook with no entry for the line in its config is refused" "1" "$L_RC"
printf -- "- repo: local\n  hooks:\n  - id: temper\n    name: temper\n    language: system\n    pass_filenames: false\n    always_run: true\n    entry: sh -c '%s'\n" "$L_CALL" > "$L_FC/.pre-commit-config.yaml"
OUT=$(cd "$L_FC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "once .pre-commit-config.yaml holds the entry, a run says the framework runs the Temper hook" "0|yes|none" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_FC/.git/default-gate/pre-commit runs the Temper hook ($L_FC/.git/temper-gate/pre-commit) through .pre-commit-config.yaml, and that hook is now current, so nothing else was written. (Only the text of .pre-commit-config.yaml was read: a stages or skip setting in it can still keep the line from running on a commit.)")|$(_l_path "$L_FC")"
# The line in a comment of that file does not count: the framework does not run it.
printf -- "- repo: local\n  hooks:\n  - id: temper\n    name: temper\n    language: system\n    # entry: sh -c '%s'\n    entry: true\n" "$L_CALL" > "$L_FC/.pre-commit-config.yaml"
OUT=$(cd "$L_FC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "an entry for the line that is only in a comment of .pre-commit-config.yaml does not count" "1" "$L_RC"
rm -f "$L_FC/.pre-commit-config.yaml"
printf '#!/bin/sh\n# lefthook generated hook\nexec lefthook run "pre-commit" "$@"\n' > "$L_FC/.git/default-gate/pre-commit"
printf 'pre-commit:\n  commands:\n    temper:\n      # run: %s\n      run: "true"\n' "$L_CALL" > "$L_FC/lefthook.yml"
OUT=$(cd "$L_FC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "a command for the line that is only in a comment of lefthook.yml does not count" "1" "$L_RC"
printf 'pre-commit:\n  commands:\n    temper:\n      run: %s\n' "$L_CALL" > "$L_FC/lefthook.yml"
OUT=$(cd "$L_FC" && bash "$L_DG_INSTALL" 2>&1); L_RC=$?
assert_eq "once lefthook.yml holds the line, a run says lefthook runs the Temper hook" "0|yes" \
  "$L_RC|$(_l_line "$OUT" "The pre-commit hook $L_FC/.git/default-gate/pre-commit runs the Temper hook ($L_FC/.git/temper-gate/pre-commit) through lefthook.yml, and that hook is now current, so nothing else was written. (Only the text of lefthook.yml was read: a stages or skip setting in it can still keep the line from running on a commit.)")"
rm -rf "$L_FC"

# A link planted above a repository to the plugin's scripts folder, or a hard link of install.sh in
# a scripts/guards folder there, does not make the repository part of the plugin: the install goes on.
L_PL="$WORKDIR/l1-planted"
rm -rf "$L_PL"
mkdir -p "$L_PL/a" "$L_PL/b/scripts/guards"
ln -s "$L_PLUG/scripts" "$L_PL/a/scripts"
ln "$L_INSTALL" "$L_PL/b/scripts/guards/install.sh"
_l_repo "$L_PL/a/proj"
_l_repo "$L_PL/b/proj"
assert_exit "a scripts link to the plugin's folder planted above a repository does not stop the install" 0 bash -c "cd '$L_PL/a/proj' && bash '$L_INSTALL'"
assert_exit "nor does a hard link of install.sh in a scripts/guards folder planted above a repository" 0 bash -c "cd '$L_PL/b/proj' && bash '$L_INSTALL'"
rm -rf "$L_PL"

# A kept older folder after the repository moves: core.hooksPath still names the old place, where
# git runs no hook, and the next run sets this repository's own older folder again by its absolute
# path, so its other hooks keep running and the gate holds. (The copy of the default-gate plugin
# takes .git/older-gate as the older value .git/hooks-temper, as in the case above.)
L_MV="$WORKDIR/l1-move-older"
L_MV2="$WORKDIR/l1-move-older-2"
L_MV_PLUG="$WORKDIR/l1-mv-plugin"
_dg_plugin "$L_MV_PLUG"
sed 's/hooks-temper/older-gate/g' "$L_MV_PLUG/scripts/guards/install.sh" > "$L_MV_PLUG/install.new"
mv "$L_MV_PLUG/install.new" "$L_MV_PLUG/scripts/guards/install.sh"
_l_repo "$L_MV"
mkdir -p "$L_MV/.git/older-gate"
printf '#!/bin/sh\n%s\n' "$L_CALL" > "$L_MV/.git/older-gate/pre-commit"
printf '#!/bin/sh\necho lfs-pre-push\n' > "$L_MV/.git/older-gate/pre-push"
chmod +x "$L_MV/.git/older-gate/pre-commit" "$L_MV/.git/older-gate/pre-push"
git -C "$L_MV" config core.hooksPath .git/older-gate
OUT=$(cd "$L_MV" && bash "$L_MV_PLUG/scripts/guards/install.sh" 2>&1); L_RC=$?
assert_eq "a kept relative older folder whose pre-commit holds only the line is set by its absolute path and calls the Temper hook" "0|$L_MV/.git/older-gate" \
  "$L_RC|$(_l_path "$L_MV")"
rm -rf "$L_MV2"
mv "$L_MV" "$L_MV2"
OUT=$(cd "$L_MV2" && bash "$L_MV_PLUG/scripts/guards/install.sh" 2>&1); L_RC=$?
assert_eq "after a move, the next run sets this repository's own older folder again, with a note, and its other hooks stay" "0|$L_MV2/.git/older-gate|yes|yes" \
  "$L_RC|$(_l_path "$L_MV2")|$(_l_line "$OUT" "Note: core.hooksPath held '$L_MV/.git/older-gate'; it now holds $L_MV2/.git/older-gate, the same older Temper folder in this repository's git folder by its absolute path, which every worktree reaches.")|$([[ -x "$L_MV2/.git/older-gate/pre-push" ]] && echo yes || echo no)"
(cd "$L_MV2" && printf '.temper/\n' > .gitignore && git add .gitignore)
_l_red "$L_MV2"
assert_exit "after the move and the run, a commit on a red gate is blocked" 1 git -C "$L_MV2" commit -q -m red
rm -rf "$L_MV2" "$L_MV_PLUG"

# husky v9: git runs husky's own hook in .husky/_, which runs .husky/pre-commit. When that hook is
# missing (a fresh clone before npm install) or not executable, .husky/pre-commit never runs, so a
# line in it does not count.
L_HM="$WORKDIR/l1-husky-missing"
_l_repo "$L_HM"
mkdir -p "$L_HM/.husky"
printf '%s\n' "$L_CALL" > "$L_HM/.husky/pre-commit"
git -C "$L_HM" config core.hooksPath .husky/_
OUT=$(cd "$L_HM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with husky's own hook missing, the line in .husky/pre-commit does not count" "1|yes|yes" \
  "$L_RC|$(_l_line "$OUT" "FAIL: git runs .husky/_/pre-commit, husky's own hook, which is missing or not executable, so .husky/pre-commit does not run.")|$(_l_last "$OUT" "Hint: run npx husky (npm install runs it too, through husky's prepare script), then run this installer again.")"
mkdir -p "$L_HM/.husky/_"
printf '#!/bin/sh\n. "$(dirname "$0")/h"\n' > "$L_HM/.husky/_/pre-commit"
OUT=$(cd "$L_HM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with husky's own hook not executable, it does not count either" "1" "$L_RC"
chmod +x "$L_HM/.husky/_/pre-commit"
OUT=$(cd "$L_HM" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "with husky's own hook in place and executable, the line counts" "0" "$L_RC"
rm -rf "$L_HM"

# The commit hooks with the real CLI: an active run with red gates and a symlink on a run-state
# path, or a link in the spec folder, never opens the gate.
L_RED="$WORKDIR/l1-red"
_l_repo "$L_RED"
printf '.temper/\n' > "$L_RED/.gitignore"
bash -c "cd '$L_RED' && bash '$L_INSTALL'" >/dev/null 2>&1
(cd "$L_RED" && "$L_PLUG/scripts/temper" init >/dev/null 2>&1 && "$L_PLUG/scripts/temper" state init demo-run >/dev/null 2>&1)
mkdir -p "$L_RED/.temper/specs/demo-run"
echo r > "$L_RED/r.txt"
git -C "$L_RED" add .gitignore r.txt >/dev/null 2>&1
assert_exit "an active run with red gates blocks a real commit" 1 git -C "$L_RED" commit -q -m red
ln -s "$WORKDIR" "$L_RED/.temper/specs/demo-run/notes"
assert_exit "a symlink in the active run's spec folder does not open the gate" 1 git -C "$L_RED" commit -q -m red
rm -f "$L_RED/.temper/specs/demo-run/notes"
mv "$L_RED/.temper/gates.json" "$WORKDIR/l1-gates.json"
ln -s "$WORKDIR/l1-gates.json" "$L_RED/.temper/gates.json"
OUT=$(git -C "$L_RED" commit -q -m red 2>&1); L_RC=$?
assert_eq "a symlinked gates.json during an active run: the native hook blocks and says to remove the symlink" "1|yes" \
  "$L_RC|$(_l_has "$OUT" 'remove the symlink')"
OUT=$(cd "$L_RED" && echo '{"tool_input": {"command": "git commit -m y"}}' | bash "$L_PLUG/scripts/guards/block-uncommitted-gate.sh" 2>&1); L_RC=$?
assert_eq "a symlinked gates.json during an active run: the in-agent commit gate blocks too" "2|yes" \
  "$L_RC|$(_l_has "$OUT" 'remove the symlink')"
mv "$L_RED/.temper/build-state.json" "$WORKDIR/l1-build-state.json"
ln -s "$WORKDIR/l1-nowhere.json" "$L_RED/.temper/build-state.json"
assert_exit "a build-state.json that is itself a symlink (even a dangling one) still counts as an active run" 1 git -C "$L_RED" commit -q -m red
rm -f "$L_RED/.temper/build-state.json"
assert_exit "with no run active, the native hook fails open" 0 git -C "$L_RED" commit -q -m norun
rm -rf "$L_RED" "$WORKDIR/l1-gates.json" "$WORKDIR/l1-build-state.json"

# block-secrets --staged scans the staged content from the index, not the work tree copy, and
# names the file; names git would quote are read too.
L_SEC="$WORKDIR/l1-secrets"
_l_repo "$L_SEC"
bash -c "cd '$L_SEC' && bash '$L_INSTALL'" >/dev/null 2>&1
L_KEY="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
L_SECRETS="$L_PLUG/scripts/guards/block-secrets.sh"
printf 'key = %s\n' "$L_KEY" > "$L_SEC/s2.txt"
git -C "$L_SEC" add s2.txt >/dev/null 2>&1
echo clean > "$L_SEC/s2.txt"
OUT=$(cd "$L_SEC" && bash "$L_SECRETS" --staged < /dev/null 2>&1); L_RC=$?
assert_eq "block-secrets --staged blocks a staged secret the work tree copy no longer holds, and names the file" "2|yes" \
  "$L_RC|$(_l_has "$OUT" "in the staged copy of 's2.txt'")"
assert_exit "a real commit of a staged secret that the work tree copy no longer holds is blocked" 1 git -C "$L_SEC" commit -q -m secret
git -C "$L_SEC" reset -q -- s2.txt >/dev/null 2>&1
rm -f "$L_SEC/s2.txt"
echo clean > "$L_SEC/c.txt"
git -C "$L_SEC" add c.txt >/dev/null 2>&1
printf 'key = %s\n' "$L_KEY" > "$L_SEC/c.txt"
assert_exit "block-secrets --staged passes when the secret is only in the unstaged work tree copy" 0 \
  bash -c "cd '$L_SEC' && bash '$L_SECRETS' --staged < /dev/null"
assert_exit "a real commit whose staged copy is clean passes, whatever the work tree holds" 0 git -C "$L_SEC" commit -q -m clean
L_ODD="$(printf 'odd name \303\251.txt')"
printf 'key = %s\n' "$L_KEY" > "$L_SEC/$L_ODD"
git -C "$L_SEC" add -- "$L_ODD" >/dev/null 2>&1
OUT=$(cd "$L_SEC" && bash "$L_SECRETS" --staged < /dev/null 2>&1); L_RC=$?
assert_eq "block-secrets --staged reads a staged name that git would quote, and names it" "2|yes" \
  "$L_RC|$(_l_has "$OUT" "in the staged copy of '$L_ODD'")"
git -C "$L_SEC" reset -q -- "$L_ODD" >/dev/null 2>&1
rm -f "$L_SEC/$L_ODD"
# A staged name that starts with a digit and a colon is read as that file (stage 0), never as an
# index stage of another path.
printf 'key = %s\n' "$L_KEY" > "$L_SEC/1:notes.txt"
git -C "$L_SEC" add -- '1:notes.txt' >/dev/null 2>&1
OUT=$(cd "$L_SEC" && bash "$L_SECRETS" --staged < /dev/null 2>&1); L_RC=$?
assert_eq "block-secrets --staged blocks a secret in a staged file named 1:notes.txt, and names it" "2|yes" \
  "$L_RC|$(_l_has "$OUT" "in the staged copy of '1:notes.txt'")"
assert_exit "a real commit of a staged 1:notes.txt that holds a secret is blocked" 1 git -C "$L_SEC" commit -q -m notes
git -C "$L_SEC" reset -q -- '1:notes.txt' >/dev/null 2>&1
rm -f "$L_SEC/1:notes.txt"
printf 'key = %s\n' "$L_KEY" > "$L_SEC/0:x.txt"
git -C "$L_SEC" add -- '0:x.txt' >/dev/null 2>&1
OUT=$(cd "$L_SEC" && bash "$L_SECRETS" --staged < /dev/null 2>&1); L_RC=$?
assert_eq "block-secrets --staged blocks a secret in a staged file named 0:x.txt, and names it" "2|yes" \
  "$L_RC|$(_l_has "$OUT" "in the staged copy of '0:x.txt'")"
rm -rf "$L_SEC"

# The guard scripts follow their own symlinks (a link to the file, or to its folder) and do nothing
# when they are not in a scripts/guards folder.
L_GL="$WORKDIR/l1-guard-links"
rm -rf "$L_GL"
mkdir -p "$L_GL/bin" "$L_GL/loose"
ln -s "$L_PLUG/scripts/guards" "$L_GL/guards"
ln -s "$L_PLUG/scripts/guards/block-uncommitted-gate.sh" "$L_GL/bin/gate.sh"
ln -s "$L_PLUG/scripts/guards/protect-regression-test.sh" "$L_GL/bin/shield.sh"
cp "$L_PLUG/scripts/guards/block-uncommitted-gate.sh" "$L_PLUG/scripts/guards/protect-regression-test.sh" "$L_GL/loose/"
_l_red "$WORKDIR"
echo g > guard-file.txt
git add guard-file.txt >/dev/null 2>&1
L_COMMIT='{"tool_input": {"command": "git commit -m x"}}'
assert_eq "uncommitted-gate blocks a red gate through a link to its file and through a link to its folder" "2|2" \
  "$(echo "$L_COMMIT" | bash "$L_GL/bin/gate.sh" >/dev/null 2>&1; echo $?)|$(echo "$L_COMMIT" | bash "$L_GL/guards/block-uncommitted-gate.sh" >/dev/null 2>&1; echo $?)"
assert_exit "uncommitted-gate outside a scripts/guards folder does nothing" 0 \
  bash -c "echo '$L_COMMIT' | bash '$L_GL/loose/block-uncommitted-gate.sh'"
mkdir -p reg-l1
echo 'def test_l1(): pass' > reg-l1/test_l1.py
echo '{"command": "fix", "regression_test": "reg-l1/test_l1.py"}' > .temper/build-state.json
L_EDIT='{"tool_input": {"file_path": "reg-l1/test_l1.py"}}'
assert_eq "the regression-test shield blocks through a link to its file and through a link to its folder" "2|2" \
  "$(echo "$L_EDIT" | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$L_GL/bin/shield.sh" >/dev/null 2>&1; echo $?)|$(echo "$L_EDIT" | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$L_GL/guards/protect-regression-test.sh" >/dev/null 2>&1; echo $?)"
assert_exit "the regression-test shield outside a scripts/guards folder does nothing" 0 \
  bash -c "echo '$L_EDIT' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$L_GL/loose/protect-regression-test.sh'"
rm -rf .git/temper-gate
git config --unset core.hooksPath 2>/dev/null || true
OUT=$(bash "$L_GL/guards/install.sh" 2>&1); L_RC=$?
assert_eq "install.sh reached through a link to its folder writes the real CLI path" "0|yes" \
  "$L_RC|$(grep -qxF "$L_CLI_LINE" .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)"
git rm -q --cached guard-file.txt >/dev/null 2>&1 || true
git config --unset core.hooksPath 2>/dev/null || true
rm -rf guard-file.txt reg-l1 "$L_GL" "$L_PLUG" "$L_DG" "$L_BIN" "$L_LINES" .git/temper-gate
