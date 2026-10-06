# shellcheck shell=bash
# Part 3 of the temper CLI test suite: the CLI in and around the plugin folder, guards and the installer.
# Sourced in order by test-temper.sh, which sets up the helpers, WORKDIR and the counters;
# not meant to run on its own.

# --- CLI: a folder inside the plugin folder is refused; the plugin folder itself is a project ---
assert_eq "the throwaway test folder is not inside the repo, so no case here runs the CLI inside the plugin folder" "no" \
  "$(wd="$(cd "$WORKDIR" && pwd -P)"; rr="$(cd "$REPO_ROOT" && pwd -P)"; [[ "${wd#"$rr"/}" != "$wd" ]] && echo yes || echo no)"
for sub in "init" "state init demo" "state get" "evidence add --stage build --claim x" "gate intent" \
           "status" "report" "bands" "metrics append x 1" "override plan --reason x"; do
  assert_exit "the CLI refuses '$sub' in a folder inside the plugin folder" 1 \
    bash -c "cd '$CLI_PLUGIN/inner/sub' && '$CLI_PLUGIN/scripts/temper' $sub"
done
assert_eq "the refused commands wrote nothing in the plugin folder" "no|no" \
  "$([[ -e "$CLI_PLUGIN/inner/sub/.temper" ]] && echo yes || echo no)|$([[ -e "$CLI_PLUGIN/.temper" ]] && echo yes || echo no)"
OUT=$(cd "$CLI_PLUGIN/inner/sub" && "$CLI_PLUGIN/scripts/temper" init 2>&1; true)
assert_eq "the refusal says to run from a project folder" "yes" \
  "$(echo "$OUT" | grep -q 'run temper from a project folder, not from a folder inside the plugin folder' && echo yes || echo no)"
ln -sfn "$CLI_PLUGIN/inner/sub" "$WORKDIR/sub-link"
assert_exit "a folder reached through a symlink that points inside the plugin folder is refused too" 1 \
  bash -c "cd '$WORKDIR/sub-link' && '$CLI_PLUGIN/scripts/temper' init"
assert_exit "a CLI reached through a symlink guards its real plugin folder" 1 \
  bash -c "cd '$CLI_PLUGIN/inner/sub' && '$WORKDIR/bin/chained-temper' init"
assert_eq "temper model still answers there and writes nothing" "$("$TEMPER" model plan)|no" \
  "$(cd "$CLI_PLUGIN/inner/sub" && "$CLI_PLUGIN/scripts/temper" model plan)|$([[ -e "$CLI_PLUGIN/inner/sub/.temper" ]] && echo yes || echo no)"
assert_eq "temper config get still answers there (the guard scripts call it)" "auto" \
  "$(cd "$CLI_PLUGIN/inner/sub" && TEMPER_CONFIG="$WORKDIR/.claude/temper.config" "$CLI_PLUGIN/scripts/temper" config get stack)"
assert_exit "an installed copy of the plugin folder (no .git of its own) is not a project" 1 \
  bash -c "cd '$CLI_PLUGIN' && '$CLI_PLUGIN/scripts/temper' init"
assert_exit "a GIT_DIR naming another repository does not make the installed copy a project" 1 \
  bash -c "cd '$CLI_PLUGIN' && GIT_DIR='$WORKDIR/.git' '$CLI_PLUGIN/scripts/temper' init"
assert_eq "the refused installed copy gets no .temper" "no" "$([[ -e "$CLI_PLUGIN/.temper" ]] && echo yes || echo no)"
git init -q "$CLI_PLUGIN"
assert_exit "the plugin folder itself is a valid project (its own git repository)" 0 bash -c "cd '$CLI_PLUGIN' && '$CLI_PLUGIN/scripts/temper' init"
assert_eq "run state is written in the plugin folder's own .temper when it is the project" "yes" \
  "$([[ -f "$CLI_PLUGIN/.temper/gates.json" ]] && echo yes || echo no)"
rm -rf "$CLI_PLUGIN" "$WORKDIR/sub-link" "$WORKDIR/bin"

# --- CLI: a slug is letters of either case, digits, '.', '_' and '-'; never '/' or '..' ---
setup
assert_exit "state init accepts an uppercase ticket key prefix" 0 "$TEMPER" state init PROJ-123-login
assert_eq "the uppercase slug names its spec folder" ".temper/specs/PROJ-123-login" "$("$TEMPER" state get spec_path)"
assert_exit "state set accepts an uppercase spec_path slug" 0 "$TEMPER" state set spec_path .temper/specs/PROJ-9-x
assert_exit "state set still refuses a spec_path slug with a '/'" 1 "$TEMPER" state set spec_path .temper/specs/PROJ/9
assert_exit "state set still refuses a spec_path slug with '..'" 1 "$TEMPER" state set spec_path .temper/specs/PROJ..9
# A run started by 9.6.4 with an uppercase slug still archives its gate ledger.
setup
mkdir -p .temper/specs/PROJ-123-login
python3 - <<'EOF'
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['spec'] = 'PROJ-123-login'; d['spec_path'] = '.temper/specs/PROJ-123-login'; json.dump(d, open(p, 'w'))
EOF
echo '{"intent": {"verdict": "PASS", "requirements": [], "ts": "t"}}' > .temper/gates.json
"$TEMPER" state archive >/dev/null
assert_eq "state archive writes the ledger of an uppercase slug's run" "yes" \
  "$([[ -f .temper/specs/PROJ-123-login/gate-ledger.json ]] && echo yes || echo no)"

# --- CLI: a spec_path the archive refuses is reported, never dropped without a word ---
bad_spec_path() {
  python3 - <<'EOF'
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['spec_path'] = '.temper/specs/../x'; json.dump(d, open(p, 'w'))
EOF
  echo '{"intent": {"verdict": "PASS", "requirements": [], "ts": "t"}}' > .temper/gates.json
}
setup; bad_spec_path
ERR=$("$TEMPER" state archive 2>&1 >/dev/null)
assert_eq "state archive warns on stderr that the ledger was not archived" "yes" \
  "$(echo "$ERR" | grep -q "gate ledger NOT archived: spec_path '.temper/specs/../x' is not .temper/specs/<slug>" && echo yes || echo no)"
assert_eq "state archive no longer says there was nothing to archive" "no" \
  "$("$TEMPER" state archive 2>/dev/null | grep -q 'nothing to archive' && echo yes || echo no)"
OUT=$("$TEMPER" state clear 2>&1)
assert_eq "state clear shows the warning and says the ledger was not archived" "yes|yes" \
  "$(echo "$OUT" | grep -q 'gate ledger NOT archived' && echo yes || echo no)|$(echo "$OUT" | grep -q 'the gate ledger was NOT archived' && echo yes || echo no)"
setup; bad_spec_path
OUT=$("$TEMPER" state init fresh 2>&1)
assert_eq "state init shows the warning for the prior run" "yes" \
  "$(echo "$OUT" | grep -q 'gate ledger NOT archived' && echo yes || echo no)"
assert_eq "state init still starts the new run" "fresh" "$("$TEMPER" state get spec)"
setup
assert_eq "a run with a valid spec_path archives with no warning" "" "$("$TEMPER" state archive 2>&1 >/dev/null)"

# --- CLI: a symlink on a run-state path is refused (exit 3): no write follows a link ---
# A throwaway plugin folder holds a copy of the CLI; a project outside it carries links into it
# (a cloned repository can track such a link). Every write subcommand is refused with exit 3 and
# one line on stderr, and nothing in the plugin folder is written, changed or deleted.
setup
LNK_PLUG="$WORKDIR/link-plugin"
LNK_PROJ="$WORKDIR/link-project"
rm -rf "$LNK_PLUG" "$LNK_PROJ"
mkdir -p "$LNK_PLUG/scripts/guards" "$LNK_PLUG/shipped" "$LNK_PLUG/.temper" "$LNK_PLUG/inner/sub"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$LNK_PLUG/scripts/"
cp "$REPO_ROOT/scripts/guards/stage-marker.sh" "$REPO_ROOT/scripts/guards/verify-stage-gate.sh" "$LNK_PLUG/scripts/guards/"
cp -R "$REPO_ROOT/agents" "$LNK_PLUG/agents"
echo '{"shipped": true}' > "$LNK_PLUG/shipped/settings.json"
echo '{"coverage_history": []}' > "$LNK_PLUG/.temper/metrics.json"
LNK_T="$LNK_PLUG/scripts/temper"
link_project() { rm -rf "$LNK_PROJ"; mkdir -p "$LNK_PROJ"; git init -q "$LNK_PROJ"; }
plugin_state() { (cd "$LNK_PLUG" && find shipped .temper inner -print | LC_ALL=C sort | tr '\n' ' '; cat shipped/settings.json .temper/metrics.json); }
LNK_BEFORE="$(plugin_state)"
link_project
ln -s "$LNK_PLUG/shipped" "$LNK_PROJ/.temper"
for sub in "init" "state init foo" "state get" "state archive" "state clear" "evidence add --stage build --claim x" \
           "gate intent" "status" "report" "bands" "metrics append coverage 42" "override plan --reason x"; do
  assert_exit "the CLI refuses '$sub' when .temper is a symlink (exit 3)" 3 bash -c "cd '$LNK_PROJ' && '$LNK_T' $sub"
done
ERR=$(cd "$LNK_PROJ" && "$LNK_T" init 2>&1 >/dev/null; true)
assert_eq "the refusal is one line on stderr that names the link" "1|yes" \
  "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')|$(echo "$ERR" | grep -q "unsafe .temper: '.temper' is a symlink" && echo yes || echo no)"
assert_eq "config get and model still answer next to a symlinked .temper" "auto|$("$TEMPER" model plan)" \
  "$(cd "$LNK_PROJ" && TEMPER_CONFIG="$WORKDIR/.claude/temper.config" "$LNK_T" config get stack)|$(cd "$LNK_PROJ" && "$LNK_T" model plan)"
link_project
ln -s ../link-plugin/.temper "$LNK_PROJ/.temper"
assert_exit "metrics append refuses a relative .temper symlink to the plugin's own .temper" 3 \
  bash -c "cd '$LNK_PROJ' && '$LNK_T' metrics append coverage 42"
link_project
ln -s "$WORKDIR/no-such-folder" "$LNK_PROJ/.temper"
assert_exit "init refuses a .temper symlink whose target does not exist" 3 bash -c "cd '$LNK_PROJ' && '$LNK_T' init"
assert_eq "the missing link target is not created" "no" "$([[ -e "$WORKDIR/no-such-folder" ]] && echo yes || echo no)"
# A plain .temper that holds a link: the gate verdicts file, a spec folder, the evidence folder.
link_project
(cd "$LNK_PROJ" && "$LNK_T" state init demo >/dev/null)
mkdir -p "$LNK_PROJ/.temper/specs/demo"
cp "$WORKDIR/.temper/specs/demo/intent.md" "$LNK_PROJ/.temper/specs/demo/intent.md"
rm -f "$LNK_PROJ/.temper/gates.json"
ln -s "$LNK_PLUG/shipped/settings.json" "$LNK_PROJ/.temper/gates.json"
assert_exit "gate intent refuses a .temper/gates.json that is a symlink" 3 \
  bash -c "cd '$LNK_PROJ' && '$LNK_T' gate intent --spec-path .temper/specs/demo"
rm -f "$LNK_PROJ/.temper/gates.json"
echo '{"intent": {"verdict": "PASS", "requirements": [], "ts": "t"}}' > "$LNK_PROJ/.temper/gates.json"
mv "$LNK_PROJ/.temper/specs/demo" "$LNK_PROJ/demo-spec"
ln -s "$LNK_PLUG/shipped" "$LNK_PROJ/.temper/specs/demo"
assert_exit "state archive refuses a spec folder that is a symlink" 3 bash -c "cd '$LNK_PROJ' && '$LNK_T' state archive"
assert_exit "state clear refuses it too" 3 bash -c "cd '$LNK_PROJ' && '$LNK_T' state clear"
assert_eq "the refused clear deleted nothing of the run state" "yes|yes" \
  "$([[ -f "$LNK_PROJ/.temper/gates.json" ]] && echo yes || echo no)|$([[ -f "$LNK_PROJ/.temper/build-state.json" ]] && echo yes || echo no)"
rm -f "$LNK_PROJ/.temper/specs/demo"
mv "$LNK_PROJ/demo-spec" "$LNK_PROJ/.temper/specs/demo"
rm -rf "$LNK_PROJ/.temper/evidence"
ln -s "$LNK_PLUG/shipped" "$LNK_PROJ/.temper/evidence"
assert_exit "evidence add refuses an evidence folder that is a symlink" 3 \
  bash -c "cd '$LNK_PROJ' && '$LNK_T' evidence add --stage build --claim x"
assert_eq "no refused command wrote, changed or deleted anything in the plugin folder" "$LNK_BEFORE" "$(plugin_state)"
rm -f "$LNK_PROJ/.temper/evidence"
assert_exit "with every link gone, the same project runs again" 0 \
  bash -c "cd '$LNK_PROJ' && '$LNK_T' evidence add --stage build --claim x && '$LNK_T' state archive"
assert_eq "and the ledger lands in the project's own spec folder" "yes" \
  "$([[ -f "$LNK_PROJ/.temper/specs/demo/gate-ledger.json" ]] && echo yes || echo no)"
# The ledger archive checks its spec folder itself as well (behind the refusal above): a specs
# folder, a spec folder or a ledger file that is a symlink is never written through.
sed -n '/^_spec_dir_ok() {/,/^}/p' "$TEMPER" > "$WORKDIR/spec-dir-ok.sh"
spec_dir_ok() { bash -c ". '$WORKDIR/spec-dir-ok.sh'; cd '$LNK_PROJ' && REPO_ROOT=\"\$PWD\" _spec_dir_ok demo"; }
assert_exit "the archive accepts a plain spec folder" 0 spec_dir_ok
rm -f "$LNK_PROJ/.temper/specs/demo/gate-ledger.json"
ln -s "$LNK_PLUG/shipped/settings.json" "$LNK_PROJ/.temper/specs/demo/gate-ledger.json"
assert_exit "the archive refuses a ledger file that is a symlink" 1 spec_dir_ok
rm -f "$LNK_PROJ/.temper/specs/demo/gate-ledger.json"
mv "$LNK_PROJ/.temper/specs/demo" "$LNK_PROJ/demo-spec"
ln -s "$LNK_PROJ/demo-spec" "$LNK_PROJ/.temper/specs/demo"
assert_exit "the archive refuses a spec folder that is a symlink" 1 spec_dir_ok
rm -f "$LNK_PROJ/.temper/specs/demo"
mv "$LNK_PROJ/demo-spec" "$LNK_PROJ/.temper/specs/demo"
mv "$LNK_PROJ/.temper/specs" "$LNK_PROJ/specs-real"
ln -s "$LNK_PROJ/specs-real" "$LNK_PROJ/.temper/specs"
assert_exit "the archive refuses a specs folder that is a symlink" 1 spec_dir_ok
rm -f "$WORKDIR/spec-dir-ok.sh"

# --- CLI and stage hooks: inside the plugin folder is decided by identity, not by path text ---
# bash keeps a leading '//' in a folder it enters, so '/' plus a full path names the same folder
# in other text (as another case does on a file system that does not tell case apart). A text
# prefix test misses it; a device and inode comparison does not.
assert_exit "the CLI refuses a folder inside the plugin folder reached by other path text" 1 \
  bash -c "cd '/$LNK_PLUG/inner/sub' && '$LNK_T' init"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="/$LNK_PLUG/inner/sub" bash "$LNK_PLUG/scripts/guards/stage-marker.sh"
assert_eq "stage-marker writes nothing in a folder inside the plugin folder reached by other path text" "no" \
  "$([[ -e "$LNK_PLUG/inner/sub/.temper" ]] && echo yes || echo no)"
mkdir -p "$LNK_PLUG/inner/sub/.temper"
echo '{"stage": "plan", "blocks": 0}' > "$LNK_PLUG/inner/sub/.temper/pending-stage.json"
assert_exit "verify-stage-gate skips that folder too" 0 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='/$LNK_PLUG/inner/sub' bash '$LNK_PLUG/scripts/guards/verify-stage-gate.sh'"
assert_eq "the skipped stop hook leaves the marker as it was" "0" \
  "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['blocks'])" "$LNK_PLUG/inner/sub/.temper/pending-stage.json")"
rm -rf "$LNK_PLUG/inner/sub/.temper"
# stage-marker records no debt in a .temper folder the CLI would refuse (it holds a symlink).
link_project
mkdir -p "$LNK_PROJ/.temper"
ln -s "$LNK_PLUG/shipped/settings.json" "$LNK_PROJ/.temper/gates.json"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$LNK_PROJ" bash "$LNK_PLUG/scripts/guards/stage-marker.sh"
assert_eq "stage-marker marks nothing in a .temper folder that holds a symlink" "no" \
  "$([[ -e "$LNK_PROJ/.temper/pending-stage.json" ]] && echo yes || echo no)"

# --- CLI and stage hooks: an exported CDPATH does not change where they find their own folder ---
assert_eq "a relative CLI call with CDPATH exported still resolves a model" "$("$TEMPER" model plan)" \
  "$(cd "$LNK_PLUG" && CDPATH="$LNK_PLUG:." scripts/temper model plan 2>/dev/null)"
assert_exit "a relative CLI call with CDPATH exported still refuses the installed plugin folder as a project" 1 \
  bash -c "cd '$LNK_PLUG' && CDPATH='$LNK_PLUG:.' scripts/temper init"
(cd "$LNK_PLUG" && echo '{"prompt": "/temper:plan x"}' | CDPATH="$LNK_PLUG:." CLAUDE_PROJECT_DIR="$LNK_PLUG/inner/sub" bash scripts/guards/stage-marker.sh)
assert_eq "stage-marker called by a relative path with CDPATH exported still writes nothing inside the plugin" "no" \
  "$([[ -e "$LNK_PLUG/inner/sub/.temper" ]] && echo yes || echo no)"
assert_eq "none of these cases wrote anything in the plugin folder" "$LNK_BEFORE" "$(plugin_state)"

# --- verify-stage-gate.sh: the block message gives the CLI by its full path, quoted for the shell ---
setup
SP_PLUG="$WORKDIR/spaced plugin"
rm -rf "$SP_PLUG"
mkdir -p "$SP_PLUG/scripts/guards"
cp "$REPO_ROOT/scripts/guards/stage-marker.sh" "$REPO_ROOT/scripts/guards/verify-stage-gate.sh" "$SP_PLUG/scripts/guards/"
echo '{"prompt": "/temper:plan x"}' | bash "$SP_PLUG/scripts/guards/stage-marker.sh"
OUT=$(echo '{}' | bash "$SP_PLUG/scripts/guards/verify-stage-gate.sh" 2>&1; true)
LINE="$(echo "$OUT" | grep ' gate plan --spec-path .temper/specs/<feature-slug>')"
CLI_TEXT="${LINE#  }"
CLI_TEXT="${CLI_TEXT%% gate plan*}"
assert_eq "the block message names the CLI as one shell word that is its full path" "1|$SP_PLUG/scripts/temper" \
  "$(eval "set -- $CLI_TEXT"; echo "$#|$1")"
assert_eq "the evidence commands in the message use the same full path" "2" \
  "$(echo "$OUT" | grep -cF "'$CLI_TEXT ")"
assert_eq "the message no longer names a bare temper command to run" "no" \
  "$(echo "$OUT" | grep -qE "^  temper |'temper (state|evidence) " && echo yes || echo no)"
rm -rf "$SP_PLUG" "$LNK_PLUG" "$LNK_PROJ"

# --- CLI: the raw intent template never passes a requirement on placeholder text ---
setup
cp "$REPO_ROOT/templates/intent.md" .temper/specs/demo/intent.md
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "gate intent FAILs the raw template" 1 "$TEMPER" gate intent
assert_eq "a placeholder that spans lines is not Problem content" "yes" \
  "$(echo "$OUT" | grep -q '\[x\] problem stated' && echo yes || echo no)"
assert_eq "no requirement row prints Python's None" "0" "$(echo "$OUT" | grep -c 'None')"
assert_eq "with no Status header each of the 13 draft-only rows says why it skipped" "13" \
  "$(echo "$OUT" | grep -c 'skipped: no recognized Status header (draft, accepted or completed)')"
cat > .temper/specs/demo/intent.md <<'EOF'
**Status:** draft

### Problem

{a placeholder that runs
over two lines}
Support spends a third of call time on status-only queries.
{one more {nested} placeholder
still open here}

### Success Criteria
- [ ] AC-01 [required]: status visible in the portal
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "real text after a placeholder that spans lines still counts, once" "yes" \
  "$(echo "$OUT" | grep -q 'problem stated .*Problem section has 1 line(s) of content' && echo yes || echo no)"

# --- install.sh: the kept hook in the git folder, the paths it runs written in full, refusals ---
setup
# The default-gate copy (see _dg_plugin) differs from install.sh in its one HOOKS_DIR line only.
_dg_plugin "$WORKDIR/dg-check"
assert_eq "the default-gate copy of install.sh differs from install.sh in its one HOOKS_DIR line only" \
  '1|2|HOOKS_DIR="$COMMON_REAL/default-gate"' \
  "$(grep -c '^HOOKS_DIR=' "$REPO_ROOT/scripts/guards/install.sh")|$(diff "$REPO_ROOT/scripts/guards/install.sh" "$WORKDIR/dg-check/scripts/guards/install.sh" | grep -c '^[<>]')|$(diff "$REPO_ROOT/scripts/guards/install.sh" "$WORKDIR/dg-check/scripts/guards/install.sh" | sed -n 's/^> //p')"
rm -rf "$WORKDIR/dg-check"
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/hooks/pre-commit .git/temper-gate .git/temper-pre-commit
K_HOOKS_BEFORE="$(ls -A .git/hooks)"
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "install.sh writes .git/temper-gate/pre-commit and points core.hooksPath at its folder" "yes|$WORKDIR/.git/temper-gate" \
  "$([[ -x .git/temper-gate/pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)"
assert_eq "install.sh writes no hook in .git/hooks (its listing before and after)" "$K_HOOKS_BEFORE" "$(ls -A .git/hooks)"
assert_eq "the hook carries the CLI path written out in full" "yes" \
  "$(grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/temper-gate/pre-commit && echo yes || echo no)"
assert_eq "the hook carries each guard script path written out in full" "yes" \
  "$(grep -qxF "SECRETS_SCRIPT=$(printf '%q' "$REPO_ROOT/scripts/guards/block-secrets.sh")" .git/temper-gate/pre-commit \
     && grep -qxF "TESTS_RAN_SCRIPT=$(printf '%q' "$REPO_ROOT/scripts/guards/verify-tests-ran.sh")" .git/temper-gate/pre-commit && echo yes || echo no)"
assert_eq "the hook has no environment override of a folder, works out no folder, and holds no plugin folder variable" "0" \
  "$(grep -cE 'TEMPER_HOOKS_DIR|dirname|PLUGIN_DIR' .git/temper-gate/pre-commit)"
assert_eq "install.sh holds no PLUGIN_ROOT or PLUGIN_REAL variable" "0" \
  "$(grep -cE 'PLUGIN_ROOT|PLUGIN_REAL' "$REPO_ROOT/scripts/guards/install.sh")"
# An upgrade over an install from before 9.6.5, recognized by its "Temper native pre-commit hook"
# line in .git/hooks: core.hooksPath is pointed at the temper-gate folder, the old hook is left as
# it was with no backup, and a note says git no longer runs it.
git config --unset core.hooksPath
rm -rf .git/temper-gate
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by an older installer).
TEMPER_HOOKS_DIR="${TEMPER_HOOKS_DIR:-/old/plugin/scripts/old-guards}"
EOF
chmod +x .git/hooks/pre-commit
K_OLD_SUM="$(cksum < .git/hooks/pre-commit)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); K_RC=$?
assert_eq "over an older Temper hook in .git/hooks, core.hooksPath is set and a note says git no longer runs that hook" \
  "0|$WORKDIR/.git/temper-gate|yes" \
  "$K_RC|$(git config --get core.hooksPath)|$(echo "$OUT" | grep -qxF "Note: git no longer runs $WORKDIR/.git/hooks/pre-commit, a hook from an older Temper; you can delete it." && echo yes || echo no)"
assert_eq "the older Temper hook is left as it was, with no backup" "yes|0" \
  "$([[ "$(cksum < .git/hooks/pre-commit)" == "$K_OLD_SUM" ]] && echo yes || echo no)|$(find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' | wc -l | tr -d ' ')"
assert_eq "the kept hook carries the current CLI path" "yes" \
  "$(grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/temper-gate/pre-commit && echo yes || echo no)"
python3 - <<'EOF'
import re
p = '.git/temper-gate/pre-commit'
s = open(p).read()
open(p, 'w').write(re.sub(r'(?m)^TEMPER_CLI=.*$', 'TEMPER_CLI=/moved/plugin/scripts/temper', s))
EOF
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1)
assert_eq "a moved CLI path in the kept hook is reported as stale and the current one written" "yes|yes" \
  "$(echo "$OUT" | grep -q 'embedded: /moved/plugin/scripts/temper' && grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/temper-gate/pre-commit && echo yes || echo no)|$(echo "$OUT" | grep -qxF "The Temper pre-commit hook $WORKDIR/.git/temper-gate/pre-commit was updated to the current plugin paths." && echo yes || echo no)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1)
assert_eq "a current kept hook is not reported as stale, and the run says it is already installed" "no|yes" \
  "$(echo "$OUT" | grep -q 'stale plugin path' && echo yes || echo no)|$(echo "$OUT" | grep -q 'is already installed' && echo yes || echo no)"
# A kept hook that is a symlink (here to an older Temper hook) is replaced by a regular file; the
# file it pointed at is left as it was.
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (an older install, linked).\necho linked\n' > "$WORKDIR/linked-hook.sh"
LINKED_SUM="$(cksum < "$WORKDIR/linked-hook.sh")"
rm -f .git/temper-gate/pre-commit
ln -s "$WORKDIR/linked-hook.sh" .git/temper-gate/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "a kept hook that is a symlink becomes a regular file, and its target is untouched" "yes|yes" \
  "$([[ -f .git/temper-gate/pre-commit && ! -L .git/temper-gate/pre-commit ]] && echo yes || echo no)|$([[ "$(cksum < "$WORKDIR/linked-hook.sh")" == "$LINKED_SUM" ]] && echo yes || echo no)"
rm -f "$WORKDIR/linked-hook.sh"
# core.hooksPath set to a folder that is not Temper's: the installer never writes there, whatever
# the value ('..', outside the repository, under the home folder, a folder with a JSON file,
# inside the repository). It keeps the hook in .git/temper-gate and prints the line that runs it,
# with a hint naming the hook in that folder, and leaves core.hooksPath as it was.
git config --unset core.hooksPath
rm -rf .git/hooks/pre-commit .git/temper-gate .git/temper-pre-commit
git config core.hooksPath sub/../dotdot-hooks
assert_exit "install.sh refuses a core.hooksPath that is not Temper's (here with '..')" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1; true)
assert_eq "the refusal names the value, keeps the hook, and the hint names the hook in that folder, last" "yes|yes|yes|yes" \
  "$(echo "$OUT" | head -1 | grep -qxF "FAIL: core.hooksPath is set to 'sub/../dotdot-hooks', a folder that is not Temper's, and this installer never writes into it." && echo yes || echo no)|$(echo "$OUT" | grep -qxF "The Temper hook is kept in $WORKDIR/.git/temper-gate/pre-commit (in the repository's git folder, never committed). Nothing else was written. To use the Temper commit gate, add the line between the BEGIN and END lines below to your pre-commit hook." && echo yes || echo no)|$(grep -q 'gate commit' .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)|$(echo "$OUT" | tail -1 | grep -qxF "Hint: add the line to your own pre-commit hook (sub/../dotdot-hooks/pre-commit), at its start or its end. It keeps your hook's own result. Create that file, executable, if it does not exist." && echo yes || echo no)"
assert_eq "the refusal writes nothing there, nothing in .git/hooks, and leaves core.hooksPath as it was" "no|no|no|no|sub/../dotdot-hooks" \
  "$([[ -e dotdot-hooks ]] && echo yes || echo no)|$([[ -e sub ]] && echo yes || echo no)|$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)|$([[ -e .git/temper-pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)"
# A value with '..' that leads out of the repository: the same refusal, and nothing is made there.
git config core.hooksPath ../outside-hooks
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); RC=$?
assert_eq "a core.hooksPath with '..' that leads outside the repository is refused, with the hook kept" "1|yes|yes" \
  "$RC|$(echo "$OUT" | grep -qxF "FAIL: core.hooksPath is set to '../outside-hooks', a folder that is not Temper's, and this installer never writes into it." && echo yes || echo no)|$(echo "$OUT" | grep -qxF "The Temper hook is kept in $WORKDIR/.git/temper-gate/pre-commit (in the repository's git folder, never committed). Nothing else was written. To use the Temper commit gate, add the line between the BEGIN and END lines below to your pre-commit hook." && echo yes || echo no)"
assert_eq "that refusal makes nothing outside and writes nothing in .git/hooks" "no|no" \
  "$([[ -e "${WORKDIR%/*}/outside-hooks" ]] && echo yes || echo no)|$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)"
git config core.hooksPath /nonexistent-temper-hooks
assert_exit "install.sh refuses an absolute core.hooksPath outside the repository" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
assert_eq "the refusal of an outside folder writes nothing" "no" "$([[ -e /nonexistent-temper-hooks ]] && echo yes || echo no)"
K_HOME_HAD="$([[ -e "$HOME/.temper-test-hooks" ]] && echo yes || echo no)"
git config core.hooksPath '~/.temper-test-hooks'
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); RC=$?
assert_eq "install.sh refuses a core.hooksPath under the home folder, names the hook there, and makes nothing" "1|yes|$K_HOME_HAD" \
  "$RC|$(echo "$OUT" | tail -1 | grep -qF "($HOME/.temper-test-hooks/pre-commit)" && echo yes || echo no)|$([[ -e "$HOME/.temper-test-hooks" ]] && echo yes || echo no)"
mkdir -p cfg-hooks
echo '{}' > cfg-hooks/settings.json
git config core.hooksPath cfg-hooks
assert_exit "install.sh refuses a hooks folder that holds a JSON file" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
assert_eq "no pre-commit is written into a folder that holds a JSON file" "no" "$([[ -e cfg-hooks/pre-commit ]] && echo yes || echo no)"
# An absolute folder inside the repository is not written either; once its pre-commit holds the
# line, a re-run says it calls the Temper hook.
mkdir -p abs-hooks
git config core.hooksPath "$(git rev-parse --show-toplevel)/abs-hooks"
assert_exit "an absolute core.hooksPath inside the repository is refused" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
K_CALL='_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1'
assert_eq "and nothing is written into it" "" "$(ls -A abs-hooks)"
printf '#!/bin/sh\n%s\n' "$K_CALL" > abs-hooks/pre-commit
chmod +x abs-hooks/pre-commit
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); RC=$?
assert_eq "once that folder's pre-commit holds the line, a re-run says it calls the Temper hook" "0|yes" \
  "$RC|$(echo "$OUT" | grep -qxF "The pre-commit hook $WORKDIR/abs-hooks/pre-commit calls the Temper hook ($WORKDIR/.git/temper-gate/pre-commit), which is now current, so nothing else was written." && echo yes || echo no)"
git config core.hooksPath ./dot-hooks/
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); RC=$?
assert_eq "a core.hooksPath with a leading ./ and a trailing / is refused, the hint names dot-hooks/pre-commit, and nothing is made" "1|yes|no" \
  "$RC|$(echo "$OUT" | tail -1 | grep -qF '(dot-hooks/pre-commit)' && echo yes || echo no)|$([[ -e dot-hooks ]] && echo yes || echo no)"
# --global is still accepted: it prints a note and installs the same as the default.
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-gate
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" --global 2>&1); RC=$?
assert_eq "--global prints the note and installs the same as the default" "0|yes|yes|$(pwd -P)/.git/temper-gate" \
  "$RC|$(echo "$OUT" | head -1 | grep -qxF 'Note: the default install now does what --global did.' && echo yes || echo no)|$([[ -x .git/temper-gate/pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-gate .git/temper-pre-commit .git/hooks/pre-commit abs-hooks dot-hooks cfg-hooks "$WORKDIR/outside"

# --- install.sh and the commit guards: no write through a link, the installer's own symlinks,
# chained hooks, worktrees, --global over a set core.hooksPath, staged-only secret scans, the
# CLI's full path in guard messages, and the CLI's refusal of an unsafe .temper folder ---
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/hooks/pre-commit .git/hooks/pre-commit.bak.* .git/temper-git-hooks .git/temper-gate .git/temper-pre-commit
I_PLUG="$WORKDIR/install-plugin"
rm -rf "$I_PLUG"
mkdir -p "$I_PLUG/scripts/guards" "$I_PLUG/inner"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$I_PLUG/scripts/"
for g in install.sh block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh protect-regression-test.sh; do
  cp "$REPO_ROOT/scripts/guards/$g" "$I_PLUG/scripts/guards/$g"
done
I_INSTALL="$I_PLUG/scripts/guards/install.sh"
I_CLI_LINE="TEMPER_CLI=$(printf '%q' "$I_PLUG/scripts/temper")"
_i_gates() { # _i_gates PASS|FAIL: a run whose plan, build, review and check gates passed, or whose check gate failed
  echo '{"command": "temper", "run_mode": "interactive"}' > .temper/build-state.json
  python3 -c '
import json, sys
json.dump({s: {"verdict": sys.argv[1] if s == "check" else "PASS", "requirements": [], "ts": "x"}
           for s in ("plan", "build", "review", "check")}, open(".temper/gates.json", "w"))' "$1"
  echo '[]' > .temper/overrides.json
}
_i_clean() { # undoes an install in this repository: core.hooksPath unset, the kept hooks removed
  git config --unset core.hooksPath 2>/dev/null || true
  rm -rf .git/temper-gate .git/temper-pre-commit
}
# A pre-commit that is a hard link to a plugin file (here one that reads as an older Temper hook):
# the installer writes nothing in .git/hooks, so the plugin file keeps its text, and the kept hook
# in .git/temper-gate carries this plugin's CLI (install.sh itself, a hook that is not Temper's and
# is refused, included).
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (plugin data)\n' > "$I_PLUG/inner/hard-target"
ln "$I_PLUG/inner/hard-target" .git/hooks/pre-commit
bash "$I_INSTALL" >/dev/null 2>&1
assert_eq "install.sh never writes into .git/hooks: a hard-linked pre-commit's plugin file keeps its text, the kept hook has this CLI" "# Temper native pre-commit hook (plugin data)|2|yes" \
  "$(sed -n 2p "$I_PLUG/inner/hard-target")|$(wc -l < "$I_PLUG/inner/hard-target" | tr -d ' ')|$(grep -qxF "$I_CLI_LINE" .git/temper-gate/pre-commit && echo yes || echo no)"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
_i_clean
I_SUM="$(cksum < "$I_INSTALL")"
ln "$I_INSTALL" .git/hooks/pre-commit
bash "$I_INSTALL" >/dev/null 2>&1
assert_eq "a pre-commit hard-linked to install.sh itself leaves install.sh as it was" "$I_SUM" "$(cksum < "$I_INSTALL")"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
_i_clean
# install.sh reached through a chain of symlinks finds the real plugin folder.
mkdir -p "$WORKDIR/inst-bin"
ln -s "$I_INSTALL" "$WORKDIR/inst-bin/temper-install"
ln -s temper-install "$WORKDIR/inst-bin/chained-install"
bash "$WORKDIR/inst-bin/chained-install" >/dev/null 2>&1
assert_eq "install.sh run through a chain of symlinks writes the real CLI path into the hook" "yes" \
  "$(grep -qxF "$I_CLI_LINE" .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)"
rm -rf "$WORKDIR/inst-bin"
_i_clean
# A copy outside a scripts/guards folder (even with a CLI where the failed suffix strip would
# look for one), or a plugin whose CLI does not run, writes no hook.
mkdir -p "$WORKDIR/loose-installer/scripts"
cp "$I_INSTALL" "$WORKDIR/loose-installer/install.sh"
cp "$TEMPER" "$WORKDIR/loose-installer/scripts/temper"
assert_exit "install.sh outside a plugin's scripts/guards folder refuses" 1 bash "$WORKDIR/loose-installer/install.sh"
chmod -x "$I_PLUG/scripts/temper"
assert_exit "install.sh refuses when the plugin's CLI is not executable" 1 bash "$I_INSTALL"
# A refusal before the repository's git folder is known prints the whole hook between a BEGIN and
# an END line, without its first line and in a subshell whose exits end only it, ready to copy.
OUT=$(bash "$I_INSTALL" 2>&1; true)
chmod +x "$I_PLUG/scripts/temper"
assert_eq "neither refusal writes a hook or sets core.hooksPath" "no|no|no|none" \
  "$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)|$([[ -e .git/temper-pre-commit ]] && echo yes || echo no)|$([[ -e .git/temper-gate ]] && echo yes || echo no)|$(git config --get core.hooksPath || echo none)"
rm -rf "$WORKDIR/loose-installer"
I_LINES="$(printf '%s\n' "$OUT" | sed -n '/^----- BEGIN Temper pre-commit hook lines -----$/,/^----- END Temper pre-commit hook lines -----$/p' | sed '1d;$d')"
printf '%s\n' "$I_LINES" > "$WORKDIR/hook-lines.sh"
assert_eq "an early refusal prints the whole hook in a subshell that keeps the host hook's result, a valid script" \
  '_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"|(|) || exit 1|yes|no|yes|yes' \
  "$(sed -n 1p "$WORKDIR/hook-lines.sh")|$(sed -n 2p "$WORKDIR/hook-lines.sh")|$(tail -1 "$WORKDIR/hook-lines.sh")|$(grep -qxF "$I_CLI_LINE" "$WORKDIR/hook-lines.sh" && echo yes || echo no)|$(grep -qxF '#!/usr/bin/env bash' "$WORKDIR/hook-lines.sh" && echo yes || echo no)|$(bash -n "$WORKDIR/hook-lines.sh" 2>/dev/null && echo yes || echo no)|$(printf '%s\n' "$OUT" | grep -qxF 'Nothing was written. To use the Temper commit gate, add the lines between the BEGIN and END lines below to your pre-commit hook.' && echo yes || echo no)"
rm -f "$WORKDIR/hook-lines.sh"
# A refusal over an outside core.hooksPath keeps the hook in the repository's git folder and prints
# exactly one line, which names no path of this machine.
git config core.hooksPath ../outside-hooks
OUT=$(bash "$I_INSTALL" 2>&1; true)
git config --unset core.hooksPath
I_LINES="$(printf '%s\n' "$OUT" | sed -n '/^----- BEGIN Temper pre-commit hook lines -----$/,/^----- END Temper pre-commit hook lines -----$/p' | sed '1d;$d')"
assert_eq "a refusal that keeps the hook prints exactly the line that runs it" \
  '_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1' \
  "$I_LINES"
assert_eq "the kept hook is the full hook with this plugin's paths, a valid bash script" "#!/usr/bin/env bash|yes|yes" \
  "$(head -1 .git/temper-gate/pre-commit)|$(grep -qxF "$I_CLI_LINE" .git/temper-gate/pre-commit && echo yes || echo no)|$(bash -n .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)"
_i_clean
# A run from a folder inside the plugin's folder whose repository's top is elsewhere (an
# installed copy inside some repository) writes nothing.
assert_exit "install.sh refuses a run from inside the plugin's folder when the repository's top is elsewhere" 1 \
  bash -c "cd '$I_PLUG/inner' && bash '$I_INSTALL'"
assert_eq "that refusal writes no hook into the enclosing repository and sets no core.hooksPath" "no|no|none" \
  "$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)|$([[ -e .git/temper-gate ]] && echo yes || echo no)|$(git config --get core.hooksPath || echo none)"
# A .git/config that is a symlink into the plugin's folder (git config writes through it) is
# refused, by the default run and by --global, before anything is written.
cp .git/config "$I_PLUG/inner/config"
I_CFG_SUM="$(cksum < "$I_PLUG/inner/config")"
mv .git/config .git/config-saved
ln -s "$I_PLUG/inner/config" .git/config
assert_exit "install.sh refuses a .git/config that is a symlink into the plugin's own folder" 1 bash "$I_INSTALL"
assert_exit "--global refuses it the same way" 1 bash "$I_INSTALL" --global
assert_eq "the plugin file behind .git/config is left as it was, and no hook folder is made" "$I_CFG_SUM|no" \
  "$(cksum < "$I_PLUG/inner/config")|$([[ -e .git/temper-gate ]] && echo yes || echo no)"
rm -f .git/config
mv .git/config-saved .git/config
# A pre-commit hook that is not Temper's is refused, even with pre-commit.bak names planted as
# symlinks into the plugin's folder (as an older installer named its backups): each is named as a
# set-aside hook, nothing is written through them, and the hook stays as it was.
printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo 'plugin data' > "$I_PLUG/inner/bak-target"
for ts in $(python3 -c 'import time; t = time.time(); print(" ".join(time.strftime("%Y%m%d%H%M%S", time.localtime(t + i)) for i in range(-1, 20)))'); do
  ln -sf "$I_PLUG/inner/bak-target" ".git/hooks/pre-commit.bak.$ts"
done
OUT=$(bash "$I_INSTALL" 2>&1); I_RC=$?
assert_eq "install.sh refuses a hook that is not Temper's, with backup names planted as symlinks into the plugin's own folder" "1|21|none" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c '^Warning: .*/pre-commit.bak.[0-9]* is a pre-commit hook that an older Temper installer set aside')|$(git config --get core.hooksPath || echo none)"
assert_eq "the plugin file behind the backup name and the existing hook are left as they were" "plugin data|exit 0" \
  "$(cat "$I_PLUG/inner/bak-target")|$(sed -n 2p .git/hooks/pre-commit)"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
_i_clean
# --global over a core.hooksPath set to another folder does what the default does: it writes
# nothing there and leaves the value as it was.
mkdir -p .husky
git config core.hooksPath .husky
assert_exit "--global refuses when core.hooksPath is set to another folder" 1 bash "$I_INSTALL" --global
assert_eq "the refused --global leaves core.hooksPath as it was and writes nothing in that folder" ".husky|" \
  "$(git config --get core.hooksPath)|$(ls -A .husky)"
git config --unset core.hooksPath
rm -rf .husky
_i_clean
# --global runs again over the core.hooksPath it set itself.
rm -f .git/hooks/pre-commit
bash "$I_INSTALL" --global >/dev/null 2>&1
OUT=$(bash "$I_INSTALL" --global 2>&1); I_RC=$?
assert_eq "--global runs again over the core.hooksPath it set itself" "0|yes" "$I_RC|$(printf '%s\n' "$OUT" | grep -q 'is already installed' && echo yes || echo no)"
_i_gates PASS
assert_exit "the --global hook passes a green gate" 0 bash .git/temper-gate/pre-commit
_i_clean
rm -f .git/hooks/pre-commit
# block-secrets.sh as an in-agent hook scans only the text a call adds; with no JSON on stdin,
# or with --staged (the installed hook's flag), it scans the staged files.
I_KEY="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
printf 'key = %s\n' "$I_KEY" > leak.txt
git add leak.txt >/dev/null 2>&1
I_SECRETS="$I_PLUG/scripts/guards/block-secrets.sh"
_i_scan() { # _i_scan <tool name> <tool_input JSON, where KEY stands for the secret> -> the exit code
  python3 -c 'import json, sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2].replace("KEY", sys.argv[3]))}))' "$1" "$2" "$I_KEY" \
    | bash "$I_SECRETS" >/dev/null 2>&1
  echo $?
}
assert_eq "block-secrets as an in-agent hook passes a call that unstages a staged secret, and an Edit that takes one out" "0|0" \
  "$(_i_scan Bash '{"command": "git restore --staged leak.txt"}')|$(_i_scan Edit '{"file_path": "leak.txt", "old_string": "key = KEY", "new_string": "key = env"}')"
assert_eq "block-secrets blocks a secret that a Write, an Edit, a MultiEdit or a Bash command adds" "2|2|2|2" \
  "$(_i_scan Write '{"file_path": "a.txt", "content": "k = KEY"}')|$(_i_scan Edit '{"file_path": "a.txt", "old_string": "x", "new_string": "k = KEY"}')|$(_i_scan MultiEdit '{"file_path": "a.txt", "edits": [{"old_string": "a", "new_string": "b"}, {"old_string": "c", "new_string": "KEY"}]}')|$(_i_scan Bash '{"command": "echo KEY > k.txt"}')"
assert_eq "block-secrets with no JSON on stdin, and with --staged (whatever is on stdin), scans the staged files" "2|2|2" \
  "$(bash "$I_SECRETS" < /dev/null >/dev/null 2>&1; echo $?)|$(bash "$I_SECRETS" --staged < /dev/null >/dev/null 2>&1; echo $?)|$(echo '{"tool_input": {"command": "ls"}}' | bash "$I_SECRETS" --staged >/dev/null 2>&1; echo $?)"
git rm -q --cached leak.txt >/dev/null 2>&1 || true
rm -f leak.txt
# The guard messages name the CLI by its full path, quoted for the shell.
I_SP="$WORKDIR/space plugin"
rm -rf "$I_SP"
mkdir -p "$I_SP/scripts/guards"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$I_SP/scripts/"
cp "$REPO_ROOT/scripts/guards/block-uncommitted-gate.sh" "$REPO_ROOT/scripts/guards/protect-regression-test.sh" "$I_SP/scripts/guards/"
I_SP_CLI="$(printf '%q' "$I_SP/scripts/temper")"
_i_gates FAIL
OUT=$(echo '{"tool_input": {"command": "git commit -m x"}}' | bash "$I_SP/scripts/guards/block-uncommitted-gate.sh" 2>&1; true)
assert_eq "uncommitted-gate's block message names the CLI by its full path, quoted" "yes" \
  "$(printf '%s\n' "$OUT" | grep -qF "run: $I_SP_CLI report" && echo yes || echo no)"
mkdir -p reg-tests
echo 'def test_x(): pass' > reg-tests/test_reg.py
ln reg-tests/test_reg.py reg-tests/test_alias.py
echo '{"command": "fix", "regression_test": "reg-tests/test_reg.py"}' > .temper/build-state.json
OUT=$(echo '{"tool_input": {"file_path": "reg-tests/test_reg.py"}}' | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$I_SP/scripts/guards/protect-regression-test.sh" 2>&1; true)
assert_eq "the regression-test shield's message names the CLI by its full path, quoted" "yes" \
  "$(printf '%s\n' "$OUT" | grep -qF "$I_SP_CLI state set regression_test \"\"" && echo yes || echo no)"
assert_exit "the regression-test shield blocks an Edit through a hard link to the recorded test (the same file)" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"reg-tests/test_alias.py\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$I_SP/scripts/guards/protect-regression-test.sh'"
rm -rf reg-tests "$I_SP"
# The CLI refuses an unsafe .temper folder with exit 3: while a run is active (build-state.json
# is there) both commit hooks block and say to remove the symlink; with no run active they fail
# open with one warning line.
I_RP="$WORKDIR/refusing-plugin"
rm -rf "$I_RP"
mkdir -p "$I_RP/scripts/guards"
for g in install.sh block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh; do
  cp "$REPO_ROOT/scripts/guards/$g" "$I_RP/scripts/guards/$g"
done
printf '#!/usr/bin/env bash\necho "FAIL: the .temper folder holds a symlink" >&2\nexit 3\n' > "$I_RP/scripts/temper"
chmod +x "$I_RP/scripts/temper"
_i_clean
bash "$I_RP/scripts/guards/install.sh" >/dev/null 2>&1
OUT=$(bash .git/temper-gate/pre-commit 2>&1); I_RC=$?
assert_eq "the installed hook blocks, naming the symlink to remove, when the CLI exits 3 during an active run" "1|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'remove the symlink')"
OUT=$(echo '{"tool_input": {"command": "git commit -m x"}}' | bash "$I_RP/scripts/guards/block-uncommitted-gate.sh" 2>&1); I_RC=$?
assert_eq "the in-agent commit gate blocks, naming the symlink to remove, when the CLI exits 3 during an active run" "2|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'remove the symlink')"
mv .temper/build-state.json "$WORKDIR/build-state.saved"
OUT=$(bash .git/temper-gate/pre-commit 2>&1); I_RC=$?
assert_eq "the installed hook fails open with one warning line when the CLI exits 3 and no run is active" "0|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'commit gate was skipped')"
OUT=$(echo '{"tool_input": {"command": "git commit -m x"}}' | bash "$I_RP/scripts/guards/block-uncommitted-gate.sh" 2>&1); I_RC=$?
assert_eq "the in-agent commit gate fails open with one warning line when the CLI exits 3 and no run is active" "0|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'commit gate was skipped')"
mv "$WORKDIR/build-state.saved" .temper/build-state.json
rm -rf "$I_RP"
_i_clean
# With CDPATH set, the scripts still find their own folder when called by a relative path.
OUT=$(cd "$WORKDIR" && CDPATH="$WORKDIR" bash install-plugin/scripts/guards/install.sh 2>&1); I_RC=$?
assert_eq "with CDPATH set, install.sh called by a relative path writes the real CLI path" "0|yes" \
  "$I_RC|$(grep -qxF "$I_CLI_LINE" .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)"
assert_eq "the installed hook runs block-secrets with --staged" "yes" \
  "$(grep -qF 'bash "$SECRETS_SCRIPT" --staged' .git/temper-gate/pre-commit && echo yes || echo no)"
_i_gates FAIL
assert_exit "with CDPATH set, uncommitted-gate called by a relative path still blocks a red gate" 2 \
  bash -c "cd '$WORKDIR' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | CDPATH='$WORKDIR' bash install-plugin/scripts/guards/block-uncommitted-gate.sh"
_i_clean
# A linked worktree: the hook is kept once in the repository's own git folder, core.hooksPath in
# the repository's config points at it, and it gates commits made in the worktree. Nothing is
# written in the repository's .git/hooks.
I_MAIN="$WORKDIR/wt-main"
I_FEAT="$WORKDIR/wt-feat"
rm -rf "$I_MAIN" "$I_FEAT"
git init -q "$I_MAIN"
git -C "$I_MAIN" config user.email "test@example.com"
git -C "$I_MAIN" config user.name "test"
git -C "$I_MAIN" commit -q --allow-empty -m init
git -C "$I_MAIN" worktree add -q "$I_FEAT" >/dev/null 2>&1
I_MAIN_HOOKS="$(ls -A "$I_MAIN/.git/hooks")"
assert_exit "in a linked worktree, install.sh installs for the whole repository" 0 \
  bash -c "cd '$I_FEAT' && bash '$I_INSTALL'"
assert_eq "the hook is kept in the main checkout's .git/temper-gate, core.hooksPath points there, and .git/hooks is as it was" \
  "yes|$I_MAIN/.git/temper-gate|yes|no" \
  "$(grep -qxF "$I_CLI_LINE" "$I_MAIN/.git/temper-gate/pre-commit" 2>/dev/null && echo yes || echo no)|$(git -C "$I_FEAT" config --get core.hooksPath)|$([[ "$(ls -A "$I_MAIN/.git/hooks")" == "$I_MAIN_HOOKS" ]] && echo yes || echo no)|$([[ -e "$I_MAIN/.git/worktrees/wt-feat/temper-gate" ]] && echo yes || echo no)"
OUT=$(cd "$I_FEAT" && bash "$I_INSTALL" 2>&1); I_RC=$?
assert_eq "a second run in the worktree says the hook is already installed and exits 0" "0|yes" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -qxF "The Temper pre-commit hook is already installed: $I_MAIN/.git/temper-gate/pre-commit (core.hooksPath points at its folder)." && echo yes || echo no)"
(cd "$I_FEAT" && "$I_PLUG/scripts/temper" init >/dev/null && _i_gates FAIL && echo x > wt.txt && git add wt.txt)
assert_exit "the hook blocks a real git commit on a red gate in the worktree" 1 git -C "$I_FEAT" commit -q -m wt
# A submodule: its git folder is in the superproject's .git/modules. The hook is kept there and the
# submodule's own config points at it; the superproject's config is left as it was.
I_SUPER="$WORKDIR/sm-super"
I_SUBSRC="$WORKDIR/sm-source"
rm -rf "$I_SUPER" "$I_SUBSRC"
git init -q "$I_SUBSRC"
git -C "$I_SUBSRC" config user.email "test@example.com"
git -C "$I_SUBSRC" config user.name "test"
git -C "$I_SUBSRC" commit -q --allow-empty -m sub
git init -q "$I_SUPER"
git -C "$I_SUPER" config user.email "test@example.com"
git -C "$I_SUPER" config user.name "test"
git -C "$I_SUPER" -c protocol.file.allow=always submodule add -q "$I_SUBSRC" sub >/dev/null 2>&1
I_SM_GIT="$I_SUPER/.git/modules/sub"
assert_exit "in a submodule, install.sh installs for the submodule's own repository" 0 \
  bash -c "cd '$I_SUPER/sub' && bash '$I_INSTALL'"
assert_eq "the hook is kept in the submodule's git folder, its config points there, and the superproject is left alone" \
  "yes|$I_SM_GIT/temper-gate|none|no" \
  "$(grep -qxF "$I_CLI_LINE" "$I_SM_GIT/temper-gate/pre-commit" 2>/dev/null && echo yes || echo no)|$(git -C "$I_SUPER/sub" config --get core.hooksPath)|$(git -C "$I_SUPER" config --get core.hooksPath || echo none)|$([[ -e "$I_SUPER/.git/temper-gate" ]] && echo yes || echo no)"
(cd "$I_SUPER/sub" && git config user.email "test@example.com" && git config user.name "test" && "$I_PLUG/scripts/temper" init >/dev/null && _i_gates FAIL && echo s > s.txt && git add s.txt)
assert_exit "the hook blocks a real git commit on a red gate in the submodule" 1 git -C "$I_SUPER/sub" commit -q -m sm
rm -rf "$I_SUPER" "$I_SUBSRC"
# A linked worktree whose repository keeps its git folder inside the plugin's folder is refused.
git init -q "$I_PLUG"
git -C "$I_PLUG" config user.email "test@example.com"
git -C "$I_PLUG" config user.name "test"
git -C "$I_PLUG" commit -q --allow-empty -m init
git -C "$I_PLUG" worktree add -q "$WORKDIR/plug-wt" >/dev/null 2>&1
assert_exit "in a linked worktree whose repository's git folder is inside the plugin's folder, install.sh refuses" 1 \
  bash -c "cd '$WORKDIR/plug-wt' && bash '$I_INSTALL'"
assert_eq "that refusal writes nothing in the plugin's git folder" "no|no|none" \
  "$([[ -e "$I_PLUG/.git/hooks/pre-commit" ]] && echo yes || echo no)|$([[ -e "$I_PLUG/.git/temper-gate" ]] && echo yes || echo no)|$(git -C "$I_PLUG" config --get core.hooksPath || echo none)"
rm -rf "$I_MAIN" "$I_FEAT" "$WORKDIR/plug-wt" "$I_PLUG"

# --- stage-marker.sh + verify-stage-gate.sh: fixed names in the project, never inside the plugin ---
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/guards/verify-stage-gate.sh"
rm -f .temper/pending-stage.json .temper/stage-gate.log
echo '{"prompt": "/temper:plan x"}' | bash "$MARKER"
OUT=$(echo '{}' | bash "$VERIFY" 2>&1; true)
assert_eq "verify-stage-gate logs each firing to .temper/stage-gate.log" "yes" \
  "$(grep -q 'blocked stop (stage=plan' .temper/stage-gate.log && echo yes || echo no)"
# The CLI's own full path is taken out first: the folder the repository sits in is not the message's.
CLI_Q="$(printf '%q' "$REPO_ROOT/scripts/temper")"
assert_eq "the block message names the stage brief without building a path from the stage" "yes|no" \
  "$(echo "$OUT" | grep -q "that stage's brief" && echo yes || echo no)|$(echo "${OUT//"$CLI_Q"/CLI}" | grep -q 'agents/' && echo yes || echo no)"
# A throwaway plugin folder holding copies of the scripts: a project folder inside it is skipped,
# the plugin folder itself (developing Temper with Temper) is a project like any other.
FAKE_PLUGIN="$WORKDIR/fake-plugin"
rm -rf "$FAKE_PLUGIN"
mkdir -p "$FAKE_PLUGIN/scripts/guards" "$FAKE_PLUGIN/sub"
cp "$MARKER" "$VERIFY" "$REPO_ROOT/scripts/guards/run-formatter.sh" "$FAKE_PLUGIN/scripts/guards/"
cp "$TEMPER" "$FAKE_PLUGIN/scripts/temper"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$FAKE_PLUGIN/sub" bash "$FAKE_PLUGIN/scripts/guards/stage-marker.sh"
assert_eq "stage-marker writes nothing in a project folder inside the plugin's own folder" "no" \
  "$([[ -e "$FAKE_PLUGIN/sub/.temper" ]] && echo yes || echo no)"
mkdir -p "$FAKE_PLUGIN/sub/.temper"
echo '{"stage": "plan", "blocks": 0}' > "$FAKE_PLUGIN/sub/.temper/pending-stage.json"
assert_exit "verify-stage-gate skips a project folder inside the plugin's own folder" 0 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$FAKE_PLUGIN/sub' bash '$FAKE_PLUGIN/scripts/guards/verify-stage-gate.sh'"
assert_eq "the skipped stop hook writes, changes and deletes nothing there" "no|0" \
  "$([[ -e "$FAKE_PLUGIN/sub/.temper/stage-gate.log" ]] && echo yes || echo no)|$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['blocks'])" "$FAKE_PLUGIN/sub/.temper/pending-stage.json")"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$FAKE_PLUGIN" bash "$FAKE_PLUGIN/scripts/guards/stage-marker.sh"
assert_eq "stage-marker skips an installed copy of the plugin folder (no .git of its own)" "no" \
  "$([[ -e "$FAKE_PLUGIN/.temper" ]] && echo yes || echo no)"
mkdir -p "$FAKE_PLUGIN/.temper"
echo '{"stage": "plan", "blocks": 0}' > "$FAKE_PLUGIN/.temper/pending-stage.json"
assert_exit "verify-stage-gate skips an installed copy of the plugin folder" 0 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$FAKE_PLUGIN' bash '$FAKE_PLUGIN/scripts/guards/verify-stage-gate.sh'"
assert_eq "the skipped stop hook leaves the installed copy's marker and log as they were" "no|0" \
  "$([[ -e "$FAKE_PLUGIN/.temper/stage-gate.log" ]] && echo yes || echo no)|$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['blocks'])" "$FAKE_PLUGIN/.temper/pending-stage.json")"
rm -rf "$FAKE_PLUGIN/.temper"
git init -q "$FAKE_PLUGIN"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$FAKE_PLUGIN" bash "$FAKE_PLUGIN/scripts/guards/stage-marker.sh"
assert_eq "stage-marker still marks the plugin folder itself as a project (its own git repository)" "plan" \
  "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['stage'])" "$FAKE_PLUGIN/.temper/pending-stage.json")"
assert_exit "verify-stage-gate blocks in the plugin folder's own repository like in any project" 2 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$FAKE_PLUGIN' bash '$FAKE_PLUGIN/scripts/guards/verify-stage-gate.sh'"

# --- run-formatter.sh: only a file inside the project, never a file of the plugin's folder ---
setup
cat >> .claude/temper.config <<'EOF'
format:
  cmd: "perl -pi -e 's/  +/ /g' {file}"
EOF
FORMATTER="$REPO_ROOT/scripts/guards/run-formatter.sh"
OUTSIDE_DIR="$(mktemp -d)"
echo 'a  b' > "$OUTSIDE_DIR/x.txt"
bash -c "echo '{\"tool_input\": {\"file_path\": \"$OUTSIDE_DIR/x.txt\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$FORMATTER'"
assert_eq "formatter: a file outside the project folder is left as it is" "a  b" "$(cat "$OUTSIDE_DIR/x.txt")"
rm -rf "$OUTSIDE_DIR"
echo 'r  s' > rel.txt
bash -c "echo '{\"tool_input\": {\"file_path\": \"rel.txt\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$FORMATTER'"
assert_eq "formatter: a relative path is taken from the project folder" "r s" "$(cat rel.txt)"
rm -f rel.txt
echo 'p  q' > "$FAKE_PLUGIN/sub/y.txt"
bash -c "echo '{\"tool_input\": {\"file_path\": \"$FAKE_PLUGIN/sub/y.txt\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$FAKE_PLUGIN/scripts/guards/run-formatter.sh'"
assert_eq "formatter: a file of the plugin's own folder is left as it is" "p  q" "$(cat "$FAKE_PLUGIN/sub/y.txt")"
mkdir -p "$FAKE_PLUGIN/.claude"
cp .claude/temper.config "$FAKE_PLUGIN/.claude/temper.config"
bash -c "echo '{\"tool_input\": {\"file_path\": \"$FAKE_PLUGIN/sub/y.txt\"}}' | CLAUDE_PROJECT_DIR='$FAKE_PLUGIN' bash '$FAKE_PLUGIN/scripts/guards/run-formatter.sh'"
assert_eq "formatter: when the project is the plugin folder itself, its files are left as they are" "p  q" "$(cat "$FAKE_PLUGIN/sub/y.txt")"
rm -rf "$FAKE_PLUGIN"

# --- guards, plan_review.py and the validators: no write lands in the plugin's own folder ---
# A throwaway plugin folder holds copies of the scripts; each copy finds that folder by the
# literal suffix of its own path, as the real scripts do. inner/code stands for any folder of it.
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-gate .git/temper-pre-commit .git/hooks/pre-commit
G_PLUG="$WORKDIR/guard-plugin"
rm -rf "$G_PLUG"
mkdir -p "$G_PLUG/scripts/guards" "$G_PLUG/inner/code"
cp "$REPO_ROOT/scripts/guards/install.sh" "$G_PLUG/scripts/guards/install.sh"
# The installer refuses to write a hook whose CLI is missing, so the throwaway plugin holds one:
# each refusal below then refuses for the reason it names.
cp "$TEMPER" "$G_PLUG/scripts/temper"
G_INSTALL="$G_PLUG/scripts/guards/install.sh"
# install.sh: a core.hooksPath that leads into the plugin folder, directly or through a symlink,
# is a folder that is not Temper's: refused, and nothing is written or made there.
git config core.hooksPath guard-plugin/inner/code
assert_exit "install.sh refuses a core.hooksPath that leads into the plugin's own folder" 1 bash "$G_INSTALL"
ln -s "$G_PLUG/inner/code" linked-hooks
git config core.hooksPath linked-hooks
assert_exit "install.sh refuses a core.hooksPath that is a symlink into the plugin's own folder" 1 bash "$G_INSTALL"
git config core.hooksPath linked-hooks/new
assert_exit "install.sh refuses a folder still to be made under a symlink into the plugin's own folder" 1 bash "$G_INSTALL"
mkdir -p rel-dir
ln -s ../guard-plugin/inner/code rel-dir/rel-link
git config core.hooksPath rel-dir/rel-link
assert_exit "install.sh refuses a relative symlink with '..' that leads into the plugin's own folder" 1 bash "$G_INSTALL"
git config --unset core.hooksPath
rm -rf .git/temper-gate
# A .git/hooks that is a symlink into the plugin's folder is only read: with no hook in it, the
# installer points core.hooksPath at the temper-gate folder and writes nothing through the link.
mv .git/hooks .git/hooks-saved
ln -s "$G_PLUG/inner/code" .git/hooks
assert_exit "a .git/hooks that is a symlink into the plugin's own folder is only read, and the install goes on" 0 bash "$G_INSTALL"
rm -f .git/hooks
mv .git/hooks-saved .git/hooks
assert_eq "none of these runs writes or creates anything in the plugin's folder" "no|no|" \
  "$([[ -e "$G_PLUG/inner/code/pre-commit" ]] && echo yes || echo no)|$([[ -e "$G_PLUG/inner/code/new" ]] && echo yes || echo no)|$(ls -A "$G_PLUG/inner/code")"
git config --unset core.hooksPath
rm -rf .git/temper-gate
# A pre-commit that is a symlink into the plugin folder (to a file that reads as an older Temper
# hook) is left as it was, never written through, and git no longer runs it.
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (plugin file)\n' > "$G_PLUG/inner/code/pre-commit"
rm -f .git/hooks/pre-commit
ln -s "$G_PLUG/inner/code/pre-commit" .git/hooks/pre-commit
OUT=$(bash "$G_INSTALL" 2>&1); G_RC=$?
assert_eq "a pre-commit symlink into the plugin folder is left as it was; the plugin file is untouched; a note says git no longer runs it" \
  "0|yes|# Temper native pre-commit hook (plugin file)|2|yes" \
  "$G_RC|$([[ -L .git/hooks/pre-commit ]] && echo yes || echo no)|$(sed -n 2p "$G_PLUG/inner/code/pre-commit")|$(wc -l < "$G_PLUG/inner/code/pre-commit" | tr -d ' ')|$(printf '%s\n' "$OUT" | grep -q '^Note: git no longer runs .*/.git/hooks/pre-commit, a hook from an older Temper' && echo yes || echo no)"
rm -f "$G_PLUG/inner/code/pre-commit" .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
git config --unset core.hooksPath
rm -rf .git/temper-gate
# The plugin's own repository: its .git folder is the one place in the plugin folder allowed.
git init -q "$G_PLUG"
git -C "$G_PLUG" config core.hooksPath inner/code
assert_exit "in the plugin's own repository, a core.hooksPath into its folder is refused" 1 \
  bash -c "cd '$G_PLUG' && bash scripts/guards/install.sh"
git -C "$G_PLUG" config --unset core.hooksPath
rm -rf "$G_PLUG/.git/temper-gate"
# A hook that is not Temper's in the plugin's own repository: refused, with the hook kept in that
# checkout's own .git folder and nothing else in the plugin folder written.
printf '#!/bin/sh\necho mine\n' > "$G_PLUG/.git/hooks/pre-commit"
chmod +x "$G_PLUG/.git/hooks/pre-commit"
OUT=$(cd "$G_PLUG" && bash scripts/guards/install.sh 2>&1); G_RC=$?
assert_eq "in the plugin's own repository, a refusal keeps the hook in its .git folder only, and sets no core.hooksPath" "1|yes|yes||none" \
  "$G_RC|$([[ -x "$G_PLUG/.git/temper-gate/pre-commit" ]] && echo yes || echo no)|$(printf '%s\n' "$OUT" | grep -qxF "The Temper hook is kept in $G_PLUG/.git/temper-gate/pre-commit (in the repository's git folder, never committed). Nothing else was written. To use the Temper commit gate, add the line between the BEGIN and END lines below to your pre-commit hook." && echo yes || echo no)|$(ls -A "$G_PLUG/inner/code")|$(git -C "$G_PLUG" config --get core.hooksPath || echo none)"
rm -f "$G_PLUG/.git/hooks/pre-commit"
assert_exit "in the plugin's own repository, the install is accepted" 0 \
  bash -c "cd '$G_PLUG' && bash scripts/guards/install.sh"
assert_eq "the hook lands in the plugin repository's .git/temper-gate, core.hooksPath points there, and nothing else in it is written" \
  "yes|$G_PLUG/.git/temper-gate|no|" \
  "$([[ -x "$G_PLUG/.git/temper-gate/pre-commit" ]] && echo yes || echo no)|$(git -C "$G_PLUG" config --get core.hooksPath)|$([[ -e "$G_PLUG/.git/hooks/pre-commit" ]] && echo yes || echo no)|$(ls -A "$G_PLUG/inner/code")"
# A repository inside the plugin folder is refused outright. The plugin's folder is told by the
# same file as this installer: a folder whose scripts/guards/install.sh is only a copy is not it.
mkdir -p "$G_PLUG/inner/proj"
git init -q "$G_PLUG/inner/proj"
assert_exit "install.sh refuses a repository that lies inside the plugin's own folder" 1 \
  bash -c "cd '$G_PLUG/inner/proj' && bash '$G_INSTALL'"
assert_eq "the refused repository inside the plugin gets no hook and no core.hooksPath" "no|no|none" \
  "$([[ -e "$G_PLUG/inner/proj/.git/hooks/pre-commit" ]] && echo yes || echo no)|$([[ -e "$G_PLUG/inner/proj/.git/temper-gate" ]] && echo yes || echo no)|$(git -C "$G_PLUG/inner/proj" config --get core.hooksPath || echo none)"
G_COPY="$WORKDIR/copy-plugin"
rm -rf "$G_COPY"
mkdir -p "$G_COPY/scripts/guards" "$G_COPY/inner"
cp "$G_INSTALL" "$G_COPY/scripts/guards/install.sh"
git init -q "$G_COPY/inner/proj"
assert_exit "a repository inside a folder whose scripts/guards/install.sh is only a copy of the installer is installed" 0 \
  bash -c "cd '$G_COPY/inner/proj' && bash '$G_INSTALL'"
rm -rf "$G_COPY"
# A repository whose git folder lies inside the plugin's folder (a .git file that points there) is
# refused, and nothing is written in that git folder.
rm -rf "$WORKDIR/sep-proj"
git init -q --separate-git-dir "$G_PLUG/inner/sep-git" "$WORKDIR/sep-proj"
assert_exit "install.sh refuses a repository whose git folder lies inside the plugin's own folder" 1 \
  bash -c "cd '$WORKDIR/sep-proj' && bash '$G_INSTALL'"
assert_eq "that refusal writes nothing in the git folder inside the plugin" "no|none" \
  "$([[ -e "$G_PLUG/inner/sep-git/temper-gate" ]] && echo yes || echo no)|$(git -C "$WORKDIR/sep-proj" config --get core.hooksPath || echo none)"
rm -rf "$WORKDIR/sep-proj" "$G_PLUG/inner/sep-git"
# GIT_DIR, GIT_WORK_TREE and GIT_CONFIG do not move the target.
git -C "$G_PLUG" config --unset core.hooksPath
rm -rf "$G_PLUG/.git/temper-gate" .git/temper-gate
env GIT_DIR="$G_PLUG/.git" GIT_WORK_TREE="$G_PLUG" bash "$G_INSTALL" >/dev/null 2>&1
assert_eq "with GIT_DIR and GIT_WORK_TREE on the plugin, the hook lands in the current folder's repository" "yes|no|none" \
  "$([[ -x .git/temper-gate/pre-commit ]] && echo yes || echo no)|$([[ -e "$G_PLUG/.git/temper-gate" ]] && echo yes || echo no)|$(git -C "$G_PLUG" config --get core.hooksPath || echo none)"
git config --unset core.hooksPath
rm -rf .git/temper-gate
git init -q --bare "$G_PLUG/inner/gitdir"
env GIT_DIR="$G_PLUG/inner/gitdir" GIT_WORK_TREE="$WORKDIR" GIT_CONFIG="$G_PLUG/inner/code/config" \
  bash "$G_INSTALL" --global >/dev/null 2>&1
assert_eq "--global with GIT_DIR and GIT_CONFIG in the plugin folder sets core.hooksPath in this repository only" \
  "$(pwd -P)/.git/temper-gate|none|no" \
  "$(git config --local --get core.hooksPath)|$(git --git-dir="$G_PLUG/inner/gitdir" config --get core.hooksPath || echo none)|$([[ -e "$G_PLUG/inner/code/config" ]] && echo yes || echo no)"
git config --unset core.hooksPath
rm -rf .git/temper-gate linked-hooks rel-dir
# The installed hook fails open when python3 is missing, and still blocks a staged secret.
rm -f .git/hooks/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo '{"command": "temper", "run_mode": "interactive"}' > .temper/build-state.json
echo '{"check": {"verdict": "FAIL", "requirements": [], "ts": "x"}}' > .temper/gates.json
echo '[]' > .temper/overrides.json
NOPY="$WORKDIR/no-python-bin"
mkdir -p "$NOPY"
for t in bash env git cat grep head sed tr date dirname; do ln -sf "$(command -v "$t")" "$NOPY/$t"; done
BASH_BIN="$(command -v bash)"
assert_exit "with python3, the installed hook blocks on a red gate" 1 "$BASH_BIN" .git/temper-gate/pre-commit
assert_exit "without python3 on PATH, the installed hook fails open" 0 env PATH="$NOPY" "$BASH_BIN" .git/temper-gate/pre-commit
G_KEY="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
printf 'key = %s\n' "$G_KEY" > leaked.txt
git add leaked.txt >/dev/null 2>&1
assert_exit "without python3 on PATH, the installed hook still blocks a staged secret" 1 \
  env PATH="$NOPY" "$BASH_BIN" .git/temper-gate/pre-commit
git rm -q --cached leaked.txt >/dev/null 2>&1 || true
rm -rf leaked.txt "$NOPY"
# A repository inside the plugin's own folder (a second checkout or worktree placed in it) is
# part of the plugin: the CLI refuses to run there, so the installed hook and the in-agent
# commit gate skip the gate there instead of blocking every commit.
G_OWN="$WORKDIR/gate-plugin"
rm -rf "$G_OWN"
mkdir -p "$G_OWN/scripts/guards" "$G_OWN/inner/proj"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$G_OWN/scripts/"
cp -R "$REPO_ROOT/agents" "$G_OWN/agents"
for g in install.sh block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh; do
  cp "$REPO_ROOT/scripts/guards/$g" "$G_OWN/scripts/guards/$g"
done
bash "$G_OWN/scripts/guards/install.sh" >/dev/null 2>&1
assert_exit "a hook whose CLI sits outside the project blocks a red gate" 1 bash .git/temper-gate/pre-commit
git init -q "$G_OWN/inner/proj"
cp -R .temper "$G_OWN/inner/proj/.temper"
cp .git/temper-gate/pre-commit "$G_OWN/inner/proj/gate-hook"
assert_exit "the same hook skips the gate in a repository inside the plugin folder (a folder above whose scripts/temper is its CLI)" 0 \
  bash -c "cd '$G_OWN/inner/proj' && bash gate-hook"
assert_exit "the in-agent commit gate blocks a red gate in a project outside the plugin folder" 2 \
  bash -c "echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
assert_exit "the in-agent commit gate skips a repository inside the plugin folder" 0 \
  bash -c "cd '$G_OWN/inner/proj' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
# The home folder is never a project: the CLI refuses to run there, so a repository whose top
# is the home folder (with a .temper left by an older version) skips the gate, never blocks.
G_HOME="$WORKDIR/gate-home"
rm -rf "$G_HOME"
git init -q "$G_HOME"
cp -R .temper "$G_HOME/.temper"
cp .git/temper-gate/pre-commit "$G_HOME/gate-hook"
assert_exit "the installed hook skips the gate in a repository at the home folder" 0 \
  bash -c "cd '$G_HOME' && HOME='$G_HOME' bash gate-hook"
assert_exit "the in-agent commit gate skips a repository at the home folder" 0 \
  bash -c "cd '$G_HOME' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | HOME='$G_HOME' bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
assert_exit "the same repository with another home folder still blocks a red gate" 2 \
  bash -c "cd '$G_HOME' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | HOME='$WORKDIR' bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
rm -rf "$G_HOME"
# A checkout of the plugin itself (its own top is the plugin's folder) is a project like any
# other: the same hook does not skip the gate there.
git init -q "$G_OWN"
cp -R .temper "$G_OWN/.temper"
cp .git/temper-gate/pre-commit "$G_OWN/gate-hook"
assert_exit "the installed hook still blocks a red gate in the plugin's own checkout" 1 \
  bash -c "cd '$G_OWN' && bash gate-hook"
rm -rf "$G_OWN"
git config --unset core.hooksPath
rm -rf .git/temper-gate
# stage-marker.sh and verify-stage-gate.sh: a .temper folder, marker or log that is a symlink
# would send the write out of the project's .temper folder, so the hooks do nothing then.
cp "$REPO_ROOT/scripts/guards/stage-marker.sh" "$REPO_ROOT/scripts/guards/verify-stage-gate.sh" "$G_PLUG/scripts/guards/"
G_PROJ="$WORKDIR/guard-project"
rm -rf "$G_PROJ"
mkdir -p "$G_PROJ"
ln -s "$G_PLUG/inner/code" "$G_PROJ/.temper"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$G_PROJ" bash "$G_PLUG/scripts/guards/stage-marker.sh"
rm -f "$G_PROJ/.temper"
mkdir -p "$G_PROJ/.temper"
ln -s "$G_PLUG/inner/code/marker.json" "$G_PROJ/.temper/pending-stage.json"
echo '{"prompt": "/temper:plan x"}' | CLAUDE_PROJECT_DIR="$G_PROJ" bash "$G_PLUG/scripts/guards/stage-marker.sh"
assert_eq "stage-marker writes nothing through a symlinked .temper folder or marker" "" "$(ls "$G_PLUG/inner/code")"
rm -f "$G_PROJ/.temper/pending-stage.json"
echo '{"stage": "plan", "blocks": 0}' > "$G_PROJ/.temper/pending-stage.json"
ln -s "$G_PLUG/inner/code/log.txt" "$G_PROJ/.temper/stage-gate.log"
assert_exit "verify-stage-gate still blocks when only its log file is a symlink" 2 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$G_PROJ' bash '$G_PLUG/scripts/guards/verify-stage-gate.sh'"
assert_eq "verify-stage-gate writes nothing through a symlinked log file" "" "$(ls "$G_PLUG/inner/code")"
rm -f "$G_PROJ/.temper/stage-gate.log" "$G_PROJ/.temper/pending-stage.json"
ln -s "$G_PLUG/inner/code/marker.json" "$G_PROJ/.temper/pending-stage.json"
echo '{"stage": "plan", "blocks": 0}' > "$G_PLUG/inner/code/marker.json"
assert_exit "verify-stage-gate skips a marker that is a symlink" 0 \
  bash -c "echo '{}' | CLAUDE_PROJECT_DIR='$G_PROJ' bash '$G_PLUG/scripts/guards/verify-stage-gate.sh'"
assert_eq "the skipped marker's target is left as it was" '{"stage": "plan", "blocks": 0}' "$(cat "$G_PLUG/inner/code/marker.json")"
rm -rf "$G_PROJ" "$G_PLUG/inner/code/marker.json"
# run-formatter.sh: a file name is only ever a name, never shell text.
cat >> .claude/temper.config <<'EOF'
format:
  cmd: "perl -pi -e 's/  +/ /g' {file}"
EOF
G_FMT="$REPO_ROOT/scripts/guards/run-formatter.sh"
for name in 'a;touch INJECTED_A;.txt' 'b$(touch INJECTED_B).txt' 'c`touch INJECTED_C`.txt'; do
  printf 'x  y\n' > "$name"
  python3 -c 'import json, sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$WORKDIR/$name" \
    | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$G_FMT"
done
assert_eq "formatter: a file name holding ';', a command substitution or backticks runs nothing" "0" \
  "$(find . -maxdepth 1 -name 'INJECTED*' | wc -l | tr -d ' ')"
assert_eq "formatter: such a file is still formatted, its name passed as one argument" "x y|x y|x y" \
  "$(cat 'a;touch INJECTED_A;.txt')|$(cat 'b$(touch INJECTED_B).txt')|$(cat 'c`touch INJECTED_C`.txt')"
rm -f 'a;touch INJECTED_A;.txt' 'b$(touch INJECTED_B).txt' 'c`touch INJECTED_C`.txt' INJECTED_*
for form in '"{file}"' "'{file}'"; do
  setup
  printf 'format:\n  cmd: perl -pi -e s/xx/x/g %s && true\n' "$form" >> .claude/temper.config
  printf 'axxb\n' > 'with space.txt'
  python3 -c 'import json, sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$WORKDIR/with space.txt" \
    | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$G_FMT"
  assert_eq "formatter: {file} written as $form takes a name with a space as one argument" "axb" "$(cat 'with space.txt')"
  rm -f 'with space.txt'
done
# The config reader takes off one pair of quotes around a whole value only, so a format.cmd
# that ends in "{file}" keeps its closing quote.
setup
printf 'format:\n  cmd: perl -pi -e s/xx/x/g "{file}"\n' >> .claude/temper.config
printf 'axxb\n' > 'end quote.txt'
python3 -c 'import json, sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$WORKDIR/end quote.txt" \
  | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$G_FMT"
assert_eq "formatter: a format.cmd that ends in \"{file}\" keeps its closing quote and runs" "axb" "$(cat 'end quote.txt')"
rm -f 'end quote.txt'
printf 'k1: "x y"\nk2: a "b"\nk3: \x27q\x27\n' > quoted.cfg
assert_eq "config get takes off one pair of matching quotes around a whole value, and only that" 'x y|a "b"|q' \
  "$(TEMPER_CONFIG=quoted.cfg "$TEMPER" config get k1)|$(TEMPER_CONFIG=quoted.cfg "$TEMPER" config get k2)|$(TEMPER_CONFIG=quoted.cfg "$TEMPER" config get k3)"
rm -f quoted.cfg
# plan_review.py: in the plugin's own repository (the current folder is the plugin folder), an
# output under its .temper folder is allowed; every other place in the plugin folder is not.
PR_OWN="$WORKDIR/pr-own-plugin"
rm -rf "$PR_OWN"
mkdir -p "$PR_OWN/scripts" "$PR_OWN/templates" "$PR_OWN/.temper/specs/probe"
cp "$REPO_ROOT/scripts/plan_review.py" "$PR_OWN/scripts/plan_review.py"
cp "$REPO_ROOT/templates/plan-review.html" "$PR_OWN/templates/plan-review.html"
printf '# Plan: probe\n\n## Tasks\n- one\n' > "$PR_OWN/.temper/specs/probe/plan.md"
echo '{"comments": [{"id": "c1", "type": "general-note", "text": "hi"}]}' > "$PR_OWN/.temper/specs/probe/export.json"
# An installed copy (no .git of its own) is not the plugin's own repository: refused there.
assert_exit "plan_review: in an installed copy, the default output under .temper is refused" 2 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py render .temper/specs/probe"
assert_exit "plan_review: in an installed copy, a merge output under .temper is refused" 2 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py merge --feature probe -o .temper/specs/probe/review-comments.json .temper/specs/probe/export.json"
assert_exit "plan_review: a GIT_DIR naming another repository does not make the installed copy its own repository" 2 \
  bash -c "cd '$PR_OWN' && GIT_DIR='$WORKDIR/.git' python3 scripts/plan_review.py render .temper/specs/probe"
assert_eq "the refused outputs in the installed copy are not written" "no|no" \
  "$([[ -e "$PR_OWN/.temper/specs/probe/review.html" ]] && echo yes || echo no)|$([[ -e "$PR_OWN/.temper/specs/probe/review-comments.json" ]] && echo yes || echo no)"
git init -q "$PR_OWN"
assert_exit "plan_review: in the plugin's own repository, the default output under .temper is written" 0 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py render .temper/specs/probe"
assert_exit "plan_review: in the plugin's own repository, the artifact output under .temper is written" 0 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py render .temper/specs/probe --target artifact -o .temper/review-artifact-probe.html"
assert_exit "plan_review: in the plugin's own repository, a merge output under .temper is written" 0 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py merge --feature probe -o .temper/specs/probe/review-comments.json .temper/specs/probe/export.json"
assert_eq "the three outputs under .temper exist" "yes|yes|yes" \
  "$([[ -f "$PR_OWN/.temper/specs/probe/review.html" ]] && echo yes || echo no)|$([[ -f "$PR_OWN/.temper/review-artifact-probe.html" ]] && echo yes || echo no)|$([[ -f "$PR_OWN/.temper/specs/probe/review-comments.json" ]] && echo yes || echo no)"
assert_exit "plan_review: in the plugin's own repository, an output outside .temper is still refused" 2 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py render .temper/specs/probe -o templates/copy.html"
ln -s "$PR_OWN/templates" "$PR_OWN/.temper/specs/link"
assert_exit "plan_review: a path under .temper that a symlink sends elsewhere in the plugin is refused" 2 \
  bash -c "cd '$PR_OWN' && python3 scripts/plan_review.py render .temper/specs/probe -o .temper/specs/link/x.html"
assert_exit "plan_review: from another folder, an output under the plugin's .temper is refused" 2 \
  python3 "$PR_OWN/scripts/plan_review.py" render "$PR_OWN/.temper/specs/probe" -o "$PR_OWN/.temper/other.html"
assert_eq "the refused outputs write nothing" "no|no|no" \
  "$([[ -e "$PR_OWN/templates/copy.html" ]] && echo yes || echo no)|$([[ -e "$PR_OWN/templates/x.html" ]] && echo yes || echo no)|$([[ -e "$PR_OWN/.temper/other.html" ]] && echo yes || echo no)"
rm -rf "$PR_OWN" "$G_PLUG"
# validate-directory.sh: git grep reads the files; no file is opened by a path the script builds.
assert_eq "validate-directory opens no file by a path it builds from a listed name" "0" \
  "$(grep -c '"\$ROOT/\$rel"' "$REPO_ROOT/scripts/validate-directory.sh")"
# validate-panels.py and validate-docs.sh: an agents or commands file that plugin.json does not list fails.
V_PLUG="$WORKDIR/listing-plugin"
rm -rf "$V_PLUG"
mkdir -p "$V_PLUG/scripts" "$V_PLUG/.claude-plugin" "$V_PLUG/agents" "$V_PLUG/commands" "$V_PLUG/docs" "$V_PLUG/.claude"
cp "$REPO_ROOT/scripts/validate-panels.py" "$REPO_ROOT/scripts/validate-docs.sh" "$V_PLUG/scripts/"
echo '{"name": "x", "agents": ["./agents/a.md"], "commands": ["./commands/temper.md"]}' > "$V_PLUG/.claude-plugin/plugin.json"
printf 'Return exactly ONE closed panel.\n' > "$V_PLUG/agents/a.md"
printf 'temper\n' > "$V_PLUG/commands/temper.md"
printf 'Use /temper and /temper:zz.\n' > "$V_PLUG/docs/commands.md"
git init -q "$V_PLUG"
assert_exit "validate-panels passes when plugin.json lists every brief and command" 0 python3 "$V_PLUG/scripts/validate-panels.py"
printf 'Return exactly ONE closed panel.\n' > "$V_PLUG/agents/zz.md"
printf 'zz\n' > "$V_PLUG/commands/zz.md"
OUT=$(python3 "$V_PLUG/scripts/validate-panels.py" 2>&1; true)
assert_eq "validate-panels names an agents and a commands file that plugin.json does not list" "yes|yes" \
  "$(echo "$OUT" | grep -qx 'FAIL agents/zz.md is not listed in .claude-plugin/plugin.json' && echo yes || echo no)|$(echo "$OUT" | grep -qx 'FAIL commands/zz.md is not listed in .claude-plugin/plugin.json' && echo yes || echo no)"
assert_exit "validate-panels fails on an unlisted file" 1 python3 "$V_PLUG/scripts/validate-panels.py"
OUT=$(bash "$V_PLUG/scripts/validate-docs.sh" 2>&1; true)
assert_eq "validate-docs names a command file that plugin.json does not list" "yes" \
  "$(echo "$OUT" | grep -A1 'command files that .claude-plugin/plugin.json does not list' | grep -q 'commands/zz.md' && echo yes || echo no)"
rm -rf "$V_PLUG"
# The dev scripts clear CDPATH before they cd: with CDPATH naming the plugin folder, cd prints the
# folder it enters and the script's own path would hold it twice.
assert_eq "every dev script clears CDPATH before its first cd" "" \
  "$(python3 -c '
import re, sys
for name in sys.argv[2:]:
    lines = open(sys.argv[1] + "/" + name).read().split("\n")
    unset = next((i for i, l in enumerate(lines) if l.strip() == "unset CDPATH"), None)
    first = next((i for i, l in enumerate(lines) if not l.lstrip().startswith("#") and re.search(r"(^|[(;&|]\s*)cd\s", l)), None)
    if unset is None or (first is not None and first < unset):
        print(name)
' "$REPO_ROOT" scripts/validate-plugin.sh scripts/validate-docs.sh scripts/validate-readme.sh \
    scripts/validate-directory.sh scripts/quality-check.sh scripts/check-known-limits.sh \
    scripts/check-mod-calls.sh scripts/check-original-options.sh scripts/version-bump.sh \
    scripts/selftest/test-validate-directory.sh)"
for vp_script in validate-readme.sh check-known-limits.sh check-original-options.sh; do
  assert_eq "$vp_script prints the same with CDPATH naming the plugin folder" \
    "$(cd "$REPO_ROOT" && env -u CDPATH bash "scripts/$vp_script" 2>&1)" \
    "$(cd "$REPO_ROOT" && CDPATH="$REPO_ROOT" bash "scripts/$vp_script" 2>&1)"
done
