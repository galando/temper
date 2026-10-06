# shellcheck shell=bash
# Part 2 of the temper CLI test suite: config, evidence run, metrics, plans and the plugin folder.
# Sourced in order by test-temper.sh, which sets up the helpers, WORKDIR and the counters;
# not meant to run on its own.

# --- v9: temper config get + evidence run ---
setup
assert_eq "config get reads a nested key" "critical" "$("$TEMPER" config get review.block-on x)"
assert_eq "config get falls back to the default for a missing key" "fallback" "$("$TEMPER" config get no.such.key fallback)"
"$TEMPER" evidence run --stage build --claim "regression test red" --phase red -- false >/dev/null
"$TEMPER" evidence run --stage build --claim "regression test green" --phase green -- true >/dev/null
assert_exit "evidence run returns 0 even when the command fails (the record is the product)" 0 \
  "$TEMPER" evidence run --stage check --claim "failing cmd" -- false
assert_eq "evidence run records the observed exit code" "1" \
  "$(python3 -c "import json; print([e for e in json.load(open('.temper/evidence/build.json')) if e['claim']=='regression test red'][0]['exit_code'])")"
assert_eq "evidence run keeps PROVEN on a nonzero exit (machine-observed, no downgrade)" "PROVEN" \
  "$(python3 -c "import json; print([e for e in json.load(open('.temper/evidence/build.json')) if e['claim']=='regression test red'][0]['label'])")"
echo '- [x] t' > .temper/specs/demo/tasks.md
assert_exit "cli-executed RED+GREEN satisfies the build gate" 0 "$TEMPER" gate build

# --- v9 hooks: protected paths, confirm-override ask tier, formatter, imports stdin ---
setup
PROTECT="$REPO_ROOT/scripts/guards/block-protected-paths.sh"
CONFIRM="$REPO_ROOT/scripts/guards/confirm-override.sh"
FORMATTER="$REPO_ROOT/scripts/guards/run-formatter.sh"
IMPORTS="$REPO_ROOT/scripts/guards/block-forbidden-imports.sh"

assert_exit "protected-paths: no config => edit passes" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/gen/model.ts\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PROTECT'"
cat >> .claude/temper.config <<'EOF'
protect:
  paths: ["**/src/gen/**", "**/v1/**"]
EOF
assert_exit "protected-paths: an edit inside a frozen path is BLOCKED" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/gen/model.ts\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PROTECT'"
assert_exit "protected-paths: an edit elsewhere passes" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/app.ts\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PROTECT'"
assert_exit "protected-paths: garbage stdin fails open" 0 \
  bash -c "echo garbage | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PROTECT'"

# The command names the CLI through the braced plugin root variable, as a command file writes it.
OUT=$(printf '%s\n' '{"tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/temper override review --reason x"}}' | bash "$CONFIRM")
assert_eq "confirm-override: a temper override command emits the ask decision" "yes" \
  "$(echo "$OUT" | grep -q '"permissionDecision": "ask"' && echo yes || echo no)"
OUT=$(echo '{"tool_input": {"command": "git status"}}' | bash "$CONFIRM")
assert_eq "confirm-override: any other command stays silent" "" "$OUT"
assert_exit "confirm-override: always exits 0 (ask is advisory, not a block)" 0 \
  bash -c "echo '{\"tool_input\": {\"command\": \"temper override plan --reason y\"}}' | bash '$CONFIRM'"

echo 'x  =  1' > messy.txt
cat >> .claude/temper.config <<'EOF'
format:
  cmd: "perl -pi -e 's/  +/ /g' {file}"
EOF
assert_exit "formatter: runs the configured command, exits 0" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"$WORKDIR/messy.txt\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$FORMATTER'"
assert_eq "formatter: the file was actually formatted" "x = 1" "$(cat messy.txt)"
assert_exit "formatter: a failing format.cmd never blocks" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"/nonexistent/x\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$FORMATTER'"

echo 'const cp = require("child_process.exec")' > risky.js
assert_exit "imports hook: reads the edited file from hook stdin and blocks a denylisted import" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"$WORKDIR/risky.js\"}}' | TEMPER_FORBIDDEN_IMPORTS='child_process.exec' bash '$IMPORTS'"
assert_exit "imports hook: empty denylist stays a no-op" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"$WORKDIR/risky.js\"}}' | bash '$IMPORTS'"

# --- v9 hardening: adversarial-review fixes (must never regress) ---

# metrics append: the value is parsed by float() INSIDE python (argv), never
# interpolated into source. A crafted payload must NOT execute and must exit 1.
setup
rm -f INJECTED
"$TEMPER" metrics append cov "1');import os;os.system('touch INJECTED')#" >/dev/null 2>&1
assert_eq "metrics append: an injection payload does not execute" "no" "$([[ -f INJECTED ]] && echo yes || echo no)"
assert_exit "metrics append: an injection payload is rejected as non-numeric" 1 \
  "$TEMPER" metrics append cov "1');import os;os.system('touch INJECTED')#"
rm -f INJECTED

# metrics append + bands agree on the friendly alias: `tests` lands in test_count_history,
# which bands' `tests` metric reads — a recorded point must actually be band-able.
setup
rm -f .temper/metrics.json
"$TEMPER" metrics append tests 42 >/dev/null
assert_eq "metrics append tests writes the alias array bands reads (test_count_history)" "yes" \
  "$(python3 -c "import json; d=json.load(open('.temper/metrics.json')); print('yes' if 'test_count_history' in d and 'tests_history' not in d else 'no')")"

# bands never crashes on valid-but-small config — the spine's 'never a crash' contract.
setup
rm -f .temper/metrics.json
for v in 80 81 82 83 84; do "$TEMPER" metrics append coverage $v >/dev/null; done
cat >> .claude/temper.config <<'EOF'
bands:
  window: 0
  metrics: [coverage]
EOF
assert_exit "bands: window 0 does not crash (exit 0/1, never a traceback)" 1 "$TEMPER" bands
setup
rm -f .temper/metrics.json
for v in 80 81 82 83 84; do "$TEMPER" metrics append coverage $v >/dev/null; done
cat >> .claude/temper.config <<'EOF'
bands:
  window: 2.5
  metrics: [coverage]
EOF
assert_exit "bands: a non-integer window does not crash" 1 "$TEMPER" bands
setup
rm -f .temper/metrics.json
"$TEMPER" metrics append coverage 80 >/dev/null
cat >> .claude/temper.config <<'EOF'
bands:
  min-points: 1
  metrics: [coverage]
EOF
assert_exit "bands: min-points 1 with a single point is graceful, not a crash" 0 "$TEMPER" bands

# _glob_touch_match (park-on-touch): proper segment match, not a loose substring.
# Assert on the park-on-touch requirement LINE, not the whole gate verdict (which also
# reflects blast radius + upstream gates). Uses a segment name ('zauth') no other test
# creates, and unique content, so the shared WORKDIR can't mask the diff.
setup
"$TEMPER" state set run_mode autonomous >/dev/null
cat > .claude/temper.config <<'EOF'
stack: auto
autonomy:
  park-on-touch: ["**/zauth/**"]
EOF
mkdir -p src/xzauthy && echo "park-false-$$" > src/xzauthy/client.js
git add -A >/dev/null 2>&1 || true
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "park-on-touch: 'xzauthy' does NOT match the 'zauth' segment (no false park)" "yes" \
  "$(echo "$OUT" | grep -q 'no changed file matches a park-on-touch' && echo yes || echo no)"
setup
"$TEMPER" state set run_mode autonomous >/dev/null
cat > .claude/temper.config <<'EOF'
stack: auto
autonomy:
  park-on-touch: ["**/zauth/**"]
EOF
mkdir -p src/zauth && echo "park-true-$$" > src/zauth/login.js
git add -A >/dev/null 2>&1 || true
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "park-on-touch: the real 'zauth' segment still parks" "yes" \
  "$(echo "$OUT" | grep -q 'src/zauth/login.js matches' && echo yes || echo no)"

# block-protected-paths.sh: segment match (no substring false-positive), interior glob honored.
setup
PP="$REPO_ROOT/scripts/guards/block-protected-paths.sh"
cat >> .claude/temper.config <<'EOF'
protect:
  paths: ["**/gen/**", "**/migrations/*.sql"]
EOF
for f in src/agent/main.py packages/oxygen/index.ts lib/legend.js; do
  assert_exit "protected-paths: '$f' is not blocked by the 'gen' substring" 0 \
    bash -c "echo '{\"tool_input\": {\"file_path\": \"$f\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PP'"
done
assert_exit "protected-paths: a real 'gen' path segment is blocked" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/gen/model.ts\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PP'"
assert_exit "protected-paths: an interior-glob pattern (*.sql) is honored" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"db/migrations/001.sql\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PP'"
assert_exit "protected-paths: a non-.sql file under migrations is not blocked" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"db/migrations/notes.txt\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$PP'"

# install.sh: an existing core.hooksPath (husky, lefthook) names the folder git runs hooks
# from. The installer never writes into it, nor into the .git/hooks folder git then ignores: it
# keeps the hook in .git/temper-gate and leaves core.hooksPath as it was.
setup
git config user.email "test@example.com"
git config user.name "test"
rm -rf .husky
mkdir -p .husky
git config core.hooksPath .husky
H_HOOKS_BEFORE="$(ls -A .git/hooks)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); H_RC=$?
assert_eq "install.sh never writes into a core.hooksPath folder that is not Temper's, and leaves the value as it was" "1||.husky|yes" \
  "$H_RC|$(ls -A .husky)|$(git config --get core.hooksPath)|$(printf '%s\n' "$OUT" | grep -qxF "FAIL: core.hooksPath is set to '.husky', a folder that is not Temper's, and this installer never writes into it." && echo yes || echo no)"
assert_eq "install.sh does not write the ignored .git/hooks either; the hook is kept in .git/temper-gate" "yes|yes" \
  "$([[ "$(ls -A .git/hooks)" == "$H_HOOKS_BEFORE" ]] && echo yes || echo no)|$(grep -q 'installed by scripts/guards/install.sh' .git/temper-gate/pre-commit 2>/dev/null && echo yes || echo no)"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .husky

# confirm-override.sh: robust matcher — quoted path, doubled space, path prefix all ASK.
setup
CO="$REPO_ROOT/scripts/guards/confirm-override.sh"
for cmd in \
  'temper override plan --reason x' \
  '"/abs/scripts/temper" override plan' \
  'temper  override plan' \
  'bash /p/temper override check'; do
  esc=$(printf '%s' "$cmd" | sed 's/"/\\"/g')
  OUT=$(printf '{"tool_input": {"command": "%s"}}' "$esc" | bash "$CO")
  assert_eq "confirm-override asks for: $cmd" "yes" "$(echo "$OUT" | grep -q '\"ask\"' && echo yes || echo no)"
done
OUT=$(echo '{"tool_input": {"command": "git status"}}' | bash "$CO")
assert_eq "confirm-override stays silent on an unrelated command" "" "$OUT"

# ======================================================================
# v9.4: acceptance criteria with stable IDs, draft-intent requirements,
# gherkin fences, cross-repo search, checkpoint feedback, commit carve-outs,
# state-init inheritance fix.
# =============================================================================

# A minimal draft that passes every new intent requirement; each case below
# mutates one thing.
good_draft() {
  cat > .temper/specs/demo/intent.md <<'EOF'
**Author:** A Author <a@example.com>
**Status:** draft
**Created:** 2026-01-01
**Reviewer:** R Reviewer <r@example.com>

## Problem
A real problem with real text.

### Success Criteria
- [ ] AC-01 [required]: criterion one
  Why: serves the real outcome
  Validate: scenario — traced later

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior

### Target Users
- developer: uses the feature → gets a result

### Open Questions

### Decisions

## Source Traceability
### Context Sources
- none: description only — nothing linked
EOF
}

# --- gate intent: the ten draft requirements ---
setup; good_draft
assert_exit "intent draft gate PASSes a complete draft" 0 "$TEMPER" gate intent

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('### Context Sources\n- none: description only — nothing linked', '')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "no Source Traceability FAILs task context recorded" "yes" "$(echo "$OUT" | grep -q 'no consulted/unavailable/none line' && echo yes || echo no)"

setup; good_draft
printf '**Ticket:** PROJ-1\n' | cat - .temper/specs/demo/intent.md > /tmp/ti && mv /tmp/ti .temper/specs/demo/intent.md
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('- none: description only', '- consulted: PROJ-12 notes — background')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a recorded PROJ-12 does not satisfy a linked PROJ-1 (whole-token match)" "yes" \
  "$(echo "$OUT" | grep -q 'PROJ-1' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('  Why: serves the real outcome', '  Why: {placeholder why}')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a placeholder Why: FAILs criteria why" "yes" "$(echo "$OUT" | grep -q 'no Why: line with real text on: AC-01' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('- developer: uses the feature → gets a result', '- developer benefits')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a Target Users bullet with no action chain FAILs" "yes" "$(echo "$OUT" | grep -q 'no action chain' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('- [ ] AC-01 [required]: criterion one', '- [ ] criterion one, no id')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a criterion without AC-NN FAILs criteria ids" "yes" "$(echo "$OUT" | grep -q 'no AC-NN id' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('- [ ] AC-01 [required]: criterion one', '- [ ] AC-01 [required]: criterion one\n- [ ] AC-01 [required]: duplicate id')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a repeated AC id is named as a duplicate" "yes" "$(echo "$OUT" | grep -q 'duplicate id: AC-01' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('AC-01 [required]', 'AC-01')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a criterion with no [required]/[optional] FAILs criteria priority" "yes" \
  "$(echo "$OUT" | grep -q '\[x\] criteria priority' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('  Validate: scenario — traced later', '  Validate: vibe — hope')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "an unknown Validate type FAILs criteria validate" "yes" "$(echo "$OUT" | grep -q 'missing/unknown Validate: type on: AC-01' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('### Open Questions\n', '### Open Questions\n- which color should the button be?\n')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "an unlabeled open question FAILs" "yes" "$(echo "$OUT" | grep -q 'neither blocking nor deferred' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('### Open Questions\n', '### Open Questions\n- Blocking: which database do we use in production; consequence: blocked migration; owner: EM\n')
s = s.replace('### Decisions\n', '### Decisions\n- which database do we use in production -> postgres (EM, 2026-01-01)\n')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "an open question re-asking a decided topic FAILs" "yes" "$(echo "$OUT" | grep -q 'already answered in ### Decisions' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('**Reviewer:** R Reviewer <r@example.com>', '**Reviewer:** {name <email>}')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a placeholder Reviewer FAILs header fields" "yes" "$(echo "$OUT" | grep -q 'missing, empty, or placeholder: Reviewer' && echo yes || echo no)"

setup; good_draft
printf '## Scenarios (BDD)\nScenario: premature\n' >> .temper/specs/demo/intent.md
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a Scenario: line in a draft FAILs no scenarios in draft, naming the line" "yes" \
  "$(echo "$OUT" | grep -q 'no scenarios in draft' && echo "$OUT" | grep -qE 'Scenario: line\(s\) at [0-9]+' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('**Status:** draft', '**Status:** accepted')
s = s.replace('  Why: serves the real outcome', '')   # would FAIL as a draft
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "an accepted intent PASSes even where the draft would FAIL" 0 "$TEMPER" gate intent
assert_eq "each draft-only requirement records a skip detail, never revisited" "13/13" \
  "$(echo "$OUT" | grep -c 'skipped — intent is accepted; this check applies to drafts only')/13"

# --- gate intent: no soft words (should / may / might / possibly) ---
setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('criterion one', 'the export should finish fast')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "a soft word in a criterion FAILs the draft intent gate" 1 "$TEMPER" gate intent
assert_eq "the detail names the criterion and the word" "yes" \
  "$(echo "$OUT" | grep -q 'soft word in: criterion AC-01 uses should' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('criterion one', 'the export Might finish')
s = s.replace('### Target Users', '### Constraints\n- output may differ per run\n- no network (possibly offline)\n\n### Target Users')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "several soft words are named and joined with ' | '" "yes" \
  "$(echo "$OUT" | grep -q 'criterion AC-01 uses might | constraint "output may differ per run" uses may | constraint "no network (possibly offline)" uses possibly' && echo yes || echo no)"

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('criterion one', 'the export should finish (source: PROJ-9)')
s = s.replace('### Target Users', '### Constraints\n- output may differ per run (source: ops guide)\n\n### Target Users')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
assert_exit "a (source: ...) marker exempts the originator's hedge word" 0 "$TEMPER" gate intent

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('criterion one', 'the export should finish')
s = s.replace('**Status:** draft', '**Status:** accepted')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
assert_exit "an accepted intent skips the no-soft-words check" 0 "$TEMPER" gate intent

setup; good_draft
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('criterion one', 'the export finishes in 2 s (mayhem is not a hit; `should` in code is not a hit)')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
assert_exit "a clean criterion (whole words only, code spans ignored) passes" 0 "$TEMPER" gate intent

# templates/example-intent.md must pass the intent gate as-is.
setup
cp "$REPO_ROOT/templates/example-intent.md" .temper/specs/demo/intent.md
assert_exit "templates/example-intent.md passes temper gate intent" 0 "$TEMPER" gate intent

# --- gate plan: gherkin fences + cross-repo search + acceptance links ---
setup
assert_exit "plan gate PASSes with fenced scenarios and valid AC links" 0 "$TEMPER" gate plan

setup
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('```gherkin', '```text')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate plan 2>&1; true)
assert_eq "a non-gherkin fence does not protect a Scenario" "yes" \
  "$(echo "$OUT" | grep -q 'scenarios in gherkin blocks' && echo "$OUT" | grep -q 'not inside a gherkin fence' && echo yes || echo no)"

setup
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read()
# drop the fences entirely, keep the Scenario lines
import re
s = re.sub(r'^```.*$', '', s, flags=re.M)
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$("$TEMPER" gate plan 2>&1; true)
assert_eq "bare Scenario: lines FAIL scenarios in gherkin blocks" "yes" \
  "$(echo "$OUT" | grep -q 'Scenario: not inside a gherkin fence' && echo yes || echo no)"

setup
cat > .temper/specs/demo/plan.md <<'EOF'
## Blast Radius
- none

## Cross-Repo Search
- used: sourcegraph — callers of demo() → 3 hits in sister repo
EOF
"$TEMPER" state set complexity medium >/dev/null
assert_exit "plan gate PASSes with a recorded cross-repo search" 0 "$TEMPER" gate plan

setup
cat > .temper/specs/demo/plan.md <<'EOF'
## Blast Radius
- none
EOF
OUT=$("$TEMPER" gate plan 2>&1; true)
assert_eq "a plan.md with no Cross-Repo Search section FAILs" "yes" \
  "$(echo "$OUT" | grep -q 'cross-repo search recorded' && echo "$OUT" | grep -q 'no heading matching' && echo yes || echo no)"

setup
printf '## Cross-Repo Search\n- used: {tool} — {query}\n' > .temper/specs/demo/plan.md
OUT=$("$TEMPER" gate plan 2>&1; true)
assert_eq "a placeholder used: line does not count as a record" "yes" \
  "$(echo "$OUT" | grep -q 'no .*used.* line with real text' && echo yes || echo no)"

# --- acceptance.py: internal links (plan) and supported evidence (check) ---
setup
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('Covers: AC-01', 'Covers: AC-99')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" plan .temper/specs/demo/intent.md .temper/evidence/plan.json 2>&1; true)
assert_eq "acceptance.py rejects a Covers reference to an unknown criterion" "yes" \
  "$(echo "$OUT" | grep -q 'unknown criterion AC-99' && echo yes || echo no)"

setup
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').replace('**Author:', '**Author:') if False else open('.temper/specs/demo/intent.md').read()
s = s.replace('[required]: demo criterion one', '[required]: demo criterion one\n  Deferred: not now')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" plan .temper/specs/demo/intent.md .temper/evidence/plan.json 2>&1; true)
assert_eq "a Deferred line on a required criterion is an error" "yes" \
  "$(echo "$OUT" | grep -q 'required criteria can never be deferred' && echo yes || echo no)"

setup
python3 - <<'EOF'
s = open('.temper/specs/demo/intent.md').read().replace('Covers: AC-02', 'Covers: AC-01')
open('.temper/specs/demo/intent.md','w').write(s)
EOF
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" plan .temper/specs/demo/intent.md .temper/evidence/plan.json 2>&1; true)
assert_eq "a Validate: scenario criterion with no covering scenario is an error" "yes" \
  "$(echo "$OUT" | grep -q 'no scenario Covers: it' && echo yes || echo no)"

setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 --cmd pytest >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null   # no cmd, no artifact -> unsupported
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" check .temper/specs/demo/intent.md .temper/evidence/check.json 2>&1; true)
assert_eq "an exit-0 row with no cmd and no artifact is NOT a supported pass" "yes" \
  "$(echo "$OUT" | grep -q "scenario 'first' has no supported passing evidence" && echo yes || echo no)"

setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 --cmd pytest >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
echo proof > .temper/specs/demo/artifact.txt
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --artifact .temper/specs/demo/artifact.txt >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
"$TEMPER" evidence add --stage check --criterion AC-01 --claim "criterion AC-01" --exit 0 --cmd "manual check" >/dev/null
"$TEMPER" evidence add --stage check --criterion AC-02 --claim "criterion AC-02" --exit 0 --cmd "manual check" >/dev/null
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" check .temper/specs/demo/intent.md .temper/evidence/check.json 2>&1; true)
assert_eq "artifact-sha and cmd rows are supported passes" "every criterion has explicit validation links" "$OUT"
echo tampered > .temper/specs/demo/artifact.txt
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" check .temper/specs/demo/intent.md .temper/evidence/check.json 2>&1; true)
assert_eq "a changed artifact no longer supports its recorded sha" "yes" \
  "$(echo "$OUT" | grep -q "scenario 'first' has no supported passing evidence" && echo yes || echo no)"
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second re-run" --exit 1 --cmd "pytest -k second" >/dev/null
OUT=$(python3 "$REPO_ROOT/scripts/acceptance.py" check .temper/specs/demo/intent.md .temper/evidence/check.json 2>&1; true)
assert_eq "the LATEST row wins — a newer failure is never hidden by an older pass" "yes" \
  "$(echo "$OUT" | grep -q "scenario 'second' has no supported passing evidence" && echo yes || echo no)"

# --criterion is recorded on both evidence add and evidence run rows.
setup
"$TEMPER" evidence add --stage check --criterion AC-01 --claim "c" --exit 0 --cmd x >/dev/null
"$TEMPER" evidence run --stage check --criterion AC-02 --claim "c2" -- true >/dev/null
assert_eq "evidence add/run record the criterion field" "AC-01|AC-02" \
  "$(python3 -c "import json; e=json.load(open('.temper/evidence/check.json')); print(e[0]['criterion'] + '|' + e[1]['criterion'])")"

# --- gate review: completion row + named findings ---
setup
OUT=$("$TEMPER" gate review 2>&1; true)
assert_eq "an empty findings ledger is not a review" "yes" \
  "$(echo "$OUT" | grep -q 'no review completion evidence' && echo yes || echo no)"
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" evidence add --stage review --claim "sql injection in login" --severity critical >/dev/null
OUT=$("$TEMPER" gate review 2>&1; true)
assert_eq "the FAIL detail names each open blocking finding" "yes" \
  "$(echo "$OUT" | grep -q 'sql injection in login' && echo yes || echo no)"
"$TEMPER" evidence add --stage review --claim "review completed" --exit 1 --cmd "review panel" >/dev/null
assert_exit "a latest nonzero completion row FAILs the gate" 1 "$TEMPER" gate review

# --- gate build: checkpoint feedback answered ---
setup
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
assert_exit "no feedback rows => requirement skipped" 0 "$TEMPER" gate build
"$TEMPER" evidence add --stage build --phase feedback --claim "feedback #1: use the builder pattern" >/dev/null
assert_exit "an unanswered feedback row FAILs the build gate" 1 "$TEMPER" gate build
"$TEMPER" evidence add --stage build --phase feedback-resolved --claim "feedback #1: applied — switched to builder" >/dev/null
assert_exit "feedback applied (with detail) answers the gate" 0 "$TEMPER" gate build
"$TEMPER" evidence add --stage build --phase feedback --claim "feedback #2: rename the helper" >/dev/null
"$TEMPER" evidence add --stage build --phase feedback-resolved --claim "feedback #2: declined" >/dev/null
OUT=$("$TEMPER" gate build 2>&1; true)
assert_eq "a decline with no reason is not an answer" "yes" \
  "$(echo "$OUT" | grep -q 'feedback #2 (declined with no reason)' && echo yes || echo no)"

# --- gate commit: no active run degrades open ---
setup
rm -f .temper/build-state.json
echo 'x' > plain.txt
git add plain.txt >/dev/null 2>&1
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_exit "a commit outside any run passes with the single 'active run' requirement" 0 "$TEMPER" gate commit
assert_eq "the carve-out names itself" "yes" "$(echo "$OUT" | grep -q 'active run' && echo "$OUT" | grep -q 'no active run — nothing to gate' && echo yes || echo no)"

# --- gate commit: build-checkpoint carve-out ---
setup
"$TEMPER" state set branch "$(git rev-parse --abbrev-ref HEAD)" >/dev/null
"$TEMPER" state set next_stage build >/dev/null
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests green task 1" --phase green --exit 0 --cmd pytest >/dev/null
echo 'code' > src.js
git add src.js >/dev/null 2>&1
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_exit "a GREEN checkpoint commit passes on the one carve-out requirement" 0 "$TEMPER" gate commit
assert_eq "the checkpoint carve-out names the green run" "yes" \
  "$(echo "$OUT" | grep -q 'build checkpoint commit' && echo "$OUT" | grep -q 'tests green task 1' && echo yes || echo no)"

setup
"$TEMPER" state set branch "$(git rev-parse --abbrev-ref HEAD)" >/dev/null
"$TEMPER" state set next_stage build >/dev/null
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests green then regress" --phase green --exit 0 --cmd pytest >/dev/null
"$TEMPER" evidence add --stage build --claim "tests green then regress" --phase green --exit 1 --cmd pytest >/dev/null
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_exit "a RED latest test run fails the checkpoint commit, naming the claim" 1 "$TEMPER" gate commit
assert_eq "the RED carve-out names the failing claim" "yes" "$(echo "$OUT" | grep -q 'tests green then regress' && echo yes || echo no)"

setup
"$TEMPER" state set branch "$(git rev-parse --abbrev-ref HEAD)" >/dev/null
"$TEMPER" state set next_stage build >/dev/null
# no plan verdict -> upstream not satisfied -> full gate applies -> FAIL (build gate never ran)
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_exit "upstream gates unmet => full commit gate applies" 1 "$TEMPER" gate commit
assert_eq "no checkpoint carve-out row when upstream is unmet" "no" \
  "$(echo "$OUT" | grep -q 'build checkpoint commit' && echo yes || echo no)"

setup
"$TEMPER" state set branch "$(git rev-parse --abbrev-ref HEAD)" >/dev/null
"$TEMPER" state set next_stage review >/dev/null   # past build => no carve-out
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests green" --phase green --exit 0 --cmd pytest >/dev/null
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_eq "next_stage != build => the final completion commit faces every gate" "no" \
  "$(echo "$OUT" | grep -q 'build checkpoint commit' && echo yes || echo no)"

# --- state init: never inherit the previous run's verdicts or overrides ---
setup
"$TEMPER" override review --reason "old run" >/dev/null
"$TEMPER" gate intent >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 --cmd pytest >/dev/null
"$TEMPER" state init demo2 --command temper >/dev/null
assert_eq "state init clears inherited overrides" "[]" "$(cat .temper/overrides.json | tr -d '[:space:]')"
assert_eq "state init clears inherited gate verdicts" "{}" "$(cat .temper/gates.json | tr -d '[:space:]')"
assert_eq "state init clears inherited evidence" "0" "$(python3 -c 'import json,os; print(len(json.load(open(".temper/evidence/check.json"))) if os.path.exists(".temper/evidence/check.json") else 0)')"
assert_eq "state init archives the prior run's ledger" "yes" "$([[ -f .temper/specs/demo/gate-ledger.json ]] && echo yes || echo no)"

setup
rm -f .temper/build-state.json      # no prior run — but an override carries an approver
"$TEMPER" override review --reason "keep the audit fact" >/dev/null
"$TEMPER" state init fresh --command temper >/dev/null
assert_eq "a pre-init override is archived, not deleted" "yes" \
  "$(ls .temper/archive/pre-init-*-overrides.json >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "the archived pre-init override keeps the reason" "keep the audit fact" \
  "$(python3 -c "import json,glob; print(json.load(open(glob.glob('.temper/archive/pre-init-*-overrides.json')[0]))[0]['reason'])")"
assert_eq "the live overrides file is reset" "[]" "$(cat .temper/overrides.json | tr -d '[:space:]')"

# --- autonomous blast radius uses base_sha (checkpoint commits already landed) ---
setup
git config user.email "t@e.com"; git config user.name t
git add -A >/dev/null 2>&1
git commit --no-verify -q -m "suite baseline for base_sha" >/dev/null 2>&1 || true
"$TEMPER" state init demo --command temper >/dev/null   # fresh state on the committed tree
"$TEMPER" state set run_mode autonomous >/dev/null
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null
mkdir -p src && echo a > src/a.js
OUT=$("$TEMPER" gate commit 2>&1; true)
assert_eq "base_sha diff + uncommitted paths feed the blast-radius count" "yes" \
  "$(echo "$OUT" | grep -qE 'blast radius — [0-9]+ file' && echo "$OUT" | grep -qE 'blast radius' && echo yes || echo no)"

# --- mods: check.commands.* and fix.max-loops config keys ---
setup
assert_eq "config get fix.max-loops defaults to 3 when the key is absent" "3" "$("$TEMPER" config get fix.max-loops)"
assert_eq "config get check.commands.test prints nothing when absent" "" "$("$TEMPER" config get check.commands.test)"
cat >> .claude/temper.config <<'CFG'
fix:
  max-loops: 4
CFG
assert_eq "config get fix.max-loops reads the configured value" "4" "$("$TEMPER" config get fix.max-loops)"
setup
printf 'check:\n  commands:\n    test: "npm test"\n    lint: npm run lint\n    typecheck: tsc --noEmit\nfix:\n  max-loops: 3\n' >> .claude/temper.config
assert_eq "config get check.commands.test prints the configured command" "npm test" "$("$TEMPER" config get check.commands.test)"
assert_eq "config get check.commands.lint prints an unquoted command" "npm run lint" "$("$TEMPER" config get check.commands.lint)"
assert_eq "config get check.commands.typecheck prints the configured command" "tsc --noEmit" "$("$TEMPER" config get check.commands.typecheck)"
assert_eq "config get fix.max-loops prints 3 when set to 3" "3" "$("$TEMPER" config get fix.max-loops)"
# fix.max-loops bounds the check->fix pair only when set; loops.max-per-type stays 2 elsewhere.
"$TEMPER" state init demo --command fix >/dev/null
assert_exit "state loop check fix iteration 1 passes under fix.max-loops 3" 0 "$TEMPER" state loop check fix --reason a
assert_exit "state loop check fix iteration 2 passes under fix.max-loops 3" 0 "$TEMPER" state loop check fix --reason b
assert_exit "state loop check fix iteration 3 passes under fix.max-loops 3" 0 "$TEMPER" state loop check fix --reason c
assert_exit "state loop check fix iteration 4 is blocked by fix.max-loops 3" 1 "$TEMPER" state loop check fix --reason d
assert_exit "state loop review build still stops at loops.max-per-type 2 (key unset for that pair)" 0 "$TEMPER" state loop review build --reason a
assert_exit "state loop review build second iteration passes" 0 "$TEMPER" state loop review build --reason b
assert_exit "state loop review build third iteration is blocked" 1 "$TEMPER" state loop review build --reason c
setup
"$TEMPER" state init demo --command fix >/dev/null
"$TEMPER" state loop check fix --reason a >/dev/null; "$TEMPER" state loop check fix --reason b >/dev/null
assert_exit "with fix.max-loops unset, check fix keeps loops.max-per-type 2" 1 "$TEMPER" state loop check fix --reason c

# --- mods: evidence accept stops the review gate counting a finding (with a reason) ---
setup
git config user.email "acc@example.com"; git config user.name "Acc Person"
"$TEMPER" evidence add --stage review --claim "weak hash" --severity critical >/dev/null
"$TEMPER" evidence add --stage review --claim "long method" --severity high >/dev/null
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
assert_exit "evidence accept needs --stage, --id and --reason" 1 "$TEMPER" evidence accept --stage review --id 1
assert_exit "evidence accept with an empty --reason exits 1" 1 "$TEMPER" evidence accept --stage review --id 1 --reason ""
assert_eq "an empty --reason writes nothing" "no" "$("$TEMPER" evidence list --stage review --json | grep '"accepted"' >/dev/null && echo yes || echo no)"
assert_exit "evidence accept rejects an unknown id" 1 "$TEMPER" evidence accept --stage review --id 9 --reason "x"
assert_exit "evidence accept rejects an unknown stage" 1 "$TEMPER" evidence accept --stage nope --id 1 --reason "x"
assert_exit "review gate FAILs while the critical finding is open" 1 "$TEMPER" gate review
assert_exit "evidence accept records the finding with a reason" 0 "$TEMPER" evidence accept --stage review --id 1 --reason "legacy hash, tracked in TICKET-9"
assert_exit "evidence accept refuses the same finding twice" 1 "$TEMPER" evidence accept --stage review --id 1 --reason "again"
assert_eq "accepted row stores reason, author and ts" "legacy hash, tracked in TICKET-9|Acc Person <acc@example.com>|yes" \
  "$("$TEMPER" evidence list --stage review --json | python3 -c 'import json,sys; a=json.load(sys.stdin)[0]["accepted"]; print("%s|%s|%s" % (a["reason"], a["author"], "yes" if a.get("ts") else "no"))')"
assert_eq "the accepted row is still in the ledger" "3" "$("$TEMPER" evidence list --stage review --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
assert_eq "evidence list shows [accepted: reason]" "yes" "$("$TEMPER" evidence list --stage review | grep '#1 .*\[accepted: legacy hash, tracked in TICKET-9\]' >/dev/null && echo yes || echo no)"
assert_exit "review gate PASSes once the only blocking finding is accepted" 0 "$TEMPER" gate review
assert_eq "the gate detail names the accepted count" "yes" "$("$TEMPER" gate review | grep '1 accepted' >/dev/null && echo yes || echo no)"
assert_exit "evidence resolve refuses an already accepted finding" 1 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by abc
assert_exit "evidence accept refuses an already resolved finding" 1 bash -c "'$TEMPER' evidence resolve --stage review --id 2 --fixed-by abc >/dev/null && '$TEMPER' evidence accept --stage review --id 2 --reason r"

# --- mods: gate intent requires an out-of-scope line and resolved questions ---
scope_fixture() { # scope_fixture <status> <out-of-scope-bullet-or-empty> <open-questions-body>
  good_draft
  python3 - "$1" "$2" "$3" <<'PYX'
import sys
status, oos, oq = sys.argv[1:4]
p = '.temper/specs/demo/intent.md'
s = open(p).read().replace('**Status:** draft', '**Status:** ' + status)
s = s.replace('### Scope and Non-goals\n- In scope: the demo\n- Out of scope: production behavior\n\n', '')
scope = '### Scope and Non-goals\n- In scope: the demo\n' + (('- Out of scope: ' + oos + '\n') if oos else '') + '\n'
s = s.replace('### Open Questions\n', scope + '### Open Questions\n' + oq + '\n', 1)
open(p, 'w').write(s)
PYX
}
setup; scope_fixture draft "billing changes" ""
assert_exit "a draft with an Out of scope line and no questions PASSes" 0 "$TEMPER" gate intent
setup; scope_fixture draft "" ""
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "a draft without an Out of scope line FAILs" 1 "$TEMPER" gate intent
assert_eq "the FAIL names out of scope stated" "yes" "$(echo "$OUT" | grep -q 'out of scope stated' && echo yes || echo no)"
setup; scope_fixture draft "{what it explicitly does not touch}" ""
assert_exit "a placeholder Out of scope line does not count in a draft" 1 "$TEMPER" gate intent
status_fixture() { # status_fixture <Status value or "none">: a good draft with the Status header replaced or removed
  good_draft
  python3 - "$1" <<'PYX'
import sys, re
p = '.temper/specs/demo/intent.md'
s = open(p).read()
if sys.argv[1] == 'none':
    s = re.sub(r'^\*\*Status:\*\*.*\n', '', s, flags=re.M)
else:
    s = re.sub(r'^\*\*Status:\*\*.*$', '**Status:** ' + sys.argv[1], s, flags=re.M)
s = s.replace('- Out of scope: production behavior\n', '')
open(p, 'w').write(s)
PYX
}
setup; status_fixture "planning"
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "an unknown Status skips out of scope with a note" "yes" "$(echo "$OUT" | grep -q 'out of scope stated .*no recognized Status header' && echo yes || echo no)"
assert_eq "an unknown Status does not fail out of scope stated" "no" "$(echo "$OUT" | grep -q '\[x\] out of scope stated' && echo yes || echo no)"
setup; status_fixture "none"
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a missing Status skips out of scope and open questions with a note" "2" \
  "$(echo "$OUT" | grep -E 'out of scope stated|open questions resolved' | grep -c 'no recognized Status header (draft, accepted or completed)')"
assert_exit "a missing Status still FAILs the gate through the status header requirement" 1 "$TEMPER" gate intent
setup; status_fixture "draft"
assert_exit "an explicit draft without Out of scope still FAILs" 1 "$TEMPER" gate intent

setup; scope_fixture accepted "" "- none"
assert_exit "an accepted intent without an Out of scope line PASSes (acceptance is never revisited)" 0 "$TEMPER" gate intent
setup; scope_fixture completed "" "- none"
assert_exit "a completed intent without an Out of scope line PASSes" 0 "$TEMPER" gate intent
setup; scope_fixture draft "billing" "- Blocking: which provider?; consequence: schema; owner: PM."
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "a draft may hold a Blocking question and still PASS" 0 "$TEMPER" gate intent
assert_eq "the gate names the Blocking question still open on the draft" "yes" "$(echo "$OUT" | grep -q 'Blocking question(s) still open on the draft' && echo yes || echo no)"
setup; scope_fixture accepted "billing" "- Blocking: which provider?; consequence: schema; owner: PM."
assert_exit "an accepted intent with a Blocking question PASSes (not revisited)" 0 "$TEMPER" gate intent
setup; scope_fixture completed "billing" "- Blocking: which provider?; consequence: schema; owner: PM."
assert_exit "a completed intent with a Blocking question PASSes" 0 "$TEMPER" gate intent
setup; scope_fixture draft "billing" "- Deferred: rename later; consequence: none; why work can proceed: cosmetic; needed by: v2."
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "a draft with only a Deferred question reports no Blocking question" "yes" "$(echo "$OUT" | grep -q 'no Blocking question remains' && echo yes || echo no)"

assert_eq "the CLI header lists temper status exactly once" "1" "$(grep -c '^#   temper status' "$TEMPER")"

# --- mods: the stage names the mod puts in its follow up prompts are the CLI's own ---
# The CLI's stage order is pinned here, and the mod's CLI test pins its CLI_STAGES and its fake
# engine's CLI_SEQ to the same text, so a change on either side fails a test. No script here reads a
# file of the mod.
MOD_STAGE_SEQ="intent plan design build review check"
assert_eq "STAGE_SEQ_TEMPER is the stage order the mod expects" "$MOD_STAGE_SEQ" \
  "$(sed -n 's/^STAGE_SEQ_TEMPER="\(.*\)"$/\1/p' "$TEMPER")"
setup
"$TEMPER" state init demo --command temper >/dev/null
assert_exit "the mod's approve intent command is accepted by the CLI" 0 "$TEMPER" state advance intent_complete plan
assert_exit "the mod's approve plan command (design first) is accepted by the CLI" 0 bash -c "'$TEMPER' state advance plan_complete design && '$TEMPER' state advance design_complete build"
assert_exit "the mod's later advances are accepted by the CLI" 0 bash -c "'$TEMPER' state advance build_complete review && '$TEMPER' state advance review_complete check && '$TEMPER' state advance check_complete commit"
assert_exit "the mod's back command is accepted by the CLI" 0 "$TEMPER" state set next_stage plan
assert_exit "the old form 'state advance intent plan' is refused by the CLI" 1 "$TEMPER" state advance intent plan

# --- mods: per-criterion status.json written after each gate; temper status --json ---
setup
"$TEMPER" evidence add --stage check --claim "AC-01 shown" --criterion AC-01 --cmd "echo ok" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null 2>&1 || true
assert_eq "gate writes .temper/status.json" "yes" "$([[ -f .temper/status.json ]] && echo yes || echo no)"
assert_eq "status.json: AC-01 passed, AC-02 open" "AC-01:required:passed|AC-02:required:open" \
  "$(python3 -c 'import json; d=json.load(open(".temper/status.json")); print("|".join("%s:%s:%s" % (c["id"], c["priority"], c["status"]) for c in d["criteria"]))')"
assert_eq "status.json: the passed criterion carries its evidence reference, the open one none" "1|0" \
  "$(python3 -c 'import json; d=json.load(open(".temper/status.json")); print("|".join(str(len(c["evidence"])) for c in d["criteria"]))')"
assert_eq "status.json carries a ts" "yes" "$(python3 -c 'import json; print("yes" if json.load(open(".temper/status.json")).get("ts") else "no")')"
OUT_JSON="$("$TEMPER" status --json)"
assert_exit "temper status --json exits 0" 0 "$TEMPER" status --json
assert_eq "temper status --json prints the same criteria as the file" "$(python3 -c 'import json; print(json.dumps(json.load(open(".temper/status.json"))["criteria"], sort_keys=True))')" \
  "$(echo "$OUT_JSON" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["criteria"], sort_keys=True))')"
# A scenario with a supported passing row passes every criterion it Covers.
setup
"$TEMPER" evidence add --stage build --claim "first passes" --scenario first --cmd "echo ok" --exit 0 >/dev/null
"$TEMPER" evidence add --stage build --claim "second passes" --scenario second --cmd "echo ok" --exit 0 >/dev/null
"$TEMPER" evidence add --stage build --claim "second regressed" --scenario second --cmd "echo ok" --exit 1 >/dev/null
"$TEMPER" gate build >/dev/null 2>&1 || true
assert_eq "scenario evidence: first covers AC-01 (passed), a later failing row leaves AC-02 open" "passed|open" \
  "$(python3 -c 'import json; d=json.load(open(".temper/status.json")); print("|".join(c["status"] for c in d["criteria"]))')"
# Fail open: an unwritable status.json never changes the verdict.
setup
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
mkdir -p .temper/status.json
assert_exit "an unwritable status.json does not change a PASS verdict" 0 "$TEMPER" gate review
rmdir .temper/status.json
# No intent.md: nothing to report, no file.
setup
rm -f .temper/specs/demo/intent.md .temper/status.json
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null 2>&1
assert_eq "no intent.md means no status.json" "no" "$([[ -f .temper/status.json ]] && echo yes || echo no)"
assert_exit "temper status --json without intent.md exits 1" 1 "$TEMPER" status --json
assert_exit "acceptance.py status needs its arguments" 2 python3 "$REPO_ROOT/scripts/acceptance.py" status

# --- the mirror commands of the Temper mod (its CLI helper) run and move the state as claimed ---
# Every command string the mod can name in a follow up prompt, in the order of the real stage sequence
# (STAGE_SEQ_TEMPER): the bar and the CLI must move together, so each one has to succeed and set next_stage.
setup
"$TEMPER" state init demo --command temper >/dev/null
mirror_step() { # mirror_step <name> <expected next_stage> <temper args...>
  local name="$1" want="$2"; shift 2
  assert_exit "mirror: $name" 0 "$TEMPER" "$@"
  assert_eq "mirror: $name sets next_stage" "$want" "$("$TEMPER" state get next_stage 2>/dev/null)"
}
mirror_step "intent_complete plan" plan state advance intent_complete plan
mirror_step "plan_complete build (simple run)" build state advance plan_complete build
mirror_step "build_complete review" review state advance build_complete review
mirror_step "review_complete check" check state advance review_complete check
mirror_step "check_complete commit" commit state advance check_complete commit
# A medium or complex run goes through design.
"$TEMPER" state advance intent_complete plan >/dev/null
mirror_step "plan_complete design" design state advance plan_complete design
mirror_step "design_complete build" build state advance design_complete build
# A step back: the CLI resumes from the stage it is pointed at.
for s in intent plan build review check; do
  mirror_step "state set next_stage $s" "$s" state set next_stage "$s"
done
assert_eq "mirror: stage is recorded by state advance" "build_complete" "$("$TEMPER" state advance build_complete review >/dev/null; "$TEMPER" state get stage)"
assert_exit "mirror: override <stage> --reason" 0 "$TEMPER" override review --reason "reviewer is on leave"
"$TEMPER" evidence add --stage review --claim "a finding" --severity low >/dev/null
assert_exit "mirror: evidence accept --stage review --id 1 --reason" 0 "$TEMPER" evidence accept --stage review --id 1 --reason "false positive"
# The mod and its fake CLI keep the same stage sequence as the real one (pinned above and in the
# mod's CLI test).
# A name that is not a stage is refused: a forged next stage cannot be recorded this way.
assert_exit "mirror: an unknown stage is refused" 1 "$TEMPER" state advance banana_complete review
# The same commands as the mod prints them: a single quoted reason with quotes escaped.
assert_exit "mirror: a reason with quotes and spaces" 0 bash -c "'$TEMPER' override check --reason 'it'\\''s fine; \$(not run)'"
# --- plan_review.py: deterministic HTML plan review (render + merge) ---
PR="$REPO_ROOT/scripts/plan_review.py"
PRD="$WORKDIR/pr/demo-feature"; mkdir -p "$PRD"
cat > "$PRD/plan.md" <<'EOF'
# Plan: Password reset

Intro with {{FEATURE_NAME}} text and a </script><b>tag</b>.

## Architecture

```markdown
## not a real section
```

## Blast Radius

- a.js callers: 3
EOF
cat > "$PRD/tasks.md" <<'EOF'
# Tasks

## Task 1: Reset endpoint
- [ ] write the test
EOF
assert_exit "plan_review render succeeds" 0 python3 "$PR" render "$PRD" -o "$PRD/review.html"
SECS=$(python3 - "$PRD/review.html" <<'EOF'
import json, re, sys
d = open(sys.argv[1]).read()
secs = json.loads(re.search(r"const SECTIONS = (.*?);\n\n//", d, re.S).group(1))
print(len(secs), "|".join(s["source"] + ":" + s["title"] for s in secs))
EOF
)
assert_eq "render splits plan.md then tasks.md at ## headings, ignoring fenced ones" \
  "4 plan.md:Plan: Password reset|plan.md:Architecture|plan.md:Blast Radius|tasks.md:Task 1: Reset endpoint" "$SECS"
assert_eq "render JSON-escapes </script> from plan text (only the real closing tag remains)" "1" \
  "$(grep -o '</script>' "$PRD/review.html" | wc -l | tr -d ' ')"
assert_eq "render does not re-expand a placeholder that appears inside the plan" "yes" \
  "$(grep -q '{{FEATURE_NAME}} text' "$PRD/review.html" && echo yes || echo no)"
assert_eq "render titles the page from the plan heading" "yes" \
  "$(grep -q '<title>Password reset plan review</title>' "$PRD/review.html" && echo yes || echo no)"
python3 "$PR" render "$PRD" --target artifact -o "$PRD/review-artifact.html" >/dev/null
assert_eq "artifact target drops the document wrapper but keeps title, style and script" "yes" \
  "$(python3 - "$PRD/review-artifact.html" <<'EOF'
import re, sys
a = open(sys.argv[1]).read()
bad = [t for t in (r"<!doctype", r"<html[\s>]", r"<head[\s>]", r"</head>", r"<body[\s>]", r"</body>", r"</html>") if re.search(t, a, re.I)]
print("yes" if not bad and "<title>" in a and "<style>" in a and "<script>" in a else "no")
EOF
)"
assert_exit "render rejects a missing spec directory" 2 python3 "$PR" render "$WORKDIR/pr/nope"
mkdir -p "$WORKDIR/pr/empty"
assert_exit "render rejects a spec directory with no plan or tasks" 2 python3 "$PR" render "$WORKDIR/pr/empty"

cat > "$WORKDIR/pr/db-dump.json" <<'EOF'
{"comments": [
  {"id": "c2", "target": "section-1", "target_title": "Architecture", "type": "plan-change", "text": "split it", "author": "Eli", "timestamp": "2026-01-02T00:00:00Z"},
  {"id": "c1", "target": "section-0", "target_title": "Plan: Password reset", "type": "weird", "text": "odd type", "timestamp": "2026-01-01T00:00:00Z"},
  {"id": "c3", "target_title": "Blast Radius", "type": "general-note", "text": "   ", "timestamp": "2026-01-03T00:00:00Z"}
 ],
 "done": [{"author": "Eli", "completed_at": "2026-01-04T00:00:00Z"}]}
EOF
cat > "$WORKDIR/pr/export.json" <<'EOF'
{"version": 1, "feature": "demo-feature", "comments": [
  {"id": "c2", "target": "Architecture", "type": "plan-change", "text": "split it", "timestamp": "2026-01-02T00:00:00Z"},
  {"id": "c4", "target": "Task 1: Reset endpoint", "type": "task-change", "text": "add a test", "timestamp": "2026-01-05T00:00:00Z"}
 ], "review_completed": false, "completed_at": null}
EOF
python3 "$PR" merge --feature demo-feature -o "$WORKDIR/pr/merged.json" "$WORKDIR/pr/db-dump.json" "$WORKDIR/pr/export.json" >/dev/null
assert_eq "merge de-duplicates by id, drops empty text, coerces unknown types, sorts by time" \
  "c1:general-note:Plan: Password reset|c2:plan-change:Architecture|c4:task-change:Task 1: Reset endpoint" \
  "$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('|'.join(c['id'] + ':' + c['type'] + ':' + c['target'] for c in d['comments']))" "$WORKDIR/pr/merged.json")"
assert_eq "merge reads completion and reviewer names from the done collection" "True|2026-01-04T00:00:00Z|Eli" \
  "$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(str(d['review_completed']) + '|' + str(d['completed_at']) + '|' + ','.join(d['reviewers_done']))" "$WORKDIR/pr/merged.json")"
python3 "$PR" merge --feature demo-feature "$WORKDIR/pr/export.json" > "$WORKDIR/pr/merged-one.json"
assert_eq "merge leaves review_completed false when nobody marked done" "False" \
  "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['review_completed'])" "$WORKDIR/pr/merged-one.json")"
echo '{not json' > "$WORKDIR/pr/bad.json"
assert_exit "merge rejects invalid JSON" 2 python3 "$PR" merge --feature demo-feature "$WORKDIR/pr/bad.json"
assert_exit "merge rejects a missing file" 2 python3 "$PR" merge --feature demo-feature "$WORKDIR/pr/nope.json"

# plan_review.py writes only a file of its own kind, and never inside the plugin's own folder.
assert_exit "render refuses an output name that does not end in .html" 2 python3 "$PR" render "$PRD" -o "$PRD/review.txt"
assert_eq "the refused render writes nothing" "no" "$([[ -e "$PRD/review.txt" ]] && echo yes || echo no)"
assert_exit "render refuses an output inside the plugin's own folder" 2 \
  python3 "$PR" render "$PRD" -o "$REPO_ROOT/no-such-folder/review.html"
assert_exit "merge refuses an output name that does not end in .json" 2 \
  python3 "$PR" merge --feature demo-feature -o "$WORKDIR/pr/merged.txt" "$WORKDIR/pr/export.json"
assert_eq "the refused merge writes nothing" "no" "$([[ -e "$WORKDIR/pr/merged.txt" ]] && echo yes || echo no)"
assert_exit "merge refuses an output inside the plugin's own folder" 2 \
  python3 "$PR" merge --feature demo-feature -o "$REPO_ROOT/no-such-folder/review-comments.json" "$WORKDIR/pr/export.json"
assert_exit "merge still prints to stdout with -o -" 0 python3 "$PR" merge --feature demo-feature -o - "$WORKDIR/pr/export.json"
# A copy in a throwaway plugin folder finds that folder by the literal suffix of its own path and
# refuses it too, including the default output of a spec folder that lies inside it.
PR_PLUG="$WORKDIR/pr-plugin"
mkdir -p "$PR_PLUG/scripts" "$PR_PLUG/templates" "$PR_PLUG/specs/x"
cp "$PR" "$PR_PLUG/scripts/plan_review.py"
cp "$REPO_ROOT/templates/plan-review.html" "$PR_PLUG/templates/plan-review.html"
cp "$PRD/plan.md" "$PR_PLUG/specs/x/plan.md"
assert_exit "render refuses the default output of a spec folder inside the plugin" 2 \
  python3 "$PR_PLUG/scripts/plan_review.py" render "$PR_PLUG/specs/x"
assert_eq "the refused default output writes nothing" "no" "$([[ -e "$PR_PLUG/specs/x/review.html" ]] && echo yes || echo no)"
assert_exit "the copy renders to a file outside its own folder" 0 \
  python3 "$PR_PLUG/scripts/plan_review.py" render "$PR_PLUG/specs/x" -o "$WORKDIR/pr/copy-review.html"

# ======================================================================
# v9.6.5: every write has a fixed target, and nothing writes inside the plugin's own folder
# ======================================================================

# --- evidence: a stage name off the fixed list never becomes a path ---
setup
mkdir -p "$WORKDIR/outside"
echo '{"keep": true}' > "$WORKDIR/outside/keep.json"
assert_exit "evidence add refuses a stage that is not on the list" 1 "$TEMPER" evidence add --stage ../../outside/x --claim c
assert_eq "the refused add created no file" "no" "$([[ -e "$WORKDIR/outside/x.json" ]] && echo yes || echo no)"
assert_exit "evidence clear refuses a stage that is not on the list" 1 "$TEMPER" evidence clear --stage ../../outside/keep
rm -f RAN
assert_exit "evidence run refuses a stage that is not on the list" 1 "$TEMPER" evidence run --stage bogus --claim c -- touch RAN
assert_eq "evidence run checks the stage before it runs the command" "no" "$([[ -f RAN ]] && echo yes || echo no)"
assert_exit "evidence list refuses a stage that is not on the list" 1 "$TEMPER" evidence list --stage ../../outside/keep
assert_exit "evidence list needs a stage" 1 "$TEMPER" evidence list
assert_exit "evidence resolve refuses a stage that is not on the list" 1 "$TEMPER" evidence resolve --stage ../../outside/keep --id 1 --fixed-by x
assert_exit "evidence accept refuses a stage that is not on the list" 1 "$TEMPER" evidence accept --stage ../../outside/keep --id 1 --reason x
assert_eq "clear, resolve and accept left the file they named untouched" '{"keep": true}' "$(cat "$WORKDIR/outside/keep.json")"
for s in intent plan design build review check commit rca fix; do
  assert_exit "evidence add accepts the listed stage '$s'" 0 "$TEMPER" evidence add --stage "$s" --claim "row for $s"
done
assert_eq "each listed stage writes its own ledger file" "9" \
  "$(python3 -c 'import os; print(sum(os.path.isfile(".temper/evidence/%s.json" % s) for s in "intent plan design build review check commit rca fix".split()))')"

# --- state init / state set: the spec slug is a plain name, never a path ---
setup
for bad in "../../outside" "-lead" "a..b" "a/b" "PROJ/1" ".hidden" "a b" ""; do
  assert_exit "state init refuses the slug '$bad'" 1 "$TEMPER" state init "$bad"
done
assert_eq "a refused state init keeps the run's state" "demo" "$("$TEMPER" state get spec)"
assert_exit "state init accepts a lowercase slug with digits, dots, dashes and underscores" 0 "$TEMPER" state init "fix-1.2_b" --command fix
assert_exit "state set refuses a spec_path outside .temper/specs" 1 "$TEMPER" state set spec_path ../../outside
assert_exit "state set refuses a spec_path whose slug is '..'" 1 "$TEMPER" state set spec_path .temper/specs/..
assert_exit "state set accepts a spec_path of the form .temper/specs/<slug>" 0 "$TEMPER" state set spec_path .temper/specs/demo
assert_exit "state set needs a key and a value" 1 "$TEMPER" state set spec_path

# --- state archive / clear: a hand-edited spec_path writes no ledger outside .temper/specs ---
setup
mkdir -p "$WORKDIR/outside/esc"
python3 - <<'EOF'
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['spec_path'] = '.temper/specs/../../outside/esc'; json.dump(d, open(p, 'w'))
EOF
"$TEMPER" state archive >/dev/null 2>&1
assert_eq "state archive writes no ledger through a spec_path that leaves .temper/specs" "no" \
  "$([[ -e "$WORKDIR/outside/esc/gate-ledger.json" ]] && echo yes || echo no)"
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "state clear writes no ledger there either" "no" "$([[ -e "$WORKDIR/outside/esc/gate-ledger.json" ]] && echo yes || echo no)"

# --- the ledger archive and the status view read the listed stage files only ---
setup
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 >/dev/null
echo '[{"claim": "stray", "criterion": "AC-01", "cmd": "x", "exit_code": 0, "ts": "2099-01-01T00:00:00Z"}]' > .temper/evidence/stray.json
"$TEMPER" state archive >/dev/null
assert_eq "the archived ledger counts the listed stage files only" "build" \
  "$(python3 -c "import json; print(','.join(sorted(json.load(open('.temper/specs/demo/gate-ledger.json'))['evidence'])))")"
assert_eq "temper status ignores a file that is not a listed stage's ledger" "open" \
  "$("$TEMPER" status --json | python3 -c 'import json,sys; print([c["status"] for c in json.load(sys.stdin)["criteria"] if c["id"] == "AC-01"][0])')"
rm -f .temper/evidence/stray.json

# --- TEMPER_DIR no longer moves the run state ---
setup
rm -rf "$WORKDIR/elsewhere"
TEMPER_DIR="$WORKDIR/elsewhere" "$TEMPER" init >/dev/null
TEMPER_DIR="$WORKDIR/elsewhere" "$TEMPER" evidence add --stage build --claim "x" >/dev/null
assert_eq "TEMPER_DIR is ignored: nothing is written to the folder it names" "no" "$([[ -e "$WORKDIR/elsewhere" ]] && echo yes || echo no)"
assert_eq "TEMPER_DIR is ignored: the row lands in the project's own .temper" "1" \
  "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/build.json"))))')"

# --- the plugin folder: the CLI's own file (symlinks followed) with the literal suffix /scripts removed ---
setup
mkdir -p "$WORKDIR/bin"
ln -sf "$TEMPER" "$WORKDIR/bin/temper"
assert_eq "a CLI reached through a symlink resolves a model from its own folder, with an empty environment" "$("$TEMPER" model plan)" \
  "$(env -i HOME="$HOME" PATH="$PATH" "$WORKDIR/bin/temper" model plan)"
assert_exit "a CLI reached through a symlink loads acceptance.py by its full path, with an empty environment" 0 \
  env -i HOME="$HOME" PATH="$PATH" "$WORKDIR/bin/temper" gate plan
assert_eq "the CLI and its Python helpers list no folder by wildcard and load no folder onto sys.path" "0" \
  "$(cat "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$REPO_ROOT/scripts/pack-discover.py" | grep -cE 'glob\.glob|^import glob|sys\.path\.insert|TEMPER_DIR:-')"

# --- CLI: the plugin folder comes from the CLI's own file, never from an environment variable ---
setup
mkdir -p "$WORKDIR/bin"
CLI_PLUGIN="$WORKDIR/cli-plugin"
rm -rf "$CLI_PLUGIN"
mkdir -p "$CLI_PLUGIN/scripts" "$CLI_PLUGIN/inner/sub"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$CLI_PLUGIN/scripts/"
cp -R "$REPO_ROOT/agents" "$CLI_PLUGIN/agents"
ln -sf ../cli-plugin/scripts/temper "$WORKDIR/bin/rel-temper"
ln -sf rel-temper "$WORKDIR/bin/chained-temper"
assert_eq "a CLI reached through a chain of relative symlinks finds its own plugin folder" "$("$TEMPER" model plan)" \
  "$(env -i HOME="$HOME" PATH="$PATH" "$WORKDIR/bin/chained-temper" model plan)"
# No value of the plugin root variable can move them: the CLI and the guard scripts never name it.
assert_eq "the CLI and the guard scripts never read the plugin root variable" "0" \
  "$(cat "$TEMPER" "$REPO_ROOT"/scripts/guards/*.sh | grep -c '_PLUGIN_ROOT')"
