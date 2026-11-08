# Implicit state machines made explicit, part 1: the CLI's lifecycle state machines (scripts/temper, adhoc_ops.py, answer_ops.py, loop_step.py): one table of allowed moves each.
# Sourced by test-temper.sh after temper-cases-16.sh (helpers: nx, vw, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

_st() { python3 -c "import json,sys; d=json.load(open('.temper/build-state.json')); v=d.get(sys.argv[1], '-'); print('-' if v is None else v)" "$1"; }
_rows() { python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$1" 2>/dev/null || echo none; }
_setj() { # _setj <file> <python expression over d>: change one JSON file of the run (a fixture, as a test writes it by hand)
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(d, open(sys.argv[1], 'w'), indent=2)" "$1" "$2"
}

# --- A1. state loop: the stages of the run's own sequence, from a stage the run has reached, back to an earlier one ---
fresh; _at review
assert_exit "A1: a /temper run's loop to rca (a stage of a fix run) is refused" 1 "$TEMPER" state loop review rca --reason x
assert_eq "A1: the refused loop leaves the run where it is" "review" "$(_st next_stage)"
assert_exit "A1: a loop from a stage the run has not reached (check, at Review) is refused" 1 "$TEMPER" state loop check build --reason x
assert_exit "A1: a loop goes back: to a stage after its from stage is refused" 1 "$TEMPER" state loop build review --reason x
assert_exit "A1: a loop from a stage that is no stage of the run is refused" 1 "$TEMPER" state loop bogus build --reason x
assert_exit "A1: a loop back from the stage the run is at passes" 0 "$TEMPER" state loop review build --reason x
rm -f .temper/build-state.json
assert_exit "A1: with no run state a loop is refused (nothing to send back)" 1 "$TEMPER" state loop review build --reason x

# --- A2, A5, A12, A15. A step back by state set next_stage does what a state loop does: one way back ---
fresh; gpass intent plan build review check
for s in build review check commit pipeline; do printf '[{"claim": "row of %s", "exit_code": 0}]\n' "$s" > ".temper/evidence/$s.json"; done
_setj .temper/build-state.json "d['stage'] = 'check_complete'; d['next_stage'] = 'commit'; d['end_report'] = 'html'; d['built_before'] = 'abc'; d['enter'] = 'review'"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed"}}, "tasks": {}}\n' > .temper/groups.json
assert_exit "A2: state set next_stage to an earlier stage goes back" 0 "$TEMPER" state set next_stage build
assert_eq "A2: it clears the evidence of the stages it redoes, as a loop does (A15: commit and pipeline too)" "0|0|0|0|0" \
  "$(_rows .temper/evidence/build.json)|$(_rows .temper/evidence/review.json)|$(_rows .temper/evidence/check.json)|$(_rows .temper/evidence/commit.json)|$(_rows .temper/evidence/pipeline.json)"
assert_eq "A2: and moves a door's entry back to the stage, as a loop does" "build" "$(_st enter)"
assert_eq "A5: the bookkeeping stage is the stage before the one the run is at again (no longer check_complete)" "design_complete" "$(_st stage)"
assert_eq "A12: a run sent back from Commit shows its report again: end_report is gone" "-" "$(_st end_report)"
"$TEMPER" state set next_stage plan >/dev/null 2>&1
assert_eq "A2: going back before Build ends the grouped run and forgets the earlier build, as a loop does" "no|" \
  "$([[ -f .temper/groups.json ]] && echo yes || echo no)|$(python3 -c "import json; print(json.load(open('.temper/build-state.json')).get('built_before', ''))")"
assert_eq "A5: back at Plan the stage is intent_complete" "intent_complete" "$(_st stage)"
fresh; gpass intent plan build review check; _at check
_setj .temper/build-state.json "d['stage'] = 'review_complete'"
printf '[{"claim": "x", "exit_code": 0}]\n' > .temper/evidence/commit.json
"$TEMPER" state loop check build --reason x >/dev/null 2>&1
assert_eq "A5, A15: a loop rewrites the stage too, and clears Commit's evidence" "design_complete|0" "$(_st stage)|$(_rows .temper/evidence/commit.json)"
fresh; "$TEMPER" state init demo --command fix >/dev/null 2>&1; _at check
printf '[{"claim": "x", "exit_code": 0}]\n' > .temper/evidence/commit.json
"$TEMPER" state loop check fix --reason x >/dev/null 2>&1
assert_eq "A5, A15: in a fix run a loop to Fix clears Commit's evidence and the stage is rca_complete" "0|rca_complete" "$(_rows .temper/evidence/commit.json)|$(_st stage)"

# --- A3, A4. temper override: a gate of the run, and a skip covers the verdict it was given for ---
fresh
assert_exit "A3: an override of a stage that is no gate (a typo) is refused" 1 "$TEMPER" override biuld --reason x
assert_eq "A3: and nothing is recorded" "[]" "$(tr -d '[:space:]' < .temper/overrides.json)"
assert_exit "A3: an override of a gate of the run is recorded" 0 "$TEMPER" override check --reason x
assert_exit "A3: rca is no gate (a fix run's gates are build, review, check and commit)" 1 "$TEMPER" override rca --reason x
gpass intent plan build review
printf '{"intent": {"verdict": "PASS"}, "plan": {"verdict": "PASS"}, "build": {"verdict": "PASS"}, "review": {"verdict": "PASS"}, "check": {"verdict": "FAIL", "requirements": [], "ts": "2026-01-02T00:00:00Z"}}\n' > .temper/gates.json
printf '[{"stage": "check", "reason": "x", "by": "the person", "ts": "2026-01-01T00:00:00Z"}]\n' > .temper/overrides.json
assert_eq "A3, A4: a skip older than the verdict does not cover it (the check ran again after the skip)" "1" \
  "$("$TEMPER" gate commit 2>&1 | grep -c 'check gate — FAIL, no override recorded')"
printf '[{"stage": "check", "reason": "x", "by": "the person", "ts": "2026-01-03T00:00:00Z"}]\n' > .temper/overrides.json
assert_eq "A3, A4: a skip given after the verdict covers it" "1" "$("$TEMPER" gate commit 2>&1 | grep -c 'check gate — FAIL, overridden by human')"
printf '[{"stage": "check", "reason": "x", "by": "the person"}]\n' > .temper/overrides.json
assert_eq "A3: a skip with no time (an older run) still covers its stage" "1" "$("$TEMPER" gate commit 2>&1 | grep -c 'check gate — FAIL, overridden by human')"

# --- A6, A7. state set: the lifecycle records are the CLI's, and the values it takes are checked ---
fresh
for k in stage command parked adhoc adhoc_done redo stage.x adhoc.stage; do
  assert_exit "A6: state set $k is refused (the CLI keeps it)" 1 "$TEMPER" state set "$k" x
done
assert_eq "A6: the refused writes changed nothing" "started|temper|-" "$(_st stage)|$(_st command)|$(_st adhoc)"
assert_exit "A6: run_mode takes interactive or autonomous only" 1 "$TEMPER" state set run_mode fast
assert_exit "A6: run_mode autonomous is taken" 0 "$TEMPER" state set run_mode autonomous
assert_exit "A6: pipeline_round counts one up at a time: 3 after round 1 is refused" 1 "$TEMPER" state set pipeline_round 3
assert_exit "A6: pipeline_round is a number" 1 "$TEMPER" state set pipeline_round two
assert_exit "A6: pipeline_round 2 after round 1 is taken" 0 "$TEMPER" state set pipeline_round 2
assert_exit "A6: pipeline_round never goes down" 1 "$TEMPER" state set pipeline_round 1
mkdir -p reg; echo 'x' > reg/a_test.sh; echo 'y' > reg/b_test.sh
assert_exit "A6: regression_test names a file of the project" 1 "$TEMPER" state set regression_test /etc/hostname
assert_exit "A6: regression_test never names a file outside the project" 1 "$TEMPER" state set regression_test ../x
assert_exit "A6: regression_test names a file that is there" 1 "$TEMPER" state set regression_test reg/none.sh
assert_exit "A6: regression_test takes the test file" 0 "$TEMPER" state set regression_test reg/a_test.sh
assert_exit "A6: the same file again is taken" 0 "$TEMPER" state set regression_test reg/a_test.sh
assert_exit "A6: a shield in place does not move to another file" 1 "$TEMPER" state set regression_test reg/b_test.sh
assert_exit "A6: \"\" lifts it" 0 "$TEMPER" state set regression_test ""
assert_exit "A6: once lifted, another file is taken" 0 "$TEMPER" state set regression_test reg/b_test.sh
rm -rf reg
rm -f .temper/build-state.json
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_eq "A7: run_mode autonomous set with no run state yet still records ran_unattended" "True" "$(_st ran_unattended)"

# --- A8. A group is passed exactly while its gate says PASS ---
f9_tasks | m_setup
_setj .temper/groups.json "d['groups']['G1'].update({'status': 'passed', 'gate': {'verdict': 'PASS', 'ts': 'x'}, 'finished_at': 'x'})"
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "A8: a group gate that fails after a PASS takes the group back to running, with no finished time" "FAIL|running|None" \
  "$(python3 -c "import json; g=json.load(open('.temper/groups.json'))['groups']['G1']; print('%s|%s|%s' % (g['gate']['verdict'], g['status'], g.get('finished_at')))")"
_setj .temper/groups.json "d['groups']['G1']['status'] = 'parked'"
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "A8: a parked group stays parked when its gate fails" "parked" "$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['status'])")"

# --- A9. A reopen asks the group question again and merges the groups again ---
f9_tasks | m_setup
_setj .temper/groups.json "d['groups']['G1'].update({'status': 'passed', 'gate': {'verdict': 'PASS'}, 'confirmed': 'x'}); d['integration'] = {'verdict': 'PASS'}"
assert_exit "A9: group reopen of a task" 0 "$TEMPER" group reopen G1 --task 1
assert_eq "A9: the reopen drops the person's Continue of the group and the merge verdict" "-|-" \
  "$(python3 -c "import json; d=json.load(open('.temper/groups.json')); print('%s|%s' % (d['groups']['G1'].get('confirmed', '-'), d.get('integration', '-')))")"

# --- A10. A task's status moves only by the table of task_cover.py ---
assert_eq "A10: the table's moves; a move it does not have is refused" "running|refused|refused|pending|refused" "$(python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
from task_cover import set_status
def mv(old, new):
    t = {'status': old} if old else {}
    try:
        set_status(t, new)
        return t['status']
    except ValueError:
        return 'refused'
print('|'.join([mv(None, 'running'), mv('passed', 'running'), mv('running', 'pending'), mv('failed', 'pending'), mv('pending', 'done')]))" "$REPO_ROOT/scripts")"
f9_tasks | m_setup
_setj .temper/groups.json "d['tasks']['1'] = {'group': 'G1', 'status': 'passed', 'attempts': []}"
assert_exit "A10: a passed task is not started again" 1 "$TEMPER" task start 1
assert_eq "A10: and stays passed" "passed" "$(m_field 1 status)"

# --- A11. The small change window: at the stage the run is at, owned by it, its gate step marked by its own gate ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
rm -rf .git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
assert_exit "A11: a window opens only at the stage the run is at (Check, at Build, is refused)" 1 "$TEMPER" adhoc open --stage check --reason x
assert_exit "A11: at Build it opens" 0 "$TEMPER" adhoc open --stage build --reason x
mkdir -p src; echo one > src/a.sh
"$TEMPER" adhoc close >/dev/null 2>&1
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "A11: another stage's gate does not mark the window's gate step" "gate" \
  "$(python3 -c "import json; print(','.join((json.load(open('.temper/build-state.json')).get('adhoc_done') or {}).get('steps', [])))")"
"$TEMPER" adhoc open --stage build --reason y >/dev/null 2>&1
assert_eq "A11: a second window keeps the step the first change still owes" "gate" \
  "$(python3 -c "import json; print(','.join((json.load(open('.temper/build-state.json')).get('adhoc_done') or {}).get('steps', [])))")"
"$TEMPER" adhoc close >/dev/null 2>&1
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
assert_eq "A11: leaving the stage ends the window's record (adhoc_done goes with the move)" "-" "$(_st adhoc_done)"
"$TEMPER" adhoc open --stage review --reason z >/dev/null 2>&1
"$TEMPER" state redo review --reason again >/dev/null 2>&1
assert_eq "A11: a redo of the stage ends an open window" "-" "$(_st adhoc)"
assert_eq "A11: the stages a window opens at are one constant, importable" "build,review,check,commit,pipeline" \
  "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import adhoc_ops; print(','.join(adhoc_ops.ADHOC_STAGES))" "$REPO_ROOT/scripts")"
rm -rf .git src; git init -q . 2>/dev/null

# --- A13. intent complete only after intent accept ---
fresh
sed -i 's/^\*\*Status:\*\* accepted$/**Status:** draft/' .temper/specs/demo/intent.md
assert_exit "A13: intent complete of a draft is refused" 1 "$TEMPER" intent complete
assert_eq "A13: and the draft stays a draft" "1|0" "$(grep -c '^\*\*Status:\*\* draft$' .temper/specs/demo/intent.md)|$(grep -c '^\*\*Completed:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent accept >/dev/null 2>&1
assert_exit "A13: once accepted, intent complete passes" 0 "$TEMPER" intent complete
assert_exit "A13: a second complete changes nothing" 0 "$TEMPER" intent complete
assert_eq "A13: completed once" "1|1" "$(grep -c '^\*\*Status:\*\* completed$' .temper/specs/demo/intent.md)|$(grep -c '^\*\*Completed:\*\*' .temper/specs/demo/intent.md)"

# --- A14. A Design: answer resolves the concern it names, never a guess between two ---
_i17() { # an intent with one Blocking Design: question and a design.md with the concerns given
  fresh
  printf '# Intent: Demo\n\n**Status:** draft\n\n### Open Questions\n\n- Blocking: Design: %s choices: A | B\n\n### Decisions\n\n- (none yet)\n' "$1" > .temper/specs/demo/intent.md
  printf '# Design\n\n## Areas of Concern\n\n### %s\n\nx\n\n### %s\n\ny\n' "$2" "$3" > .temper/specs/demo/design.md
}
_i17 "How is the cache cleared?" "The cache clearing on price change" "The cache warming on deploy"
"$TEMPER" intent answer 'Design: How is the cache cleared?' 'A' >/dev/null 2>&1
assert_eq "A14: two concerns that share as many words with the question: neither is resolved" "0" "$(grep -c '^resolved:' .temper/specs/demo/design.md)"
_i17 "Logs hold customer names: mask them?" "Logs hold customer names" "Logs hold customer names in traces too"
"$TEMPER" intent answer 'Design: Logs hold customer names: mask them?' 'A' >/dev/null 2>&1
assert_eq "A14: the concern whose title the question names is resolved, not the wordier one" "1|0" \
  "$(sed -n '/^### Logs hold customer names$/,/^### Logs hold customer names in/p' .temper/specs/demo/design.md | grep -c '^resolved: A$')|$(sed -n '/in traces too/,$p' .temper/specs/demo/design.md | grep -c '^resolved:')"

# --- A17, A18. The step back budget: loop_step.budget, the rule temper next offers it by ---
assert_eq "A17: budget: build->plan once; check->build takes fix.max-loops when set; else loops.max-per-type (default 2)" "1|5|3|2|2" "$(python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
from loop_step import budget
c = lambda vals: (lambda k, d='': vals.get(k, d))
print('|'.join(str(x) for x in [budget('build', 'plan', c({'loops.max-per-type': '5'})), budget('check', 'build', c({'loops.max-per-type': '3', 'fix.max-loops': '5'})),
      budget('review', 'build', c({'loops.max-per-type': '3', 'fix.max-loops': '5'})), budget('review', 'build', c({})), budget('review', 'build', c({'loops.max-per-type': 'x'}))]))" "$REPO_ROOT/scripts")"
fresh; gpass intent plan; _at build
assert_exit "A17: the first step back from Build to Plan is taken" 0 "$TEMPER" state loop build plan --reason x
_at build
assert_exit "A17: a second one is refused, as temper next says (build->plan is once per run)" 1 "$TEMPER" state loop build plan --reason y
fresh; gpass intent plan build review; _at review
"$TEMPER" state loop review build --reason x >/dev/null 2>&1
sed -i 's/^  max-per-type: 2$/  max-per-type: 3/' .claude/temper.config
_at review
"$TEMPER" state loop review build --reason y >/dev/null 2>&1
assert_eq "A18: each step stores the budget as it is now" "2|3" \
  "$(python3 -c "import json; l=json.load(open('.temper/feedback-loops.json'))['active_loops'][0]; print('%s|%s' % (l['iteration'], l['max_iterations']))")"

# --- A20. A finding's state, one reading of the shape the CLI writes ---
assert_eq "A20: finding_state reads resolved, accepted, contested, escalated and open" "resolved|accepted|contested|escalated|open|open" "$(python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
from findings import finding_state
print('|'.join(finding_state(r) for r in [{'resolved': {'fixed_by': 'a'}}, {'accepted': {'reason': 'r'}}, {'contested': {'cite': 'c'}},
      {'escalated': {'reason': 'r'}}, {'severity': 'high'}, 'not a row']))" "$REPO_ROOT/scripts")"
fresh; mkdir -p .temper/evidence
printf '[{"claim": "a", "severity": "critical", "label": "PROVEN", "contested": {"cite": "x", "quote": "q", "reason": "r"}}, {"claim": "review completed", "exit_code": 0}]\n' > .temper/evidence/review.json
assert_eq "A20: a contested finding still counts against the Review gate" "1" "$("$TEMPER" gate review 2>&1 | grep -c 'contested: x')"

# --- A16: a writer waits on for a lock holder that is alive (up to TEMPER_LOCK_MAX_S), and writes past only a gone or stuck one ---
setup; mkdir -p .temper/evidence .temper/.lock
sleep 30 & HOLDER=$!
printf '%s.1' "$HOLDER" > .temper/.lock/owner
( sleep 2.5; rm -rf .temper/.lock ) & FREE=$!
out="$(TEMPER_LOCK_WAIT_S=1 "$TEMPER" evidence add --stage build --claim "after a live holder" 2>&1)"; rc=$?
wait "$FREE"
assert_eq "A16: a holder that is alive is waited for past the wait: the row lands under the lock, with no WARN" "0|0|1" \
  "$rc|$(printf '%s' "$out" | grep -c WARN)|$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")"
mkdir -p .temper/.lock; printf '%s.1' "$HOLDER" > .temper/.lock/owner
out="$(TEMPER_LOCK_WAIT_S=1 TEMPER_LOCK_MAX_S=2 "$TEMPER" evidence add --stage build --claim "past a stuck holder" 2>&1)"; rc=$?
assert_eq "A16: a live holder past TEMPER_LOCK_MAX_S is written past with a WARN (a stuck holder never wedges a run)" "0|1|yes" \
  "$rc|$(printf '%s' "$out" | grep -c 'WARN.*lock')|$([[ -d .temper/.lock ]] && echo yes || echo no)"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
rm -rf .temper/.lock
