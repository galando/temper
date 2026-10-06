#!/usr/bin/env bash
#
# test-temper.sh — unit tests for scripts/temper (the deterministic spine).
#
# Plain-bash assertions, no test framework dependency (consistent with the rest of
# Temper's tooling). Runs entirely in a throwaway tmp dir; never touches the repo.
set -uo pipefail

# The repo root: this script's folder with the literal suffix /scripts/tests removed.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${TESTS_DIR%/scripts/tests}"
[[ "$REPO_ROOT" != "$TESTS_DIR" && -x "$REPO_ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the repo root from $TESTS_DIR"; exit 1; }
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
assert_eq "a missing Status skips out of scope and open questions with a note" "2" "$(echo "$OUT" | grep -c 'no recognized Status header (draft, accepted or completed)')"
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
for bad in "../../outside" "Bad-Slug" "a..b" "a/b" ".hidden" ""; do
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
"$TEMPER" state archive >/dev/null
assert_eq "state archive writes no ledger through a spec_path that leaves .temper/specs" "no" \
  "$([[ -e "$WORKDIR/outside/esc/gate-ledger.json" ]] && echo yes || echo no)"
"$TEMPER" state clear >/dev/null
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

# --- the plugin folder: a literal suffix strip, and CLAUDE_PLUGIN_ROOT for a CLI reached through a symlink ---
setup
mkdir -p "$WORKDIR/bin"
ln -sf "$TEMPER" "$WORKDIR/bin/temper"
assert_eq "a CLI reached through a symlink resolves a model through CLAUDE_PLUGIN_ROOT" "$("$TEMPER" model plan)" \
  "$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT" "$WORKDIR/bin/temper" model plan)"
assert_exit "a CLI reached through a symlink loads acceptance.py by its full path" 0 \
  env CLAUDE_PLUGIN_ROOT="$REPO_ROOT" "$WORKDIR/bin/temper" gate plan
assert_eq "the CLI and its Python helpers list no folder by wildcard and load no folder onto sys.path" "0" \
  "$(cat "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$REPO_ROOT/scripts/pack-discover.py" | grep -cE 'glob\.glob|^import glob|sys\.path\.insert|TEMPER_DIR:-')"

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
# Any other hook is backed up first.
printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "a non-Temper hook is backed up before it is replaced" "1" \
  "$(find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' -exec grep -l 'echo mine' {} + | wc -l | tr -d ' ')"
find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' -delete
# A symlinked pre-commit is replaced by a regular file; the file it pointed at is left as it was.
printf '#!/bin/sh\necho linked\n' > "$WORKDIR/linked-hook.sh"
rm -f .git/hooks/pre-commit
ln -s "$WORKDIR/linked-hook.sh" .git/hooks/pre-commit
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "a symlinked pre-commit becomes a regular file, and its target is untouched" "yes|yes" \
  "$([[ -f .git/hooks/pre-commit && ! -L .git/hooks/pre-commit ]] && echo yes || echo no)|$(grep -q 'echo linked' "$WORKDIR/linked-hook.sh" && ! grep -q 'Temper native' "$WORKDIR/linked-hook.sh" && echo yes || echo no)"
find .git/hooks -maxdepth 1 -name 'pre-commit.bak.*' -delete
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
assert_eq "--global writes .git/temper-git-hooks/pre-commit and points core.hooksPath at it" "yes|.git/temper-git-hooks" \
  "$([[ -x .git/temper-git-hooks/pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)"
git config --unset core.hooksPath 2>/dev/null || true
rm -rf .git/temper-git-hooks abs-hooks dot-hooks cfg-hooks "$WORKDIR/outside"

# --- stage-marker.sh + verify-stage-gate.sh: fixed names in the project, never inside the plugin ---
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/guards/verify-stage-gate.sh"
rm -f .temper/pending-stage.json .temper/stage-gate.log
echo '{"prompt": "/temper:plan x"}' | bash "$MARKER"
OUT=$(echo '{}' | bash "$VERIFY" 2>&1; true)
assert_eq "verify-stage-gate logs each firing to .temper/stage-gate.log" "yes" \
  "$(grep -q 'blocked stop (stage=plan' .temper/stage-gate.log && echo yes || echo no)"
assert_eq "the block message names the stage brief without building a path from the stage" "yes|no" \
  "$(echo "$OUT" | grep -q "that stage's brief" && echo yes || echo no)|$(echo "$OUT" | grep -q 'agents/' && echo yes || echo no)"
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
assert_eq "stage-marker still marks the plugin folder itself as a project" "plan" \
  "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['stage'])" "$FAKE_PLUGIN/.temper/pending-stage.json")"

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
assert_eq "formatter: when the project is the plugin folder itself, its files are formatted" "p q" "$(cat "$FAKE_PLUGIN/sub/y.txt")"
rm -rf "$FAKE_PLUGIN"

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

# --- pack-discover.py: named subfolders, no wildcard; Temper's own folder is never scanned ---
setup
PD_HOME="$WORKDIR/fake-home-pd"
rm -rf "$PD_HOME"
mkdir -p "$PD_HOME/.claude/plugins" "$PD_HOME/other/.claude-plugin" "$PD_HOME/other/commands/nested/deeper" \
  "$PD_HOME/other/skills/.hidden-skill" "$PD_HOME/other/skills/real-skill" .claude/commands
echo '{"description": "other plugin"}' > "$PD_HOME/other/.claude-plugin/plugin.json"
printf -- '---\ndescription: top\n---\n' > "$PD_HOME/other/commands/top.md"
printf -- '---\ndescription: inner\n---\n' > "$PD_HOME/other/commands/nested/deeper/inner.md"
printf -- '---\ndescription: hidden\n---\n' > "$PD_HOME/other/commands/.secret.md"
printf -- '---\ndescription: hidden skill\n---\n' > "$PD_HOME/other/skills/.hidden-skill/SKILL.md"
printf -- '---\ndescription: real skill\n---\n' > "$PD_HOME/other/skills/real-skill/SKILL.md"
printf -- '---\ndescription: local\n---\n' > .claude/commands/local-cmd.md
printf -- '---\ndescription: hidden local\n---\n' > .claude/commands/.hidden-cmd.md
cat > "$PD_HOME/.claude/plugins/installed_plugins.json" <<EOF
{"plugins": {
  "temper-fork@somewhere": [{"version": "1", "installPath": "$REPO_ROOT", "lastUpdated": "2026-01-01T00:00:00Z"}],
  "other@market": [{"version": "1", "installPath": "$PD_HOME/other", "lastUpdated": "2026-01-01T00:00:00Z"}]
}}
EOF
PD_OUT="$(HOME="$PD_HOME" python3 "$REPO_ROOT/scripts/pack-discover.py")"
assert_eq "pack-discover never scans Temper's own folder, whatever its entry is called" "0" "$(printf '%s\n' "$PD_OUT" | grep -c 'temper-fork')"
assert_eq "pack-discover lists the commands at any depth under commands, hidden ones left out" "other:inner|other:top" \
  "$(printf '%s\n' "$PD_OUT" | awk -F'|' '$1 == "CMD" {print $2}' | sort | paste -sd'|' -)"
assert_eq "pack-discover lists each skill folder's SKILL.md, hidden folders left out" "other:real-skill" \
  "$(printf '%s\n' "$PD_OUT" | awk -F'|' '$1 == "SKILL" {print $2}' | sort | paste -sd'|' -)"
assert_eq "pack-discover lists the project's own commands, hidden ones left out" "local-cmd" \
  "$(printf '%s\n' "$PD_OUT" | awk -F'|' '$1 == "LOCAL_CMD" {print $2}' | sort | paste -sd'|' -)"
rm -rf "$PD_HOME" .claude/commands

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

echo ""
echo "=== test-temper.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
