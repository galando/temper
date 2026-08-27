#!/usr/bin/env bash
#
# test-temper.sh — unit tests for scripts/temper (the deterministic spine).
#
# Plain-bash assertions, no test framework dependency (consistent with the rest of
# Temper's tooling). Runs entirely in a throwaway tmp dir; never touches the repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPER="$REPO_ROOT/scripts/temper"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

assert_eq() { # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $1 — expected '$2', got '$3'"
  fi
}

assert_exit() { # assert_exit <name> <expected-code> <cmd...>
  local name="$1" expected="$2"; shift 2
  local actual out
  out="$(mktemp "$WORKDIR/assert-out.XXXXXX")"
  "$@" >"$out" 2>&1; actual=$?
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name — expected exit $expected, got $actual"
    sed 's/^/    /' "$out"
  fi
  rm -f "$out"
}

setup() {
  cd "$WORKDIR"
  rm -rf .temper .claude
  mkdir -p .claude .temper/specs/demo
  git init -q . 2>/dev/null || true
  cat > .claude/temper.config <<'EOF'
stack: auto
packs: [quality, tdd, security, git]
review:
  block-on: [critical]
check:
  coverage-threshold: 80
eval:
  enabled: true
  pass-threshold: 0.75
loops:
  max-per-type: 2
autonomy:
  enabled: false
  max-blast-radius: 15
  park-on-touch: ["**/auth/**", "**/payment/**"]
  budget:
    max-total-loops: 4
    max-stages: 12
EOF
  cat > .temper/specs/demo/intent.md <<'EOF'
**Status:** draft

## Problem
Users cannot do the demo thing today.

## Success Criteria
- one
- two

Scenario: first
Scenario: second
EOF
  cat > .temper/specs/demo/tasks.md <<'EOF'
- [x] done task
EOF
  "$TEMPER" init >/dev/null
  "$TEMPER" state init demo --command temper >/dev/null
}

# --- grep -c zero-match must not double-print (the "0\n0" bug) ---
setup
cat > .temper/specs/demo/tasks.md <<'EOF'
- [x] a
- [x] b
EOF
assert_exit "build gate PASSes with zero unchecked tasks (no double-count)" 1 "$TEMPER" gate build
# (still FAILs on the RED/GREEN requirement — no test evidence yet — but must not crash)

# --- plan gate: criteria -> scenarios coverage ---
setup
assert_exit "plan gate PASSes: 2 scenarios for 2 criteria" 0 "$TEMPER" gate plan

setup
cat > .temper/specs/demo/intent.md <<'EOF'
## Success Criteria
- one
- two
- three

Scenario: first
EOF
assert_exit "plan gate FAILs: 1 scenario for 3 criteria" 1 "$TEMPER" gate plan

# --- plan gate: blast radius required for medium/complex, not for trivial/simple ---
setup
assert_exit "plan gate PASSes without a Blast Radius section (no complexity set)" 0 "$TEMPER" gate plan
"$TEMPER" state set complexity medium >/dev/null
assert_exit "plan gate FAILs: medium complexity needs a Blast Radius section" 1 "$TEMPER" gate plan
cat > .temper/specs/demo/plan.md <<'EOF'
## Blast Radius
- no external consumers
EOF
assert_exit "plan gate PASSes once plan.md has a Blast Radius section" 0 "$TEMPER" gate plan

# --- build gate: RED then GREEN required ---
setup
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
assert_exit "build gate FAILs on GREEN with no RED (TDD discipline)" 1 "$TEMPER" gate build

setup
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
assert_exit "build gate PASSes on RED then GREEN + no unchecked tasks" 0 "$TEMPER" gate build

# --- review gate: block-on severity ---
setup
assert_exit "review gate PASSes with no findings" 0 "$TEMPER" gate review
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
assert_exit "review gate FAILs on an open critical finding" 1 "$TEMPER" gate review

# --- check gate: coverage threshold ---
setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 60 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
assert_exit "check gate FAILs below coverage threshold (60 < 80)" 1 "$TEMPER" gate check
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
assert_exit "check gate PASSes above coverage threshold (90 >= 80)" 0 "$TEMPER" gate check

# --- check gate: scenarios must be traced to a test (the flagship "rate limiting" story) ---
setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
assert_exit "check gate FAILs when a scenario has no traced test (1/2 covered)" 1 "$TEMPER" gate check
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
assert_exit "check gate PASSes once every scenario is traced (2/2 covered)" 0 "$TEMPER" gate check

# --- evidence: PROVEN downgrade on missing artifact ---
setup
OUT=$("$TEMPER" evidence add --stage check --claim "x" --exit 0 --artifact does/not/exist --label PROVEN 2>&1)
assert_eq "PROVEN downgrades to HEURISTIC when artifact is missing" "yes" "$(echo "$OUT" | grep -q 'downgraded to HEURISTIC' && echo yes || echo no)"

# --- commit gate: aggregates prior gate verdicts + honors overrides ---
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
assert_exit "commit gate PASSes once every upstream gate is green" 0 "$TEMPER" gate commit

setup
"$TEMPER" evidence add --stage review --claim "critical thing" --severity critical >/dev/null
assert_exit "commit gate FAILs with an unresolved review finding, no override" 1 "$TEMPER" gate commit
"$TEMPER" override review --reason "manually verified safe" >/dev/null
"$TEMPER" gate intent >/dev/null; "$TEMPER" gate plan >/dev/null; "$TEMPER" gate build >/dev/null 2>&1 || true
"$TEMPER" gate check >/dev/null 2>&1 || true
assert_eq "override is recorded and visible in report" "yes" "$("$TEMPER" report | grep -q 'overridden' && echo yes || echo no)"

# --- state: illegal transitions rejected, loop budget enforced ---
setup
assert_exit "state advance rejects an unknown stage name" 1 "$TEMPER" state advance not_a_real_stage build
assert_exit "state advance accepts a known stage" 0 "$TEMPER" state advance build_complete review
assert_exit "state loop allows iterations up to max-per-type" 0 "$TEMPER" state loop review build --reason r1
assert_exit "state loop allows the second iteration" 0 "$TEMPER" state loop review build --reason r2
assert_exit "state loop blocks the third iteration (max-per-type: 2)" 1 "$TEMPER" state loop review build --reason r3

# --- state get: bare call dumps the whole state; degrades cleanly on corrupted JSON ---
setup
assert_eq "state get (bare) dumps the whole state file" "yes" "$("$TEMPER" state get | grep -q '"spec": "demo"' && echo yes || echo no)"
echo '{"stage": "started", "spec": "demo"' > .temper/build-state.json
assert_exit "state get (bare) does not crash on a corrupted state file" 0 "$TEMPER" state get
assert_eq "state get (bare) falls back to {} on a corrupted state file" "yes" "$("$TEMPER" state get | grep -q '^{}$' && echo yes || echo no)"

# --- state advance: missing args fail cleanly instead of an unbound-variable crash ---
setup
OUT=$("$TEMPER" state advance 2>&1)
assert_eq "state advance with zero args exits 1" "1" "$("$TEMPER" state advance >/dev/null 2>&1; echo $?)"
assert_eq "state advance with zero args prints a usage message, not an unbound-variable crash" "yes" "$(echo "$OUT" | grep -q 'usage: temper state advance' && ! echo "$OUT" | grep -q 'unbound variable' && echo yes || echo no)"
OUT=$("$TEMPER" state advance build_complete 2>&1)
assert_eq "state advance with one arg prints a usage message, not an unbound-variable crash" "yes" "$(echo "$OUT" | grep -q 'usage: temper state advance' && ! echo "$OUT" | grep -q 'unbound variable' && echo yes || echo no)"

# --- state advance: stage vocabulary is scoped per command (temper vs fix) ---
setup
assert_exit "a /temper run rejects fix-only stage names (rca_complete)" 1 "$TEMPER" state advance rca_complete design
assert_exit "a /temper run accepts its own stage names" 0 "$TEMPER" state advance plan_complete design

setup
"$TEMPER" state init bug2 --command fix >/dev/null
assert_exit "a /temper:fix run accepts rca_complete" 0 "$TEMPER" state advance rca_complete fix
assert_exit "a /temper:fix run rejects temper-only stage names (plan_complete)" 1 "$TEMPER" state advance plan_complete design

# --- /temper:fix commits: no plan gate required (fix has no such stage) ---
setup
"$TEMPER" state init bug1 --command fix >/dev/null
"$TEMPER" evidence add --stage build --claim "regression test" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "regression test" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
assert_exit "fix commit gate PASSes without a plan gate" 0 "$TEMPER" gate commit

# --- autonomy: park-on-touch blocks commit in autonomous mode only ---
setup
"$TEMPER" state set run_mode autonomous >/dev/null
mkdir -p src/auth && echo x > src/auth/login.js
git add -A >/dev/null 2>&1 || true
assert_exit "autonomous commit gate parks on a park-on-touch path" 1 "$TEMPER" gate commit
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "park reason names the matched path" "yes" "$(echo "$OUT" | grep -q 'src/auth/login.js' && echo yes || echo no)"

# --- native pre-commit hook: does `git commit` actually get blocked/allowed for
# real, not just gate_commit()'s decision logic in isolation? Everything above tests
# the CLI function; this installs the real hook (scripts/hooks/install.sh) and runs a
# real `git commit`, the same way a human's `git commit` reaches it.
setup
git config user.email "test@example.com"
git config user.name "test"
bash "$REPO_ROOT/scripts/hooks/install.sh" >/dev/null
echo '{"command": "temper", "run_mode": "interactive"}' > .temper/build-state.json
echo 'x' > file.txt
git add file.txt >/dev/null 2>&1

# The "eval" entry below is a stale key a pre-upgrade .temper/gates.json would still
# carry — gate_commit's stages_to_check no longer names "eval" so it is never visited.
# This fixture doubles as coverage for that; a dedicated case follows further down too.
cat > .temper/gates.json <<'EOF'
{
  "plan": {"verdict": "PASS", "requirements": [], "ts": "x"},
  "build": {"verdict": "PASS", "requirements": [], "ts": "x"},
  "review": {"verdict": "PASS", "requirements": [], "ts": "x"},
  "check": {"verdict": "FAIL", "requirements": [], "ts": "x"},
  "eval": {"verdict": "PASS", "requirements": [], "ts": "x"}
}
EOF
echo '[]' > .temper/overrides.json
assert_exit "native pre-commit hook blocks a real git commit on a red gate" 1 git commit -m "test"
assert_eq "the blocked commit never actually landed" "yes" "$(git log --oneline 2>&1 | grep -q . && echo no || echo yes)"

python3 -c "
import json
d = json.load(open('.temper/gates.json'))
d['check'] = {'verdict': 'PASS', 'requirements': [], 'ts': 'x'}
json.dump(d, open('.temper/gates.json', 'w'))
"
assert_exit "native pre-commit hook allows a real git commit once the gate is green" 0 git commit -m "test"
assert_eq "the allowed commit actually landed" "yes" "$(git log --oneline 2>&1 | grep -q . && echo yes || echo no)"

# --- v8 compat: Eval-stage removal must not break a pre-upgrade project ---

# 1. A stale `eval:` block in .claude/temper.config never breaks a gate — every setup()
#    fixture above already writes one (see the config heredoc), so this run's whole
#    green suite is itself evidence; this case makes the claim explicit and standalone.
setup
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
assert_exit "gate build runs cleanly against a config with a stale eval: block" 0 "$TEMPER" gate build

# 2. A stale "eval" key in .temper/gates.json is ignored by gate_commit, not iterated.
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
python3 -c "
import json
d = json.load(open('.temper/gates.json'))
d['eval'] = {'verdict': 'FAIL', 'requirements': [], 'ts': 'x'}
json.dump(d, open('.temper/gates.json', 'w'))
"
assert_exit "commit gate PASSes and ignores a stale FAIL 'eval' key in gates.json" 0 "$TEMPER" gate commit

# 3. Legacy state left by an in-flight v7.0.x run: next_stage "eval" forward-maps to
#    "commit", written through to disk (not just stdout) so a later raw read sees it too.
setup
python3 -c "
import json
d = json.load(open('.temper/build-state.json'))
d['next_stage'] = 'eval'
json.dump(d, open('.temper/build-state.json', 'w'))
"
assert_eq "state get forward-maps legacy next_stage 'eval' to 'commit'" "commit" "$("$TEMPER" state get next_stage)"
assert_eq "the next_stage forward-map is written through to disk" "commit" "$(python3 -c "import json; print(json.load(open('.temper/build-state.json'))['next_stage'])")"

# 4. Legacy stage "eval_complete": the hook (L1, reads build-state.json directly, cannot
#    call this CLI) no longer treats a raw/unhealed value as green — but a prior CLI
#    touch heals the file on disk, and the hook then sees "check_complete" and passes.
setup
git config user.email "test@example.com"
git config user.name "test"
bash "$REPO_ROOT/scripts/hooks/install.sh" >/dev/null
python3 -c "
import json
d = json.load(open('.temper/build-state.json'))
d['stage'] = 'eval_complete'
json.dump(d, open('.temper/build-state.json', 'w'))
"
assert_exit "verify-tests-ran.sh no longer matches a raw, unhealed 'eval_complete'" 2 bash "$REPO_ROOT/scripts/hooks/verify-tests-ran.sh"
"$TEMPER" state get stage >/dev/null   # a CLI touch heals the on-disk value
assert_eq "the stage forward-map is written through to disk" "check_complete" "$(python3 -c "import json; print(json.load(open('.temper/build-state.json'))['stage'])")"
assert_exit "verify-tests-ran.sh passes once the CLI has healed the state to check_complete" 0 bash "$REPO_ROOT/scripts/hooks/verify-tests-ran.sh"

# --- v8: evidence clear + state loop auto-clears downstream evidence (Decision 7) ---
# A loop means "we are going backwards"; evidence is append-only, so a stale row from a
# stage being redone (or an abandoned parallel Check run on a Review FAIL) must not
# survive to inflate the next gate's count. `temper evidence clear` is the direct tool;
# `state loop <from> <to>` calls it automatically for <to> and everything downstream of
# it in STAGE_SEQ_TEMPER — the spine-level backstop behind the orchestrator's
# kill-before-clear ordering.
setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence clear --stage check >/dev/null
assert_eq "evidence clear truncates a stage's ledger to []" "[]" "$(cat .temper/evidence/check.json | tr -d '[:space:]')"

setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
"$TEMPER" state loop check build --reason "regression found downstream" >/dev/null
assert_eq "state loop check->build auto-clears check evidence (check is downstream of build)" "[]" "$(cat .temper/evidence/check.json | tr -d '[:space:]')"
assert_exit "check gate FAILs closed again after the auto-clear (stale scenario coverage cannot mask a regression)" 1 "$TEMPER" gate check

# --- pack-discover.py: install-path selection uses lastUpdated, not (version, installPath)
# (feedback re-entry fix). Real installed_plugins.json entries commonly carry
# "version": "unknown" for every candidate, which made the old (version, installPath)
# tiebreak an unrelated path-string sort — "install-old" > "install-new" lexicographically,
# so the *older* entry won even though "install-new" has the newer lastUpdated. ---
setup
PACK_HOME="$WORKDIR/fake-home"
mkdir -p "$PACK_HOME/.claude/plugins" \
  "$PACK_HOME/install-old/.claude-plugin" \
  "$PACK_HOME/install-new/.claude-plugin" \
  "$PACK_HOME/install-new/skills/demo"
echo '{"description": "old install"}' > "$PACK_HOME/install-old/.claude-plugin/plugin.json"
echo '{"description": "new install"}' > "$PACK_HOME/install-new/.claude-plugin/plugin.json"
cat > "$PACK_HOME/install-new/skills/demo/SKILL.md" <<'EOF'
---
description: "demo skill"
---
EOF
cat > "$PACK_HOME/.claude/plugins/installed_plugins.json" <<EOF
{
  "plugins": {
    "demo@marketA": [
      {"version": "unknown", "installPath": "$PACK_HOME/install-old", "lastUpdated": "2026-01-01T00:00:00Z"},
      {"version": "unknown", "installPath": "$PACK_HOME/install-new", "lastUpdated": "2026-06-01T00:00:00Z"}
    ]
  }
}
EOF
PACK_OUT="$(HOME="$PACK_HOME" python3 "$REPO_ROOT/scripts/pack-discover.py")"
assert_eq "pack-discover picks the entry with the newest lastUpdated, not the alphabetically-last path" "1" "$(printf '%s\n' "$PACK_OUT" | grep -c "install-new")"
assert_eq "pack-discover does not pick the older lastUpdated entry" "0" "$(printf '%s\n' "$PACK_OUT" | grep -c "install-old")"

# --- pack-discover.py: cross-marketplace dedup — the SAME package name installed from
# TWO different marketplace keys (e.g. feature-dev@marketA and feature-dev@marketB, the
# real-world case being feature-dev installed from both claude-plugins-official and
# claude-code-plugins) must still emit each target exactly once, not once per
# marketplace key. Scenario: "Pack discovery deduplicates targets installed from two
# marketplaces" (intent.md). ---
setup
DEDUP_HOME="$WORKDIR/fake-home-dedup"
mkdir -p "$DEDUP_HOME/.claude/plugins" \
  "$DEDUP_HOME/marketA-install/.claude-plugin" \
  "$DEDUP_HOME/marketA-install/skills/feature-dev" \
  "$DEDUP_HOME/marketB-install/.claude-plugin" \
  "$DEDUP_HOME/marketB-install/skills/feature-dev"
echo '{"description": "feature-dev plugin (market A)"}' > "$DEDUP_HOME/marketA-install/.claude-plugin/plugin.json"
echo '{"description": "feature-dev plugin (market B)"}' > "$DEDUP_HOME/marketB-install/.claude-plugin/plugin.json"
cat > "$DEDUP_HOME/marketA-install/skills/feature-dev/SKILL.md" <<'EOF'
---
description: "Guided feature development (market A)"
---
EOF
cat > "$DEDUP_HOME/marketB-install/skills/feature-dev/SKILL.md" <<'EOF'
---
description: "Guided feature development (market B)"
---
EOF
cat > "$DEDUP_HOME/.claude/plugins/installed_plugins.json" <<EOF
{
  "plugins": {
    "feature-dev@claude-plugins-official": [
      {"version": "1.0.0", "installPath": "$DEDUP_HOME/marketA-install", "lastUpdated": "2026-01-01T00:00:00Z"}
    ],
    "feature-dev@claude-code-plugins": [
      {"version": "1.0.0", "installPath": "$DEDUP_HOME/marketB-install", "lastUpdated": "2026-06-01T00:00:00Z"}
    ]
  }
}
EOF
DEDUP_OUT="$(HOME="$DEDUP_HOME" python3 "$REPO_ROOT/scripts/pack-discover.py")"
assert_eq "pack-discover emits feature-dev:feature-dev exactly once across two marketplace keys" "1" "$(printf '%s\n' "$DEDUP_OUT" | grep -c "^SKILL|feature-dev:feature-dev|")"
assert_eq "pack-discover does not emit a second, market-B-suffixed duplicate" "1" "$(printf '%s\n' "$DEDUP_OUT" | grep -c "feature-dev:feature-dev")"

# --- stage-marker.sh + verify-stage-gate.sh: the standalone-stage gate guarantee ---
# stage-marker records the gate a /temper:{stage} session owes; verify-stage-gate blocks
# Stop until gates.json carries a verdict for it (any verdict), failing open after 2
# blocks. See docs/decisions/0005-deterministic-stage-gate-enforcement.md.
setup
MARKER="$REPO_ROOT/scripts/hooks/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/hooks/verify-stage-gate.sh"

echo '{"prompt": "/temper:plan add a thing"}' | bash "$MARKER"
assert_eq "stage-marker records the owed stage" "plan" "$(python3 -c "import json; print(json.load(open('.temper/pending-stage.json'))['stage'])")"

rm -f .temper/pending-stage.json
echo '{"prompt": "please run /temper:plan for me"}' | bash "$MARKER"
assert_eq "stage-marker ignores a mid-sentence mention" "absent" "$([[ -f .temper/pending-stage.json ]] && echo created || echo absent)"
echo '{"prompt": "/temper add login"}' | bash "$MARKER"
assert_eq "stage-marker ignores the unified /temper command" "absent" "$([[ -f .temper/pending-stage.json ]] && echo created || echo absent)"
echo 'not json at all' | bash "$MARKER"
assert_exit "stage-marker fails open on garbage stdin" 0 bash -c "echo garbage | bash '$MARKER'"

assert_exit "verify-stage-gate passes with no marker" 0 bash "$VERIFY"

echo '{"prompt": "/temper:plan x"}' | bash "$MARKER"
assert_exit "verify-stage-gate BLOCKS when no verdict exists" 2 bash "$VERIFY"
assert_eq "block is counted in the marker" "1" "$(python3 -c "import json; print(json.load(open('.temper/pending-stage.json'))['blocks'])")"

echo '{"plan": {"verdict": "FAIL"}}' > .temper/gates.json
assert_exit "a FAIL verdict satisfies the guarantee (gate ran)" 0 bash "$VERIFY"
assert_eq "marker cleared once the verdict exists" "absent" "$([[ -f .temper/pending-stage.json ]] && echo present || echo absent)"

rm -f .temper/gates.json
echo '{"prompt": "/temper:build x"}' | bash "$MARKER"
bash "$VERIFY" >/dev/null 2>&1; bash "$VERIFY" >/dev/null 2>&1
assert_exit "loop guard fails open on the third stop attempt" 0 bash "$VERIFY"
assert_eq "loop-guard fail-open clears the marker" "absent" "$([[ -f .temper/pending-stage.json ]] && echo present || echo absent)"

echo '{"stage": "plan"' > .temper/pending-stage.json
assert_exit "corrupt marker fails open" 0 bash "$VERIFY"

# stop_hook_active with our counter at 0 means the marker isn't persisting — fail open
# rather than loop. (Regression: the harness JSON must travel as argv; piping it into
# `python3 - <<heredoc` silently discards it, since the heredoc owns stdin.)
rm -f .temper/pending-stage.json .temper/gates.json
echo '{"prompt": "/temper:check x"}' | bash "$MARKER"
assert_exit "stop_hook_active with a stuck counter fails open" 0 \
  bash -c "echo '{\"stop_hook_active\": true}' | bash '$VERIFY'"
rm -f .temper/pending-stage.json
echo '{"prompt": "/temper:check x"}' | bash "$MARKER"
assert_exit "stop_hook_active=false still blocks normally" 2 \
  bash -c "echo '{\"stop_hook_active\": false}' | bash '$VERIFY'"

# Time-scoping: a verdict from BEFORE the marker (a previous run's leftovers) must not
# satisfy this session's debt; one recorded after it must.
rm -f .temper/gates.json .temper/pending-stage.json
echo '{"plan": {"verdict": "PASS", "ts": "2020-01-01T00:00:00Z"}}' > .temper/gates.json
echo '{"prompt": "/temper:plan a new feature"}' | bash "$MARKER"
assert_exit "a pre-marker verdict does NOT pay this session's debt" 2 bash "$VERIFY"
python3 -c "
import json; g=json.load(open('.temper/gates.json'))
g['plan']['ts']='2099-01-01T00:00:00Z'; json.dump(g, open('.temper/gates.json','w'))"
assert_exit "a post-marker verdict does" 0 bash "$VERIFY"

# Backward compat: missing timestamps degrade to the any-verdict check, never a block.
rm -f .temper/pending-stage.json
echo '{"plan": {"verdict": "PASS"}}' > .temper/gates.json
echo '{"stage": "plan", "blocks": 0}' > .temper/pending-stage.json
assert_exit "verdict without ts + old marker format still clears" 0 bash "$VERIFY"

# End-to-end with the real CLI: marker -> real `temper gate plan` FAIL -> stop allowed.
rm -f .temper/gates.json .temper/pending-stage.json
echo '{"prompt": "/temper:plan x"}' | bash "$MARKER"
"$TEMPER" gate plan --spec-path .temper/specs/empty >/dev/null 2>&1 || true
assert_exit "real gate FAIL verdict unblocks the stop" 0 bash "$VERIFY"

# --- temper model: config override > agents/{stage}.md frontmatter, resolved in bash ---
setup
# Defaults come from the real agents/*.md frontmatter — no table in the CLI to drift.
assert_eq "model plan defaults to agents/plan.md frontmatter" \
  "$(awk '/^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1 && /^model:/{sub(/^model:[[:space:]]*/,""); print; exit}' "$REPO_ROOT/agents/plan.md")" \
  "$("$TEMPER" model plan)"
assert_eq "model --all emits one stage=model line per agent stage" "8" "$("$TEMPER" model --all | grep -c '^[a-z]*=')"
assert_eq "model --all covers every agent stage (incl. fix-command stages)" "intent plan design build review check rca fix" \
  "$("$TEMPER" model --all | cut -d= -f1 | tr '\n' ' ' | sed 's/ $//')"
assert_eq "model rca defaults to agents/rca.md frontmatter" \
  "$(awk '/^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1 && /^model:/{sub(/^model:[[:space:]]*/,""); print; exit}' "$REPO_ROOT/agents/rca.md")" \
  "$("$TEMPER" model rca)"
assert_eq "model fix defaults to agents/fix.md frontmatter" \
  "$(awk '/^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1 && /^model:/{sub(/^model:[[:space:]]*/,""); print; exit}' "$REPO_ROOT/agents/fix.md")" \
  "$("$TEMPER" model fix)"
assert_exit "model rejects an unknown stage" 1 "$TEMPER" model bogus
assert_exit "model rejects 'commit' (not an Agent stage)" 1 "$TEMPER" model commit

# A models: block in the project config overrides the frontmatter default.
cat >> .claude/temper.config <<'EOF'
models:
  review: opus
  check: claude-opus-5
EOF
assert_eq "models.{stage} config overrides the frontmatter default" "opus" "$("$TEMPER" model review)"
assert_eq "models.{stage} accepts a full model ID, not just an alias" "claude-opus-5" "$("$TEMPER" model check)"
assert_eq "an unset stage still falls back to frontmatter" "$("$TEMPER" model plan)" "$(cd "$REPO_ROOT" && ./scripts/temper model plan)"
assert_eq "model --all reflects overrides" "review=opus" "$("$TEMPER" model --all | grep '^review=')"

# Absent config => frontmatter defaults, never an empty string.
rm -f .claude/temper.config
assert_eq "no config file => frontmatter default, non-empty" "1" "$([[ -n "$("$TEMPER" model build)" ]] && echo 1 || echo 0)"
assert_exit "model --all succeeds with no config file" 0 "$TEMPER" model --all

# --- protect-regression-test.sh: the fix loop's write shield ---
# Once a /temper:fix run records its regression test (state.regression_test), an agent
# Edit/Write targeting that file is blocked (exit 2) — the agent fixing the code must
# not weaken the check on it. Everything else: fail-open.
setup
SHIELD="$REPO_ROOT/scripts/hooks/protect-regression-test.sh"
"$TEMPER" state init bug2 --command fix >/dev/null
mkdir -p test && echo 'assert(true)' > test/regression.spec.js

assert_exit "shield: no recorded regression test => edit passes" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

"$TEMPER" state set regression_test test/regression.spec.js >/dev/null
assert_exit "shield: editing the recorded regression test is BLOCKED" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
OUT=$(echo '{"tool_input": {"file_path": "test/regression.spec.js"}}' | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$SHIELD" 2>&1; true)
assert_eq "shield: the block names the human release valve" "yes" "$(echo "$OUT" | grep -q 'temper state set regression_test' && echo yes || echo no)"

assert_exit "shield: an absolute path to the same file is also BLOCKED" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"$WORKDIR/test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
assert_exit "shield: editing any other file passes" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/resetService.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

# The shield is fix-run-scoped: a /temper (feature) run never blocks, even with a
# stray regression_test key in state.
setup
mkdir -p test && echo 'assert(true)' > test/regression.spec.js
"$TEMPER" state set regression_test test/regression.spec.js >/dev/null
assert_exit "shield: inert outside a fix run (command != fix)" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

# Degradation contract: garbage stdin, missing state, cleared shield — all fail open.
setup
"$TEMPER" state init bug3 --command fix >/dev/null
"$TEMPER" state set regression_test test/regression.spec.js >/dev/null
assert_exit "shield: garbage stdin fails open" 0 \
  bash -c "echo 'not json' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
"$TEMPER" state set regression_test "" >/dev/null
assert_exit "shield: a human clearing regression_test lifts the block" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
rm -f .temper/build-state.json
assert_exit "shield: no state file fails open" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"anything.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

# --- temper bands: deterministic control-band drift check (closing the loop) ---
# Detection is pure arithmetic over .temper/metrics.json history arrays — no model, no
# network. BREACH (exit 1) only at 2sigma+; 1sigma logs but never breaches; too few
# points is INSUFFICIENT-DATA, never a breach (degradation contract).
setup
rm -f .temper/metrics.json
assert_exit "bands: no metrics.json is INSUFFICIENT-DATA, exit 0" 0 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1)
assert_eq "bands: no metrics.json reports INSUFFICIENT-DATA" "yes" "$(echo "$OUT" | grep -q 'INSUFFICIENT-DATA' && echo yes || echo no)"

echo 'this is not json' > .temper/metrics.json
assert_exit "bands: malformed metrics.json degrades to insufficient data, never crashes" 0 "$TEMPER" bands

python3 -c "
import json
json.dump({'coverage_history': [85, 86, 85, 86, 85, 86, 85, 86], 'test_count_history': []},
          open('.temper/metrics.json', 'w'))
"
assert_exit "bands: an in-band latest point is OK, exit 0" 0 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1)
assert_eq "bands: in-band verdict is OK" "yes" "$(echo "$OUT" | grep -q 'temper bands -> OK' && echo yes || echo no)"
assert_eq "bands: a metric with no points reports insufficient data without failing the run" "yes" "$(echo "$OUT" | grep -q 'tests — insufficient data' && echo yes || echo no)"

# A collapsed latest point (85-86 baseline, then 60) is far beyond 3 sigma.
python3 -c "
import json
json.dump({'coverage_history': [85, 86, 85, 86, 85, 86, 85, 86, 60]},
          open('.temper/metrics.json', 'w'))
"
assert_exit "bands: a 3sigma coverage collapse is a BREACH, exit 1" 1 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1; true)
assert_eq "bands: the breach names the metric and tier" "yes" "$(echo "$OUT" | grep -q '\[3sigma\] coverage' && echo yes || echo no)"
assert_eq "bands: the 3sigma tier maps to the propose action by default" "yes" "$(echo "$OUT" | grep -q 'action=propose' && echo yes || echo no)"
assert_eq "bands: a breach names the closing-the-loop next step (intent.md)" "yes" "$(echo "$OUT" | grep -q 'intent.md' && echo yes || echo no)"

# A flat baseline (sigma = 0) treats ANY deviation as 3sigma — documented behavior.
python3 -c "
import json
json.dump({'coverage_history': [80, 80, 80, 80, 80, 80, 79]}, open('.temper/metrics.json', 'w'))
"
assert_exit "bands: any deviation from a perfectly flat baseline is a BREACH" 1 "$TEMPER" bands

# Slow drift: six consecutive same-side points elevate to 2sigma even when each point
# is individually inside the bands (the Western-Electric-style run rule).
python3 -c "
import json
json.dump({'coverage_history': [10, 10, 10, 10, 11, 11, 11, 11, 11, 11]},
          open('.temper/metrics.json', 'w'))
"
assert_exit "bands: a 6-point same-side run is a drift BREACH" 1 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1; true)
assert_eq "bands: drift is labeled as drift" "yes" "$(echo "$OUT" | grep -q 'drift' && echo yes || echo no)"

# 1 sigma logs but does not breach: baseline mean 82.5, sigma ~2.5, latest ~1.4 sigma out.
python3 -c "
import json
json.dump({'coverage_history': [80, 85, 80, 85, 80, 85, 79]}, open('.temper/metrics.json', 'w'))
"
assert_exit "bands: a 1sigma excursion logs but is not a breach" 0 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1)
assert_eq "bands: the 1sigma excursion is reported with the log action" "yes" "$(echo "$OUT" | grep -q 'action=log' && echo yes || echo no)"

# History points as objects ({value: N}) parse the same as bare numbers.
python3 -c "
import json
json.dump({'coverage_history': [{'value': 85}, {'value': 86}, {'value': 85}, {'value': 86}, {'value': 60}]},
          open('.temper/metrics.json', 'w'))
"
assert_exit "bands: object-shaped history points ({value: N}) are read like numbers" 1 "$TEMPER" bands

# Config overrides: window, min-points, metrics list, and tier actions all honored.
cat >> .claude/temper.config <<'EOF'
bands:
  window: 4
  min-points: 6
  metrics: [coverage]
  tiers:
    3sigma: page-a-human
EOF
python3 -c "
import json
json.dump({'coverage_history': [85, 86, 85, 86, 60]}, open('.temper/metrics.json', 'w'))
"
assert_exit "bands: config min-points 6 turns a 5-point series into insufficient data" 0 "$TEMPER" bands
python3 -c "
import json
json.dump({'coverage_history': [85, 86, 85, 86, 85, 86, 60]}, open('.temper/metrics.json', 'w'))
"
OUT=$("$TEMPER" bands 2>&1; true)
assert_eq "bands: config tier action overrides the default" "yes" "$(echo "$OUT" | grep -q 'action=page-a-human' && echo yes || echo no)"
assert_eq "bands: metrics list from config drops the tests series" "no" "$(echo "$OUT" | grep -q 'tests' && echo yes || echo no)"

# --json emits the persisted verdict file, machine-readable.
OUT=$("$TEMPER" bands --json 2>&1; true)
assert_eq "bands: --json output parses and carries the verdict" "BREACH" "$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])" 2>/dev/null)"
assert_eq "bands: verdict is persisted to .temper/bands.json" "yes" "$([[ -f .temper/bands.json ]] && echo yes || echo no)"

# Unknown metric names are skipped with a notice, never a crash or a breach.
setup
python3 -c "
import json
json.dump({'coverage_history': [85, 86, 85, 86]}, open('.temper/metrics.json', 'w'))
"
cat >> .claude/temper.config <<'EOF'
bands:
  metrics: [coverage, made-up-series]
EOF
assert_exit "bands: an unknown metric name is skipped, not fatal" 0 "$TEMPER" bands
OUT=$("$TEMPER" bands 2>&1)
assert_eq "bands: the unknown metric is named in a skip notice" "yes" "$(echo "$OUT" | grep -q 'made-up-series — unknown metric' && echo yes || echo no)"

# --- v9: intent gate — the fail-fast gate ---
# intent.md absent => trivial path => PASS. Present => Problem stated (not template
# placeholders), >=1 success criterion, a Status header. The commit gate requires an
# intent verdict exactly when the artifact exists (tested with the commit fixtures).
setup
rm -f .temper/specs/demo/intent.md
assert_exit "intent gate PASSes when intent.md is absent (trivial path)" 0 "$TEMPER" gate intent
cat > .temper/specs/demo/intent.md <<'EOF'
## Problem
{What problem are we solving? For whom?}

## Success Criteria
EOF
assert_exit "intent gate FAILs on template placeholders and zero criteria" 1 "$TEMPER" gate intent
cat > .temper/specs/demo/intent.md <<'EOF'
**Status:** draft

## Problem
Support spends a third of call time on status-only queries.

## Success Criteria
- [ ] status visible in the portal
  Validate: scenario — covered later
EOF
assert_exit "intent gate PASSes with a real Problem, a criterion, and a Status header" 0 "$TEMPER" gate intent
python3 -c "
s = open('.temper/specs/demo/intent.md').read()
open('.temper/specs/demo/intent.md','w').write(s.replace('**Status:** draft\n\n',''))
"
assert_exit "intent gate FAILs without a Status header (the lifecycle needs a home)" 1 "$TEMPER" gate intent

# An EMPTY spec path is poisonous for the absent-artifact-means-skip gates: with no
# state and no --spec-path they must refuse to guess (usage error, no verdict), never
# record a vacuous PASS on "/intent.md".
setup
rm -f .temper/build-state.json .temper/gates.json
mkdir -p .temper/specs/idea
cat > .temper/specs/idea/intent.md <<'EOF'
## Problem
{still a placeholder}
EOF
assert_exit "gate intent with no state and no --spec-path refuses to guess (exit 1)" 1 "$TEMPER" gate intent
assert_eq "the refusal writes NO verdict (no vacuous stage-marker payment)" "no" \
  "$([[ -f .temper/gates.json ]] && python3 -c "import json; print('yes' if 'intent' in json.load(open('.temper/gates.json')) else 'no')" || echo no)"
assert_exit "gate design with no state and no --spec-path also refuses" 1 "$TEMPER" gate design
assert_exit "gate intent --spec-path works without state and judges the real draft" 1 \
  "$TEMPER" gate intent --spec-path .temper/specs/idea

# Template placeholders never satisfy the gate: the template's own '- [ ] {criterion}'
# bullets and '**Status:** {draft | accepted | completed}' line must not count.
setup
cp "$REPO_ROOT/templates/intent.md" .temper/specs/demo/intent.md
python3 -c "
s = open('.temper/specs/demo/intent.md').read()
s = s.replace('{What problem are we solving? For whom? Why is this needed?}',
              'Handlers spend a third of call time on status-only queries.')
open('.temper/specs/demo/intent.md','w').write(s)
"
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_exit "a template-verbatim intent with only the Problem filled still FAILs" 1 "$TEMPER" gate intent
assert_eq "placeholder criteria bullets are not counted" "yes" "$(echo "$OUT" | grep -q 'no real success criteria' && echo yes || echo no)"
assert_eq "the placeholder Status line is not accepted" "yes" "$(echo "$OUT" | grep -q 'placeholder doesn.t count' && echo yes || echo no)"

# temper report renders the intent stage (verdict + requirement rows).
setup
"$TEMPER" gate intent >/dev/null
assert_eq "temper report renders the intent row" "yes" "$("$TEMPER" report | grep -q '^intent' && echo yes || echo no)"

# The commit gate demands an intent verdict exactly when intent.md exists.
setup
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
assert_exit "commit gate FAILs when intent.md exists but its gate never ran" 1 "$TEMPER" gate commit
"$TEMPER" gate intent >/dev/null
assert_exit "commit gate PASSes once the intent gate ran" 0 "$TEMPER" gate commit

# intent_complete is a valid /temper state transition; the fix sequence rejects it.
setup
assert_exit "a /temper run accepts intent_complete" 0 "$TEMPER" state advance intent_complete plan
assert_eq "state init points a temper run at the intent stage first" "intent" \
  "$(rm -f .temper/build-state.json; "$TEMPER" state init demo2 --command temper >/dev/null; "$TEMPER" state get next_stage)"

# stage-marker marks /temper:intent sessions (they owe a gate intent verdict).
setup
MARKER="$REPO_ROOT/scripts/hooks/stage-marker.sh"
echo '{"prompt": "/temper:intent capture this idea"}' | bash "$MARKER"
assert_eq "stage-marker records the owed intent stage" "intent" "$(python3 -c "import json; print(json.load(open('.temper/pending-stage.json'))['stage'])")"

# --- v9: design gate is no longer vacuous ---
# design.md absent => stage skipped => PASS. design.md present => must carry an Areas
# of Concern heading (an explicit "None flagged" section counts; silence does not).
setup
assert_exit "design gate PASSes when design.md is absent (stage skipped)" 0 "$TEMPER" gate design
cat > .temper/specs/demo/design.md <<'EOF'
# Design: demo
## System Architecture
stuff
EOF
assert_exit "design gate FAILs when design.md has no Areas of Concern section" 1 "$TEMPER" gate design
cat >> .temper/specs/demo/design.md <<'EOF'
## Areas of Concern
None flagged — no two applicable policies conflicted.
EOF
assert_exit "design gate PASSes once concerns are flagged (or explicitly none)" 0 "$TEMPER" gate design

# The commit gate requires a design verdict exactly when design.md exists.
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 >/dev/null
"$TEMPER" gate check >/dev/null
assert_exit "commit gate PASSes with no design.md and no design verdict" 0 "$TEMPER" gate commit
printf '# Design\n## Areas of Concern\nNone flagged — simple change.\n' > .temper/specs/demo/design.md
assert_exit "commit gate FAILs when design.md exists but its gate never ran" 1 "$TEMPER" gate commit
"$TEMPER" gate design >/dev/null
assert_exit "commit gate PASSes once the design gate ran" 0 "$TEMPER" gate commit

# --- v9: artifact-only commits pass the commit gate (the committed artifact chain) ---
setup
git config user.email "test@example.com"
git config user.name "test"
echo "# Intent: demo" > .temper/specs/demo/captured.md
git add .temper/specs/demo/ >/dev/null 2>&1
assert_exit "an all-specs staged set passes the commit gate mid-run (no stage verdicts)" 0 "$TEMPER" gate commit
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "the artifact-only carve-out names itself" "yes" "$(echo "$OUT" | grep -q 'artifact-only commit' && echo yes || echo no)"
echo 'code' > src.js
git add src.js >/dev/null 2>&1
assert_exit "one staged file outside .temper/specs/ restores every gate requirement" 1 "$TEMPER" gate commit

# --- v9: override records the approver's identity ---
setup
git config user.name "Jane Approver"
git config user.email "jane@example.com"
"$TEMPER" override review --reason "accepted the risk" >/dev/null
assert_eq "override entry records who approved" "Jane Approver <jane@example.com>" \
  "$(python3 -c "import json; print(json.load(open('.temper/overrides.json'))[0]['by'])")"

# --- v9: the gate ledger is archived into the spec dir (audit trail survives) ---
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" override plan --reason "test archive" >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --label HEURISTIC >/dev/null
"$TEMPER" state archive >/dev/null
assert_eq "state archive writes the ledger WITHOUT deleting live state" "yes" \
  "$([[ -f .temper/specs/demo/gate-ledger.json && -f .temper/gates.json ]] && echo yes || echo no)"
rm -f .temper/specs/demo/gate-ledger.json
"$TEMPER" state clear >/dev/null
assert_eq "state clear writes gate-ledger.json into the spec dir" "yes" "$([[ -f .temper/specs/demo/gate-ledger.json ]] && echo yes || echo no)"
assert_eq "the archived ledger carries the plan verdict" "PASS" \
  "$(python3 -c "import json; print(json.load(open('.temper/specs/demo/gate-ledger.json'))['gates']['plan']['verdict'])")"
assert_eq "the archived ledger carries the override" "test archive" \
  "$(python3 -c "import json; print(json.load(open('.temper/specs/demo/gate-ledger.json'))['overrides'][0]['reason'])")"

# --- v9: temper metrics append + data-driven bands series ---
setup
rm -f .temper/metrics.json
assert_exit "metrics append rejects a non-numeric value" 1 "$TEMPER" metrics append coverage abc
assert_exit "metrics append rejects a malformed series name" 1 "$TEMPER" metrics append "Bad Name" 1
"$TEMPER" metrics append my_series 10 >/dev/null
"$TEMPER" metrics append my_series 10 >/dev/null
"$TEMPER" metrics append my_series 10 >/dev/null
"$TEMPER" metrics append my_series 10 >/dev/null
"$TEMPER" metrics append my_series 99 >/dev/null
assert_eq "metrics append creates and grows <series>_history" "5" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/metrics.json'))['my_series_history']))")"
cat >> .claude/temper.config <<'EOF'
bands:
  metrics: [my_series]
EOF
assert_exit "bands reads a custom appended series by name and detects the breach" 1 "$TEMPER" bands

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
PROTECT="$REPO_ROOT/scripts/hooks/block-protected-paths.sh"
CONFIRM="$REPO_ROOT/scripts/hooks/confirm-override.sh"
FORMATTER="$REPO_ROOT/scripts/hooks/run-formatter.sh"
IMPORTS="$REPO_ROOT/scripts/hooks/block-forbidden-imports.sh"

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

OUT=$(echo '{"tool_input": {"command": "$CLAUDE_PLUGIN_ROOT/scripts/temper override review --reason x"}}' | bash "$CONFIRM")
assert_eq "confirm-override: a temper override command emits the ask decision" "yes" \
  "$(echo "$OUT" | grep -q '"permissionDecision": "ask"' && echo yes || echo no)"
OUT=$(echo '{"tool_input": {"command": "git status"}}' | bash "$CONFIRM")
assert_eq "confirm-override: any other command stays silent" "" "$OUT"
assert_exit "confirm-override: always exits 0 (ask is advisory, not a block)" 0 \
  bash -c "echo '{\"tool_input\": {\"command\": \"temper override plan --reason y\"}}' | bash '$CONFIRM'"

echo 'x  =  1' > messy.txt
cat >> .claude/temper.config <<'EOF'
format:
  cmd: "sed -i 's/  */ /g' {file}"
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
PP="$REPO_ROOT/scripts/hooks/block-protected-paths.sh"
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

# install.sh: respect an existing core.hooksPath (husky/lefthook) — install where git
# actually looks, not the ignored .git/hooks/ (which would make the gate inert).
setup
git config user.email "test@example.com"
git config user.name "test"
rm -f .git/hooks/pre-commit    # clear any hook a prior test left in the shared WORKDIR
mkdir -p .husky
git config core.hooksPath .husky
bash "$REPO_ROOT/scripts/hooks/install.sh" >/dev/null 2>&1
assert_eq "install.sh honors core.hooksPath — hook lands where git looks" "yes" \
  "$([[ -f .husky/pre-commit ]] && grep -q 'installed by scripts/hooks/install.sh' .husky/pre-commit && echo yes || echo no)"
assert_eq "install.sh does NOT write the ignored .git/hooks/pre-commit when core.hooksPath is set" "yes" \
  "$([[ ! -f .git/hooks/pre-commit ]] && echo yes || echo no)"
git config --unset core.hooksPath 2>/dev/null || true

# confirm-override.sh: robust matcher — quoted path, doubled space, path prefix all ASK.
setup
CO="$REPO_ROOT/scripts/hooks/confirm-override.sh"
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

# --- temper root: agent-agnostic plugin-root resolution (v9.2.0) ---
# The single mechanic behind reference/portability.md's "Plugin Root Resolution": the
# CLI resolves from its own location first, so it answers with NO environment at all.
setup
assert_eq "root resolves from the script's own location, no env vars" \
  "$REPO_ROOT" "$(env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT "$TEMPER" root)"
assert_eq "root ignores a bogus CLAUDE_PLUGIN_ROOT when its own location is valid" \
  "$REPO_ROOT" "$(CLAUDE_PLUGIN_ROOT=/nonexistent "$TEMPER" root)"
assert_eq "root ignores a bogus CURSOR_PLUGIN_ROOT when its own location is valid" \
  "$REPO_ROOT" "$(CURSOR_PLUGIN_ROOT=/nonexistent "$TEMPER" root)"
# A copy of the CLI outside any install falls back to the env var — Claude's first,
# then Cursor's. This is the path a symlinked or vendored `temper` actually takes.
mkdir -p "$WORKDIR/loose"
cp "$TEMPER" "$WORKDIR/loose/temper"
assert_eq "root falls back to CURSOR_PLUGIN_ROOT outside an install" \
  "$REPO_ROOT" "$(env -u CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT="$REPO_ROOT" bash "$WORKDIR/loose/temper" root)"
assert_eq "root prefers CLAUDE_PLUGIN_ROOT over CURSOR_PLUGIN_ROOT" \
  "$REPO_ROOT" "$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CURSOR_PLUGIN_ROOT=/nonexistent bash "$WORKDIR/loose/temper" root)"
assert_exit "root FAILs loudly when nothing resolves" 1 \
  env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT bash "$WORKDIR/loose/temper" root

# --- cursor-adapter.sh: one rule implementation, two hook contracts (v9.2.0) ---
# Cursor answers with JSON on stdout, not an exit code, and always expects exit 0.
# These assertions pin the translation both ways; a regression here silently un-gates
# every Cursor install, which is exactly how the old .cursor/ export rotted.
setup
ADAPTER="$REPO_ROOT/scripts/hooks/cursor-adapter.sh"

_cursor() { # _cursor <script> <payload-json>
  printf '%s' "$2" | bash "$ADAPTER" "$1" 2>/dev/null
}

assert_eq "adapter maps beforeShellExecution + confirm-override to Cursor's ask tier" "ask" \
  "$(_cursor confirm-override.sh '{"hook_event_name":"beforeShellExecution","command":"temper override plan --reason x","workspace_roots":["'"$WORKDIR"'"]}' \
     | python3 -c 'import json,sys; print(json.load(sys.stdin).get("permission",""))' 2>/dev/null)"
assert_eq "adapter allows an unrelated shell command" "allow" \
  "$(_cursor confirm-override.sh '{"hook_event_name":"beforeShellExecution","command":"git status","workspace_roots":["'"$WORKDIR"'"]}' \
     | python3 -c 'import json,sys; print(json.load(sys.stdin).get("permission",""))' 2>/dev/null)"
assert_eq "adapter answers beforeSubmitPrompt with continue:true" "True" \
  "$(_cursor stage-marker.sh '{"hook_event_name":"beforeSubmitPrompt","prompt":"/temper:plan add auth","workspace_roots":["'"$WORKDIR"'"]}' \
     | python3 -c 'import json,sys; print(json.load(sys.stdin).get("continue"))' 2>/dev/null)"
# ...and the rule underneath it still did its job: the marker names the owed stage.
assert_eq "adapter hands the rule a Claude-shaped payload (marker records the stage)" "plan" \
  "$(python3 -c 'import json;print(json.load(open(".temper/pending-stage.json"))["stage"])' 2>/dev/null)"
# workspace_roots[0] is Cursor's name for the project dir; the rules read
# CLAUDE_PROJECT_DIR. Run the adapter from OUTSIDE the project so a $PWD fallback
# cannot pass this by accident — the marker must still land in $WORKDIR/.temper/.
rm -f "$WORKDIR/.temper/pending-stage.json"
( cd / && printf '%s' '{"hook_event_name":"beforeSubmitPrompt","prompt":"/temper:build x","workspace_roots":["'"$WORKDIR"'"]}' \
    | bash "$ADAPTER" stage-marker.sh ) >/dev/null 2>&1
assert_eq "adapter routes workspace_roots[0] to the rule as the project dir" "build" \
  "$(python3 -c 'import json; print(json.load(open("'"$WORKDIR"'/.temper/pending-stage.json"))["stage"])' 2>/dev/null)"

# Cursor's stop response is void — a rule that exits 2 there CANNOT block. The adapter
# must say so (stderr + hooks.log) and still exit 0; claiming a block that did not
# happen is the misrepresentation this whole surface exists to avoid.
setup
printf '%s' '{"hook_event_name":"beforeSubmitPrompt","prompt":"/temper:review x","workspace_roots":["'"$WORKDIR"'"]}' \
  | bash "$ADAPTER" stage-marker.sh >/dev/null 2>&1
STOP_ERR=$(printf '%s' '{"hook_event_name":"stop","status":"completed","workspace_roots":["'"$WORKDIR"'"]}' \
  | bash "$ADAPTER" verify-stage-gate.sh 2>&1 >/dev/null); STOP_RC=$?
assert_eq "adapter exits 0 on an unblockable stop verdict" "0" "$STOP_RC"
assert_eq "adapter labels an unblockable stop verdict advisory" "yes" \
  "$(echo "$STOP_ERR" | grep -q 'advisory' && echo yes || echo no)"
assert_eq "adapter records the advisory verdict in .temper/hooks.log" "yes" \
  "$(grep -q 'cursor-adapter advisory' "$WORKDIR/.temper/hooks.log" 2>/dev/null && echo yes || echo no)"

# Fail-open, every path — same contract as every other hook here.
assert_eq "adapter is permissive on unparseable stdin" "" \
  "$(echo 'not json' | bash "$ADAPTER" stage-marker.sh 2>/dev/null)"
assert_eq "adapter is permissive when the named rule does not exist" "allow" \
  "$(_cursor no-such-rule.sh '{"hook_event_name":"beforeShellExecution","command":"x"}' \
     | python3 -c 'import json,sys; print(json.load(sys.stdin).get("permission",""))' 2>/dev/null)"
assert_eq "adapter is permissive with no rule argument at all" "True" \
  "$(printf '%s' '{"hook_event_name":"beforeSubmitPrompt","prompt":"x"}' | bash "$ADAPTER" 2>/dev/null \
     | python3 -c 'import json,sys; print(json.load(sys.stdin).get("continue"))' 2>/dev/null)"
assert_exit "adapter always exits 0 (Cursor reads the verdict on stdout)" 0 \
  bash -c "printf '%s' '{\"hook_event_name\":\"stop\"}' | bash '$ADAPTER' verify-stage-gate.sh >/dev/null 2>&1"

# --- Multi-agent surface (v9.3.0) ---
# These are repo-shape assertions, not CLI behavior — but they guard the two failure
# modes that are INVISIBLE at runtime: a skill the `skills` CLI silently drops, and a
# per-agent surface that stops covering something. validate-plugin.sh asserts the same
# invariants in CI; duplicating the cheapest of them here means a contributor running
# only the unit tests still trips over them.
assert_eq "every skill carries the frontmatter the skills CLI requires" "" \
  "$(for f in "$REPO_ROOT"/skills/*/SKILL.md; do
       slug=$(basename "$(dirname "$f")")
       n=$(awk '/^---[[:space:]]*$/{k++; if(k==2)exit; next} k==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$f")
       d=$(awk '/^---[[:space:]]*$/{k++; if(k==2)exit; next} k==1 && /^description:/{print "y"; exit}' "$f")
       [[ "$n" == "$slug" && -n "$d" ]] || echo "$slug"
     done)"
assert_eq "the temper entry-point skill exists (skills-only installs depend on it)" "yes" \
  "$([[ -f "$REPO_ROOT/skills/temper/SKILL.md" ]] && echo yes || echo no)"
# A skills-only install has no scripts/temper. The entry-point skill must say so and
# refuse, rather than letting the model grade its own gates — the one failure Temper
# exists to prevent.
assert_eq "the entry-point skill refuses to run without the CLI" "yes" \
  "$(grep -q 'git clone https://github.com/galando/temper.git' "$REPO_ROOT/skills/temper/SKILL.md" \
     && grep -qi 'do \*\*not\*\* proceed\|Do \*\*not\*\* proceed' "$REPO_ROOT/skills/temper/SKILL.md" \
     && echo yes || echo no)"

assert_eq "every agent manifest agrees on the version" "" \
  "$(cd "$REPO_ROOT" && python3 -c "
import json
def ver(p):
    d = json.load(open(p))
    return d.get('version') or (d.get('plugins') or [{}])[0].get('version')
base = ver('.claude-plugin/plugin.json')
print(' '.join(p for p in ['plugin.json', '.cursor-plugin/plugin.json', '.codex-plugin/plugin.json',
                           '.agents/plugins/marketplace.json'] if ver(p) != base))")"

assert_eq ".opencode/skills is a symlink, never a copy" "yes" \
  "$([[ -L "$REPO_ROOT/.opencode/skills" && -d "$REPO_ROOT/.opencode/skills" ]] && echo yes || echo no)"

# Every command has a Gemini shim, and every shim POINTS at its command rather than
# restating it. A shim that grew a prompt body is the second copy that rotted the old
# .cursor/ export.
assert_eq "every command has a Gemini shim that points at it" "" \
  "$(for f in "$REPO_ROOT"/commands/*.md; do
       stem=$(basename "$f" .md)
       if [[ "$stem" == "temper" ]]; then shim="$REPO_ROOT/.gemini/commands/temper.toml"
       else shim="$REPO_ROOT/.gemini/commands/temper/$stem.toml"; fi
       [[ -f "$shim" ]] && grep -q "commands/$stem.md" "$shim" || echo "$stem"
     done)"
assert_eq "no Gemini shim carries a prompt body (all under 3KB)" "" \
  "$(find "$REPO_ROOT/.gemini/commands" -name '*.toml' -size +3k -printf '%f\n' 2>/dev/null)"

echo ""
echo "=== test-temper.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
