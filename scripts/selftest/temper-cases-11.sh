# Release 9.7.5, Phases B and C (F6 to F22). Sourced by test-temper.sh after temper-cases-10.sh (helpers: nx, vw, labels,
# gpass, gfail, fresh, setup). Every throwaway project here is the selftest's own folder, and its folder names are unit and src.


# --- F12. tasks.md file lists and manual tasks ---
assert_eq "F12: a bullet list under **Files:** and a one line **File:** both declare files" "docs/guide.md,src/b.py|a.py,b.py|1|0" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PYT'
import sys, tempfile, os; sys.path.insert(0, sys.argv[1])
import tasks_md
d = tempfile.mkdtemp(); p = os.path.join(d, 'tasks.md')
open(p, 'w').write("## Group G1: A\n**Depends:** none\n**Validate:** `true`\n**Context:**\nc\n\n### Task 1: one\n**Files:**\n- `docs/guide.md`\n- src/b.py\n**Depends:** none\n**Test:** manual — the guide reads well\n**Cases:**\n- names the install step\n- [ ] done\n\n### Task 2: two\n**File:** `a.py`, `b.py`\n**Test:** `pytest -q`\n**Cases:**\n- x\n- [x] done\n")
r = tasks_md.parse(p)
print('|'.join([','.join(r['tasks'][0]['files']), ','.join(r['tasks'][1]['files']), str(int(r['tasks'][0]['manual'])), str(int(r['tasks'][1]['manual']))]))
PYT
)"
m_setup <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Docs
**Depends:** none
**Validate:** `true`
**Context:**
The guide.

### Task 1: Write the guide
**Files:**
- `docs/guide.md`
**Depends:** none
**Test:** manual — the guide reads well and its links work
**Cases:**
- the guide names the install step
- the guide links the changelog
- [ ] done
TASKS
"$TEMPER" task start 1 >/dev/null 2>&1
mkdir -p .claude/worktrees/temper-demo-T1/docs; echo "# Guide" > .claude/worktrees/temper-demo-T1/docs/guide.md
assert_exit "F12: task test refuses a manual task" 1 "$TEMPER" task test 1 --phase red
OUT="$("$TEMPER" task gate 1 --model sonnet 2>&1)"; rc=$?
assert_eq "F12: the gate of a manual task waits for the person (exit 0, no attempt spent)" "0|1|running|" \
  "$rc|$(grep -c 'asks the person to confirm Task 1' <<<"$OUT")|$(m_field 1 status)|$(m_field 1 attempts | tr -d '[]')"
assert_eq "F12: the Manual task question names the Cases, with a name question on Confirm and a Stop" \
  "ask|Manual task|Confirm|Stop|Task 1 (Write the guide) is a manual task. Confirm by hand that each Case holds: the guide names the install step; the guide links the changelog." \
  "$(nx "'|'.join([d['action'], d['ask']['question']['header'], d['ask']['question']['options'][0]['label'], d['ask']['question']['options'][1]['label'], d['ask']['question']['question']])")"
assert_eq "F12: Confirm runs task confirm with the typed name, then the task gate" "task confirm 1 --by '{answer}'|task gate 1 --model person" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['ask']['options'][0]['calls'])")"
assert_exit "F12: a confirmation needs a name" 1 "$TEMPER" task confirm 1
"$TEMPER" task confirm 1 --by "Dana Cohen" >/dev/null 2>&1
assert_eq "F12: the confirmation is recorded with the typed name, and a ledger row says so" "Dana Cohen|1" \
  "$(m_field 1 confirmed_by)|$(grep -c 'Task 1 confirmed by Dana Cohen' .temper/evidence/build.json)"
"$TEMPER" task gate 1 --model person >/dev/null 2>&1
assert_eq "F12: after the confirmation the gate passes the task and ticks its box" "passed|1" "$(m_field 1 status)|$(grep -c '^- \[x\]' .temper/specs/demo/tasks.md)"
assert_eq "F12: a plan of only manual tasks has no RED then GREEN to show: that row passes" "True" \
  "$("$TEMPER" gate build 2>&1 | grep -c 'every task is manual' | sed 's/1/True/')"
assert_eq "F12: the all-tasks check counts a task with no checkbox as not done" "False" \
  "$(python3 -E -s "$REPO_ROOT/scripts/task_rows.py" all-tasks <(printf '## Group G1: A\n**Depends:** none\n\n### Task 1: a\n**File:** `a.py`\n**Test:** `true`\n**Cases:**\n- x\n\n### Task 2: b\n**File:** `b.py`\n**Test:** `true`\n**Cases:**\n- y\n- [x] done\n') /dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['pass'])")"

# --- F18. A command the CLI runs imports the code of the folder it runs in; R10: no credential reaches it ---
mkdir -p r18/root_pkg r18/wt_pkg
printf 'WHERE = "root"\n' > r18/root_pkg/mod18.py
printf 'WHERE = "worktree"\n' > r18/wt_pkg/mod18.py
assert_eq "F18: the folder the command runs in comes first on PYTHONPATH, ahead of an installed copy" "worktree" \
  "$(PYTHONPATH="$PWD/r18/root_pkg" python3 -I - "$REPO_ROOT/scripts" "$PWD/r18/wt_pkg" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['python3 -c "import mod18; print(mod18.WHERE)"'])
print(out.decode().strip() if rc == 0 else 'rc=%s %s' % (rc, out.decode()))
PYT
)"
assert_eq "F18: a credential named variable is not handed over, and an ordinary one is" "none|kept" \
  "$(MY_API_TOKEN=abc ORDINARY_VAR=kept python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['echo "${MY_API_TOKEN:-none}|${ORDINARY_VAR:-gone}"'])
print(out.decode().strip())
PYT
)"
rm -rf r18

# --- F7. Build validates each success criterion; a failure names the scenario and its Test: command ---
f7_intent() { # f7_intent: an intent whose AC-02 is proven by a scenario with a Test: line (the long command is cut at 60)
  cat > .temper/specs/demo/intent.md <<'INT'
**Status:** accepted

## Problem
The CLI prints plain text.

### Success Criteria
- [ ] AC-01 [required]: the CLI lists categories
  Why: people need them
  Validate: code — the listing test
- [ ] AC-02 [required]: the CLI lists categories in color
  Why: people scan by color
  Validate: scenario — the color scenario
- [ ] AC-03 [required]: the guide reads well
  Why: onboarding
  Validate: manual — a person reads it

## Scenarios (BDD)
```gherkin
Scenario: the CLI lists categories in color
  Given categories
  When listed
  Then they are colored
  Covers: AC-02
  Test: pytest unit/test_cli.py::test_color_output_for_each_category_listed -q
```
INT
}
F7CMD="pytest unit/test_cli.py::test_color_output_for_each_category_listed -q"; F7CUT="${F7CMD:0:60}"
fresh; f7_intent; : > .temper/evidence/build.json
OUT="$(python3 "$REPO_ROOT/scripts/acceptance.py" build .temper/specs/demo/intent.md .temper/evidence/build.json)"
assert_eq "F7: with no row each criterion says why: code FAIL, scenario FAIL naming the Test: cut at 60, manual CONFIRM" \
  "AC-01 FAIL: Validate: code, and no passing row records it.|AC-02 FAIL: scenario 'the CLI lists categories in color' ($F7CUT) has no row run by the CLI.|AC-03 CONFIRM: the person confirms it at Check" \
  "$(echo "$OUT" | paste -sd'|' -)"
"$TEMPER" evidence run --stage build --scenario 'the CLI lists categories in color' --claim 'scenario test' -- bash -c 'exit 4' >/dev/null 2>&1
OUT="$(python3 "$REPO_ROOT/scripts/acceptance.py" build .temper/specs/demo/intent.md .temper/evidence/build.json | sed -n 2p)"
assert_eq "F7: a failed scenario line names the scenario, its command cut at 60 characters, and the exit" \
  "AC-02 FAIL: scenario 'the CLI lists categories in color' ($F7CUT) exit 4." "$OUT"
"$TEMPER" evidence run --stage build --scenario 'the CLI lists categories in color' --claim 'scenario test' -- true >/dev/null 2>&1
"$TEMPER" evidence add --stage build --scenario 'the CLI lists categories in color' --claim 'an agent says it passed' --cmd true --exit 0 >/dev/null 2>&1
assert_eq "F7: a CLI-run row with exit 0 passes the scenario criterion" "AC-02 PASS: 1 scenario(s) ran green" \
  "$(python3 "$REPO_ROOT/scripts/acceptance.py" build .temper/specs/demo/intent.md .temper/evidence/build.json | sed -n 2p)"
fresh; f7_intent; : > .temper/evidence/build.json
"$TEMPER" evidence add --stage build --scenario 'the CLI lists categories in color' --claim 'an agent says it passed' --cmd true --exit 0 >/dev/null 2>&1
assert_eq "F7: a row an agent wrote (not run by the CLI) does not pass a scenario criterion" "AC-02 FAIL:" \
  "$(python3 "$REPO_ROOT/scripts/acceptance.py" build .temper/specs/demo/intent.md .temper/evidence/build.json | sed -n 2p | cut -c1-11)"

# --- F8 and F9. The scenario tests: owed by a task, run by the group gate and by integrate ---
f9_tasks | m_setup
f9_intent "bash -c 'exit 0'" "bash -c 'exit 5'"
assert_eq "F9: a scenario traced to two tasks is owed by the task all the others precede; one traced to a task, by it" "alpha|beta" \
  "$(python3 "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 2 | cut -f1 | paste -sd'|' -)"
assert_eq "F9: Task 1 owes nothing, since Task 2 comes after it in the trace of both" "" \
  "$(python3 "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 1)"
assert_eq "F9: task show lists the scenario tests the task owes, with the exact-name rule" "1|1|1" \
  "$("$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1; "$TEMPER" task show 2 | grep -c 'SCENARIO TESTS (write these tests with these exact names; a test named otherwise does not count)')|$("$TEMPER" task show 2 | grep -c "^alpha: bash -c 'exit 0'")|$("$TEMPER" task show 2 | grep -c "^beta: bash -c 'exit 5'")"
assert_eq "F9: a failed scenario test is named with its scenario, command and exit" "scenario 'beta' (bash -c 'exit 5') exit 5" \
  "$(python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import scenario_ops
print(scenario_ops.run_owed([("alpha", "bash -c 'exit 0'"), ("beta", "bash -c 'exit 5'")], sys.argv[2], 20))
PYT
)"
assert_eq "F9: pytest exit 4 tells the agent to write the test under that exact name" "1" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import scenario_ops
print(int('Write the test with the exact name' in scenario_ops.failure('x', 'pytest unit/t.py::test_x -q', 4)))
PYT
)"
f9_tasks | m_setup; f9_intent "bash -c 'exit 0'" "bash -c 'exit 3'"
python3 - <<'PYT'
import json
d = json.load(open('.temper/groups.json'))
for n in ('1', '2'):
    d.setdefault('tasks', {})[n] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))
PYT
OUT="$("$TEMPER" group gate G1 2>&1)"
assert_eq "F9: the group gate fails on a scenario test and names the scenario, command and exit" "1" "$(grep -c "group G1: scenario 'beta' (bash -c 'exit 3') exit 3" <<<"$OUT")"
f9_intent "bash -c 'exit 0'" "bash -c 'exit 0'"
assert_eq "F9: the group gate passes once the scenario tests pass" "PASS: group G1" "$("$TEMPER" group gate G1 2>&1 | tail -1)"

# F17 on the group gate: a timeout is recorded with its limit
f9_tasks | m_setup; f9_intent "true" "true"
python3 - <<'PYT'
import json
d = json.load(open('.temper/groups.json'))
for n in ('1', '2'):
    d.setdefault('tasks', {})[n] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))
PYT
sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `sleep 5`/' .temper/specs/demo/tasks.md
python3 -c "
import json
for f in ('.temper/groups.json', '.temper/build-state.json'):
    d = json.load(open(f)); d.pop('plan_hash', None); json.dump(d, open(f, 'w'))"
"$TEMPER" group gate G1 --timeout-s 1 >/dev/null 2>&1
assert_eq "F17: a timed out group gate is recorded as a timeout with its limit" "FAIL|1" \
  "$(python3 -c "import json; g=json.load(open('.temper/groups.json'))['groups']['G1']['gate']; print(g['verdict']+'|'+str(g.get('timeout_s')))")"
assert_exit "F17: --timeout-s takes a whole number" 1 "$TEMPER" group gate G1 --timeout-s abc

# --- F8. The fallback record pass: a gate that fails only for rows nobody recorded sends a fix pass that records and changes no code ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "criteria validated" "AC-01 FAIL: scenario 'first' (no Test: line) has no row run by the CLI. AC-02 FAIL: Validate: code, and no passing row records it."
assert_eq "F8: only missing rows: the fix pass is launched with Record lines, and no code is to change" "work|temper:temper-build|1|1|1|1" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], str(a['prompt'].count('Record scenario: first')), str(a['prompt'].count('Record criterion: AC-02')), str(a['prompt'].count('Record only')), str(int('state set record_pass' in ' '.join(a['after'])))])")"
assert_eq "F8: the record pass's gate call is the last of its after calls" "gate build" "$(nx "d['agents'][0]['after'][-1].split('temper ', 1)[1]")"
"$TEMPER" state set record_pass "$(nx "d['agents'][0]['after'][-2].split('record_pass ', 1)[1].strip(chr(39))")" >/dev/null 2>&1
assert_eq "F8: the pass runs once per round: the next call asks the gate question" "ask" "$(nx "d['action']")"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "criteria validated" "AC-02 FAIL: scenario 'second' (bash -c 'exit 3') exit 3."
assert_eq "F8: a row that exists and failed keeps the gate question" "ask" "$(nx "d['action']")"

# --- F16. build.grouped.max-groups, and a plan with tasks and no groups stops Build with no agent ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_three_groups > .temper/specs/demo/tasks.md; rm -f .temper/groups.json
"$TEMPER" acceptance skip --reason "the scheduling cases below" >/dev/null 2>&1   # 9.8.0: else the acceptance writer comes first
assert_eq "F16: by default two groups start at once" "group start G1|group start G2" "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['calls'] if 'group start' in c)")"
printf 'build:\n  grouped:\n    max-groups: 3\n' > .claude/temper.config
assert_eq "F16: max-groups 3 starts all three" "3" "$(nx "str(sum(1 for c in d['calls'] if 'group start' in c))")"
for bad in 0 -1 two 1.5; do
  printf 'build:\n  grouped:\n    max-groups: %s\n' "$bad" > .claude/temper.config
  assert_eq "F16: max-groups '$bad' means 2" "2" "$(nx "str(sum(1 for c in d['calls'] if 'group start' in c))")"
done
printf 'build:\n  grouped:\n    max-groups: 1\n' > .claude/temper.config
assert_eq "F16: max-groups 1 starts one" "1" "$(nx "str(sum(1 for c in d['calls'] if 'group start' in c))")"
printf 'stack: auto\n' > .claude/temper.config
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '# Tasks: demo\n\n### Task 1: a\n**File:** `src/a.sh`\n**Test:** `true`\n**Cases:**\n- a\n- [ ] done\n' > .temper/specs/demo/tasks.md; rm -f .temper/groups.json
assert_eq "F16: tasks and no groups stops Build with a question and no agent" "ask|Build stopped: tasks.md has tasks but no groups, so Build cannot run them in isolated groups. Run Plan again to write the tasks in groups.|Run Plan again (Recommended)|Save for later" \
  "$(nx "'|'.join([d['action'], d['ask']['question']['question'], d['ask']['options'][0]['label'], d['ask']['options'][1]['label']])")"
assert_eq "F16: Run Plan again is a loop from Build to Plan with a reason" "back|1" \
  "$(nx "d['ask']['options'][0]['move'] + '|' + str(len(d['ask']['options'][0]['calls']))")"
"$TEMPER" state loop build plan --reason "no groups" >/dev/null 2>&1; gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "F16: with the loop budget spent the text says to write the groups by hand or save" "1" \
  "$(nx "str(int('write the groups by hand' in d['ask']['question']['question']))")"

# --- F17. After a timed out group gate the question offers a rerun at double the limit ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: make test", "timeout_s": 600}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F17: a timed out gate offers a rerun at 1200 seconds first" "Run the gate again with twice the time (Recommended)|group gate G1 --timeout-s 1200" \
  "$(nx "d['ask']['options'][0]['label'] + '|' + d['ask']['options'][0]['calls'][0].split('temper ', 1)[1]")"

# --- F13. Change reopens the task it concerns and the tasks that must reopen with it ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_change_tasks > .temper/specs/demo/tasks.md; second_group
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}, "3": {"status": "passed", "group": "G1"}, "4": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F13: the group question keeps Continue, Change and Stop" "Continue (Recommended)|Change|Stop" "$(nx "'|'.join(o['label'] for o in d['ask']['question']['options'])")"
assert_eq "F13: Change asks Which task changes? with one option per task; a task shares files with the one it depends on and reopens with it" \
  "Which task changes?|Task 1 (with Task 2)|Task 2|Task 3|Task 4" \
  "$(nx "c = d['ask']['change']['question']; c['question'] + '|' + '|'.join(o['label'] for o in c['options'])")"
assert_eq "F13: a task's option reopens the task and its companions with the feedback number" \
  "group reopen G1 --task 1 --task 2 --feedback {K}|Re-runs Task 1 and Task 2; the other tasks of G1 keep their work." \
  "$(nx "o = d['ask']['change']['options'][0]; o['calls'][0].split('temper ', 1)[1] + '|' + o['description']")"
assert_eq "F13: Change records each feedback item first" "1" \
  "$(nx "str(int('evidence add --stage build --phase feedback --claim' in d['ask']['options'][1]['do'] and 'Which task changes?' in d['ask']['options'][1]['do']))")"

# --- F14. The small-change window ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
assert_exit "F14: close with no window is an error" 1 "$TEMPER" adhoc close
assert_exit "F14: open needs a reason" 1 "$TEMPER" adhoc open --stage build
assert_exit "F14: open takes a known stage" 1 "$TEMPER" adhoc open --stage intent --reason "x"
assert_exit "F14: open at Build with a reason" 0 "$TEMPER" adhoc open --stage build --reason "rename a variable"
assert_exit "F14: a second open is refused" 1 "$TEMPER" adhoc open --stage build --reason "again"
mkdir -p src; echo one > src/a.sh; echo two > src/b.sh
OUT="$("$TEMPER" adhoc close 2>&1)"
assert_eq "F14: close records the files changed since the open (src/a.sh, src/b.sh), not every dirty file" "src/a.sh,src/b.sh|gate" \
  "$(python3 -c "import json; d=json.load(open('.temper/build-state.json'))['adhoc_done']; print(','.join(f for f in d['files'] if f.startswith('src/'))+'|'+','.join(d['steps']))")"
assert_exit "F14: a window can open again after a close" 0 "$TEMPER" adhoc open --stage check --reason "fix an off by one"
echo changed >> src/a.sh
git add -A >/dev/null 2>&1; git commit -qm "the small change" >/dev/null 2>&1
echo dirty-from-before-the-open-is-not-counted > docs-note.txt
"$TEMPER" adhoc close >/dev/null 2>&1
assert_eq "F14: a change at Check re-runs Review of the changed files, then Check, then the commit gate; a change in a commit counts" "review,check,commit|src/a.sh,src/b.sh" \
  "$(python3 -c "import json; d=json.load(open('.temper/build-state.json'))['adhoc_done']; print(','.join(d['steps'])+'|'+','.join(f for f in d['files'] if f.startswith('src')))")"
"$TEMPER" adhoc open --stage review --reason "a doc fix" >/dev/null 2>&1; echo more > docs/guide.md 2>/dev/null || { mkdir -p docs; echo more > docs/guide.md; }
"$TEMPER" adhoc close >/dev/null 2>&1
assert_eq "F14: a change of docs only re-runs only the stage's own gate" "gate|True" \
  "$(python3 -c "import json; d=json.load(open('.temper/build-state.json'))['adhoc_done']; print(','.join(d['steps'])+'|'+str(d['doc_only']))")"

# --- F14. The gate questions offer Make a small change; a closed change runs the steps it touches ---
fresh; gpass intent plan build review check; _at check
assert_eq "F14: a passed Check keeps Loop back to Build beside Commit, and offers the small change before Save" \
  "Commit (Recommended)|Loop back to Build|Commit and open PR|More options" "$(labels)"
assert_eq "F14: the option opens the window with a reason question and says what to do" "adhoc|1|1|1" \
  "$(nx "o = [x for x in d['ask']['more']['options'] if x['label'] == 'Make a small change'][0]; '|'.join([o['move'], str(len(o['calls'])), str(int('adhoc open --stage check --reason' in o['calls'][0])), str(int('adhoc close' in o['do'] and o.get('reason') is True))])")"
assert_eq "F14: the description is the agreed sentence" "Change the work yourself, with no loop back; the change re-runs only what it touches." \
  "$(nx "[x for x in d['ask']['more']['options'] if x['label'] == 'Make a small change'][0]['description']")"
python3 - <<'PYT'
import json
d = json.load(open('.temper/build-state.json')); d['adhoc'] = {'stage': 'check', 'reason': 'x', 'base': '', 'files': {}}; json.dump(d, open('.temper/build-state.json', 'w'))
PYT
assert_eq "F14: it is not offered while a window is open" "0" "$(nx "str(sum(1 for o in d['ask']['options'] + d['ask'].get('more', {}).get('options', []) if o['label'] == 'Make a small change'))")"
python3 - <<'PYT'
import json
d = json.load(open('.temper/build-state.json')); d.pop('adhoc'); d['adhoc_done'] = {'stage': 'check', 'reason': 'x', 'files': ['src/a.sh'], 'doc_only': False, 'steps': ['review', 'check', 'commit']}; json.dump(d, open('.temper/build-state.json', 'w'))
PYT
assert_eq "F14: after a code change at Check the Review agent runs first, over the changed files only" "work|temper:temper-review|1" \
  "$(nx "'|'.join([d['action'], d['agents'][0]['type'], str(d['agents'][0]['prompt'].count('Ad-hoc change: review only src/a.sh'))])")"
python3 - <<'PYT'
import json
d = json.load(open('.temper/build-state.json')); d['adhoc_done']['steps'] = ['check', 'commit']; json.dump(d, open('.temper/build-state.json', 'w'))
g = json.load(open('.temper/gates.json')); g['review'] = {'verdict': 'FAIL', 'requirements': [{'name': 'critical findings', 'pass': False, 'detail': '1 open'}]}; json.dump(g, open('.temper/gates.json', 'w'))
PYT
assert_eq "F14: a failed Review of a change made at Check never offers to advance from a stage the run has left" "ask|0" \
  "$(nx "d['action'] + '|' + str(sum(1 for o in d['ask']['options'] for c in o['calls'] if 'state advance review_complete' in c))")"
python3 - <<'PYT'
import json
d = json.load(open('.temper/build-state.json')); d['adhoc_done'] = {'stage': 'build', 'reason': 'x', 'files': ['docs/a.md'], 'doc_only': True, 'steps': ['gate']}; json.dump(d, open('.temper/build-state.json', 'w'))
PYT
fresh; gpass intent plan build; _at build
python3 - <<'PYT'
import json
d = json.load(open('.temper/build-state.json')); d['adhoc_done'] = {'stage': 'build', 'reason': 'x', 'files': ['docs/a.md'], 'doc_only': True, 'steps': ['gate']}; json.dump(d, open('.temper/build-state.json', 'w'))
PYT
assert_eq "F14: a change made at Build, or of docs only, re-runs only the stage's gate call" "work|0|gate build" \
  "$(nx "'|'.join([d['action'], str(len(d['agents'])), d['calls'][0].split('temper ', 1)[1]])")"

# --- F19. A task an earlier task already built: its RED run passed; the person decides, nothing retries it ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "covered", "group": "G1", "attempt": 3, "covered": {"cmd": "pytest unit/test_a.py -q", "tail": "3 passed in 0.02s"}}}}\n' > .temper/groups.json
assert_eq "F19: the covered question names the task, the RED command and its output, with the four options" \
  "ask|Task 1 (done task): its tests already pass before any change, so an earlier task built it. The RED run pytest unit/test_a.py -q passed (exit 0): 3 passed in 0.02s. Accept it as done?|Accept it as done|Run it again|Loop back to Plan|Save for later" \
  "$(nx "'|'.join([d['action'], d['ask']['question']['question']] + [o['label'] for o in d['ask']['options']])")"
assert_eq "F19: Accept asks for a reason and runs task accept; Run it again runs task retry" "task accept 1 --reason '{reason}'|True|task retry 1" \
  "$(nx "o = d['ask']['options']; o[0]['calls'][0].split('temper ', 1)[1] + '|' + str(o[0]['reason']) + '|' + o[1]['calls'][0].split('temper ', 1)[1]")"
assert_eq "F19: Accept it as done is the move covered, not a finding's accept (9.8.0)" "covered|redo" \
  "$(nx "o = d['ask']['options']; o[0]['move'] + '|' + o[1]['move']")"
assert_exit "F19: task start holds a covered task back" 1 "$TEMPER" task start 1
printf 'autonomy:\n  enabled: true\n' > .claude/temper.config; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_eq "F19: an armed run takes the covered task as done, with a reason, and does not park" "auto|1|0" \
  "$(nx "d['action'] + '|' + str(sum(1 for c in d['calls'] if 'task accept 1 --reason' in c)) + '|' + str(sum(1 for c in d['calls'] if 'park' in c))")"
printf 'stack: auto\n' > .claude/temper.config
assert_exit "F19: task accept needs a reason" 1 "$TEMPER" task accept 1
assert_exit "F19: a task that is not covered is not accepted" 1 "$TEMPER" task accept 2 --reason "x"

# --- F21. The blast radius skips Temper's own files and test output; a source file that looks like one still counts ---
assert_eq "F21: Temper's files and test output do not count; coverage.py and src files do" "no|no|no|no|no|no|no|no|no|yes|yes|yes" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PYT'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('blast_filter', sys.argv[1] + '/blast_filter.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
paths = ['.claude/temper.config', '.claude/settings.json', '.temper/specs/x/intent.md', '.claude/worktrees/temper-x-G1/a.py', '.coverage', 'htmlcov/index.html',
         'pkg/__pycache__/a.cpython-312.pyc', 'target/surefire-reports/TEST-a.xml', '.pytest_cache/v/cache/lastfailed', 'coverage.py', 'src/htmlcov_view.py', 'src/app.py']
print('|'.join('yes' if m.counts(p) else 'no' for p in paths))
PYT
)"
setup; "$TEMPER" state set run_mode autonomous >/dev/null
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
printf 'stack: auto\nautonomy:\n  enabled: true\n  max-blast-radius: 1\n' > .claude/temper.config
mkdir -p htmlcov .pytest_cache; echo x > .coverage; echo x > htmlcov/index.html; echo x > .pytest_cache/f
OUT="$("$TEMPER" gate commit 2>&1)"
assert_eq "F21: the blast radius row never names the config or a coverage file" "0" "$(grep '\] blast radius' <<<"$OUT" | grep -cE 'temper.config|\.coverage|htmlcov|pytest_cache')"
echo y > src_extra.py
OUT="$("$TEMPER" gate commit 2>&1)"
assert_eq "F21: one undeclared source file still fails the row" "1" "$(grep -c '^ *\[x\] blast radius' <<<"$OUT")"

# --- F22. Maven: the declared test classes only, offline, a new surefire report per class; a Maven group verifies with JaCoCo ---
mkdir -p fakebin f22/src/test/java/com/acme f22/target
cat > fakebin/mvn <<'FAKE'
#!/usr/bin/env bash
# a fake mvn: records its arguments, writes a surefire report for each class of -Dtest= unless FAKE_NO_REPORT is set
printf '%s\n' "$*" > "${FAKE_MVN_LOG:-/dev/null}"
[[ -z "${FAKE_NO_REPORT:-}" ]] || exit 0
for a in "$@"; do
  case "$a" in -Dtest=*) for c in $(echo "${a#-Dtest=}" | tr ',' ' '); do c="${c%%#*}"; mkdir -p target/surefire-reports; echo "<testsuite/>" > "target/surefire-reports/TEST-com.acme.$c.xml"; done ;; esac
done
exit "${FAKE_MVN_EXIT:-0}"
FAKE
chmod +x fakebin/mvn
F22LOG="$PWD/mvn.log"
run_loop() { (cd f22 && PATH="$WORKDIR/fakebin:$PATH" FAKE_MVN_LOG="$F22LOG" python3 -E -s "$REPO_ROOT/scripts/maven_loop.py" run . 60 "$1" src/test/java/com/acme/FooTest.java src/test/java/com/acme/BarTest.java src/main/java/com/acme/Foo.java >/dev/null 2>&1; echo $?); }
assert_eq "F22: a green Maven run with a report for each declared class exits 0" "0" "$(run_loop 'mvn test -Dgroups=fast')"
assert_eq "F22: it runs offline, with the skip flags, only the declared classes, and keeps the declared flags" "1|1|1|1" \
  "$(grep -c -e '-o ' "$F22LOG" | sed 's/.*/1/')|$(grep -c 'Dtest=FooTest,BarTest' "$F22LOG")|$(grep -c 'Dcheckstyle.skip=true' "$F22LOG")|$(grep -c 'Dgroups=fast' "$F22LOG")"
assert_eq "F22: a #method of the declared command is kept for its class" "1" "$(run_loop 'mvn test -Dtest=FooTest#parses' >/dev/null; grep -c 'Dtest=FooTest#parses,BarTest' "$F22LOG")"
rm -rf f22/target
assert_eq "F22: a run that leaves no new surefire report for a class fails (exit 3)" "3" "$(FAKE_NO_REPORT=1 run_loop 'mvn test')"
printf '#!/usr/bin/env bash\n: > "${FAKE_MVN_LOG}.mvnd"\nexec "$(dirname "$0")/mvn" "$@"\n' > fakebin/mvnd; chmod +x fakebin/mvnd
rm -f "$F22LOG" "$F22LOG.mvnd"; run_loop 'mvn test' >/dev/null
assert_eq "F22: mvnd is used when it is on the PATH" "yes" "$([[ -f "$F22LOG.mvnd" ]] && echo yes || echo no)"
rm -f "$F22LOG.mvnd"
rm -rf fakebin f22 "$F22LOG"
fresh; f9_tasks > .temper/specs/demo/tasks.md
assert_eq "F22: a plan with no Maven group skips the row" "True|skipped: no Maven group" \
  "$(python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" plan-rows .temper/specs/demo "$PWD" | sed -n 2p | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['pass'])+'|'+d['detail'])")"
sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `mvn test`/' .temper/specs/demo/tasks.md
assert_eq "F22: a Maven group that does not verify with JaCoCo is named by the plan row" "False|1" \
  "$(python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" plan-rows .temper/specs/demo "$PWD" | sed -n 2p | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['pass'])+'|'+str(d['detail'].count('G1')))")"
sed -i 's/^\*\*Validate:\*\* `mvn test`$/**Validate:** `mvn verify -Pjacoco`/' .temper/specs/demo/tasks.md
assert_eq "F22: mvn verify with JaCoCo passes the row" "True" \
  "$(python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" plan-rows .temper/specs/demo "$PWD" | sed -n 2p | python3 -c "import json,sys; print(json.load(sys.stdin)['pass'])")"

# --- F6. The Context Map: the plan gate row, the Context check as the CLI's own question, and plan review ---
_cmap() { # _cmap <reviewed line> [entry lines...]: plan.md with a Context Map at the top
  local reviewed="$1"; shift
  { printf '# Plan\n\n## Context Map\n'; printf '%s\n' "$@"; printf -- '- reviewed: %s\n\n## Blast Radius\n\nnone\n' "$reviewed"; } > .temper/specs/demo/plan.md
}
_crow() { python3 -E -s "$REPO_ROOT/scripts/plan_ops.py" row .temper/specs/demo "${1:-auto}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['pass'])+'|'+d['detail'])"; }
fresh
_cmap auto '- use: intent.md AC-01 - the scope' '- use: src/auth/ (12 files) - the flow this change extends'
assert_eq "F6: a map of uses reviewed auto passes in auto mode" "True" "$(_crow auto | cut -d'|' -f1)"
_cmap auto '- use: intent.md - scope' '- gap: no rate limit policy found'
assert_eq "F6: auto mode refuses reviewed: auto when the map has a gap" "False" "$(_crow auto | cut -d'|' -f1)"
_cmap auto '- use: intent.md - scope'
assert_eq "F6: always refuses every reviewed: auto, and off accepts a gap" "False|True" "$(_crow always | cut -d'|' -f1)|$(_cmap auto '- gap: x'; _crow off | cut -d'|' -f1)"
_cmap pending '- use: intent.md - scope'
assert_eq "F6: pending fails and says the answer is not recorded yet" "False|1" "$(_crow auto | cut -d'|' -f1)|$(_crow auto | grep -c 'answer is not recorded yet')"
_cmap human
assert_eq "F6: a map with no use, ignore or gap entry fails" "False" "$(_crow auto | cut -d'|' -f1)"
{ printf '# Plan\n\n## Context Map\n'; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do printf -- '- use: source %s\n' "$i"; done; printf -- '- reviewed: human\n'; } > .temper/specs/demo/plan.md
assert_eq "F6: more than 12 entries fails, naming the cap" "False|1" "$(_crow auto | cut -d'|' -f1)|$(_crow auto | grep -c '12')"
{ printf '# Plan\n\n## Context Map\n- use: %s\n- reviewed: human\n' "$(printf 'x%.0s' $(seq 1 120))"; } > .temper/specs/demo/plan.md
assert_eq "F6: a line over 100 characters fails" "False" "$(_crow auto | cut -d'|' -f1)"
assert_exit "F6: plan review with no plan.md fails" 1 bash -c "cd '$PWD' && rm -f .temper/specs/demo/plan.md && '$TEMPER' plan review --answer 'x'"
printf '# Plan\n\nno map\n' > .temper/specs/demo/plan.md
assert_exit "F6: plan review with no Context Map fails" 1 "$TEMPER" plan review --answer 'x'
_cmap pending '- use: intent.md - scope' '- ignore: .temper/specs/old/ - other scope'
"$TEMPER" plan review --answer "Narrow the focus" --focus "src/auth/" >/dev/null 2>&1
assert_eq "F6: plan review writes the answer and focus into the map and sets reviewed: human" "1|1|1|0" \
  "$(grep -c '^- answer: Narrow the focus' .temper/specs/demo/plan.md)|$(grep -c '^- focus: src/auth/' .temper/specs/demo/plan.md)|$(grep -c '^- reviewed: human' .temper/specs/demo/plan.md)|$(grep -c 'reviewed: pending' .temper/specs/demo/plan.md)"
assert_exit "F6: an answer over 100 characters is refused" 1 "$TEMPER" plan review --answer "$(printf 'y%.0s' $(seq 1 130))"
# the question in next and the view
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
printf '\n### Open Questions\n\n- Blocking: Context check: is this the right context for the plan? choices: Right direction | Narrow the focus | Fix the sources.\n' >> .temper/specs/demo/intent.md
_cmap pending '- use: intent.md - scope' '- gap: no rate limit policy'
gfail plan "context map reviewed" "the Context check is pending: the person's answer is not recorded yet"
assert_eq "F6: the pending check is the plan gate's only failed row: ask is the Context check, not the failed gate question" \
  "ask|Temper gate|It could not find: no rate limit policy. Is that right?|As planned (Recommended)|Something else|Carry forward" \
  "$(nx "'|'.join([d['action'], d['ask']['question']['header'], d['ask']['question']['question']] + [o['label'] for o in d['ask']['options']])")"
assert_eq "F6: As planned runs plan review --answer then the plan gate; Carry forward runs nothing; each option carries the table" "plan review --answer 'As planned'|gate plan|0|1" \
  "$(nx "o = d['ask']['options']; '|'.join([o[0]['calls'][0].split('temper ', 1)[1], o[0]['calls'][1].split('temper ', 1)[1], str(len(o[2]['calls'])), str(int('Context Map' in o[0]['preview']))])")"
assert_eq "F6: next and the view carry context_map and context_check, and the Blocking line is not asked twice" "2|3|0" \
  "$(nx "str(len(d['context_map']['rows'])) + '|' + str(len(d['context_check']['options'])) + '|' + str(len(d.get('blocking', [])))")"
assert_eq "F6: the view holds the same, and the status says the answer is not recorded yet" "3|1" \
  "$(vw "str(len(d['context_check']['options'])) + '|' + str(int('not recorded yet' in d['status']))")"
"$TEMPER" plan review --answer "Right direction" >/dev/null 2>&1
assert_eq "F6: once reviewed there is no context_check" "None" "$(nx "d.get('context_check')")"

# --- The audit of the port: the SKIP lines of the criteria (F7) ---
mkdir -p f7skip; cat > f7skip/intent.md <<'INT'
**Status:** accepted

## Problem
The demo.

### Success Criteria
- [ ] AC-01 [required]: a thing
  Why: x
  Validate: telepathy — read minds
- [ ] AC-02 [optional]: a later thing
  Why: y
  Validate: code — later
  Deferred: next release

## Scenarios (BDD)
INT
echo '[]' > f7skip/ev.json
assert_eq "F7: a Validate type checked at Check, and a deferred optional criterion, are SKIP lines with their reason" \
  "AC-01 SKIP: telepathy is checked at Check|AC-02 SKIP: deferred" \
  "$(python3 "$REPO_ROOT/scripts/acceptance.py" build f7skip/intent.md f7skip/ev.json | paste -sd'|' -)"
rm -rf f7skip
setup

# --- The audit of the port (F14, F18): Teach Me gives way to the small change at a passed Review with open findings; the Review snapshot; the worktree copy wins through task test ---
_all_labels() { nx "'|'.join([o['label'] for o in d['ask']['options']] + [o['label'] for o in d['ask'].get('more', {}).get('options', [])])"; }
fresh; gpass intent plan build review; _at review
mkdir -p .temper/evidence; printf '[{"claim": "review completed", "severity": null, "label": "PROVEN"}]\n' > .temper/evidence/review.json
assert_eq "F14: at a passed Review with no finding, Teach Me stays and no small change is offered beside it" "1|1" "$(_all_labels | tr '|' '\n' | grep -c '^Teach Me$')|$(_all_labels | tr '|' '\n' | grep -c '^Make a small change$')"
printf '[{"claim": "review completed", "severity": null, "label": "PROVEN"}, {"claim": "src/a.sh:3 a style nit", "severity": "low", "label": "HEURISTIC", "confidence": 80}]\n' > .temper/evidence/review.json
assert_eq "F14: with an open finding Teach Me gives way to Make a small change, in both questions" "0|1" "$(_all_labels | tr '|' '\n' | grep -c '^Teach Me$')|$(_all_labels | tr '|' '\n' | grep -c '^Make a small change$')"
setup
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
"$TEMPER" adhoc open --stage check --reason "fix an off by one" >/dev/null 2>&1
mkdir -p src; echo changed > src/a.sh
"$TEMPER" adhoc close >/dev/null 2>&1
assert_eq "F14: closing a change that re-runs Review takes the Review code snapshot then" "1" \
  "$(python3 -c "import json; print(int(bool(json.load(open('.temper/build-state.json')).get('review_snapshot'))))")"
python3 -c "
import json
d = json.load(open('.temper/build-state.json')); d.pop('review_snapshot', None); json.dump(d, open('.temper/build-state.json', 'w'))"
"$TEMPER" adhoc open --stage review --reason "a doc fix" >/dev/null 2>&1; mkdir -p docs; echo more > docs/guide.md
"$TEMPER" adhoc close >/dev/null 2>&1
assert_eq "F14: a change of docs only takes no snapshot" "0" \
  "$(python3 -c "import json; print(int(bool(json.load(open('.temper/build-state.json')).get('review_snapshot'))))")"
setup
# F18 through task test: a package importable from the project root (PYTHONPATH here) and from the task worktree: the worktree copy wins
f9_tasks | m_setup
mkdir -p f18inst f18probe; echo "WHO = 'installed'" > f18inst/pkgx.py; printf 'import pkgx\nprint("WHO=" + pkgx.WHO)\n' > f18probe/probe.py
"$TEMPER" task start 1 >/dev/null 2>&1
python3 - "$PWD/f18probe/probe.py" <<'PYT'
import re, sys
p = '.temper/specs/demo/tasks.md'
t = open(p).read()
open(p, 'w').write(re.sub(r'^\*\*Test:\*\*.*$', '**Test:** `python3 ' + sys.argv[1] + '`', t, count=1, flags=re.M))
PYT
python3 -c "
import json
for f in ('.temper/groups.json', '.temper/build-state.json'):
    d = json.load(open(f)); d.pop('plan_hash', None); json.dump(d, open(f, 'w'))"
echo "WHO = 'worktree'" > .claude/worktrees/temper-demo-T1/pkgx.py
assert_eq "F18: task test runs with the task worktree first on PYTHONPATH, so the worktree copy of a package wins" "WHO=worktree" \
  "$(PYTHONPATH="$PWD/f18inst" "$TEMPER" task test 1 --phase red 2>&1 | grep '^WHO=')"
rm -rf f18inst f18probe
setup
# F14 in a fix run: the Fix stage question is asked, and it does not offer the small change (its change is the fix itself)
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1
mkdir -p .temper/specs/demo-bug; printf '# Root cause\nx\n' > .temper/specs/demo-bug/rca.md
_at fix; gpass build fix rca
assert_eq "F14: a fix run's Fix stage question does not offer Make a small change" "ask|fix|0" \
  "$(nx "d['action'] + '|' + d['stage'] + '|' + str(sum(1 for o in d['ask']['options'] + d['ask'].get('more', {}).get('options', []) if o['label'] == 'Make a small change'))")"
setup
