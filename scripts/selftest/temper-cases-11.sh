# Release 9.7.5, Phases B and C (F6 to F22). Sourced by test-temper.sh after temper-cases-10.sh (helpers: nx, vw, labels,
# gpass, gfail, fresh, setup). Every throwaway project here is the selftest's own folder, and its folder names are unit and src.

m_setup() { # m_setup <tasks.md text on stdin>: a fresh repository on the run's feature branch with the plan approved, one group started
  local text; text="$(cat)"
  setup
  rm -rf .git README; git init -q . 2>/dev/null
  git config user.email t@example.com; git config user.name T
  echo base > README; git add README; git commit -q -m base
  git checkout -q -B feature/demo
  printf '%s\n' "$text" > .temper/specs/demo/tasks.md
  printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" group start G1 >/dev/null 2>&1
}
m_field() { python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['tasks'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"; }

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
f9_tasks() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
**Traced to:** Scenario: "alpha"
- [ ] done

### Task 2: second
**File:** `src/b.sh`, `unit/b_test.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b holds
**Traced to:** Scenario: "alpha", "beta"
- [ ] done
TASKS
}
f9_intent() { # f9_intent <alpha command> <beta command>
  cat > .temper/specs/demo/intent.md <<INT
**Status:** accepted

## Problem
The demo.

### Success Criteria
- [ ] AC-01 [required]: alpha works
  Why: a
  Validate: scenario — alpha
- [ ] AC-02 [required]: beta works
  Why: b
  Validate: scenario — beta

## Scenarios (BDD)
\`\`\`gherkin
Scenario: alpha
  Given a
  When b
  Then c
  Covers: AC-01
  Test: $1
\`\`\`
\`\`\`gherkin
Scenario: beta
  Given a
  When b
  Then c
  Covers: AC-02
  Test: $2
\`\`\`
INT
}
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
