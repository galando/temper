# Case file 87 (adversarial review 7): the tests themselves. Sourced by test-temper.sh; its helpers (fresh, gpass,
# _unattended, setup) are used here. Each check is a finding of the review: it failed on the code under review, and
# the commit that added it fixed it. The first words of every assertion are "review 7:". The review's check of past
# commits of the floor (F3) is not here: it reads commits that are never rewritten.

# --- the helpers of this file ---
_repo87() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_next87() { # what next does: its action and its calls, the path of the CLI left out
  "$TEMPER" next --json 2>/dev/null | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
print("%s %s" % (d.get("action"), " ".join(re.sub(r"^\S*/temper ", "", c) for c in d.get("calls") or [])[:120]))'
}

# --- F1: rules 4, 5 and 9: the suite's failed run is replaced by a passing run of another command, under its claim ---
# An unattended run at Check whose suite (check.commands.test) fails: the CLI runs it and the run stops. The session
# then types `temper evidence run` with the suite's own claim and the command `true`. The suite was not run again and
# still fails on this tree, no budget was spent, and the gate's command was not changed by the person; the Check gate
# must stay FAIL and next must not go on by rule.
_unattended check; _repo87
printf 'check:\n  commands:\n    test: "exit 1"\n' >> .claude/temper.config
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_f1_before="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['check']['verdict'])" 2>/dev/null)"
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
_f1_after="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['check']['verdict'])" 2>/dev/null)"
_f1_next="$(_next87)"
assert_eq "review 7: a passing evidence run of another command under the suite's claim does not pass Check while the suite fails" \
  "before=FAIL|after=FAIL|no state advance by rule" \
  "before=$_f1_before|after=$_f1_after|$([[ "$_f1_next" == auto*"state advance check_complete"* ]] && echo "$_f1_next" || echo 'no state advance by rule')"

# The same for a scenario: its declared Test fails, and a passing run of `true` under the scenario's name covers it.
fresh; sed -i '0,/^  Test: true$/s//  Test: sh src\/first_test.sh/' .temper/specs/demo/intent.md
_prev87=intent
for _s87 in plan build review check; do
  gpass "$_prev87"; [[ "$_prev87" == plan ]] && "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
  "$TEMPER" state advance "${_prev87}_complete" "$_s87" >/dev/null 2>&1; _prev87="$_s87"
done
_repo87; echo 'exit 1' > src/first_test.sh; git add src/first_test.sh; git commit -q -m test
"$TEMPER" check run >/dev/null 2>&1
_f1s_row() { python3 -c "
import json
g = json.load(open('.temper/gates.json'))['check']
print(next((str(r.get('pass')) for r in g.get('requirements') or [] if r.get('name') == 'scenarios traced to tests'), 'absent'))" 2>/dev/null; }
"$TEMPER" gate check >/dev/null 2>&1; _f1s_before="$(_f1s_row)"
"$TEMPER" evidence run --stage check --scenario first --claim 'scenario: first -> sh src/first_test.sh' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1; _f1s_after="$(_f1s_row)"
assert_eq "review 7: a passing evidence run of another command under a scenario's name does not cover the scenario whose Test fails" \
  "before=False|after=False" "before=$_f1s_before|after=$_f1s_after"


# --- F2: D38e sets three of the old loop keys high with a sed that, since WP29, matches nothing in the selftest config ---
# D38e (case 45) said it set loops.max-per-type, autonomy.budget.max-total-loops and autonomy.budget.max-stages high with
# a sed over the config setup() writes, which holds none of them since WP29, so "set high they change no refusal" was
# proven for fix.max-loops alone. The check runs D38e's own setup lines (from the line that sets fix.max-loops to the
# first repeat) on the same config and reads what they set. The review's check ran a copy of the sed; a copy would stay
# as it was when D38e changes, so the check reads case 45 itself.
fresh
_f2_setup="$(awk '/max-loops: 9/ {on = 1} on && /^for _i in 1 2; do gfail check/ {exit} on' "$TESTS_DIR/temper-cases-45.sh")"
eval "$_f2_setup"
assert_eq "review 7: D38e's config holds each old loop key it says it sets high" \
  "max-per-type: 9|max-total-loops: 99|max-stages: 99" \
  "$(grep -oE 'max-per-type: 9|max-total-loops: 99|max-stages: 99' .claude/temper.config | paste -sd'|' -)"

# --- F3: NEW-RULES-1 (rule 5): one `evidence run` of `true` under a claim only the CLI's checks write ---
# The acceptance row, a fix's regression proof and a fix's `tests pass` read rows by claim; a run of another command
# under such a claim stands for no run of the locked tests or of the suite (as F1 holds for Check's suite). The gates
# count only a run of the lock's command (acceptance) or of the suite owner's command (a fix run), and the audit's
# scratch run showed the Build verdict itself flipping PASS in an unattended run.
_built87() { # the group and its task passed, as the CLI's group gate leaves them
  python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d["groups"]["G1"].update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
}
_row87() { # _row87 <row name> [python over r that sets r]: pass of that row of the Build verdict, or absent
  python3 - "$1" "${2:-r = str(x.get('pass'))}" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get("build") or {}
except (OSError, ValueError):
    e = {}
x = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[1]), None)
if x is None:
    print("absent")
else:
    r = None
    exec(sys.argv[2])
    print(r)
PY
}
_acc87() { # _acc87 [skip]: a run at Build whose acceptance test (it prints FAIL: acc and exits 1) is locked, or with
           # `skip` one whose writer skipped the tests (a passing file on disk, no lock: a skip never lifts a lock); the
           # task passed, a RED and a GREEN recorded
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done' | m_setup
  "$TEMPER" acceptance start >/dev/null 2>&1
  mkdir -p .temper/specs/demo/acceptance
  if [[ "${1:-}" == skip ]]; then
    printf 'exit 0\n' > .temper/specs/demo/acceptance/accept_test.sh
    "$TEMPER" acceptance skip --reason 'the writer locked no test' >/dev/null 2>&1
  else
    printf 'echo "FAIL: acc"\nexit 1\n' > .temper/specs/demo/acceptance/accept_test.sh   # a script: the test's own output, then its exit
    "$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1
  fi
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase red -- false >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase green -- true >/dev/null 2>&1
  _built87
  "$TEMPER" integrate >/dev/null 2>&1 || true
  "$TEMPER" gate build >/dev/null 2>&1
}
_fix87() { # a fix run whose suite's second test still fails and that changed no test: both fix rows fail the Build gate
  setup; rm -rf .git src unit; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  mkdir -p src unit
  echo 'echo 1' > src/total87.sh; echo 'echo a' > src/other87.sh
  printf '[ "$(bash src/total87.sh)" = 2 ] || { echo "FAIL: test_total expected 2"; exit 1; }\n' > unit/test_total87.sh
  printf '[ "$(bash src/other87.sh)" = b ] || { echo "FAIL: test_other expected b"; exit 1; }\n' > unit/test_other87.sh
  python3 -B - <<'PY'
p = ".claude/temper.config"
s = open(p).read()
s = s.replace("  coverage-threshold: 80\n", '  coverage-threshold: 80\n  commands:\n    test: "bash unit/test_total87.sh && bash unit/test_other87.sh"\n', 1)
open(p, "w").write(s)
PY
  git add -A >/dev/null 2>&1; git commit -q -m base
  rm -f .temper/groups.json .temper/view.json .temper/build-state.json
  "$TEMPER" state init bug --command fix --feature "the total is one short" >/dev/null 2>&1; _base_known
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  mkdir -p .temper/specs/bug
  printf '# RCA: the total is one short\n\n## Root cause\n\nsrc/total87.sh prints 1.\n\n## Fix\n\nPrint 2.\n' > .temper/specs/bug/rca.md
  gpass rca; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
  echo 'echo 2' > src/total87.sh   # the fix; unit/test_other87.sh still fails (it needs a change of its own)
  "$TEMPER" check build-checks >/dev/null 2>&1 || true
  "$TEMPER" gate build >/dev/null 2>&1
}
_f3_next() { # what next does while the run is marked as going on by itself: its action and calls
  _ran_unattended; _next87
}
_acc87
assert_eq "review 7: the fixture's lock is taken (its command is recorded) and the Build gate fails on the locked test's own output" \
  "sh .temper/specs/demo/acceptance/accept_test.sh|FAIL: acc" \
  "$(python3 -c "import json; print(json.load(open('.temper/evidence/acceptance-lock.json')).get('cmd'))")|$(_row87 'acceptance tests written before Build' "r = ' '.join(str(x.get('detail') or '').split())[:40]")"
_f3_before="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['build']['verdict'])" 2>/dev/null)"
_f3n_before="$(_f3_next)"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build)' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_f3_after="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['build']['verdict'])" 2>/dev/null)"
_f3n_after="$(_f3_next)"
assert_eq "review 7: a passing evidence run of true under the acceptance claim passes no Build verdict, and no unattended run goes on by it" \
  "before=FAIL|after=FAIL|row=False|no advance before|no advance after" \
  "before=$_f3_before|after=$_f3_after|row=$(_row87 'acceptance tests written before Build')|$([[ "$_f3n_before" == auto*'state advance build_complete'* ]] && echo 'advance before' || echo 'no advance before')|$([[ "$_f3n_after" == auto*'state advance build_complete'* ]] && echo 'advance after' || echo 'no advance after')"

# A genuine re-run of the locked command through evidence run is read: the row fails on that run, not with the "no run
# of the locked acceptance command" note. The re-run keeps its exit code alone (cmd_evidence_run records no output), so
# the row says the exit; the checks' own run of the locked command (above) fails on the test's own output.
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build)' \
  -- sh .temper/specs/demo/acceptance/accept_test.sh >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 7: a re-run of the locked acceptance command still counts: the row fails on that run and says its exit, never the no-run note" \
  "row=False|detail=the locked command exited 1 (a re-run through evidence run keeps its exit code, not its output)" \
  "row=$(_row87 'acceptance tests written before Build')|detail=$(_row87 'acceptance tests written before Build' "r = ' '.join(str(x.get('detail') or '').split())")"

# The ': skipped' form: a run of `true` under either claim leaves the writer's skip a skip (never a pass).
_acc87 skip
_f3s_before="$(_row87 'acceptance tests written before Build' "r = '%s:%s' % (x.get('pass'), x.get('state'))")"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build)' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_f3s_after="$(_row87 'acceptance tests written before Build' "r = '%s:%s' % (x.get('pass'), x.get('state'))")"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build): skipped' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_f3s_after2="$(_row87 'acceptance tests written before Build' "r = '%s:%s' % (x.get('pass'), x.get('state'))")"
assert_eq "review 7: a passing evidence run of true under the acceptance claim or its ': skipped' form leaves the writer's skip a skip" \
  "before=None:skipped|after=None:skipped|after2=None:skipped" \
  "before=$_f3s_before|after=$_f3s_after|after2=$_f3s_after2"

# A fix run: `true` under the regression proof's claim or the suite's claim ('Integration suite') passes no row, while
# the suite's own command still counts (its run is read, and fails on its output here).
_fix87
_f3f_before="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['build']['verdict'])" 2>/dev/null)"
"$TEMPER" evidence run --stage build --claim 'Integration suite' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_f3f_suite="$(_row87 'tests pass')"
"$TEMPER" evidence run --stage build --claim 'regression proof' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_f3f_verdict="$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['build']['verdict'])" 2>/dev/null)"
assert_eq "review 7: a passing evidence run of true under a fix run's suite claim or regression proof claim passes neither row nor the Build verdict" \
  "before=FAIL|suite=False|after=FAIL" \
  "before=$_f3f_before|suite=$_f3f_suite|after=$_f3f_verdict"
assert_eq "review 7: in the fix run the suite's row reads the suite's own run, which fails on its second test, never the run of true" \
  "False|the suite's own run, exited 1" \
  "$(_row87 'tests pass')|$(_row87 'tests pass' "d = str(x.get('detail') or ''); r = 'the suite\'s own run, exited 1' if d.startswith('the suite (bash unit/test_total87.sh') and d.endswith(') exited 1') else ' '.join(d.split())[:60]")"
"$TEMPER" evidence run --stage build --claim 'regression proof' \
  -- bash unit/test_total87.sh '&&' bash unit/test_other87.sh >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 7: a re-run of the suite's own command still counts as the proof: the row fails on the suite's run, never on the note" \
  "row=False|note=absent" \
  "row=$(_row87 'regression proof')|note=$([[ "$(_row87 'regression proof' "r = str(x.get('detail') or '')")" == *'counts nowhere'* ]] && echo present || echo absent)"
