# Implicit state machines made explicit, part 2: the flow's derived states (flow.py and the task, finding and intent row modules): one definition each.
# Sourced by test-temper.sh after temper-cases-17.sh (helpers: nx, vw, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

# --- B2: a RED that passed is COVERED only when the attempt holds no problem of its own ---
b2_red_passed() { # a run with Task 1 started and its RED passed (its Test: is `true`)
  m_setup < <(f9_tasks)
  "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
}
b2_red_passed
assert_eq "B2: a RED that passed with nothing else changed is still COVERED" "0|covered" \
  "$("$TEMPER" task gate 1 --model m >/dev/null 2>&1; echo $?)|$(m_field 1 status)"
b2_red_passed; echo stray > .claude/worktrees/temper-demo-T1/stray.txt
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "B2: a RED that passed beside an undeclared change FAILs and names it (not COVERED)" "1|failed|1" \
  "$rc|$(m_field 1 status)|$(printf '%s' "$out" | grep -c 'undeclared change: stray.txt')"
b2_red_passed; mkdir -p .claude/worktrees/temper-demo-T1/src; echo x > .claude/worktrees/temper-demo-T1/src/a.sh
git -C .claude/worktrees/temper-demo-T1 add src/a.sh; git -C .claude/worktrees/temper-demo-T1 commit -q -m "by hand" >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "B2: a RED that passed beside a commit the CLI did not make FAILs and parks (not COVERED)" "1|failed|1" \
  "$rc|$(m_field 1 status)|$(printf '%s' "$out" | grep -c 'not made by the CLI')"

# --- B3: a covered task has a state of its own in the view, the report and the panel (one function, tasks_md.display_state) ---
b2_red_passed; "$TEMPER" task gate 1 --model m >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "B3: the view's build grid shows a covered task as covered, not waiting" "covered" \
  "$(vw "[t['state'] for g in d['build']['groups'] for t in g['tasks'] if t['n'] == 1][0]")"
assert_eq "B3: the report draws the covered state with its own word" "1" \
  "$(python3 "$REPO_ROOT/scripts/run_report.py" render --view .temper/view.json -o - 2>/dev/null | grep -c "class='warn'>◑ covered<")"
assert_eq "B3: the panel of a covered task says COVERED" "1" \
  "$("$TEMPER" panel task 1 2>/dev/null | grep -c 'Gate: COVERED')"
"$TEMPER" task accept 1 --reason "built by the parser task" >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "B3: a covered task the person accepted passes, and its panel keeps the person's reason (accepted_covered is read)" "passed|pass|1" \
  "$(m_field 1 status)|$(vw "[t['state'] for g in d['build']['groups'] for t in g['tasks'] if t['n'] == 1][0]")|$("$TEMPER" panel task 1 2>/dev/null | grep -c 'Gate: PASS (accepted:')"

# --- B4: one readiness and one "done" for a task (tasks_md.py: the schedule, task start's reason, the gate row) ---
m_setup < <(f9_tasks | sed 's/^\*\*Depends:\*\* Task 1$/**Depends:** none/; s|`src/b.sh`, `unit/b_test.sh`|`src/a.sh`, `unit/b_test.sh`|')
out="$("$TEMPER" task start 2 2>&1)"; rc=$?
assert_eq "B4: task start names the ready task a file overlaps, as the schedule decides it (not 'not in the ready set')" "1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'not ready: files overlap Task 1')"
m_setup < <(f9_tasks)
sed -i 's/^- \[ \] done$/- [x] done/' .temper/specs/demo/tasks.md
assert_eq "B4: a box ticked by hand in a started group is not a done task for the gate row (the run's record decides)" "1" \
  "$("$TEMPER" gate build 2>&1 | grep -c '\[x\] all tasks complete.*2 of 2 task(s) not done')"
setup
assert_eq "B4: a run with no record of its tasks is still judged by its boxes" "1" \
  "$("$TEMPER" gate build 2>&1 | grep -c '\[v\] all tasks complete')"

# --- B1: MOVES is the checked list of the moves an option carries (it was PERSON_MOVES, read nowhere) ---
assert_eq "B1: every move flow.py writes is in MOVES, and MOVES holds no move flow.py never writes" "ok" \
  "$(python3 - "$REPO_ROOT/scripts" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import flow
src = open(sys.argv[1] + '/flow.py').read()
used = set(re.findall(r'\bmove="([A-Za-z]+)"', src)) | set(re.findall(r'"move": "([A-Za-z]+)"', src)) | set(re.findall(r'return "(approve)" if', src)) | {'advance'}
print('ok' if used == flow.MOVES and not hasattr(flow, 'PERSON_MOVES') else 'used-not-listed %s listed-not-used %s' % (sorted(used - flow.MOVES), sorted(flow.MOVES - used)))
PY
)"
assert_eq "B1: an option with a move outside MOVES is refused" "refused" \
  "$(python3 -c "
import sys; sys.path.insert(0, sys.argv[1]); import flow
try:
    flow.Builder.opt(flow.Builder.__new__(flow.Builder), 'x', 'y', move='skipAll'); print('allowed')
except ValueError:
    print('refused')" "$REPO_ROOT/scripts" 2>&1)"

# --- B5: the loops view shows the live budget and the time of the latest step ---
fresh; gpass intent plan build review; _at review
printf '{"active_loops": [{"id": "loop-1", "from_stage": "review", "to_stage": "build", "reason": "second", "iteration": 2, "max_iterations": 2, "started": "2026-01-01T00:00:00Z", "at": "2026-01-02T00:00:00Z"}, {"id": "loop-2", "from_stage": "build", "to_stage": "plan", "reason": "p", "iteration": 1, "max_iterations": 2, "started": "2026-01-01T12:00:00Z"}], "history": []}\n' > .temper/feedback-loops.json
sed -i 's/max-per-type: 2/max-per-type: 3/' .claude/temper.config
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "B5: a loop's max is the live budget (config 3), Build to Plan's is its fixed 1, and at is the latest step" \
  "3|2026-01-02T00:00:00Z|1|2026-01-01T12:00:00Z" \
  "$(vw "'|'.join(str(x) for l in d['loops'] for x in (l['max'], l['at']))")"

# --- B6: the stages a small change window opens at are adhoc_ops.py's one list; Pipeline opens it from its own question ---
assert_eq "B6: flow's window stages are adhoc_ops.py's (Pipeline among them), the option is offered at each but Pipeline" \
  "yes|yes|build,review,check,commit" \
  "$(python3 -c "
import sys; sys.path.insert(0, sys.argv[1]); import flow, adhoc_ops
B = flow.Builder
print('|'.join(['yes' if B.ADHOC_STAGES == tuple(getattr(adhoc_ops, 'ADHOC_STAGES', adhoc_ops.STAGES)) else 'no',
                'yes' if 'pipeline' in B.ADHOC_STAGES else 'no', ','.join(B.ADHOC_OPTION_STAGES)]))" "$REPO_ROOT/scripts" 2>&1)"

# --- B7: the acceptance writer's launches are bounded, and the end of the bound is recorded, not silent ---
m_setup < <(f9_tasks); rm -f .temper/groups.json; f9_intent true true
"$TEMPER" acceptance start >/dev/null 2>&1; "$TEMPER" acceptance start >/dev/null 2>&1
assert_exit "B7: a third launch of the writer is refused by the CLI" 1 "$TEMPER" acceptance start
assert_eq "B7: after two launches with no lock the flow records the skip (a visible call), launching no writer" "work|acceptance skip|0" \
  "$(nx "'|'.join([d['action'], ' '.join(d['calls'][0].split('temper ', 1)[1].split()[:2]), str(len(d['agents']))])")"
bash -c "$(nx "d['calls'][0]")" >/dev/null 2>&1
assert_eq "B7: the skip is on record with its reason, and Build goes on to its groups" "yes|group start G1" \
  "$(python3 -c "import json; print('yes' if 'locked no tests in 2 launches' in json.load(open('.temper/evidence/acceptance-lock.json')).get('skipped', '') else 'no')")|$(nx "d['calls'][0].split('temper ', 1)[1]")"
# a reopened lock: each correction launch counts; past the bound the Check question is the person's
m_setup < <(f9_tasks); rm -f .temper/groups.json; f9_intent true true
mkdir -p .temper/specs/demo/acceptance
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01(self):\n        self.assertEqual(1 + 1, 2)\n' > .temper/specs/demo/acceptance/test_ac.py
"$TEMPER" acceptance lock --cmd "python3 -m unittest discover -s .temper/specs/demo/acceptance -t .temper/specs/demo/acceptance" >/dev/null 2>&1
gpass build review; "$TEMPER" state advance build_complete review >/dev/null 2>&1; "$TEMPER" state advance review_complete check >/dev/null 2>&1
gfail check "acceptance tests written before Build" "reopened to correct a test (x); not locked again"
"$TEMPER" acceptance reopen --reason "The test asks for what the intent does not say" >/dev/null 2>&1
assert_eq "B7: the correction writer's launch is counted by its before call" "temper:temper-acceptance|acceptance start" \
  "$(nx "a = d['agents'][0]; a['type'] + '|' + a['before'][0].split('temper ', 1)[1]")"
"$TEMPER" acceptance start >/dev/null 2>&1; "$TEMPER" acceptance start >/dev/null 2>&1
assert_exit "B7: a third correction launch for the same reopen is refused" 1 "$TEMPER" acceptance start
assert_eq "B7: after two correction launches the person gets the Check question, no writer is launched again" "ask|no" \
  "$(nx "d['action'] + '|' + ('yes' if any(a.get('type') == 'temper:temper-acceptance' for a in d.get('agents', [])) else 'no')")"

# --- B8: a finding's state is read one way (fresh_review.state_of, to become findings.finding_state): the keys the CLI writes ---
fresh; gpass intent plan build; _at review
cat > .temper/evidence/review.json <<'JSON'
[{"claim": "a.py:1 nested resolve", "severity": "critical", "resolved": {"fixed_by": "abc", "ts": "t"}},
 {"claim": "a.py:2 accepted", "severity": "critical", "accepted": {"reason": "r", "author": "p", "ts": "t"}},
 {"claim": "a.py:3 a key nothing writes", "severity": "critical", "fixed_by": "by hand"},
 {"claim": "a.py:4 a key nothing writes", "severity": "critical", "accepted_reason": "by hand"},
 {"claim": "a.py:5 contested", "severity": "critical", "contested": {"cite": "a.py:5", "quote": "q"}}]
JSON
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "B8: the view reads only the CLI's keys: resolved, accepted, open, open, open (a contest keeps it open)" "resolved|accepted|open|open|open" \
  "$(vw "'|'.join(f['state'] for f in d['findings'])")"

# --- B9: an intent's status and its Blocking questions are read one way (intent_parse.py) by the flow and the gate rows ---
b9_intent() { # a draft whose one Blocking question has a checkbox, as `temper intent answer` matches it; $1 is the Status line
  fresh
  cat > .temper/specs/demo/intent.md <<MD
# Intent: Demo

$1
**Author:** the person

### Problem

The demo prints nothing yet.

### Open Questions

- [ ] Blocking: Who may run the demo? choices: Admins only | Everyone
- Blocking: Context check: is this the right direction? choices: Right direction | Narrow the focus

### Decisions

- (none yet)
MD
}
b9_intent '**Status:** draft'
"$TEMPER" gate intent >/dev/null 2>&1; "$TEMPER" go >/dev/null 2>&1
assert_eq "B9: a Blocking line with a checkbox is one the flow asks and the gate row counts (both, besides the Context check)" "1|Who may run the demo?|1" \
  "$(vw "len(d['blocking_asks'])")|$(vw "d['blocking_asks'][0]['question']['question']")|$("$TEMPER" gate intent 2>&1 | grep -c '\[x\] blocking question open — 2 Blocking question(s) open: Who may run the demo?')"
assert_eq "B9: the draft rows name the same two questions" "1" \
  "$("$TEMPER" gate intent 2>&1 | grep -c 'open questions resolved — 2 Blocking question(s) still open on the draft')"
assert_eq "B9: one parser reads the status the way intent accept does: the first Status line, any case" "accepted|None|draft" \
  "$(python3 -c "
import sys; sys.path.insert(0, sys.argv[1]); import intent_parse as P
print('|'.join(str(P.status(t)) for t in ['**Status:** Accepted \n', '**Status:** {draft|accepted}\n**Status:** accepted\n', 'x\n**Status:**draft']))" "$REPO_ROOT/scripts")"

# --- B10: an earlier stage with no verdict and no skip is not shown as passed ---
fresh; gpass intent; _at review; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "B10: Intent passed; Plan and Build, with no verdict and no skip, show as not done; Review is here" "passed|todo|todo|here" \
  "$(vw "'|'.join(s['mark'] for s in d['stages'] if s['id'] in ('intent', 'plan', 'build', 'review'))")"

# --- B11: the CI fix round is bounded by the flow, whatever value the run state holds ---
b11_round() { # b11_round <value>: a red Pipeline at that pipeline_round, as written into the run state
  _pl; _plctx '{"status": "red", "failed_jobs": [{"name": "unit", "stage": "test", "id": "1", "error": "boom"}], "fix": ["unit/a.sh: 4"], "round": 1}'
  "$TEMPER" gate pipeline >/dev/null 2>&1
  python3 -c "
import json, sys
p = '.temper/build-state.json'; d = json.load(open(p)); d['pipeline_round'] = json.loads(sys.argv[1]); json.dump(d, open(p, 'w'))" "$1"
}
for v in '"x"' '-1' '0'; do
  b11_round "$v"
  assert_eq "B11: a pipeline_round of $v is past the limit: the question offers no fix round" "End the run (Recommended)|Save for later" "$(labels)"
done
b11_round '"2"'
assert_eq "B11: a round written as text is read as its number" "Apply the fix and push (Recommended)" "$(labels | cut -d'|' -f1)"

# --- B12 (pinned, not a defect): the flow's sequence is the CLI's in the same order, less the stages the run does not visit ---
assert_eq "B12: flow.SEQ (and Pipeline last) is the CLI's _run_seq order" "intent plan design build review check commit pipeline|rca fix review check commit" \
  "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import flow; print(' '.join(flow.SEQ['temper'] + ['pipeline']) + '|' + ' '.join(flow.SEQ['fix']))" "$REPO_ROOT/scripts")"
assert_eq "B12: and the CLI's own lists say the same" "intent plan design build review check commit pipeline|rca fix review check commit" \
  "$(sed -n 's/^STAGE_SEQ_TEMPER="\(.*\)"$/\1 commit pipeline/p' "$TEMPER")|$(sed -n 's/^STAGE_SEQ_FIX="\(.*\)"$/\1 commit/p' "$TEMPER")"
fresh; gpass intent plan; _at design; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "B12: a run at Design keeps Design in its sequence when nothing else asks for it (the current stage is always in it)" "passed|passed|here" \
  "$(vw "'|'.join(s['mark'] for s in d['stages'] if s['id'] in ('intent', 'plan', 'design'))")"

# --- B13 (pinned): the flow decides a group by its gate; a status left at passed beside a FAIL gate does not pass it ---
m_setup < <(f9_tasks)
python3 - <<'PY'
import json
p = '.temper/groups.json'; d = json.load(open(p))
d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}, '2': {'status': 'passed', 'group': 'G1'}}
d['groups']['G1'].update({'status': 'passed', 'gate': {'verdict': 'FAIL', 'reason': 'the group check failed', 'ts': 't'}})
json.dump(d, open(p, 'w'))
PY
assert_eq "B13: a group whose gate FAILed is asked about as failed, whatever its status says" "ask|Group G1 failed its check (the group check failed). Run its tasks again?" \
  "$(nx "d['action'] + '|' + d['ask']['question']['question']")"
