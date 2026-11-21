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

