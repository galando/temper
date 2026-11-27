# shellcheck shell=bash
# Part 1 of the temper CLI test suite: state, gates, evidence and the intent gate.
# Sourced in order by test-temper.sh, which sets up the helpers, WORKDIR and the counters;
# not meant to run on its own.

# --- grep -c zero-match must not double-print (the "0\n0" bug) ---
setup
cat > .temper/specs/demo/tasks.md <<'EOF'
- [x] a
- [x] b
EOF
assert_exit "build gate PASSes with zero unchecked tasks (no double-count)" 1 "$TEMPER" gate build
# (still FAILs on the RED/GREEN requirement — no test evidence yet — but must not crash)

# --- plan gate: every criterion is tied to what proves it (criteria -> validation; WP26: no count of scenarios) ---
setup
assert_exit "plan gate PASSes: 2 scenarios for 2 criteria" 0 "$TEMPER" gate plan

setup
python3 - <<'EOF'
p = '.temper/specs/demo/intent.md'
s = open(p).read().replace('### Constraints', '- [ ] AC-03 [required]: demo criterion three\n  Why: a third outcome\n  Validate: scenario — traced to a test below\n\n### Constraints')
open(p, 'w').write(s)
EOF
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "WP26 plan gate FAILs a scenario criterion no scenario covers on criteria -> validation, and writes no row criteria -> scenarios" \
  "FAIL|validation=False|scenarios row=absent" \
  "$(python3 -c "
import json
g = json.load(open('.temper/gates.json')).get('plan') or {}
rows = {x['name']: x for x in g.get('requirements') or []}
print('%s|validation=%s|scenarios row=%s' % (g.get('verdict'), (rows.get('criteria -> validation') or {}).get('pass'),
      'present' if 'criteria -> scenarios' in rows else 'absent'))")"

# --- plan gate: no tier needs a plan.md or a Blast Radius section (WP26) ---
setup
assert_exit "plan gate PASSes without a Blast Radius section (no complexity set)" 0 "$TEMPER" gate plan
"$TEMPER" state set complexity medium >/dev/null
fresh_reviewed   # 9.7.6: a medium plan also needs its fresh review
assert_exit "WP26 plan gate PASSes at medium complexity with no plan.md: no tier needs a Blast Radius section" 0 "$TEMPER" gate plan
setup
"$TEMPER" state set complexity medium >/dev/null
cat > .temper/specs/demo/plan.md <<'EOF'
## Context Map
- use: intent.md - the accepted scope
- reviewed: auto - every source is current and on topic

## Blast Radius
- no external consumers
EOF
fresh_reviewed   # 9.7.6: a medium plan also needs its fresh review
assert_exit "plan gate PASSes once plan.md has a Blast Radius section" 0 "$TEMPER" gate plan

# --- build gate: RED then GREEN required ---
setup
ev_green build "tests"
_scen
assert_exit "build gate FAILs on GREEN with no RED (TDD discipline)" 1 "$TEMPER" gate build

setup
ev_red build "tests"
ev_green build "tests"
_scen
assert_exit "build gate PASSes on RED then GREEN + no unchecked tasks" 0 "$TEMPER" gate build

# --- review gate: block-on severity ---
setup
review_done --cmd "review panel"
assert_exit "review gate PASSes with no findings" 0 "$TEMPER" gate review
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
assert_exit "review gate FAILs on an open critical finding" 1 "$TEMPER" gate review

# --- review gate: a finding fixed in this run is resolved, not deleted (woningscout #984) ---
# 9.8.5 (WP18): resolve takes only a commit the CLI recorded after the reviewed HEAD: a run at Review, and cli_commit
review_repo rv1; C1FIX="$(cli_commit)"
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
"$TEMPER" evidence add --stage review --claim "missing null check" --severity high >/dev/null
assert_exit "evidence resolve needs --stage, --id and --fixed-by" 1 "$TEMPER" evidence resolve --stage review --id 1
assert_exit "evidence resolve rejects an unknown id" 1 "$TEMPER" evidence resolve --stage review --id 9 --fixed-by "$C1FIX"
assert_exit "evidence resolve rejects an unknown stage" 1 "$TEMPER" evidence resolve --stage nope --id 1 --fixed-by abc123
assert_exit "review gate still FAILs before the finding is resolved" 1 "$TEMPER" gate review
assert_exit "evidence resolve marks the critical finding fixed" 0 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$C1FIX"
assert_exit "evidence resolve refuses to resolve the same finding twice" 1 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$C1FIX"
review_done --cmd "review panel"
assert_exit "review gate PASSes once the only blocking finding is resolved" 0 "$TEMPER" gate review
assert_eq "the resolved row is still in the ledger" "3" "$("$TEMPER" evidence list --stage review --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
assert_eq "evidence list shows the id and the resolver" "yes" "$("$TEMPER" evidence list --stage review | grep "#1 .*\[resolved: $C1FIX\]" >/dev/null && echo yes || echo no)"
assert_eq "the gate detail names the resolved count" "yes" "$("$TEMPER" gate review | grep '1 resolved in this run' >/dev/null && echo yes || echo no)"
"$TEMPER" evidence add --stage review --claim "second injection" --severity critical >/dev/null
assert_exit "a new unresolved critical finding FAILs the gate again" 1 "$TEMPER" gate review
cd "$WORKDIR"; rm -rf "$WORKDIR/rv1"

# --- check gate: coverage threshold ---
# review 3 of WP32: coverage is only what the CLI measured (a value recorded with evidence add is not read), so the
# coverage command prints the total and `check run` measures it
setup
printf 'check:\n  commands:\n    test: "true"\n    coverage: echo "TOTAL 10 4 60%%"\n' >> .claude/temper.config
"$TEMPER" check run >/dev/null 2>&1
ev_green check "tests"
ev_scen check first
ev_scen check second
assert_exit "check gate FAILs below coverage threshold (60 < 80)" 1 "$TEMPER" gate check
sed -i 's/TOTAL 10 4 60%/TOTAL 10 1 90%/' .claude/temper.config; "$TEMPER" check run >/dev/null 2>&1
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
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
rm -f threshold-injected
assert_exit "check gate FAILs on a quote-bearing coverage threshold" 1 "$TEMPER" gate check
assert_eq "a quote-bearing coverage threshold writes no file" "no" "$([[ -e threshold-injected ]] && echo yes || echo no)"
OUT=$("$TEMPER" gate check 2>&1; true)
assert_eq "the FAIL names the coverage row" "yes" \
  "$(grep -q '\[x\] coverage — ' <<<"$OUT" && echo yes || echo no)"
assert_eq "still no file after the gate runs again" "no" "$([[ -e threshold-injected ]] && echo yes || echo no)"
rm -f threshold-injected

# --- check gate: scenarios must be traced to a test (the flagship "rate limiting" story) ---
setup
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
assert_exit "check gate FAILs when a scenario has no traced test (1/2 covered)" 1 "$TEMPER" gate check
ev_scen check second
assert_exit "check gate PASSes once every scenario is traced (2/2 covered)" 0 "$TEMPER" gate check

# --- evidence: PROVEN downgrade on missing artifact ---
setup
OUT=$("$TEMPER" evidence add --stage check --claim "x" --exit 0 --artifact does/not/exist --label PROVEN 2>&1)
assert_eq "PROVEN downgrades to HEURISTIC when artifact is missing" "yes" "$(grep -q 'downgraded to HEURISTIC' <<<"$OUT" && echo yes || echo no)"

# --- commit gate: aggregates prior gate verdicts + honors overrides ---
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
ev_red build "tests"
ev_green build "tests"
_scen
"$TEMPER" gate build >/dev/null
review_done --cmd "review panel"
"$TEMPER" gate review >/dev/null
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
"$TEMPER" gate check >/dev/null
assert_exit "commit gate PASSes once every upstream gate is green" 0 "$TEMPER" gate commit

setup
"$TEMPER" evidence add --stage review --claim "critical thing" --severity critical >/dev/null
assert_exit "commit gate FAILs with an unresolved review finding, no override" 1 "$TEMPER" gate commit
"$TEMPER" override review --reason "manually verified safe" >/dev/null
"$TEMPER" gate intent >/dev/null; "$TEMPER" gate plan >/dev/null; "$TEMPER" gate build >/dev/null 2>&1 || true
"$TEMPER" gate check >/dev/null 2>&1 || true
assert_eq "override is recorded and visible in report" "yes" "$("$TEMPER" report | grep 'overridden' >/dev/null && echo yes || echo no)"

# --- state: illegal transitions rejected, the budget enforced (WP10: a step back from a failed gate spends one) ---
setup
assert_exit "state advance rejects an unknown stage name" 1 "$TEMPER" state advance not_a_real_stage build
_at build build
assert_exit "state advance accepts a known stage" 0 "$TEMPER" state advance build_complete review
gfail review "no blocking findings" "1 open high finding"
assert_exit "state loop allows steps back from a failed gate up to budget.per-failure" 0 "$TEMPER" state loop review build --reason r1
_at review; gfail review "no blocking findings" "1 open high finding"
assert_exit "state loop allows the second iteration" 0 "$TEMPER" state loop review build --reason r2
_at review; gfail review "no blocking findings" "1 open high finding"
assert_exit "state loop blocks the third step back for one failure (budget.per-failure: 2)" 1 "$TEMPER" state loop review build --reason r3

# --- state loop: a /temper run clears the temper sequence from the target stage down ---
setup
"$TEMPER" evidence add --stage plan --claim "plan row" --exit 0 >/dev/null
ev_green build "tests"
_scen
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
ev_green check "tests"
_at review   # a loop goes back from the stage the run is at
"$TEMPER" state loop review build --reason r1 >/dev/null
assert_eq "a temper-run loop keeps the plan evidence above the target" "1" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/plan.json"))))')"
assert_eq "a temper-run loop clears build evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/build.json"))))')"
assert_eq "a temper-run loop clears review evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))')"
assert_eq "a temper-run loop clears check evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/check.json"))))')"
# P1: the loop sends the run back to its target stage, so the build-checkpoint commit carve-out applies
assert_eq "state loop review build sets next_stage to build" "build" "$("$TEMPER" state get next_stage)"
# R6: a loop target must be a known stage; a typo writes no next_stage
assert_exit "state loop to an unknown stage is refused" 1 "$TEMPER" state loop review bogus --reason typo
assert_eq "state loop to an unknown stage leaves next_stage alone" "build" "$("$TEMPER" state get next_stage)"
setup
"$TEMPER" state set branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" >/dev/null
_at check
"$TEMPER" gate intent >/dev/null; "$TEMPER" gate plan >/dev/null
echo 'fix' > loopfix.js; git add loopfix.js >/dev/null 2>&1
"$TEMPER" state loop check build --reason "review found a defect" >/dev/null
ev_green build "fix tests"
assert_eq "state loop check build: next_stage is build" "build" "$("$TEMPER" state get next_stage)"
assert_eq "after a loop back to build, a fix commit rides the checkpoint carve-out" "yes" \
  "$("$TEMPER" gate commit 2>&1 | grep -c 'build checkpoint commit' >/dev/null && echo yes || echo no)"

# --- state loop: a /temper:fix run clears build, review and check on a loop back to fix (woningscout #984) ---
setup
"$TEMPER" state init bug3 --command fix >/dev/null; _base_known
ev_red build "regression test"
ev_green build "regression test"
"$TEMPER" evidence add --stage review --claim "sql injection" --severity critical >/dev/null
ev_green check "tests"
assert_exit "a fix run's review gate FAILs on the open finding" 1 "$TEMPER" gate review
_at review
assert_exit "state loop review fix is accepted in a fix run" 0 "$TEMPER" state loop review fix --reason "fix the injection"
assert_eq "a fix-run loop clears the build evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/build.json"))))')"
assert_eq "a fix-run loop clears the review evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))')"
assert_eq "a fix-run loop clears the check evidence" "0" "$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/check.json"))))')"
review_done --cmd "review panel"
assert_exit "the review gate can pass again after the loop" 0 "$TEMPER" gate review
"$TEMPER" evidence add --stage review --claim "kept" --severity critical >/dev/null
_at check
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
assert_eq "state advance with zero args prints a usage message, not an unbound-variable crash" "yes" "$(grep -q 'usage: temper state advance' <<<"$OUT" && ! grep -q 'unbound variable' <<<"$OUT" && echo yes || echo no)"
OUT=$("$TEMPER" state advance build_complete 2>&1)
assert_eq "state advance with one arg prints a usage message, not an unbound-variable crash" "yes" "$(grep -q 'usage: temper state advance' <<<"$OUT" && ! grep -q 'unbound variable' <<<"$OUT" && echo yes || echo no)"

# --- state advance: stage vocabulary is scoped per command (temper vs fix) ---
setup
assert_exit "a /temper run rejects fix-only stage names (rca_complete)" 1 "$TEMPER" state advance rca_complete design
_at plan plan; "$TEMPER" state set complexity medium >/dev/null; "$TEMPER" state set want_design true >/dev/null
assert_exit "a /temper run accepts its own stage names" 0 "$TEMPER" state advance plan_complete design

setup
"$TEMPER" state init bug2 --command fix >/dev/null; _base_known
assert_exit "a /temper:fix run accepts rca_complete" 0 "$TEMPER" state advance rca_complete fix
assert_exit "a /temper:fix run rejects temper-only stage names (plan_complete)" 1 "$TEMPER" state advance plan_complete design

# --- /temper:fix commits: no plan gate required (fix has no such stage) ---
setup
"$TEMPER" state init bug1 --command fix >/dev/null; _base_known
ev_red build "regression test"
ev_green build "regression test"
"$TEMPER" gate build >/dev/null
review_done --cmd "review panel"
"$TEMPER" gate review >/dev/null
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
"$TEMPER" gate check >/dev/null
assert_exit "fix commit gate PASSes without a plan gate" 0 "$TEMPER" gate commit

# --- autonomy: park-on-touch blocks commit in autonomous mode only ---
setup
_ran_unattended   # WP11: the state a run the person started at the approval leaves
mkdir -p src/auth && echo x > src/auth/login.js
git add -A >/dev/null 2>&1 || true
assert_exit "autonomous commit gate parks on a park-on-touch path" 1 "$TEMPER" gate commit
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "park reason names the matched path" "yes" "$(grep -q 'src/auth/login.js' <<<"$OUT" && echo yes || echo no)"

# --- native pre-commit hook: does `git commit` actually get blocked/allowed for
# real, not just gate_commit()'s decision logic in isolation? Everything above tests
# the CLI function; this installs the real hook (scripts/guards/install.sh) and runs a
# real `git commit`, the same way a human's `git commit` reaches it.
setup
git config user.email "test@example.com"
git config user.name "test"
# A plain repository: the hook is kept in .git/temper-gate and core.hooksPath points at that
# folder by its absolute path. Nothing else is written in the git folder (listed before and after).
P_GIT_BEFORE="$(_git_list .git)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); P_RC=$?
assert_eq "install.sh in a plain repository keeps the hook in .git/temper-gate and points core.hooksPath at that folder" \
  "0|yes|$WORKDIR/.git/temper-gate|yes" \
  "$P_RC|$([[ -x .git/temper-gate/pre-commit ]] && echo yes || echo no)|$(git config --get core.hooksPath)|$(printf '%s\n' "$OUT" | grep -cxF "Installed Temper pre-commit hook -> $WORKDIR/.git/temper-gate/pre-commit (core.hooksPath points at that folder, so every worktree of this repository runs it)." >/dev/null && echo yes || echo no)"
assert_eq "install.sh writes nothing else in the git folder: its listing is the same before and after" "$P_GIT_BEFORE" "$(_git_list .git)"
assert_eq "install.sh ends with how to uninstall, naming the command" "yes" \
  "$(printf '%s\n' "$OUT" | tail -1 | grep -qF "To uninstall: run 'temper guards uninstall'" && echo yes || echo no)"
OUT=$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); P_RC=$?
assert_eq "a second run in the plain repository says the hook is already installed" "0|yes" \
  "$P_RC|$(printf '%s\n' "$OUT" | grep -cxF "The Temper pre-commit hook is already installed: $WORKDIR/.git/temper-gate/pre-commit (core.hooksPath points at its folder)." >/dev/null && echo yes || echo no)"
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
ev_red build "tests"
ev_green build "tests"
_scen
assert_exit "gate build runs cleanly against a config with a stale eval: block" 0 "$TEMPER" gate build

# 2. A stale "eval" key in .temper/gates.json is ignored by gate_commit, not iterated.
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
ev_red build "tests"
ev_green build "tests"
_scen
"$TEMPER" gate build >/dev/null
review_done --cmd "review panel"
"$TEMPER" gate review >/dev/null
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
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
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
"$TEMPER" evidence clear --stage check >/dev/null
assert_eq "evidence clear truncates a stage's ledger to []" "[]" "$(cat .temper/evidence/check.json | tr -d '[:space:]')"

setup
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
"$TEMPER" gate check >/dev/null
_at check
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
AUDIT_PY="$(mktemp -d)/audit-run.py"   # outside the fixture: an untracked file there is a change outside the plan (9.8.0)
cat > "$AUDIT_PY" <<'PY'
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
PACK_OUT="$(HOME="$PACK_HOME" python3 -I "$AUDIT_PY" \
  "$PACK_HOME|$PD_WD_REAL/fake-home|$REPO_ROOT|$PD_RR_REAL" "$REPO_ROOT/scripts/pack-discover.py" 2>"$WORKDIR/audit.txt")"
assert_eq "pack-discover opens and lists nothing in the home folder or in Temper's own folder" "NO READ" "$(cat "$WORKDIR/audit.txt")"
assert_eq "pack-discover prints only the project's rows, nothing from the home folder" "LOCAL_CMD|local-cmd" \
  "$(printf '%s\n' "$PACK_OUT" | cut -d'|' -f1,2 | paste -sd' ' -)"
# The audit hook sees reads: the same run, watching the project's own .claude folder, records them.
HOME="$PACK_HOME" python3 -I "$AUDIT_PY" "$PD_WD_REAL/.claude" "$REPO_ROOT/scripts/pack-discover.py" >/dev/null 2>"$WORKDIR/audit.txt"
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

# --- guardrails-snippet.py: the guardrails pack's hook entries, printed for the person to add to a
# project settings file. The plugin folder is the one that holds the script, found after following
# links. Temper opens no Claude Code settings file: the script reads the pack's own snippet only. ---
setup
GS="$REPO_ROOT/scripts/guardrails-snippet.py"
GS_PROJ="$WORKDIR/gs-project"
GS_HOME="$WORKDIR/gs-home"
rm -rf "$GS_PROJ" "$GS_HOME" "$WORKDIR/gs-bin" "$WORKDIR/gs-q" "$WORKDIR/gs-loose" "$WORKDIR/gs-empty"
mkdir -p "$GS_PROJ/.claude" "$GS_HOME" "$WORKDIR/gs-bin"
ln -s "$GS" "$WORKDIR/gs-bin/guardrails-snippet.py"
cd "$GS_PROJ" || exit 1
GS_OUT="$(HOME="$GS_HOME" python3 "$GS" 2>"$WORKDIR/gs-err.txt")"; GS_RC=$?
assert_eq "guardrails-snippet exits 0 and prints nothing on stderr" "0|" "$GS_RC|$(cat "$WORKDIR/gs-err.txt")"
# Every command of the pack's snippet comes out in the same place, with the plugin folder in double
# quotes in place of the plugin root variable; the rest of the snippet is unchanged.
GS_CHECK="$(python3 - "$REPO_ROOT/packs/guardrails/settings-guardrails.json" "$REPO_ROOT" "$GS_OUT" <<'PY'
import json, sys
pack, root, out = json.load(open(sys.argv[1])), sys.argv[2], json.loads(sys.argv[3])
want = pack["hooks"]
got = out.get("hooks")
cmds = []
for event, blocks in want.items():
    for block in blocks:
        for hook in block["hooks"]:
            c = hook["command"]
            name = c.split("/scripts/guards/", 1)[1]
            hook["command"] = 'bash "%s/scripts/guards/%s"' % (root, name)
            cmds.append(hook["command"])
print("|".join([
    "same" if got == want else "differs",
    "keys:" + ",".join(sorted(out)),
    str(len(cmds)),
    cmds[0],
]))
PY
)"
assert_eq "guardrails-snippet prints the pack's hooks object, each command with the plugin folder in double quotes in place of the root variable" \
  "same|keys:hooks|8|bash \"$REPO_ROOT/scripts/guards/block-secrets.sh\"" "$GS_CHECK"
assert_eq "guardrails-snippet prints the same JSON on every run" "$GS_OUT" "$(HOME="$GS_HOME" python3 "$GS" 2>/dev/null)"
assert_eq "guardrails-snippet run through a link finds the plugin folder the link points at" \
  "$GS_OUT" "$(HOME="$GS_HOME" python3 "$WORKDIR/gs-bin/guardrails-snippet.py" 2>&1)"
# It refuses with exit 2 and one line: a plugin folder no command could quote, a script outside a
# scripts folder, and a plugin folder with no snippet.
mkdir -p "$WORKDIR/gs-q/it's/scripts" "$WORKDIR/gs-q/it's/packs/guardrails" "$WORKDIR/gs-loose" "$WORKDIR/gs-empty/scripts"
cp "$GS" "$WORKDIR/gs-q/it's/scripts/"; cp "$REPO_ROOT/packs/guardrails/settings-guardrails.json" "$WORKDIR/gs-q/it's/packs/guardrails/"
cp "$GS" "$WORKDIR/gs-loose/"; cp "$GS" "$WORKDIR/gs-empty/scripts/"
GS_REFUSE=""
for gs_copy in "$WORKDIR/gs-q/it's/scripts/guardrails-snippet.py" "$WORKDIR/gs-loose/guardrails-snippet.py" \
  "$WORKDIR/gs-empty/scripts/guardrails-snippet.py"; do
  gs_err="$(python3 "$gs_copy" 2>&1 >/dev/null)"; gs_rc=$?
  GS_REFUSE+="$gs_rc:$(printf '%s\n' "$gs_err" | wc -l | tr -d ' '):$(python3 "$gs_copy" 2>/dev/null | wc -c | tr -d ' ');"
done
assert_eq "guardrails-snippet refuses with exit 2, one line and no output for a quote in the plugin folder, no scripts folder and no snippet" \
  "2:1:0;2:1:0;2:1:0;" "$GS_REFUSE"
# Nothing but the pack's snippet is opened (a settings file of the project or the home folder would
# show here even when it does not exist), and no folder is listed. audit-opens.py <script> runs the script and prints, on stderr,
# every open, scandir and listdir it makes (the script file itself and Python's own files aside).
cat > "$WORKDIR/audit-opens.py" <<'PY'
import os, runpy, sys
script = sys.argv[1]
own = tuple({os.path.realpath(p) + os.sep for p in (sys.prefix, sys.base_prefix, sys.exec_prefix, sys.base_exec_prefix)})
seen, busy = [], []
def hook(event, args):
    if busy or event not in ("open", "os.scandir", "os.listdir") or not args or not isinstance(args[0], str):
        return
    busy.append(1)
    try:
        path = os.path.realpath(os.path.abspath(args[0]))
        if path != os.path.realpath(script) and not path.startswith(own):
            seen.append(event + " " + path)
    finally:
        busy.pop()
sys.addaudithook(hook)
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit:
    pass
print("\n".join(seen) if seen else "NOTHING", file=sys.stderr)
PY
HOME="$GS_HOME" python3 -I "$WORKDIR/audit-opens.py" "$GS" >/dev/null 2>"$WORKDIR/gs-audit.txt"
assert_eq "guardrails-snippet opens the pack's snippet and nothing else: no project or home settings file, no folder listing" \
  "open $(cd "$REPO_ROOT" && pwd -P)/packs/guardrails/settings-guardrails.json" "$(cat "$WORKDIR/gs-audit.txt")"
assert_eq "guardrails-snippet's source opens a file in one place and never asks for the home folder's contents" "1|0" \
  "$(grep -c 'open(' "$GS")|$(grep -cE 'expanduser|listdir|scandir|glob|walk\(|getcwd' "$GS")"
# No shipped script or mod file reads a Claude Code settings file: the one file that names the
# personal settings file is this script, in the words it prints and in its docstring.
assert_eq "no shipped script or mod file but guardrails-snippet.py names a project settings file to open" \
  "scripts/guardrails-snippet.py" \
  "$(cd "$REPO_ROOT" && grep -rlE 'settings\.local\.json|"settings\.json"' scripts hooks | grep -v '^scripts/selftest/' | sort | paste -sd' ' -)"
assert_eq "the lister that read the project's settings files is gone" "no" \
  "$([[ -e "$REPO_ROOT/scripts/guard-entries.py" ]] && echo yes || echo no)"
cd "$WORKDIR" || exit 1
rm -rf "$GS_PROJ" "$GS_HOME" "$WORKDIR/gs-bin" "$WORKDIR/gs-q" "$WORKDIR/gs-loose" "$WORKDIR/gs-empty" \
  "$WORKDIR/gs-err.txt" "$WORKDIR/gs-audit.txt" "$WORKDIR/audit-opens.py"

# --- stage-marker.sh + verify-stage-gate.sh: the standalone-stage gate guarantee ---
# stage-marker records the gate a /temper:{stage} session owes; verify-stage-gate blocks
# Stop until gates.json carries a verdict for it (any verdict), failing open after 2
# blocks. See docs/decisions/0005-deterministic-stage-gate-enforcement.md.
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/guards/verify-stage-gate.sh"

echo '{"prompt": "/temper:temper draft add a thing"}' | bash "$MARKER"
assert_eq "stage-marker records the owed stage" "intent" "$(python3 -c "import json; print(json.load(open('.temper/pending-stage.json'))['stage'])")"

rm -f .temper/pending-stage.json
echo '{"prompt": "please run /temper:temper draft an idea for me"}' | bash "$MARKER"
assert_eq "stage-marker ignores a mid-sentence mention" "absent" "$([[ -f .temper/pending-stage.json ]] && echo created || echo absent)"
echo '{"prompt": "/temper add login"}' | bash "$MARKER"
assert_eq "stage-marker ignores the unified /temper command" "absent" "$([[ -f .temper/pending-stage.json ]] && echo created || echo absent)"
# The stage commands are doors into /temper (ADR 0012): a session may end at any gate, so none is marked.
for door in plan design build review check; do
  echo "{\"prompt\": \"/temper:$door add a thing\"}" | bash "$MARKER"
  assert_eq "stage-marker does not mark the /temper:$door door" "absent" "$([[ -f .temper/pending-stage.json ]] && echo created || echo absent)"
done
echo 'not json at all' | bash "$MARKER"
assert_exit "stage-marker fails open on garbage stdin" 0 bash -c "echo garbage | bash '$MARKER'"

assert_exit "verify-stage-gate passes with no marker" 0 bash "$VERIFY"

echo '{"prompt": "/temper:temper draft x"}' | bash "$MARKER"
assert_exit "verify-stage-gate BLOCKS when no verdict exists" 2 bash "$VERIFY"
assert_eq "block is counted in the marker" "1" "$(python3 -c "import json; print(json.load(open('.temper/pending-stage.json'))['blocks'])")"

echo '{"intent": {"verdict": "FAIL"}}' > .temper/gates.json
assert_exit "a FAIL verdict satisfies the guarantee (gate ran)" 0 bash "$VERIFY"
assert_eq "marker cleared once the verdict exists" "absent" "$([[ -f .temper/pending-stage.json ]] && echo present || echo absent)"

rm -f .temper/gates.json
echo '{"prompt": "/temper:temper draft x"}' | bash "$MARKER"
bash "$VERIFY" >/dev/null 2>&1; bash "$VERIFY" >/dev/null 2>&1
assert_exit "loop guard fails open on the third stop attempt" 0 bash "$VERIFY"
assert_eq "loop-guard fail-open clears the marker" "absent" "$([[ -f .temper/pending-stage.json ]] && echo present || echo absent)"

echo '{"stage": "plan"' > .temper/pending-stage.json
assert_exit "corrupt marker fails open" 0 bash "$VERIFY"

# stop_hook_active with our counter at 0 means the marker isn't persisting — fail open
# rather than loop. (Regression: the harness JSON must travel as argv; piping it into
# `python3 - <<heredoc` silently discards it, since the heredoc owns stdin.)
rm -f .temper/pending-stage.json .temper/gates.json
echo '{"prompt": "/temper:temper draft x"}' | bash "$MARKER"
assert_exit "stop_hook_active with a stuck counter fails open" 0 \
  bash -c "echo '{\"stop_hook_active\": true}' | bash '$VERIFY'"
rm -f .temper/pending-stage.json
echo '{"prompt": "/temper:temper draft x"}' | bash "$MARKER"
assert_exit "stop_hook_active=false still blocks normally" 2 \
  bash -c "echo '{\"stop_hook_active\": false}' | bash '$VERIFY'"

# Time-scoping: a verdict from BEFORE the marker (a previous run's leftovers) must not
# satisfy this session's debt; one recorded after it must.
rm -f .temper/gates.json .temper/pending-stage.json
echo '{"intent": {"verdict": "PASS", "ts": "2020-01-01T00:00:00Z"}}' > .temper/gates.json
echo '{"prompt": "/temper:temper draft a new feature"}' | bash "$MARKER"
assert_exit "a pre-marker verdict does NOT pay this session's debt" 2 bash "$VERIFY"
python3 -c "
import json; g=json.load(open('.temper/gates.json'))
g['intent']['ts']='2099-01-01T00:00:00Z'; json.dump(g, open('.temper/gates.json','w'))"
assert_exit "a post-marker verdict does" 0 bash "$VERIFY"

# Backward compat: missing timestamps degrade to the any-verdict check, never a block.
rm -f .temper/pending-stage.json
echo '{"plan": {"verdict": "PASS"}}' > .temper/gates.json
echo '{"stage": "plan", "blocks": 0}' > .temper/pending-stage.json
assert_exit "verdict without ts + old marker format still clears" 0 bash "$VERIFY"

# End-to-end with the real CLI: marker -> real `temper gate plan` FAIL -> stop allowed.
rm -f .temper/gates.json .temper/pending-stage.json
echo '{"prompt": "/temper:temper draft x"}' | bash "$MARKER"
"$TEMPER" gate intent --spec-path .temper/specs/empty >/dev/null 2>&1 || true
assert_exit "a real gate verdict unblocks the stop" 0 bash "$VERIFY"

# --- temper model: config override > the stage brief's frontmatter, resolved in bash ---
setup
# Defaults come from the real stage briefs' frontmatter — no table in the CLI to drift.
assert_eq "model plan defaults to agents/plan.md frontmatter" \
  "$(awk '/^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1 && /^model:/{sub(/^model:[[:space:]]*/,""); print; exit}' "$REPO_ROOT/agents/plan.md")" \
  "$("$TEMPER" model plan)"
assert_eq "model --all emits one stage=model line per agent stage, plus the task agent's two" "14" "$("$TEMPER" model --all | grep -c '^[a-z-]*=')"
assert_eq "model --all covers every agent stage (incl. fix-command stages) and the task models" "intent plan plan-revise plan-review design acceptance build review check pipeline rca fix task task-escalation" \
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
assert_eq "an unset stage still falls back to frontmatter" "$("$TEMPER" model plan)" "$(cd "$REPO_ROOT" && env -u TEMPER_SELFTEST_ROOT ./scripts/temper model plan)"
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
"$TEMPER" state init bug2 --command fix >/dev/null; _base_known
mkdir -p test && echo 'assert(true)' > test/regression.spec.js

assert_exit "shield: no recorded regression test => edit passes" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

"$TEMPER" state set regression_test test/regression.spec.js >/dev/null
assert_exit "shield: editing the recorded regression test is BLOCKED" 2 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
OUT=$(echo '{"tool_input": {"file_path": "test/regression.spec.js"}}' | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$SHIELD" 2>&1; true)
assert_eq "shield: the block names the human release valve" "yes" "$(grep -q 'temper state set regression_test' <<<"$OUT" && echo yes || echo no)"

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
"$TEMPER" state init bug3 --command fix >/dev/null; _base_known
"$TEMPER" state set regression_test test/regression.spec.js >/dev/null
assert_exit "shield: garbage stdin fails open" 0 \
  bash -c "echo 'not json' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
"$TEMPER" state set regression_test "" >/dev/null
assert_exit "shield: a human clearing regression_test lifts the block" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"test/regression.spec.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"
rm -f .temper/build-state.json
assert_exit "shield: no state file fails open" 0 \
  bash -c "echo '{\"tool_input\": {\"file_path\": \"anything.js\"}}' | CLAUDE_PROJECT_DIR='$WORKDIR' bash '$SHIELD'"

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

### Rules covered
- Who: not applicable
- When: not applicable
- How much: not applicable
- Exempt: not applicable
- States: not applicable
- Where it shows: not applicable
- Exceptions: not applicable

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
assert_eq "the filled Problem counts as content" "yes" "$(grep -q '\[v\] problem stated' <<<"$OUT" && echo yes || echo no)"
assert_exit "a template-verbatim intent with only the Problem filled still FAILs" 1 "$TEMPER" gate intent
assert_eq "placeholder criteria bullets are not counted" "yes" "$(grep -q 'no real success criteria' <<<"$OUT" && echo yes || echo no)"
assert_eq "the placeholder Status line is not accepted" "yes" "$(grep -q 'placeholder doesn.t count' <<<"$OUT" && echo yes || echo no)"

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
ev_red build "tests"
ev_green build "tests"
_scen
"$TEMPER" gate build >/dev/null
review_done --cmd "review panel"
"$TEMPER" gate review >/dev/null
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
"$TEMPER" gate check >/dev/null
assert_exit "commit gate FAILs when intent.md exists but its gate never ran" 1 "$TEMPER" gate commit
"$TEMPER" gate intent >/dev/null
assert_exit "commit gate PASSes once the intent gate ran" 0 "$TEMPER" gate commit

# intent_complete is a valid /temper state transition; the fix sequence rejects it.
setup
_pass intent
assert_exit "a /temper run accepts intent_complete" 0 "$TEMPER" state advance intent_complete plan
assert_eq "state init points a temper run at the intent stage first" "intent" \
  "$(rm -f .temper/build-state.json; "$TEMPER" state init demo2 --command temper >/dev/null; "$TEMPER" state get next_stage)"

# stage-marker marks a session that captured a draft with /temper:temper draft (it owes a gate intent verdict; WP28).
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
echo '{"prompt": "/temper:temper draft capture this idea"}' | bash "$MARKER"
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
ev_red build "tests"
ev_green build "tests"
_scen
"$TEMPER" gate build >/dev/null
review_done --cmd "review panel"
"$TEMPER" gate review >/dev/null
ev_green check "tests"
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null
ev_scen check first
ev_scen check second
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
_at build   # WP32, rule 1 (D30): before the approval no commit is made, the spec folder's either (temper-cases-81.sh)
assert_exit "an all-specs staged set passes the commit gate mid-run (no stage verdicts)" 0 "$TEMPER" gate commit
OUT=$("$TEMPER" gate commit 2>&1)
assert_eq "the artifact-only carve-out names itself" "yes" "$(grep -q 'artifact-only commit' <<<"$OUT" && echo yes || echo no)"
echo 'code' > src.js
git add src.js >/dev/null 2>&1
assert_exit "one staged file outside .temper/specs/ restores every gate requirement" 1 "$TEMPER" gate commit

# --- 9.7.3: override records that the person decided it, and asks git for no name or email ---
setup
git config user.name "Jane Approver"
git config user.email "jane@example.com"
OV_OUT="$(USER=jane-login "$TEMPER" override review --reason "accepted the risk")"
assert_eq "override entry records that the person decided it, with no git name, email or login name" "the person|0" \
  "$(python3 -c "import json; print(json.load(open('.temper/overrides.json'))[0]['by'])")|$({ cat .temper/overrides.json; printf '%s' "$OV_OUT"; } | grep -cE 'Jane|jane')"
# No shipped script asks git for a name or an email, or reads a login name.
assert_eq "no shipped script runs git config user.name or user.email, or reads USER or LOGNAME" "" \
  "$(cd "$REPO_ROOT" && { echo scripts/temper; git ls-files 'scripts/*.py' 'scripts/guards/*.sh'; } | grep -v '^scripts/selftest/' \
    | xargs grep -lE 'config[^|;&]*user\.(name|email)|\$\{?(USER|LOGNAME)\b|environ[^)]*(USER|LOGNAME)|whoami|getpass|getlogin|getpwuid' || true)"
# git needs an identity for the commits the CLI makes: _git_id_args asks git only whether it has one
# (an exit status) and passes a fixed one when it has none.
GID_HOME="$WORKDIR/gid-home"; GID_REPO="$WORKDIR/gid-repo"
rm -rf "$GID_HOME" "$GID_REPO"; mkdir -p "$GID_HOME" "$GID_REPO"; git -C "$GID_REPO" init -q
GID_OUT="$(cd "$GID_REPO" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL \
  -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  HOME="$GID_HOME" XDG_CONFIG_HOME="$GID_HOME" GIT_CONFIG_NOSYSTEM=1 bash -c "$(sed -n '/^_git_id_args() {/,/^}/p' "$TEMPER")"'
_git_id_args; echo "|"; git config user.email "some@example.com"; _git_id_args; echo "|"; git config user.name "Some One"; _git_id_args')"
assert_eq "_git_id_args passes a fixed identity unless git has one set (never one guessed from the system), and prints nothing of git's own" \
  "-c user.name=Temper -c user.email=temper@localhost
|
-c user.name=Temper -c user.email=temper@localhost
|" "$GID_OUT"
rm -rf "$GID_HOME" "$GID_REPO"

# --- v9: the gate ledger is archived into the spec dir (audit trail survives) ---
setup
"$TEMPER" gate intent >/dev/null
"$TEMPER" gate plan >/dev/null
"$TEMPER" override plan --reason "test archive" >/dev/null
"$TEMPER" evidence run --stage build --claim "tests" --label HEURISTIC -- true >/dev/null
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
