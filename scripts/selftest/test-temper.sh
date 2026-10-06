#!/usr/bin/env bash
#
# test-temper.sh — unit tests for scripts/temper (the deterministic spine).
#
# Plain-bash assertions, no test framework dependency (consistent with the rest of
# Temper's tooling). Runs entirely in a throwaway tmp dir; never touches the repo.
set -uo pipefail

# The repo root: this script's folder with the literal suffix /scripts/selftest removed.
unset CDPATH
TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${TESTS_DIR%/scripts/selftest}"
[[ "$REPO_ROOT" != "$TESTS_DIR" && -x "$REPO_ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the repo root from $TESTS_DIR"; exit 1; }
TEMPER="$REPO_ROOT/scripts/temper"
WORKDIR="$(mktemp -d)" || exit 1
WORKDIR="$(cd -P "$WORKDIR" && pwd)" || exit 1   # physical, as the scripts see their own folders
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
  cd "$WORKDIR" || exit 1   # never run the deletes below anywhere but the throwaway folder
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
**Author:** Demo Author <demo@example.com>
**Status:** accepted
**Created:** 2026-01-01
**Reviewer:** Demo Reviewer <rev@example.com>
**Complexity:** simple

## Problem
Users cannot do the demo thing today.

### Success Criteria
- [ ] AC-01 [required]: demo criterion one
  Why: keeps the demo flow honest
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: demo criterion two
  Why: second criterion for scenario parity
  Validate: scenario — traced to a test below

### Constraints
- keep the demo self-contained (proposed)

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior
- Must keep working: the existing suite

### Target Users
- developer: runs the demo → sees the output

### Open Questions

### Decisions

## Scenarios (BDD)
#### Happy Path
```gherkin
Scenario: first
  Given a demo
  When it runs
  Then it works
  Note: unit
  Covers: AC-01
```
```gherkin
Scenario: second
  Given a demo
  When it runs again
  Then it still works
  Note: unit
  Covers: AC-02
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
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

## Cross-Repo Search
- not available: no cross-repo search tool connected
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
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
assert_exit "review gate PASSes with no findings" 0 "$TEMPER" gate review
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
assert_exit "review gate FAILs on an open critical finding" 1 "$TEMPER" gate review

# --- review gate: a finding fixed in this run is resolved, not deleted (woningscout #984) ---
setup
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
"$TEMPER" evidence add --stage review --claim "missing null check" --severity high >/dev/null
assert_exit "evidence resolve needs --stage, --id and --fixed-by" 1 "$TEMPER" evidence resolve --stage review --id 1
assert_exit "evidence resolve rejects an unknown id" 1 "$TEMPER" evidence resolve --stage review --id 9 --fixed-by abc123
assert_exit "evidence resolve rejects an unknown stage" 1 "$TEMPER" evidence resolve --stage nope --id 1 --fixed-by abc123
assert_exit "review gate still FAILs before the finding is resolved" 1 "$TEMPER" gate review
assert_exit "evidence resolve marks the critical finding fixed" 0 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by abc123
assert_exit "evidence resolve refuses to resolve the same finding twice" 1 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by abc123
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
assert_exit "review gate PASSes once the only blocking finding is resolved" 0 "$TEMPER" gate review
assert_eq "the resolved row is still in the ledger" "3" "$("$TEMPER" evidence list --stage review --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
assert_eq "evidence list shows the id and the resolver" "yes" "$("$TEMPER" evidence list --stage review | grep '#1 .*\[resolved: abc123\]' >/dev/null && echo yes || echo no)"
assert_eq "the gate detail names the resolved count" "yes" "$("$TEMPER" gate review | grep '1 resolved in this run' >/dev/null && echo yes || echo no)"
"$TEMPER" evidence add --stage review --claim "second injection" --severity critical >/dev/null
assert_exit "a new unresolved critical finding FAILs the gate again" 1 "$TEMPER" gate review

# --- check gate: coverage threshold ---
setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 60 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
assert_exit "check gate FAILs below coverage threshold (60 < 80)" 1 "$TEMPER" gate check
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
assert_exit "check gate PASSes above coverage threshold (90 >= 80)" 0 "$TEMPER" gate check

# --- check gate: the coverage threshold is data, never Python source ---
# A threshold that closes the quote and calls open() would have written a file when the
# config value was spliced into the program text. Passed as argv it is just a string
# that is not a number: the gate FAILs and nothing is written.
setup
python3 - .claude/temper.config <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("  coverage-threshold: 80\n",
              "  coverage-threshold: 0') and open('threshold-injected','w').write('x') and float('0\n")
open(p, 'w').write(s)
PY
assert_eq "the quote-bearing threshold is read back unchanged" \
  "0') and open('threshold-injected','w').write('x') and float('0" "$("$TEMPER" config get check.coverage-threshold)"
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
rm -f threshold-injected
assert_exit "check gate FAILs on a quote-bearing coverage threshold" 1 "$TEMPER" gate check
assert_eq "a quote-bearing coverage threshold writes no file" "no" "$([[ -e threshold-injected ]] && echo yes || echo no)"
OUT=$("$TEMPER" gate check 2>&1; true)
assert_eq "the FAIL names the coverage row" "yes" \
  "$(echo "$OUT" | grep -q '\[x\] coverage >= threshold' && echo yes || echo no)"
assert_eq "still no file after the gate runs again" "no" "$([[ -e threshold-injected ]] && echo yes || echo no)"
rm -f threshold-injected

# --- check gate: scenarios must be traced to a test (the flagship "rate limiting" story) ---
setup
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
assert_exit "check gate FAILs when a scenario has no traced test (1/2 covered)" 1 "$TEMPER" gate check
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
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
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
"$TEMPER" gate check >/dev/null
assert_exit "commit gate PASSes once every upstream gate is green" 0 "$TEMPER" gate commit

setup
"$TEMPER" evidence add --stage review --claim "critical thing" --severity critical >/dev/null
assert_exit "commit gate FAILs with an unresolved review finding, no override" 1 "$TEMPER" gate commit
"$TEMPER" override review --reason "manually verified safe" >/dev/null
"$TEMPER" gate intent >/dev/null; "$TEMPER" gate plan >/dev/null; "$TEMPER" gate build >/dev/null 2>&1 || true
"$TEMPER" gate check >/dev/null 2>&1 || true
assert_eq "override is recorded and visible in report" "yes" "$("$TEMPER" report | grep 'overridden' >/dev/null && echo yes || echo no)"

# --- state: illegal transitions rejected, loop budget enforced ---
setup
assert_exit "state advance rejects an unknown stage name" 1 "$TEMPER" state advance not_a_real_stage build
assert_exit "state advance accepts a known stage" 0 "$TEMPER" state advance build_complete review
assert_exit "state loop allows iterations up to max-per-type" 0 "$TEMPER" state loop review build --reason r1
assert_exit "state loop allows the second iteration" 0 "$TEMPER" state loop review build --reason r2
assert_exit "state loop blocks the third iteration (max-per-type: 2)" 1 "$TEMPER" state loop review build --reason r3

# --- state loop: a /temper run clears the temper sequence from the target stage down ---
setup
"$TEMPER" evidence add --stage plan --claim "plan row" --exit 0 >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" state loop review build --reason r1 >/dev/null
assert_eq "a temper-run loop keeps the plan evidence above the target" "1" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/plan.json"))))')"
assert_eq "a temper-run loop clears build evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/build.json"))))')"
assert_eq "a temper-run loop clears review evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))')"
assert_eq "a temper-run loop clears check evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/check.json"))))')"

# --- state loop: a /temper:fix run clears build, review and check on a loop back to fix (woningscout #984) ---
setup
"$TEMPER" state init bug3 --command fix >/dev/null
"$TEMPER" evidence add --stage build --claim "regression test" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "regression test" --exit 0 --phase green >/dev/null
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
assert_exit "a fix run's review gate FAILs on the open finding" 1 "$TEMPER" gate review
assert_exit "state loop review fix is accepted in a fix run" 0 "$TEMPER" state loop review fix --reason "fix the injection"
assert_eq "a fix-run loop clears the build evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/build.json"))))')"
assert_eq "a fix-run loop clears the review evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))')"
assert_eq "a fix-run loop clears the check evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/check.json"))))')"
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
assert_exit "the review gate can pass again after the loop" 0 "$TEMPER" gate review
"$TEMPER" evidence add --stage review --claim "kept" --severity critical >/dev/null
"$TEMPER" state loop check fix --reason "second loop" >/dev/null
assert_eq "a fix-run loop back to fix from check also clears review" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))')"

# --- state get: bare call dumps the whole state; degrades cleanly on corrupted JSON ---
setup
assert_eq "state get (bare) dumps the whole state file" "yes" "$("$TEMPER" state get | grep '"spec": "demo"' >/dev/null && echo yes || echo no)"
echo '{"stage": "started", "spec": "demo"' > .temper/build-state.json
assert_exit "state get (bare) does not crash on a corrupted state file" 0 "$TEMPER" state get
assert_eq "state get (bare) falls back to {} on a corrupted state file" "yes" "$("$TEMPER" state get | grep '^{}$' >/dev/null && echo yes || echo no)"

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
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
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
# the CLI function; this installs the real hook (scripts/guards/install.sh) and runs a
# real `git commit`, the same way a human's `git commit` reaches it.
setup
git config user.email "test@example.com"
git config user.name "test"
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null
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
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
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
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null
python3 -c "
import json
d = json.load(open('.temper/build-state.json'))
d['stage'] = 'eval_complete'
json.dump(d, open('.temper/build-state.json', 'w'))
"
assert_exit "verify-tests-ran.sh no longer matches a raw, unhealed 'eval_complete'" 2 bash "$REPO_ROOT/scripts/guards/verify-tests-ran.sh"
"$TEMPER" state get stage >/dev/null   # a CLI touch heals the on-disk value
assert_eq "the stage forward-map is written through to disk" "check_complete" "$(python3 -c "import json; print(json.load(open('.temper/build-state.json'))['stage'])")"
assert_exit "verify-tests-ran.sh passes once the CLI has healed the state to check_complete" 0 bash "$REPO_ROOT/scripts/guards/verify-tests-ran.sh"

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
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
"$TEMPER" gate check >/dev/null
"$TEMPER" state loop check build --reason "regression found downstream" >/dev/null
assert_eq "state loop check->build auto-clears check evidence (check is downstream of build)" "[]" "$(cat .temper/evidence/check.json | tr -d '[:space:]')"
assert_exit "check gate FAILs closed again after the auto-clear (stale scenario coverage cannot mask a regression)" 1 "$TEMPER" gate check

# --- pack-discover.py reads only the project: nothing in the home folder and nothing in Temper's
# own folder. HOME names a plain fake home that holds one neutral note. An audit hook records every
# file and folder the script opens or lists (it fires for a path that does not exist too), so the
# home needs nothing in it: none may be in that home or in this plugin's folder. ---
setup
PACK_HOME="$WORKDIR/fake-home"
rm -rf "$PACK_HOME"
mkdir -p "$PACK_HOME/notes" .claude/commands
printf -- '---\ndescription: home note\n---\n' > "$PACK_HOME/notes/home-note.md"
printf -- '---\ndescription: local\n---\n' > .claude/commands/local-cmd.md
# audit-run.py <watched prefixes, '|' separated> <script>: runs the script and prints, on stderr,
# every open, scandir and listdir of a path under a watched prefix (the script file itself aside).
cat > "$WORKDIR/audit-run.py" <<'PY'
import runpy, sys
watch, script = sys.argv[1].split("|"), sys.argv[2]
seen = []
def hook(event, args):
    if event in ("open", "os.scandir", "os.listdir") and args and isinstance(args[0], str) \
            and args[0] != script and any(args[0].startswith(w) for w in watch):
        seen.append(event + " " + args[0])
sys.addaudithook(hook)
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit:
    pass
print("\n".join("READ " + s for s in seen) if seen else "NO READ", file=sys.stderr)
PY
PD_WD_REAL="$(cd "$WORKDIR" && pwd -P)"
PD_RR_REAL="$(cd "$REPO_ROOT" && pwd -P)"
PACK_OUT="$(HOME="$PACK_HOME" python3 -I "$WORKDIR/audit-run.py" \
  "$PACK_HOME|$PD_WD_REAL/fake-home|$REPO_ROOT|$PD_RR_REAL" "$REPO_ROOT/scripts/pack-discover.py" 2>"$WORKDIR/audit.txt")"
assert_eq "pack-discover opens and lists nothing in the home folder or in Temper's own folder" "NO READ" "$(cat "$WORKDIR/audit.txt")"
assert_eq "pack-discover prints only the project's rows, nothing from the home folder" "LOCAL_CMD|local-cmd" \
  "$(printf '%s\n' "$PACK_OUT" | cut -d'|' -f1,2 | paste -sd' ' -)"
# The audit hook sees reads: the same run, watching the project's own .claude folder, records them.
HOME="$PACK_HOME" python3 -I "$WORKDIR/audit-run.py" "$PD_WD_REAL/.claude" "$REPO_ROOT/scripts/pack-discover.py" >/dev/null 2>"$WORKDIR/audit.txt"
assert_eq "the audit hook records the project command the script reads" "1" \
  "$(grep -cxF "READ open $PD_WD_REAL/.claude/commands/local-cmd.md" "$WORKDIR/audit.txt")"
assert_eq "pack-discover's source asks for no home folder, environment or JSON file" "0" \
  "$(grep -cE 'expanduser|getenv|environ|\.json|GLOBAL_CMD' "$REPO_ROOT/scripts/pack-discover.py")"
rm -rf "$PACK_HOME" .claude/commands "$WORKDIR/audit.txt"

# --- pack-discover.py: each project target once, with its own description; a command and a skill
# that share a name are two rows; two runs print the same rows. ---
setup
mkdir -p .claude/commands .claude/skills/shared .claude/skills/other
printf -- '---\ndescription: "shared command"\n---\n' > .claude/commands/shared.md
printf -- '---\ndescription: b command\n---\n' > .claude/commands/b-cmd.md
printf -- '---\ndescription: shared skill | piped\n---\n' > .claude/skills/shared/SKILL.md
printf 'no frontmatter\n' > .claude/skills/other/SKILL.md
DEDUP_OUT="$(python3 "$REPO_ROOT/scripts/pack-discover.py")"
assert_eq "pack-discover prints each project command and skill once, commands first, each sorted by name" \
  "LOCAL_CMD|b-cmd|b command;LOCAL_CMD|shared|shared command;LOCAL_SKILL|other|;LOCAL_SKILL|shared|shared skill / piped" \
  "$(printf '%s\n' "$DEDUP_OUT" | awk -F'|' '{print $1 "|" $2 "|" $4}' | paste -sd';' -)"
assert_eq "pack-discover prints the full resolved path of the file a link reads" \
  "$PD_WD_REAL/.claude/commands/shared.md|$PD_WD_REAL/.claude/skills/shared/SKILL.md" \
  "$(printf '%s\n' "$DEDUP_OUT" | awk -F'|' '$2 == "shared" {print $3}' | paste -sd'|' -)"
assert_eq "pack-discover prints the same rows on every run" "$DEDUP_OUT" "$(python3 "$REPO_ROOT/scripts/pack-discover.py")"
rm -rf .claude/commands .claude/skills

# --- guard-entries.py: the Temper guard entries in the project's two settings files, each with its
# status. The plugin folder is the one that holds the script, found after following links. The
# commands are built at run time (GE_VAR is the plugin root variable's name), so no tracked file
# holds a plugin path form. GE_OLD stands for an earlier plugin folder. ---
setup
GE="$REPO_ROOT/scripts/guard-entries.py"
GE_VAR=CLAUDE_PLUGIN_ROOT
GE_PROJ="$WORKDIR/ge-project"
GE_OLD="$WORKDIR/ge-old-plugin"
GE_HOME="$WORKDIR/ge-home"
GE_OUTSIDE="$WORKDIR/ge-outside"
rm -rf "$GE_PROJ" "$GE_OLD" "$GE_HOME" "$GE_OUTSIDE" "$WORKDIR/ge-link" "$WORKDIR/ge-bin" "$WORKDIR/ge-proj-link"
mkdir -p "$GE_PROJ/.claude" "$GE_PROJ/tools/scripts/guards" "$GE_OLD/scripts/guards" "$GE_HOME" "$GE_OUTSIDE" "$WORKDIR/ge-bin"
printf 'x\n' > "$GE_OLD/scripts/guards/block-uncommitted-gate.sh"
ln -s "$REPO_ROOT" "$WORKDIR/ge-link"
ln -s "$GE" "$WORKDIR/ge-bin/guard-entries.py"
ln -s "$GE_PROJ" "$WORKDIR/ge-proj-link"
cat > "$GE_PROJ/.claude/settings.json" <<EOF
{"permissions": {"allow": []},
 "hooks": {
  "PreToolUse": [
   {"matcher": "Edit|Write", "hooks": [
     {"type": "command", "command": "bash \"$REPO_ROOT/scripts/guards/block-secrets.sh\""},
     {"type": "command", "command": "bash \"$WORKDIR/ge-link/scripts/guards/protect-regression-test.sh\""},
     {"type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/tools/block-secrets.sh\""},
     {"type": "command", "command": "\"\$CLAUDE_PROJECT_DIR\"/tools/block-protected-paths.sh"},
     {"type": "command", "command": "bash tools/block-secrets.sh"},
     {"type": "command", "command": "bash \"$GE_PROJ/tools/scripts/guards/block-secrets.sh\""},
     {"type": "command", "command": "bash \"$GE_OLD/scripts/a/b/block-secrets.sh\""},
     {"type": "command", "command": "bash ./my-lint.sh"}]},
   {"matcher": "Bash", "hooks": [
     {"type": "command", "command": "bash \"$GE_OLD/scripts/guards/block-uncommitted-gate.sh\""},
     {"type": "command", "command": "bash $GE_OLD/scripts/legacy/confirm-override.sh"},
     {"type": "command", "command": "bash \${$GE_VAR}/scripts/guards/confirm-override.sh"},
     {"type": "command", "command": "bash \"$REPO_ROOT/scripts/retired/run-formatter.sh\""}]}],
  "PostToolUse": [
   {"hooks": [{"type": "command", "command": "bash $REPO_ROOT/scripts/guards/run-formatter.sh"}]}]}}
EOF
cat > "$GE_PROJ/.claude/settings.local.json" <<EOF
{"hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [
  {"type": "command", "command": "bash \"$REPO_ROOT/scripts/guards/block-secrets.sh\""}]}]}}
EOF
GE_WANT="$(printf '%s\n' \
  ".claude/settings.json|PreToolUse|Edit|Write|$REPO_ROOT/scripts/guards/block-secrets.sh|current" \
  ".claude/settings.json|PreToolUse|Edit|Write|$WORKDIR/ge-link/scripts/guards/protect-regression-test.sh|current" \
  ".claude/settings.json|PreToolUse|Bash|$GE_OLD/scripts/guards/block-uncommitted-gate.sh|stale" \
  ".claude/settings.json|PreToolUse|Bash|$GE_OLD/scripts/legacy/confirm-override.sh|stale" \
  ".claude/settings.json|PreToolUse|Bash|\${$GE_VAR}/scripts/guards/confirm-override.sh|stale" \
  ".claude/settings.json|PreToolUse|Bash|$REPO_ROOT/scripts/retired/run-formatter.sh|stale" \
  ".claude/settings.json|PostToolUse||$REPO_ROOT/scripts/guards/run-formatter.sh|current" \
  ".claude/settings.local.json|PreToolUse|Edit|$REPO_ROOT/scripts/guards/block-secrets.sh|current")"
cd "$GE_PROJ" || exit 1
GE_OUT="$(HOME="$GE_HOME" python3 "$GE" 2>"$WORKDIR/ge-err.txt")"; GE_RC=$?
assert_eq "guard-entries lists both files' Temper guard entries in file order: current under this plugin folder (also through a link), stale for an earlier plugin folder, an older guard scripts folder, the plugin root variable and a missing script" \
  "$GE_WANT" "$GE_OUT"
assert_eq "guard-entries exits 0 and prints nothing on stderr when both files read" "0|" "$GE_RC|$(cat "$WORKDIR/ge-err.txt")"
assert_eq "guard-entries leaves the user's copies alone (the CLAUDE_PROJECT_DIR variable, a relative path, a path inside the project, a path deeper than one folder under scripts) and a hook that names no guard script" \
  "0" "$(printf '%s\n' "$GE_OUT" | grep -cE 'tools/|scripts/a/b/|my-lint')"
assert_eq "guard-entries run through a link finds the plugin folder the link points at" \
  "$GE_WANT" "$(HOME="$GE_HOME" python3 "$WORKDIR/ge-bin/guard-entries.py" 2>&1)"
assert_eq "guard-entries prints the same lines on every run" "$GE_OUT" "$(HOME="$GE_HOME" python3 "$GE" 2>/dev/null)"
# The home folder: refused by file identity, also when HOME spells it through a link.
GE_REFUSE="$(HOME="$GE_PROJ" python3 "$GE" 2>&1)"; GE_RC=$?
assert_eq "guard-entries refuses with exit 2 and one line when the project folder is the home folder" "2|1|1" \
  "$GE_RC|$(printf '%s\n' "$GE_REFUSE" | wc -l | tr -d ' ')|$(printf '%s\n' "$GE_REFUSE" | grep -c 'home folder')"
assert_exit "guard-entries refuses when HOME names the project folder through a link" 2 \
  env HOME="$WORKDIR/ge-proj-link" python3 "$GE"
# A file that is not JSON: named on stderr, exit 1, and the other file is still listed.
printf 'not json {\n' > .claude/settings.json
GE_OUT="$(HOME="$GE_HOME" python3 "$GE" 2>"$WORKDIR/ge-err.txt")"; GE_RC=$?
assert_eq "guard-entries names a settings file that is not JSON, exits 1, and still lists the other file" \
  "1|.claude/settings.local.json|PreToolUse|Edit|$REPO_ROOT/scripts/guards/block-secrets.sh|current|1" \
  "$GE_RC|$GE_OUT|$(grep -c '^guard-entries: \.claude/settings\.json is not valid JSON' "$WORKDIR/ge-err.txt")"
# Nothing outside the project is opened or listed: a settings file linked out of the project is
# named, never read. audit-outside.py <project> <script> runs the script and prints, on stderr,
# every open, scandir and listdir of a path outside that project (the script file itself and
# Python's own files, which load as the script runs, aside).
printf '{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "bash %s/scripts/guards/block-secrets.sh"}]}]}}\n' \
  "$REPO_ROOT" > "$GE_OUTSIDE/notes.json"
rm -f .claude/settings.json
ln -s "$GE_OUTSIDE/notes.json" .claude/settings.json
cat > "$WORKDIR/audit-outside.py" <<'PY'
import os, runpy, sys
project, script = os.path.realpath(sys.argv[1]), sys.argv[2]
own = tuple({os.path.realpath(p) + os.sep for p in (sys.prefix, sys.base_prefix, sys.exec_prefix, sys.base_exec_prefix)})
seen, busy = [], []
def hook(event, args):
    if busy or event not in ("open", "os.scandir", "os.listdir") or not args or not isinstance(args[0], str):
        return
    busy.append(1)
    try:
        path = os.path.realpath(os.path.abspath(args[0]))
        if path != os.path.realpath(script) and not path.startswith(project + os.sep) and not path.startswith(own):
            seen.append(event + " " + path)
    finally:
        busy.pop()
sys.addaudithook(hook)
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit:
    pass
print("\n".join("READ " + s for s in seen) if seen else "NO READ", file=sys.stderr)
PY
GE_PROJ_REAL="$(pwd -P)"
GE_OUT="$(HOME="$GE_HOME" python3 -I "$WORKDIR/audit-outside.py" "$GE_PROJ_REAL" "$GE" 2>"$WORKDIR/ge-audit.txt")"
assert_eq "guard-entries opens and lists nothing outside the project, the home folder and its own plugin folder included" \
  "NO READ" "$(grep -v '^guard-entries: ' "$WORKDIR/ge-audit.txt")"
assert_eq "guard-entries names a settings file that resolves outside the project instead of reading it" "1|.claude/settings.local.json" \
  "$(grep -c '^guard-entries: \.claude/settings\.json resolves outside the project folder' "$WORKDIR/ge-audit.txt")|$(printf '%s\n' "$GE_OUT" | cut -d'|' -f1)"
# The audit hook sees reads: the same run, told the project is another folder, records the one it opens.
HOME="$GE_HOME" python3 -I "$WORKDIR/audit-outside.py" "$GE_HOME" "$GE" >/dev/null 2>"$WORKDIR/ge-audit.txt"
assert_eq "the audit hook records the project settings file the script opens" "1" \
  "$(grep -cxF "READ open $GE_PROJ_REAL/.claude/settings.local.json" "$WORKDIR/ge-audit.txt")"
assert_eq "guard-entries' source opens a file in one place and never asks for the home folder's contents" "1|0" \
  "$(grep -c 'open(' "$GE")|$(grep -cE 'expanduser|listdir|scandir|glob|walk\(' "$GE")"
# The plugin folder inside the project: a copy of the script in vendor/temper decides by its own
# folder. Its scripts are Temper's (current when the file exists), another path in the project is the
# user's, and this checkout, outside that project, is an earlier plugin folder.
GE_IN="$WORKDIR/ge-inside"
rm -rf "$GE_IN"
mkdir -p "$GE_IN/.claude" "$GE_IN/vendor/temper/scripts/guards"
cp "$GE" "$GE_IN/vendor/temper/scripts/guard-entries.py"
printf 'x\n' > "$GE_IN/vendor/temper/scripts/guards/block-secrets.sh"
cat > "$GE_IN/.claude/settings.local.json" <<EOF
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "bash \"$GE_IN/vendor/temper/scripts/guards/block-secrets.sh\""},
  {"type": "command", "command": "bash \"$GE_IN/vendor/temper/scripts/guards/run-formatter.sh\""},
  {"type": "command", "command": "bash \"$GE_IN/tools/scripts/guards/block-secrets.sh\""},
  {"type": "command", "command": "bash \"$REPO_ROOT/scripts/guards/block-secrets.sh\""}]}]}}
EOF
cd "$GE_IN" || exit 1
assert_eq "guard-entries with the plugin folder inside the project: its scripts are Temper's, current or stale, the project's own path is the user's" \
  "$(printf '%s\n' \
    ".claude/settings.local.json|PreToolUse|Bash|$GE_IN/vendor/temper/scripts/guards/block-secrets.sh|current" \
    ".claude/settings.local.json|PreToolUse|Bash|$GE_IN/vendor/temper/scripts/guards/run-formatter.sh|stale" \
    ".claude/settings.local.json|PreToolUse|Bash|$REPO_ROOT/scripts/guards/block-secrets.sh|stale")" \
  "$(HOME="$GE_HOME" python3 "$GE_IN/vendor/temper/scripts/guard-entries.py" 2>&1)"
cd "$WORKDIR" || exit 1
rm -rf "$GE_PROJ" "$GE_OLD" "$GE_HOME" "$GE_OUTSIDE" "$GE_IN" "$WORKDIR/ge-link" "$WORKDIR/ge-bin" "$WORKDIR/ge-proj-link" \
  "$WORKDIR/ge-err.txt" "$WORKDIR/ge-audit.txt" "$WORKDIR/audit-outside.py"

# --- stage-marker.sh + verify-stage-gate.sh: the standalone-stage gate guarantee ---
# stage-marker records the gate a /temper:{stage} session owes; verify-stage-gate blocks
# Stop until gates.json carries a verdict for it (any verdict), failing open after 2
# blocks. See docs/decisions/0005-deterministic-stage-gate-enforcement.md.
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/guards/verify-stage-gate.sh"

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

# --- temper model: config override > the stage brief's frontmatter, resolved in bash ---
setup
# Defaults come from the real stage briefs' frontmatter — no table in the CLI to drift.
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
SHIELD="$REPO_ROOT/scripts/guards/protect-regression-test.sh"
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
**Author:** A Author <a@example.com>
**Created:** 2026-01-01
**Reviewer:** R Reviewer <r@example.com>

## Problem
Support spends a third of call time on status-only queries.

### Success Criteria
- [ ] AC-01 [required]: status visible in the portal
  Why: cuts per-call handle time
  Validate: scenario — covered later
- [ ] AC-02 [optional]: status emailed nightly
  Why: nice-to-have digest
  Validate: manual — checked by hand

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior

### Target Users
- support agent: opens the portal → sees status without a call

### Open Questions

## Source Traceability
### Context Sources
- none: description only — nothing linked
EOF
assert_exit "intent gate PASSes with a real Problem, a criterion, and a Status header" 0 "$TEMPER" gate intent
python3 -c "
s = open('.temper/specs/demo/intent.md').read()
open('.temper/specs/demo/intent.md','w').write(s.replace('**Status:** draft\n',''))
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
import re
s = open('.temper/specs/demo/intent.md').read()
# The template's Problem placeholder, which may span lines, is replaced by one real line.
s = re.sub(r'(?m)(^#+ *Problem *\n\s*)\{[^{}]*\}',
           lambda m: m.group(1) + 'Handlers spend a third of call time on status-only queries.', s, count=1)
open('.temper/specs/demo/intent.md','w').write(s)
"
OUT=$("$TEMPER" gate intent 2>&1; true)
assert_eq "the filled Problem counts as content" "yes" "$(echo "$OUT" | grep -q '\[v\] problem stated' && echo yes || echo no)"
assert_exit "a template-verbatim intent with only the Problem filled still FAILs" 1 "$TEMPER" gate intent
assert_eq "placeholder criteria bullets are not counted" "yes" "$(echo "$OUT" | grep -q 'no real success criteria' && echo yes || echo no)"
assert_eq "the placeholder Status line is not accepted" "yes" "$(echo "$OUT" | grep -q 'placeholder doesn.t count' && echo yes || echo no)"

# temper report renders the intent stage (verdict + requirement rows).
setup
"$TEMPER" gate intent >/dev/null
# grep without -q: under `pipefail`, `grep -q` exits on the first match and the report's
# python still writing gets SIGPIPE, which turned this into a timing-dependent failure
# on a loaded machine. Reading to EOF makes the pipeline's status grep's own.
assert_eq "temper report renders the intent row" "yes" "$("$TEMPER" report | grep '^intent' >/dev/null && echo yes || echo no)"

# temper report from a project whose path holds quotes: the ledger paths cross as argv,
# so a quote in the folder name cannot end the program text early.
QUOTED_DIR="$WORKDIR/it's a \"quoted\" project"
mkdir -p "$QUOTED_DIR/.temper"
cd "$QUOTED_DIR" || exit 1
printf '%s\n' '{"intent": {"verdict": "FAIL", "requirements": [{"name": "demo row", "pass": false, "detail": "d"}], "ts": "t"}}' > .temper/gates.json
printf '%s\n' '[{"stage": "intent", "reason": "r", "by": "b", "ts": "t"}]' > .temper/overrides.json
assert_exit "temper report runs when the project path holds a quote" 0 "$TEMPER" report
assert_eq "temper report reads gates.json from a quoted project path" "yes" \
  "$("$TEMPER" report | grep 'demo row' >/dev/null && echo yes || echo no)"
assert_eq "temper report reads overrides.json from a quoted project path" "yes" \
  "$("$TEMPER" report | grep '^intent *FAIL (overridden)' >/dev/null && echo yes || echo no)"
cd "$WORKDIR" || exit 1
rm -rf "$QUOTED_DIR"

# The commit gate demands an intent verdict exactly when intent.md exists.
setup
"$TEMPER" gate plan >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 1 --phase red >/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --exit 0 --phase green >/dev/null
"$TEMPER" gate build >/dev/null
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
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
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
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
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" gate review >/dev/null
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null
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

# The command names the CLI by the unbraced plugin root variable, written here at run time.
CO_VAR=CLAUDE_PLUGIN_ROOT
OUT=$(printf '{"tool_input": {"command": "$%s/scripts/temper override review --reason x"}}' "$CO_VAR" | bash "$CONFIRM")
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

# install.sh: respect an existing core.hooksPath (husky/lefthook) — install where git
# actually looks, not the ignored .git/hooks folder (which would make the gate inert).
setup
git config user.email "test@example.com"
git config user.name "test"
rm -f .git/hooks/pre-commit    # clear any hook a prior test left in the shared WORKDIR
mkdir -p .husky
git config core.hooksPath .husky
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "install.sh honors core.hooksPath — hook lands where git looks" "yes" \
  "$([[ -f .husky/pre-commit ]] && grep -q 'installed by scripts/guards/install.sh' .husky/pre-commit && echo yes || echo no)"
assert_eq "install.sh does NOT write the ignored .git/hooks/pre-commit when core.hooksPath is set" "yes" \
  "$([[ ! -f .git/hooks/pre-commit ]] && echo yes || echo no)"
git config --unset core.hooksPath 2>/dev/null || true

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
assert_eq "a CLI reached through a symlink resolves a model from its own folder, with no CLAUDE_PLUGIN_ROOT" "$("$TEMPER" model plan)" \
  "$(env -u CLAUDE_PLUGIN_ROOT "$WORKDIR/bin/temper" model plan)"
assert_exit "a CLI reached through a symlink loads acceptance.py by its full path, with no CLAUDE_PLUGIN_ROOT" 0 \
  env -u CLAUDE_PLUGIN_ROOT "$WORKDIR/bin/temper" gate plan
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
  "$(env -u CLAUDE_PLUGIN_ROOT "$WORKDIR/bin/chained-temper" model plan)"
assert_eq "a CLAUDE_PLUGIN_ROOT naming another folder is ignored by the CLI" "$("$TEMPER" model plan)" \
  "$(CLAUDE_PLUGIN_ROOT=/nonexistent "$WORKDIR/bin/chained-temper" model plan)"
assert_eq "the CLI never reads CLAUDE_PLUGIN_ROOT" "0" "$(grep -c 'CLAUDE_PLUGIN_ROOT' "$TEMPER")"

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

# --- install.sh: literal targets, the paths it runs written in full, refusals ---
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -f .git/hooks/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "install.sh writes .git/hooks/pre-commit by default" "yes" "$([[ -x .git/hooks/pre-commit ]] && echo yes || echo no)"
assert_eq "the hook carries the CLI path written out in full" "yes" \
  "$(grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/hooks/pre-commit && echo yes || echo no)"
assert_eq "the hook carries each guard script path written out in full" "yes" \
  "$(grep -qxF "SECRETS_SCRIPT=$(printf '%q' "$REPO_ROOT/scripts/guards/block-secrets.sh")" .git/hooks/pre-commit \
     && grep -qxF "TESTS_RAN_SCRIPT=$(printf '%q' "$REPO_ROOT/scripts/guards/verify-tests-ran.sh")" .git/hooks/pre-commit && echo yes || echo no)"
assert_eq "the hook has no environment override of a folder and works out no folder" "0" \
  "$(grep -cE 'TEMPER_HOOKS_DIR|dirname' .git/hooks/pre-commit)"
# An install from before 9.6.5 is recognized by its "Temper native pre-commit hook" line: it is
# replaced in place with no backup, and its embedded folder is reported as stale.
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by an older installer).
TEMPER_HOOKS_DIR="${TEMPER_HOOKS_DIR:-/old/plugin/scripts/old-guards}"
EOF
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1)
assert_eq "an older Temper hook is reported as a stale path" "yes" \
  "$(echo "$OUT" | grep -q 'stale plugin path' && echo "$OUT" | grep -q 'embedded: /old/plugin/scripts/old-guards' && echo yes || echo no)"
assert_eq "an older Temper hook is replaced in place, with no backup" "0" \
  "$(find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' | wc -l | tr -d ' ')"
assert_eq "the replaced hook carries the current CLI path" "yes" \
  "$(grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/hooks/pre-commit && echo yes || echo no)"
python3 - <<'EOF'
import re
p = '.git/hooks/pre-commit'
s = open(p).read()
open(p, 'w').write(re.sub(r'(?m)^TEMPER_CLI=.*$', 'TEMPER_CLI=/moved/plugin/scripts/temper', s))
EOF
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1)
assert_eq "a moved CLI path is reported as stale and the current one written" "yes" \
  "$(echo "$OUT" | grep -q 'embedded: /moved/plugin/scripts/temper' && grep -qxF "TEMPER_CLI=$(printf '%q' "$REPO_ROOT/scripts/temper")" .git/hooks/pre-commit && echo yes || echo no)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1)
assert_eq "a current hook is not reported as stale" "no" "$(echo "$OUT" | grep -q 'stale plugin path' && echo yes || echo no)"
# A symlinked pre-commit (here to an older Temper hook) is replaced by a regular file; the file
# it pointed at is left as it was.
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (an older install, linked).\necho linked\n' > "$WORKDIR/linked-hook.sh"
LINKED_SUM="$(cksum < "$WORKDIR/linked-hook.sh")"
rm -f .git/hooks/pre-commit
ln -s "$WORKDIR/linked-hook.sh" .git/hooks/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "a symlinked pre-commit becomes a regular file, and its target is untouched" "yes|yes" \
  "$([[ -f .git/hooks/pre-commit && ! -L .git/hooks/pre-commit ]] && echo yes || echo no)|$([[ "$(cksum < "$WORKDIR/linked-hook.sh")" == "$LINKED_SUM" ]] && echo yes || echo no)"
rm -f "$WORKDIR/linked-hook.sh"
# core.hooksPath: accepted only inside the repository, with no '..', in a folder with no JSON file.
rm -f .git/hooks/pre-commit
git config core.hooksPath ../outside-hooks
assert_exit "install.sh refuses a core.hooksPath with '..'" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1; true)
assert_eq "the refusal prints the hook lines to add by hand" "yes" \
  "$(echo "$OUT" | grep -q 'Nothing was written' && echo "$OUT" | grep -q 'gate commit' && echo yes || echo no)"
assert_eq "the refusal writes nothing" "no|no" \
  "$([[ -e "${WORKDIR%/*}/outside-hooks" ]] && echo yes || echo no)|$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)"
git config core.hooksPath /nonexistent-temper-hooks
assert_exit "install.sh refuses an absolute core.hooksPath outside the repository" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
assert_eq "the refusal of an outside folder writes nothing" "no" "$([[ -e /nonexistent-temper-hooks ]] && echo yes || echo no)"
git config core.hooksPath '~/.temper-test-hooks'
assert_exit "install.sh refuses a core.hooksPath under the home folder" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
mkdir -p cfg-hooks
echo '{}' > cfg-hooks/settings.json
git config core.hooksPath cfg-hooks
assert_exit "install.sh refuses a hooks folder that holds a JSON file" 1 bash "$REPO_ROOT/scripts/guards/install.sh"
assert_eq "no pre-commit is written into a folder that holds a JSON file" "no" "$([[ -e cfg-hooks/pre-commit ]] && echo yes || echo no)"
git config core.hooksPath "$(git rev-parse --show-toplevel)/abs-hooks"
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "an absolute core.hooksPath inside the repository is accepted and made relative" "yes" \
  "$([[ -x abs-hooks/pre-commit ]] && echo yes || echo no)"
git config core.hooksPath ./dot-hooks/
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "a core.hooksPath with a leading ./ and a trailing / is accepted" "yes" "$([[ -x dot-hooks/pre-commit ]] && echo yes || echo no)"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-git-hooks
bash "$REPO_ROOT/scripts/guards/install.sh" --global >/dev/null 2>&1
assert_eq "--global writes .git/temper-git-hooks/pre-commit and points core.hooksPath at its absolute path" "yes|$(pwd -P)/.git/temper-git-hooks" \
  "$([[ -x .git/temper-git-hooks/pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-git-hooks abs-hooks dot-hooks cfg-hooks "$WORKDIR/outside"

# --- install.sh and the commit guards: no write through a link, the installer's own symlinks,
# chained hooks, worktrees, --global over a set core.hooksPath, staged-only secret scans, the
# CLI's full path in guard messages, and the CLI's refusal of an unsafe .temper folder ---
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/hooks/pre-commit .git/hooks/pre-commit.bak.* .git/temper-git-hooks
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
# A pre-commit that is a hard link to a plugin file (here one that reads as an older Temper
# hook, so the installer replaces it): the new hook is moved into place, so the plugin file
# keeps its text (install.sh itself, which is not a Temper hook and is refused, included).
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (plugin data)\n' > "$I_PLUG/inner/hard-target"
ln "$I_PLUG/inner/hard-target" .git/hooks/pre-commit
bash "$I_INSTALL" >/dev/null 2>&1
assert_eq "install.sh never writes through a hard-linked pre-commit; the plugin file keeps its text" "# Temper native pre-commit hook (plugin data)|2|yes" \
  "$(sed -n 2p "$I_PLUG/inner/hard-target")|$(wc -l < "$I_PLUG/inner/hard-target" | tr -d ' ')|$(grep -qxF "$I_CLI_LINE" .git/hooks/pre-commit && echo yes || echo no)"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
I_SUM="$(cksum < "$I_INSTALL")"
ln "$I_INSTALL" .git/hooks/pre-commit
bash "$I_INSTALL" >/dev/null 2>&1
assert_eq "a pre-commit hard-linked to install.sh itself leaves install.sh as it was" "$I_SUM" "$(cksum < "$I_INSTALL")"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
# install.sh reached through a chain of symlinks finds the real plugin folder.
mkdir -p "$WORKDIR/inst-bin"
ln -s "$I_INSTALL" "$WORKDIR/inst-bin/temper-install"
ln -s temper-install "$WORKDIR/inst-bin/chained-install"
bash "$WORKDIR/inst-bin/chained-install" >/dev/null 2>&1
assert_eq "install.sh run through a chain of symlinks writes the real CLI path into the hook" "yes" \
  "$(grep -qxF "$I_CLI_LINE" .git/hooks/pre-commit 2>/dev/null && echo yes || echo no)"
rm -rf "$WORKDIR/inst-bin" .git/hooks/pre-commit
# A copy outside a scripts/guards folder (even with a CLI where the failed suffix strip would
# look for one), or a plugin whose CLI does not run, writes no hook.
mkdir -p "$WORKDIR/loose-installer/scripts"
cp "$I_INSTALL" "$WORKDIR/loose-installer/install.sh"
cp "$TEMPER" "$WORKDIR/loose-installer/scripts/temper"
assert_exit "install.sh outside a plugin's scripts/guards folder refuses" 1 bash "$WORKDIR/loose-installer/install.sh"
chmod -x "$I_PLUG/scripts/temper"
assert_exit "install.sh refuses when the plugin's CLI is not executable" 1 bash "$I_INSTALL"
chmod +x "$I_PLUG/scripts/temper"
assert_eq "neither refusal writes a hook" "no" "$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)"
rm -rf "$WORKDIR/loose-installer"
# A refusal prints the hook lines between a BEGIN and an END line, ready to copy.
git config core.hooksPath ../outside-hooks
OUT=$(bash "$I_INSTALL" 2>&1; true)
git config --unset core.hooksPath
I_LINES="$(printf '%s\n' "$OUT" | sed -n '/^----- BEGIN Temper pre-commit hook lines -----$/,/^----- END Temper pre-commit hook lines -----$/p' | sed '1d;$d')"
printf '%s\n' "$I_LINES" > "$WORKDIR/hook-lines.sh"
assert_eq "a refusal prints the whole hook, a valid bash script, between a BEGIN and an END line" "#!/usr/bin/env bash|yes|yes" \
  "$(head -1 "$WORKDIR/hook-lines.sh")|$(grep -qxF "$I_CLI_LINE" "$WORKDIR/hook-lines.sh" && echo yes || echo no)|$(bash -n "$WORKDIR/hook-lines.sh" 2>/dev/null && echo yes || echo no)"
rm -f "$WORKDIR/hook-lines.sh"
# A run from a folder inside the plugin's folder whose repository's top is elsewhere (an
# installed copy inside some repository) writes nothing.
assert_exit "install.sh refuses a run from inside the plugin's folder when the repository's top is elsewhere" 1 \
  bash -c "cd '$I_PLUG/inner' && bash '$I_INSTALL'"
assert_eq "that refusal writes no hook into the enclosing repository" "no" "$([[ -e .git/hooks/pre-commit ]] && echo yes || echo no)"
# --global with a .git/config that is a symlink into the plugin's folder writes nothing.
cp .git/config "$I_PLUG/inner/config"
I_CFG_SUM="$(cksum < "$I_PLUG/inner/config")"
mv .git/config .git/config-saved
ln -s "$I_PLUG/inner/config" .git/config
assert_exit "--global refuses a .git/config that is a symlink into the plugin's own folder" 1 bash "$I_INSTALL" --global
assert_eq "the plugin file behind .git/config is left as it was, and no hook folder is made" "$I_CFG_SUM|no" \
  "$(cksum < "$I_PLUG/inner/config")|$([[ -e .git/temper-git-hooks ]] && echo yes || echo no)"
rm -f .git/config
mv .git/config-saved .git/config
# A pre-commit hook that is not Temper's is refused, even with pre-commit.bak names planted as
# symlinks into the plugin's folder (as an older installer named its backups): nothing is
# written through them, and the hook stays as it was.
printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo 'plugin data' > "$I_PLUG/inner/bak-target"
for ts in $(python3 -c 'import time; t = time.time(); print(" ".join(time.strftime("%Y%m%d%H%M%S", time.localtime(t + i)) for i in range(-1, 20)))'); do
  ln -sf "$I_PLUG/inner/bak-target" ".git/hooks/pre-commit.bak.$ts"
done
assert_exit "install.sh refuses a hook that is not Temper's, with backup names planted as symlinks into the plugin's own folder" 1 bash "$I_INSTALL"
assert_eq "the plugin file behind the backup name and the existing hook are left as they were" "plugin data|exit 0" \
  "$(cat "$I_PLUG/inner/bak-target")|$(sed -n 2p .git/hooks/pre-commit)"
rm -f .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
# --global refuses when core.hooksPath is already set: the default mode installs into that folder.
mkdir -p .husky
git config core.hooksPath .husky
assert_exit "--global refuses when core.hooksPath is already set" 1 bash "$I_INSTALL" --global
assert_eq "the refused --global leaves core.hooksPath as it was and writes no hook" ".husky|no" \
  "$(git config --get core.hooksPath)|$([[ -e .git/temper-git-hooks/pre-commit ]] && echo yes || echo no)"
git config --unset core.hooksPath
rm -rf .husky
# --global runs again over the core.hooksPath it set itself.
rm -f .git/hooks/pre-commit
bash "$I_INSTALL" --global >/dev/null 2>&1
assert_exit "--global runs again over the core.hooksPath it set itself" 0 bash "$I_INSTALL" --global
_i_gates PASS
assert_exit "the --global hook passes a green gate" 0 bash .git/temper-git-hooks/pre-commit
git config --unset core.hooksPath
rm -rf .git/temper-git-hooks .git/hooks/pre-commit
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
rm -f .git/hooks/pre-commit
bash "$I_RP/scripts/guards/install.sh" >/dev/null 2>&1
OUT=$(bash .git/hooks/pre-commit 2>&1); I_RC=$?
assert_eq "the installed hook blocks, naming the symlink to remove, when the CLI exits 3 during an active run" "1|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'remove the symlink')"
OUT=$(echo '{"tool_input": {"command": "git commit -m x"}}' | bash "$I_RP/scripts/guards/block-uncommitted-gate.sh" 2>&1); I_RC=$?
assert_eq "the in-agent commit gate blocks, naming the symlink to remove, when the CLI exits 3 during an active run" "2|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'remove the symlink')"
mv .temper/build-state.json "$WORKDIR/build-state.saved"
OUT=$(bash .git/hooks/pre-commit 2>&1); I_RC=$?
assert_eq "the installed hook fails open with one warning line when the CLI exits 3 and no run is active" "0|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'commit gate was skipped')"
OUT=$(echo '{"tool_input": {"command": "git commit -m x"}}' | bash "$I_RP/scripts/guards/block-uncommitted-gate.sh" 2>&1); I_RC=$?
assert_eq "the in-agent commit gate fails open with one warning line when the CLI exits 3 and no run is active" "0|1" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -c 'commit gate was skipped')"
mv "$WORKDIR/build-state.saved" .temper/build-state.json
rm -rf "$I_RP" .git/hooks/pre-commit
# With CDPATH set, the scripts still find their own folder when called by a relative path.
OUT=$(cd "$WORKDIR" && CDPATH="$WORKDIR" bash install-plugin/scripts/guards/install.sh 2>&1); I_RC=$?
assert_eq "with CDPATH set, install.sh called by a relative path writes the real CLI path" "0|yes" \
  "$I_RC|$(grep -qxF "$I_CLI_LINE" .git/hooks/pre-commit 2>/dev/null && echo yes || echo no)"
assert_eq "the installed hook runs block-secrets with --staged" "yes" \
  "$(grep -qF 'bash "$SECRETS_SCRIPT" --staged' .git/hooks/pre-commit && echo yes || echo no)"
_i_gates FAIL
assert_exit "with CDPATH set, uncommitted-gate called by a relative path still blocks a red gate" 2 \
  bash -c "cd '$WORKDIR' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | CDPATH='$WORKDIR' bash install-plugin/scripts/guards/block-uncommitted-gate.sh"
rm -f .git/hooks/pre-commit
# A linked worktree: the hook goes into the repository's own hooks folder, once, and gates
# commits made in the worktree.
I_MAIN="$WORKDIR/wt-main"
I_FEAT="$WORKDIR/wt-feat"
rm -rf "$I_MAIN" "$I_FEAT"
git init -q "$I_MAIN"
git -C "$I_MAIN" config user.email "test@example.com"
git -C "$I_MAIN" config user.name "test"
git -C "$I_MAIN" commit -q --allow-empty -m init
git -C "$I_MAIN" worktree add -q "$I_FEAT" >/dev/null 2>&1
assert_exit "in a linked worktree, install.sh installs into the repository's own hooks folder" 0 \
  bash -c "cd '$I_FEAT' && bash '$I_INSTALL'"
assert_eq "the hook lands in the main checkout's .git/hooks" "yes" \
  "$(grep -qxF "$I_CLI_LINE" "$I_MAIN/.git/hooks/pre-commit" 2>/dev/null && echo yes || echo no)"
OUT=$(cd "$I_FEAT" && bash "$I_INSTALL" 2>&1); I_RC=$?
assert_eq "a second run in the worktree says the hook is already installed and exits 0" "0|yes" \
  "$I_RC|$(printf '%s\n' "$OUT" | grep -q 'already installed for this worktree' && echo yes || echo no)"
(cd "$I_FEAT" && "$I_PLUG/scripts/temper" init >/dev/null && _i_gates FAIL && echo x > wt.txt && git add wt.txt)
assert_exit "the hook blocks a real git commit on a red gate in the worktree" 1 git -C "$I_FEAT" commit -q -m wt
# A linked worktree whose repository keeps its git folder inside the plugin's folder is refused.
git init -q "$I_PLUG"
git -C "$I_PLUG" config user.email "test@example.com"
git -C "$I_PLUG" config user.name "test"
git -C "$I_PLUG" commit -q --allow-empty -m init
git -C "$I_PLUG" worktree add -q "$WORKDIR/plug-wt" >/dev/null 2>&1
assert_exit "in a linked worktree whose repository's git folder is inside the plugin's folder, install.sh refuses" 1 \
  bash -c "cd '$WORKDIR/plug-wt' && bash '$I_INSTALL'"
assert_eq "that refusal writes nothing in the plugin's git folder" "no" \
  "$([[ -e "$I_PLUG/.git/hooks/pre-commit" ]] && echo yes || echo no)"
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
G_PLUG="$WORKDIR/guard-plugin"
rm -rf "$G_PLUG"
mkdir -p "$G_PLUG/scripts/guards" "$G_PLUG/inner/code"
cp "$REPO_ROOT/scripts/guards/install.sh" "$G_PLUG/scripts/guards/install.sh"
# The installer refuses to write a hook whose CLI is missing, so the throwaway plugin holds one:
# each refusal below then refuses for the reason it names.
cp "$TEMPER" "$G_PLUG/scripts/temper"
G_INSTALL="$G_PLUG/scripts/guards/install.sh"
# install.sh: a core.hooksPath that leads into the plugin folder, directly or through a symlink.
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
mv .git/hooks .git/hooks-saved
ln -s "$G_PLUG/inner/code" .git/hooks
assert_exit "install.sh refuses a .git/hooks that is a symlink into the plugin's own folder" 1 bash "$G_INSTALL"
rm -f .git/hooks
mv .git/hooks-saved .git/hooks
assert_eq "none of these refusals writes or creates anything in the plugin's folder" "no|no" \
  "$([[ -e "$G_PLUG/inner/code/pre-commit" ]] && echo yes || echo no)|$([[ -e "$G_PLUG/inner/code/new" ]] && echo yes || echo no)"
# A pre-commit that is a symlink into the plugin folder (to a file that reads as an older Temper
# hook, so the installer replaces it) is replaced, never written through.
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (plugin file)\n' > "$G_PLUG/inner/code/pre-commit"
rm -f .git/hooks/pre-commit
ln -s "$G_PLUG/inner/code/pre-commit" .git/hooks/pre-commit
bash "$G_INSTALL" >/dev/null 2>&1
assert_eq "a pre-commit symlink into the plugin folder becomes a regular file; the plugin file is untouched" "yes|# Temper native pre-commit hook (plugin file)|2" \
  "$([[ -f .git/hooks/pre-commit && ! -L .git/hooks/pre-commit ]] && echo yes || echo no)|$(sed -n 2p "$G_PLUG/inner/code/pre-commit")|$(wc -l < "$G_PLUG/inner/code/pre-commit" | tr -d ' ')"
rm -f "$G_PLUG/inner/code/pre-commit" .git/hooks/pre-commit .git/hooks/pre-commit.bak.*
# The plugin's own repository: its .git folder is the one place in the plugin folder allowed.
git init -q "$G_PLUG"
git -C "$G_PLUG" config core.hooksPath inner/code
assert_exit "in the plugin's own repository, a core.hooksPath into its folder is refused" 1 \
  bash -c "cd '$G_PLUG' && bash scripts/guards/install.sh"
git -C "$G_PLUG" config --unset core.hooksPath
assert_exit "in the plugin's own repository, the default .git/hooks is accepted" 0 \
  bash -c "cd '$G_PLUG' && bash scripts/guards/install.sh"
assert_eq "the hook lands in the plugin repository's .git/hooks, and nowhere else in it" "yes|no" \
  "$([[ -x "$G_PLUG/.git/hooks/pre-commit" ]] && echo yes || echo no)|$([[ -e "$G_PLUG/inner/code/pre-commit" ]] && echo yes || echo no)"
# A repository inside the plugin folder is refused outright.
mkdir -p "$G_PLUG/inner/proj"
git init -q "$G_PLUG/inner/proj"
assert_exit "install.sh refuses a repository that lies inside the plugin's own folder" 1 \
  bash -c "cd '$G_PLUG/inner/proj' && bash '$G_INSTALL'"
assert_eq "the refused repository inside the plugin gets no hook" "no" \
  "$([[ -e "$G_PLUG/inner/proj/.git/hooks/pre-commit" ]] && echo yes || echo no)"
# GIT_DIR, GIT_WORK_TREE and GIT_CONFIG do not move the target.
rm -f "$G_PLUG/.git/hooks/pre-commit" .git/hooks/pre-commit
env GIT_DIR="$G_PLUG/.git" GIT_WORK_TREE="$G_PLUG" bash "$G_INSTALL" >/dev/null 2>&1
assert_eq "with GIT_DIR and GIT_WORK_TREE on the plugin, the hook lands in the current folder's repository" "yes|no" \
  "$([[ -x .git/hooks/pre-commit ]] && echo yes || echo no)|$([[ -e "$G_PLUG/.git/hooks/pre-commit" ]] && echo yes || echo no)"
git init -q --bare "$G_PLUG/inner/gitdir"
env GIT_DIR="$G_PLUG/inner/gitdir" GIT_WORK_TREE="$WORKDIR" GIT_CONFIG="$G_PLUG/inner/code/config" \
  bash "$G_INSTALL" --global >/dev/null 2>&1
assert_eq "--global with GIT_DIR and GIT_CONFIG in the plugin folder sets core.hooksPath in this repository only" \
  "$(pwd -P)/.git/temper-git-hooks|none|no" \
  "$(git config --local --get core.hooksPath)|$(git --git-dir="$G_PLUG/inner/gitdir" config --get core.hooksPath || echo none)|$([[ -e "$G_PLUG/inner/code/config" ]] && echo yes || echo no)"
git config --unset core.hooksPath
rm -rf .git/temper-git-hooks linked-hooks rel-dir
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
assert_exit "with python3, the installed hook blocks on a red gate" 1 "$BASH_BIN" .git/hooks/pre-commit
assert_exit "without python3 on PATH, the installed hook fails open" 0 env PATH="$NOPY" "$BASH_BIN" .git/hooks/pre-commit
G_KEY="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
printf 'key = %s\n' "$G_KEY" > leaked.txt
git add leaked.txt >/dev/null 2>&1
assert_exit "without python3 on PATH, the installed hook still blocks a staged secret" 1 \
  env PATH="$NOPY" "$BASH_BIN" .git/hooks/pre-commit
git rm -q --cached leaked.txt >/dev/null 2>&1 || true
rm -rf leaked.txt "$NOPY" .git/hooks/pre-commit
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
assert_exit "a hook whose CLI sits outside the project blocks a red gate" 1 bash .git/hooks/pre-commit
git init -q "$G_OWN/inner/proj"
cp -R .temper "$G_OWN/inner/proj/.temper"
cp .git/hooks/pre-commit "$G_OWN/inner/proj/.git/hooks/pre-commit"
assert_exit "the same hook skips the gate in a repository inside the plugin folder" 0 \
  bash -c "cd '$G_OWN/inner/proj' && bash .git/hooks/pre-commit"
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
cp .git/hooks/pre-commit "$G_HOME/.git/hooks/pre-commit"
assert_exit "the installed hook skips the gate in a repository at the home folder" 0 \
  bash -c "cd '$G_HOME' && HOME='$G_HOME' bash .git/hooks/pre-commit"
assert_exit "the in-agent commit gate skips a repository at the home folder" 0 \
  bash -c "cd '$G_HOME' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | HOME='$G_HOME' bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
assert_exit "the same repository with another home folder still blocks a red gate" 2 \
  bash -c "cd '$G_HOME' && echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | HOME='$WORKDIR' bash '$G_OWN/scripts/guards/block-uncommitted-gate.sh'"
rm -rf "$G_HOME"
rm -rf "$G_OWN" .git/hooks/pre-commit
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
# validate-plugin.sh: a plugin path is the braced variable, '/' and a fixed path that names a tracked
# file (never a folder), in every file git lists, the tests and docs included. The bad forms are
# written at run time from tokens (@R@ the braced root, @O@ the root with its brace still open, @U@ the root
# with no braces), so no tracked file holds one.
VP_PLUG="$WORKDIR/root-var-plugin"
rm -rf "$VP_PLUG"
mkdir -p "$VP_PLUG/scripts/selftest" "$VP_PLUG/commands" "$VP_PLUG/reference" "$VP_PLUG/docs" "$VP_PLUG/packs/demo"
cp "$REPO_ROOT/scripts/validate-plugin.sh" "$VP_PLUG/scripts/validate-plugin.sh"
printf 'x\n' > "$VP_PLUG/scripts/temper"
printf 'x\n' > "$VP_PLUG/reference/plan.md"
printf 'x\n' > "$VP_PLUG/packs/demo/rules.md"
VP_VAR=CLAUDE_PLUGIN_ROOT
vp_expand() { sed -e "s/@R@/\${$VP_VAR}/g" -e "s/@O@/\${$VP_VAR/g" -e "s/@U@/\$$VP_VAR/g"; }
vp_expand > "$VP_PLUG/commands/x.md" <<'EOF'
Run @U@/scripts/temper gate plan.
The folder @R@ holds it.
Read @R@/packs/{name}/rules.md first.
Read @R@/../outside.md first.
List @R@/packs/*/rules.md first.
Run @R@/$SUB/x first.
Run @O@:-/opt/x}/scripts/temper first.
Read @R@/packs/<name>/rules.md first.
Read @R@/packs/[name]/rules.md first.
Read @R@/packs/(name)/rules.md first.
Read @R@/reference/(plan|build).md first.
Read @R@/reference/%s.md first.
List @R@/packs/demo/rule?.md first.
Read @R@/reference/missing.md first.
Read @R@/ first.
Read @R@/reference/later.md first.
See @R@/packs/demo/ for the pack.
Read @R@/packs/demo first.
Run `@R@/scripts/temper gate plan --spec-path .temper/specs/{slug}`.
The CLAUDE_PLUGIN_ROOT variable names the plugin folder.
Read @R@/packs/demo/rules.md.
"command": "bash \"@R@/scripts/temper\""
EOF
printf 'See @R@/reference/plan.md, then "@R@/scripts/temper".\n' | vp_expand > "$VP_PLUG/reference/ok.md"
printf 'Docs may say @U@.\n' | vp_expand > "$VP_PLUG/docs/free.md"
printf 'echo "@R@/../x"\n' | vp_expand > "$VP_PLUG/scripts/selftest/t.sh"
printf 'ignored.md\n' > "$VP_PLUG/.gitignore"
printf 'Read @U@/x first.\n' | vp_expand > "$VP_PLUG/ignored.md"
git init -q "$VP_PLUG"
git -C "$VP_PLUG" add -A
printf 'x\n' > "$VP_PLUG/reference/later.md"   # on disk, not tracked
OUT=$(bash "$VP_PLUG/scripts/validate-plugin.sh" 2>&1; true)
assert_eq "validate-plugin flags the unbraced, no-slash, default, placeholder, '..', wildcard, bracket, group, second-variable, printf, missing, empty, untracked and folder forms" \
  "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18" \
  "$(echo "$OUT" | sed -n 's/^  commands\/x\.md:\([0-9]*\): .*/\1/p' | paste -sd' ' -)"
assert_eq "validate-plugin names a path that is not a tracked file" "1|1" \
  "$(echo "$OUT" | grep -c '^  commands/x\.md:14: not a tracked file: reference/missing\.md$')|$(echo "$OUT" | grep -c '^  commands/x\.md:16: not a tracked file: reference/later\.md$')"
assert_eq "validate-plugin names a tracked folder, with or without a trailing '/', as not a tracked file" "1|1" \
  "$(echo "$OUT" | grep -c '^  commands/x\.md:17: not a tracked file: packs/demo/$')|$(echo "$OUT" | grep -c '^  commands/x\.md:18: not a tracked file: packs/demo$')"
assert_eq "validate-plugin reads every file: docs and tests are checked too" "1|1" \
  "$(echo "$OUT" | grep -c '^  docs/free\.md:1: unbraced')|$(echo "$OUT" | grep -c '^  scripts/selftest/t\.sh:1: ')"
assert_eq "validate-plugin leaves fixed tracked paths, the variable named in prose, an ignored file and itself alone" "0|0|0" \
  "$(echo "$OUT" | grep -c '^  reference/ok\.md:')|$(echo "$OUT" | grep -c '^  ignored\.md:')|$(echo "$OUT" | grep -c '^  scripts/validate-plugin\.sh:')"
assert_eq "validate-plugin.sh holds neither the unbraced nor the braced variable literally" "0|0" \
  "$(grep -cF "\$$VP_VAR" "$REPO_ROOT/scripts/validate-plugin.sh")|$(grep -cF "\${$VP_VAR" "$REPO_ROOT/scripts/validate-plugin.sh")"
rm -rf "$VP_PLUG"
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

# --- block-protected-paths.sh and block-uncommitted-gate.sh: the CLI next to the script ---
setup
cat >> .claude/temper.config <<'EOF'
protect:
  paths: ["**/frozen/**"]
EOF
assert_exit "protected-paths finds its CLI next to it, whatever CLAUDE_PLUGIN_ROOT says" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"src/frozen/a.ts\"}}' | CLAUDE_PLUGIN_ROOT=/nonexistent CLAUDE_PROJECT_DIR='$WORKDIR' bash '$REPO_ROOT/scripts/guards/block-protected-paths.sh'"
UG="$REPO_ROOT/scripts/guards/block-uncommitted-gate.sh"
echo 'x' > gate-file.txt
git add gate-file.txt >/dev/null 2>&1
assert_exit "uncommitted-gate: a git commit on a red gate is BLOCKED, with CLAUDE_PLUGIN_ROOT pointing nowhere" 2 \
  bash -c "echo '{\"tool_input\": {\"command\": \"git commit -m x\"}}' | CLAUDE_PLUGIN_ROOT=/nonexistent bash '$UG'"
assert_exit "uncommitted-gate: any other command passes" 0 \
  bash -c "echo '{\"tool_input\": {\"command\": \"git status\"}}' | CLAUDE_PLUGIN_ROOT=/nonexistent bash '$UG'"
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
cp "$REPO_ROOT"/scripts/guards/*.sh "$CL_PLUG/scripts/guards/"
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

# --- install.sh never writes over a pre-commit hook that is not Temper's, nor a file git tracks:
# it prints a FAIL line, the hook lines and a hint (husky v8 under sh, husky v9, the pre-commit
# framework, a tracked hooks folder), and the lines work where the hint puts them. An older
# Temper hook is replaced and an old installer's backup is named. --global sets an absolute
# core.hooksPath that linked worktrees use. Both commit hooks block on the CLI's exit 3 while a
# run is active. block-secrets --staged scans the staged content. The guard scripts follow their
# own symlinks and do nothing outside a scripts/guards folder ---
setup
git config user.email "test@example.com"
git config user.name "test"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/hooks/pre-commit .git/hooks/pre-commit.bak.* .git/temper-git-hooks
L_PLUG="$WORKDIR/l1-plugin"
rm -rf "$L_PLUG"
mkdir -p "$L_PLUG/scripts/guards"
cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$L_PLUG/scripts/"
for g in install.sh block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh protect-regression-test.sh; do
  cp "$REPO_ROOT/scripts/guards/$g" "$L_PLUG/scripts/guards/$g"
done
L_INSTALL="$L_PLUG/scripts/guards/install.sh"
L_CLI_LINE="TEMPER_CLI=$(printf '%q' "$L_PLUG/scripts/temper")"
L_LINES="$WORKDIR/l1-hook-lines.sh"
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
_l_repo() { # _l_repo <folder>: a new repository with one commit
  rm -rf "$1"
  git init -q "$1"
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "test"
  git -C "$1" commit -q --allow-empty -m init
}
_l_has() { # _l_has <text> <fixed string>: yes when a line of the text holds the string
  printf '%s\n' "$1" | grep -qF -- "$2" && echo yes || echo no
}

# A hook of the user's in .git/hooks: refused, left as it was, no backup; FAIL first, the hook
# lines, a hint last.
printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
L_SUM="$(cksum < .git/hooks/pre-commit)"
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "install.sh refuses a pre-commit hook that is not Temper's: FAIL first, the hook lines, a hint last" "1|yes|yes|yes" \
  "$L_RC|$(printf '%s\n' "$OUT" | head -1 | grep -q "^FAIL: .git/hooks/pre-commit holds a pre-commit hook that is not Temper's" && echo yes || echo no)|$(_l_has "$OUT" "$L_CLI_LINE")|$(printf '%s\n' "$OUT" | tail -1 | grep -qF 'Hint: add the lines at the end of your own pre-commit hook (.git/hooks/pre-commit).' && echo yes || echo no)"
assert_eq "the refused hook is left as it was, and no backup is made" "yes|0" \
  "$([[ "$(cksum < .git/hooks/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)|$(find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' | wc -l | tr -d ' ')"
# The lines added at the end of that hook gate a real commit; a second run of the installer then
# says so and writes nothing.
_l_lines "$OUT"
cat "$L_LINES" >> .git/hooks/pre-commit
L_SUM="$(cksum < .git/hooks/pre-commit)"
_l_red "$WORKDIR"
echo l1 > l1-file.txt
git add l1-file.txt >/dev/null 2>&1
assert_exit "with the hook lines added at the end of a hook of the user's, a real commit on a red gate is blocked" 1 git commit -q -m l1
OUT=$(bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a hook of the user's that holds the current lines is reported and left as it was" "0|yes|yes" \
  "$L_RC|$(_l_has "$OUT" 'already runs the current Temper hook lines')|$([[ "$(cksum < .git/hooks/pre-commit)" == "$L_SUM" ]] && echo yes || echo no)"
git rm -q --cached l1-file.txt >/dev/null 2>&1 || true
rm -f l1-file.txt .git/hooks/pre-commit
if [[ -n "$L_DASH" ]]; then
  assert_exit "the hook lines are plain sh: dash reads them without a syntax error" 0 "$L_DASH" -n "$L_LINES"
fi

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
OUT=$(cd "$L_H8" && env PATH="$L_BIN:$PATH" bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v8: install.sh refuses the tracked .husky/pre-commit and gives the husky hint" "1|yes|yes|yes" \
  "$L_RC|$(_l_has "$OUT" 'FAIL: .husky/pre-commit is tracked by git')|$(_l_has "$OUT" "$L_CLI_LINE")|$(printf '%s\n' "$OUT" | tail -1 | grep -q '^Hint: husky runs .husky/pre-commit with sh, so add the lines at the end of that file' && echo yes || echo no)"
assert_eq "husky v8: the refusal leaves the tracked hook as it was and adds no file" "yes|" \
  "$([[ "$(cksum < "$L_H8/.husky/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(git -C "$L_H8" status --short)"
rm -f "$L_H8/husky.log"
echo a > "$L_H8/a.txt"
git -C "$L_H8" add a.txt >/dev/null 2>&1
assert_exit "husky v8: after the refusal a commit still works under sh" 0 env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m a
_l_lines "$OUT"
cat "$L_LINES" >> "$L_H8/.husky/pre-commit"
rm -f "$L_H8/husky.log"
echo b > "$L_H8/b.txt"
git -C "$L_H8" add b.txt >/dev/null 2>&1
assert_exit "husky v8: with the lines at the end of .husky/pre-commit, a commit with no run passes under sh" 0 \
  env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m b
assert_eq "husky v8: husky's own line ran once" "husky-ran" "$(cat "$L_H8/husky.log" 2>/dev/null)"
_l_red "$L_H8"
echo c > "$L_H8/c.txt"
git -C "$L_H8" add c.txt >/dev/null 2>&1
assert_exit "husky v8: with the lines at the end of .husky/pre-commit, a commit on a red gate is blocked under sh" 1 \
  env PATH="$L_BIN:$PATH" git -C "$L_H8" commit -q -m c
OUT=$(cd "$L_H8" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v8: once .husky/pre-commit holds the current lines, install.sh says so and writes nothing" "0|yes" \
  "$L_RC|$(_l_has "$OUT" 'already runs the current Temper hook lines')"
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
OUT=$(cd "$L_H9" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v9: install.sh refuses husky's generated hook and gives the husky hint" "1|yes|yes|yes" \
  "$L_RC|$(_l_has "$OUT" "FAIL: .husky/_/pre-commit holds a pre-commit hook that is not Temper's")|$([[ "$(cksum < "$L_H9/.husky/_/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(printf '%s\n' "$OUT" | tail -1 | grep -q '^Hint: husky runs .husky/pre-commit' && echo yes || echo no)"
_l_lines "$OUT"
cat "$L_LINES" >> "$L_H9/.husky/pre-commit"
rm -f "$L_H9/husky.log"
echo a > "$L_H9/a.txt"
git -C "$L_H9" add a.txt >/dev/null 2>&1
assert_exit "husky v9: with the lines at the end of .husky/pre-commit, a commit with no run passes under sh" 0 \
  env PATH="$L_BIN:$PATH" git -C "$L_H9" commit -q -m a
assert_eq "husky v9: husky's own line ran once" "husky-ran" "$(cat "$L_H9/husky.log" 2>/dev/null)"
_l_red "$L_H9"
echo b > "$L_H9/b.txt"
git -C "$L_H9" add b.txt >/dev/null 2>&1
assert_exit "husky v9: with the lines at the end of .husky/pre-commit, a commit on a red gate is blocked under sh" 1 \
  env PATH="$L_BIN:$PATH" git -C "$L_H9" commit -q -m b
OUT=$(cd "$L_H9" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "husky v9: once .husky/pre-commit holds the current lines, install.sh says so and writes nothing" "0|yes|yes" \
  "$L_RC|$(_l_has "$OUT" 'already runs the current Temper hook lines')|$([[ "$(cksum < "$L_H9/.husky/_/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)"
rm -rf "$L_H9"

# The pre-commit framework: its hook is refused with the local-hook hint. When the framework is
# installed after Temper it keeps Temper's hook as pre-commit.legacy and runs it in migration
# mode; with nothing chained that works, and a red gate still blocks.
L_PC="$WORKDIR/l1-precommit"
_l_repo "$L_PC"
cat > "$L_PC/.git/hooks/pre-commit" <<'EOF'
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
chmod +x "$L_PC/.git/hooks/pre-commit"
cp "$L_PC/.git/hooks/pre-commit" "$WORKDIR/l1-framework-hook"
OUT=$(cd "$L_PC" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "the pre-commit framework's hook is refused with the local-hook hint" "1|yes|yes" \
  "$L_RC|$(_l_has "$OUT" "FAIL: .git/hooks/pre-commit holds a pre-commit hook that is not Temper's")|$(printf '%s\n' "$OUT" | tail -1 | grep -q '^Hint: the pre-commit framework owns this hook, so save the lines as a script and run it from a local hook' && echo yes || echo no)"
rm -f "$L_PC/.git/hooks/pre-commit"
bash -c "cd '$L_PC' && bash '$L_INSTALL'" >/dev/null 2>&1
mv "$L_PC/.git/hooks/pre-commit" "$L_PC/.git/hooks/pre-commit.legacy"
cp "$WORKDIR/l1-framework-hook" "$L_PC/.git/hooks/pre-commit"
printf 'framework.log\n.temper/\n' > "$L_PC/.gitignore"
git -C "$L_PC" add .gitignore >/dev/null 2>&1
assert_exit "the framework installed over Temper's hook: a commit with no run passes in migration mode" 0 git -C "$L_PC" commit -q -m framework
assert_eq "the framework's own checks ran" "framework-ran" "$(cat "$L_PC/framework.log" 2>/dev/null)"
_l_red "$L_PC"
echo x > "$L_PC/x.txt"
git -C "$L_PC" add x.txt >/dev/null 2>&1
assert_exit "the framework installed over Temper's hook: a commit on a red gate is still blocked" 1 git -C "$L_PC" commit -q -m red
rm -rf "$L_PC" "$WORKDIR/l1-framework-hook"

# A team's tracked hooks folder: a tracked pre-commit, even an older Temper hook, is never written;
# a new hook in a folder git does not ignore comes with a note not to commit it.
L_TR="$WORKDIR/l1-tracked"
_l_repo "$L_TR"
mkdir -p "$L_TR/.githooks"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by an older installer).\nTEMPER_CLI=/old/plugin/scripts/temper\n' > "$L_TR/.githooks/pre-commit"
chmod +x "$L_TR/.githooks/pre-commit"
git -C "$L_TR" add .githooks/pre-commit >/dev/null 2>&1
git -C "$L_TR" commit -q -m hooks
git -C "$L_TR" config core.hooksPath .githooks
L_SUM="$(cksum < "$L_TR/.githooks/pre-commit")"
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a tracked pre-commit (here an older Temper hook) is refused and left as it was" "1|yes|yes|" \
  "$L_RC|$(_l_has "$OUT" 'FAIL: .githooks/pre-commit is tracked by git')|$([[ "$(cksum < "$L_TR/.githooks/pre-commit")" == "$L_SUM" ]] && echo yes || echo no)|$(git -C "$L_TR" status --short)"
git -C "$L_TR" config core.hooksPath team-hooks
mkdir -p "$L_TR/team-hooks"
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a new hook in a folder git does not ignore is written, with a note not to commit it" "0|yes|yes" \
  "$L_RC|$(grep -qxF "$L_CLI_LINE" "$L_TR/team-hooks/pre-commit" 2>/dev/null && echo yes || echo no)|$(_l_has "$OUT" 'Note: git does not ignore team-hooks/pre-commit')"
# A folder that cannot be made (a file is in the way) is refused with a FAIL line and the hook
# lines, never a bare shell error.
echo x > "$L_TR/blocked"
git -C "$L_TR" config core.hooksPath blocked/hooks
OUT=$(cd "$L_TR" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a hooks folder that cannot be made gives a FAIL line and the hook lines, no shell error" "1|yes|yes|0" \
  "$L_RC|$(_l_has "$OUT" "FAIL: the hooks folder 'blocked/hooks' could not be created")|$(_l_has "$OUT" "$L_CLI_LINE")|$(printf '%s\n' "$OUT" | grep -c 'mkdir:')"
rm -rf "$L_TR"

# An older Temper hook (9.6.4 and earlier embedded a scripts folder) is replaced; the backup the
# old installer made of the user's hook, which it never ran, is named with how to restore it.
L_OLD="$WORKDIR/l1-old"
_l_repo "$L_OLD"
mkdir -p "$WORKDIR/l1-old-plugin/scripts/hooks"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by scripts/hooks/install.sh).\nTEMPER_HOOKS_DIR="${TEMPER_HOOKS_DIR:-%s}"\n' "$WORKDIR/l1-old-plugin/scripts/hooks" > "$L_OLD/.git/hooks/pre-commit"
printf '#!/bin/sh\necho user-hook\n' > "$L_OLD/.git/hooks/pre-commit.bak.20260101000000"
chmod +x "$L_OLD/.git/hooks/pre-commit" "$L_OLD/.git/hooks/pre-commit.bak.20260101000000"
OUT=$(cd "$L_OLD" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "an older Temper hook is replaced with the current one" "0|yes" \
  "$L_RC|$(grep -qxF "$L_CLI_LINE" "$L_OLD/.git/hooks/pre-commit" && echo yes || echo no)"
assert_eq "the old installer's backup is named, with the lines to add and how to move it back" "yes|yes|yes" \
  "$(_l_has "$OUT" 'Warning: .git/hooks/pre-commit.bak.20260101000000 is a pre-commit hook that an older Temper installer set aside')|$(_l_has "$OUT" 'then move it back to .git/hooks/pre-commit')|$(_l_has "$OUT" "$L_CLI_LINE")"
assert_eq "a stale path that still exists is not called failing open, and no hook is said to run first" "no|no" \
  "$(_l_has "$OUT" 'failing open')|$(_l_has "$OUT" 'runs it first')"
printf '#!/usr/bin/env bash\n# Temper native pre-commit hook (installed by scripts/hooks/install.sh).\nTEMPER_HOOKS_DIR="${TEMPER_HOOKS_DIR:-%s}"\n' "$WORKDIR/l1-gone-plugin/scripts/hooks" > "$L_OLD/.git/hooks/pre-commit"
OUT=$(cd "$L_OLD" && bash "$L_INSTALL" 2>&1)
assert_eq "a stale path that is gone is reported as failing open" "yes" "$(_l_has "$OUT" 'failing open')"
rm -rf "$L_OLD" "$WORKDIR/l1-old-plugin"

# --global: refused over a hook of the user's in .git/hooks (git would skip it); otherwise it sets
# an absolute core.hooksPath, which a linked worktree uses, so its commits are gated too.
L_GM="$WORKDIR/l1-gmain"
L_GW="$WORKDIR/l1-gwt"
_l_repo "$L_GM"
rm -rf "$L_GW"
git -C "$L_GM" worktree add -q "$L_GW" >/dev/null 2>&1
L_GM_REAL="$(cd -P "$L_GM" && pwd)"
printf '#!/bin/sh\necho mine\n' > "$L_GM/.git/hooks/pre-commit"
chmod +x "$L_GM/.git/hooks/pre-commit"
OUT=$(cd "$L_GM" && bash "$L_INSTALL" --global 2>&1); L_RC=$?
assert_eq "--global refuses when .git/hooks/pre-commit holds a hook that is not Temper's" "1|yes|yes|none" \
  "$L_RC|$(_l_has "$OUT" "FAIL: .git/hooks/pre-commit holds a pre-commit hook that is not Temper's. --global sets core.hooksPath")|$(_l_has "$OUT" "$L_CLI_LINE")|$(git -C "$L_GM" config --get core.hooksPath || echo none)"
rm -f "$L_GM/.git/hooks/pre-commit"
assert_exit "--global installs in the main checkout" 0 bash -c "cd '$L_GM' && bash '$L_INSTALL' --global"
assert_eq "--global sets core.hooksPath to the absolute path of the repository's temper-git-hooks folder" \
  "$L_GM_REAL/.git/temper-git-hooks|$L_GM_REAL/.git/temper-git-hooks/pre-commit" \
  "$(git -C "$L_GM" config --get core.hooksPath)|$(cd "$L_GW" && git rev-parse --git-path hooks/pre-commit)"
OUT=$(cd "$L_GW" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "in a linked worktree the default mode accepts that core.hooksPath and finds the hook there" "0|yes" \
  "$L_RC|$(_l_has "$OUT" 'already installed for this worktree')"
_l_red "$L_GW"
printf '.temper/\n' > "$L_GW/.gitignore"
echo w > "$L_GW/w.txt"
git -C "$L_GW" add .gitignore w.txt >/dev/null 2>&1
assert_exit "after --global in the main checkout, a commit on a red gate in a linked worktree is blocked" 1 git -C "$L_GW" commit -q -m wt
# The relative value an earlier --global wrote names no folder in a linked worktree: refused with a
# FAIL line and the hook lines (no mkdir error), and --global in the main checkout makes it absolute.
git -C "$L_GM" config core.hooksPath .git/temper-git-hooks
OUT=$(cd "$L_GW" && bash "$L_INSTALL" 2>&1); L_RC=$?
assert_eq "a relative core.hooksPath through .git in a linked worktree is refused with a FAIL line and the hook lines" "1|yes|yes|0" \
  "$L_RC|$(_l_has "$OUT" "FAIL: core.hooksPath is set to the relative path '.git/temper-git-hooks'")|$(_l_has "$OUT" "$L_CLI_LINE")|$(printf '%s\n' "$OUT" | grep -c 'mkdir:')"
assert_exit "--global in the main checkout runs over that earlier relative value" 0 bash -c "cd '$L_GM' && bash '$L_INSTALL' --global"
assert_eq "and sets the absolute path instead" "$L_GM_REAL/.git/temper-git-hooks" "$(git -C "$L_GM" config --get core.hooksPath)"
rm -rf "$L_GM" "$L_GW"

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
rm -f .git/hooks/pre-commit
OUT=$(bash "$L_GL/guards/install.sh" 2>&1); L_RC=$?
assert_eq "install.sh reached through a link to its folder writes the real CLI path" "0|yes" \
  "$L_RC|$(grep -qxF "$L_CLI_LINE" .git/hooks/pre-commit 2>/dev/null && echo yes || echo no)"
git rm -q --cached guard-file.txt >/dev/null 2>&1 || true
rm -rf guard-file.txt reg-l1 "$L_GL" "$L_PLUG" "$L_BIN" "$L_LINES" .git/hooks/pre-commit

echo ""
echo "=== test-temper.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
