# Release 9.8.4: the faults one failed run of a complex feature exposed (8 criteria, about 30 files, risk H). Sourced by
# test-temper.sh after temper-cases-19.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 6b. Each case file starts from a clean fixture: no folder, file or commit an earlier case file left ---
assert_eq "9.8.4 6b: a case file starts in an empty work folder (no .git, no file an earlier case file left)" "0" \
  "$(find "$WORKDIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"

# --- 6a. The GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n, GIT_CONFIG_VALUE_n family passes whole to a command the CLI runs ---
setup
assert_eq "9.8.4 6a: git configured through GIT_CONFIG_* still works under run_env (no 'unable to parse command-line config')" "0|false|1" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.interactive GIT_CONFIG_VALUE_0=false python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['git config --get credential.interactive; echo "rc=$?"; echo "${GIT_CONFIG_COUNT:-unset}"'])
lines = out.decode().split()
print('%s|%s|%s' % (rc, lines[0] if lines else '', lines[-1] if lines else ''))
PYT
)"
assert_eq "9.8.4 6a: a credential named variable is still left out" "none" \
  "$(MY_API_KEY_0=abc python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['echo "${MY_API_KEY_0:-none}"'])
print(out.decode().strip())
PYT
)"

assert_eq "9.8.4 6a: a family with a credential key (an extra header) is left out whole, so git parses and the header is gone" "unset|unset|ok" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0='Authorization: basic abc' python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['echo "${GIT_CONFIG_COUNT:-unset}|${GIT_CONFIG_VALUE_0:-unset}|$(git status >/dev/null 2>&1 && echo ok || echo broken)"'])
print(out.decode().strip())
PYT
)"

# --- 7b. .temper/brief.md is local run state: init lists it in the clone's info/exclude ---
setup
"$TEMPER" brief --text "a change" >/dev/null 2>&1 || printf '# brief\n' > .temper/brief.md
assert_eq "9.8.4 7b: init lists .temper/brief.md in info/exclude, so it is never an untracked file" "1|0" \
  "$(grep -cx '/.temper/brief.md' "$(git rev-parse --git-common-dir)/info/exclude")|$(git status --porcelain --untracked-files=all | grep -c 'brief.md')"

# --- 2. The group gate keeps the FAIL lines of its Validate output and counts its failures; group fix commits a fix agent's work ---
m_setup <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `bash -c 'echo collecting; echo "FAIL: alpha is missing"; test -f src/ok.txt'`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- a bad input is refused
- [x] done
TASKS
python3 -c "
import json; p = '.temper/groups.json'; d = json.load(open(p)); d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}}; json.dump(d, open(p, 'w'))"
"$TEMPER" group gate G1 >/dev/null 2>&1
_g1() { python3 -c "import json,sys; g = json.load(open('.temper/groups.json'))['groups']['G1']; print(eval(sys.argv[1]))" "$1"; }
assert_eq "9.8.4 2a: the group gate keeps the FAIL lines of its Validate output, and counts the failure" "FAIL|['FAIL: alpha is missing']|True|1" \
  "$(_g1 "'|'.join([g['gate']['verdict'], str(g['gate'].get('fail_lines')), str(g['gate'].get('ran')), str(g.get('fails'))])")"
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "9.8.4 2c: a second failed group check counts 2" "2" "$(_g1 "g.get('fails')")"
assert_exit "9.8.4 2b: group fix asks for the fix agent on a failed group" 0 "$TEMPER" group fix G1
assert_eq "9.8.4 2b: and records the request, and counts the attempt" "True|1" "$(_g1 "'%s|%s' % (bool((g.get('fix') or {}).get('requested')), g.get('fix_tries'))")"
WT="$(_g1 "g['worktree']")"; mkdir -p "$WT/src"; echo ok > "$WT/src/ok.txt"
assert_exit "9.8.4 2b: group fix --commit commits the fix agent's work on the group branch as the CLI's own commit" 0 "$TEMPER" group fix G1 --commit
assert_eq "9.8.4 2b: the commit is recorded as the CLI's, the request is done, the gate is cleared to run again, and the worktree is clean" "True|False|False|2|0" \
  "$(python3 -c "
import json, subprocess
d = json.load(open('.temper/groups.json')); g = d['groups']['G1']
head = subprocess.run(['git', '-C', g['worktree'], 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
print('%s|%s|%s|%s' % (head in d.get('cli_commits', []), 'fix' in g, 'gate' in g, g.get('fails')))")|$(git -C "$WT" status --porcelain | grep -vc '^?? .temper/' )"
assert_exit "9.8.4 2b: the group gate passes on the fixed tree" 0 "$TEMPER" group gate G1
assert_exit "9.8.4 2b: group fix is refused on a group whose gate did not fail" 1 "$TEMPER" group fix G1

assert_eq "9.8.4 2a: a FAIL line is what failed, not a traceback's header" "['FAIL: test_x (t.T.test_x)', 'AssertionError: 1 != 2', 'FAILED (failures=1)']" \
  "$(python3 - "$REPO_ROOT/scripts" <<'PYF'
import sys
sys.path.insert(0, sys.argv[1])
# WP20: fail_lines moved from task_ops.py (which runs a mode on import) to run_env.py, shared with the baseline
import run_env
out = b'..F\n=====\nFAIL: test_x (t.T.test_x)\n-----\nTraceback (most recent call last):\n  File \"t.py\", line 3\nAssertionError: 1 != 2\n\nFAILED (failures=1)\n'
print(run_env.fail_lines(out))
PYF
)"

# --- 1. The plan gate fails when a test file a group's Validate runs is edited by a task of a later group ---
setup
mkdir -p test scripts/selftest
printf 'def test_a():\n    assert True\n' > test/test_core.py
printf 'source "$(dirname "$0")/cases-8.sh"\n' > scripts/selftest/run.sh; printf 'true\n' > scripts/selftest/cases-8.sh
_p1() { # _p1 <tasks.md>: the plan gate rows of that plan, as plan_rows.py prints them, for the row named group validate order
  printf '%s\n' "$1" > p1-tasks.md
  python3 -I "$REPO_ROOT/scripts/plan_rows.py" 15 4096 4096 "$(python3 -c "import sys, json; sys.path.insert(0, sys.argv[1]); import tasks_md; print(json.dumps(tasks_md.parse(sys.argv[2])))" "$REPO_ROOT/scripts" p1-tasks.md)" "$PWD" \
    | python3 -c "import json, sys; r = [json.loads(l) for l in sys.stdin if '\"group validate order\"' in l]; print('%s|%s' % (r[0]['pass'], r[0]['detail']) if r else 'no row')"
}
_p1tasks() { cat <<TASKS
**Integration:** \`true\`

## Group G1: Core
**Depends:** none
**Validate:** \`$1\`
**Context:**
The core.

### Task 1: core
**File:** \`src/core.py\`
**Depends:** none
**Test:** \`true\`
**Cases:**
- a
- b
- [ ] done

## Group G2: Tests
**Depends:** G1
**Validate:** \`true\`
**Context:**
The tests.

### Task 2: update the tests
**File:** \`$2\`
**Depends:** none
**Test:** \`true\`
**Cases:**
- a
- b
- [ ] done
TASKS
}
assert_eq "9.8.4 1: a test file G1's Validate runs, edited by a task of the later G2, fails the row and names the file and both groups" \
  "False|G1's Validate runs test/test_core.py, which Task 2 of G2 edits" \
  "$(_p1 "$(_p1tasks "python3 -m pytest test/test_core.py -q" test/test_core.py)" | cut -d: -f1)"
assert_eq "9.8.4 1: a folder the Validate runs counts (pytest test/)" "False" "$(_p1 "$(_p1tasks "pytest test/" test/test_core.py)" | cut -d'|' -f1)"
assert_eq "9.8.4 1: a file the Validate's own script sources counts (a selftest that runs case files)" \
  "False|G1's Validate runs scripts/selftest/cases-8.sh, which Task 2 of G2 edits" \
  "$(_p1 "$(_p1tasks "bash scripts/selftest/run.sh" scripts/selftest/cases-8.sh)" | cut -d: -f1)"
assert_eq "9.8.4 1: a test module named the dotted way (python3 -m unittest test.test_core) counts" \
  "False|G1's Validate runs test/test_core.py, which Task 2 of G2 edits" \
  "$(_p1 "$(_p1tasks "python3 -m unittest test.test_core" test/test_core.py)" | cut -d: -f1)"
assert_eq "9.8.4 1: a new test file a later group writes is no conflict (G1 cannot run a file that does not exist yet)" "True" \
  "$(_p1 "$(_p1tasks "pytest test/" test/test_new.py)" | cut -d'|' -f1)"
assert_eq "9.8.4 1: a Validate that runs other files passes" "True" "$(_p1 "$(_p1tasks "pytest test/test_other.py" test/test_core.py)" | cut -d'|' -f1)"
rm -rf test scripts p1-tasks.md

# --- 3b. After a loop back that changes plan.md or tasks.md, the fresh review gets one more round past its cap ---
setup
printf 'plan:\n  fresh-review: auto\n  fresh-review-rounds: 1\n' >> .claude/temper.config
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state set complexity medium >/dev/null 2>&1
printf '## Context Map\n- use: intent.md - the scope\n- reviewed: auto - current\n\n## Blast Radius\n- none\n\n## Cross-Repo Search\n- not available: none\n' > .temper/specs/demo/plan.md
"$TEMPER" plan fresh start >/dev/null 2>&1
_frow() { "$TEMPER" gate plan >/dev/null 2>&1; python3 -c "
import json, sys
r = [x for x in json.load(open('.temper/gates.json'))['plan']['requirements'] if x['name'] == 'fresh review ran']
print(('%s|%s' % (r[0]['pass'], r[0]['detail'])) if r else 'absent')"; }
"$TEMPER" state loop plan intent --reason "the scope is wrong" >/dev/null 2>&1
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
assert_exit "9.8.4 3b: before plan.md or tasks.md changes, the cap still holds" 1 "$TEMPER" plan fresh start
echo "- a revised step" >> .temper/specs/demo/tasks.md
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "9.8.4 3b: after the loop back changed tasks.md, next launches one more round instead of a dead end" "temper:temper-plan-review|1" \
  "$(nx "a = d['agents'][0]; a['type'] + '|' + str(int('Round: 2 of 2.' in a['prompt']))")"
assert_exit "9.8.4 3b: and the CLI takes that launch" 0 "$TEMPER" plan fresh start
assert_exit "9.8.4 3b: one more round only: a third launch is refused" 1 "$TEMPER" plan fresh start
gfail plan "fresh review ran" "x"; "$TEMPER" state redo plan --reason "the Context check: include the export" >/dev/null 2>&1
echo "- a replanned step" >> .temper/specs/demo/tasks.md
assert_exit "9.8.4 3b: a replan (state redo plan) that changes tasks.md earns one more round as well" 0 "$TEMPER" plan fresh start

# --- 5. Build model by risk: a complex or risk H plan builds its tasks on sonnet; an explicit task-model still wins ---
fresh
_tm() { echo "$("$TEMPER" model task)|$(python3 "$REPO_ROOT/scripts/cli_ctx.py" models --plugin "$REPO_ROOT" --config-file .claude/temper.config | sed -n 's/^task=//p')"; }
assert_eq "9.8.4 5: a simple plan keeps the brief's model for its tasks (the CLI and the flow agree)" "claude-haiku-5-5|claude-haiku-5-5" "$(_tm)"
"$TEMPER" state set complexity complex >/dev/null 2>&1
assert_eq "9.8.4 5: a complex plan builds its tasks on sonnet" "sonnet|sonnet" "$(_tm)"
"$TEMPER" state set complexity medium >/dev/null 2>&1; riskH
assert_eq "9.8.4 5: a risk H plan builds its tasks on sonnet" "sonnet|sonnet" "$(_tm)"
assert_eq "9.8.4 5: and says where the model comes from" "task=sonnet (risk)" \
  "$(python3 "$REPO_ROOT/scripts/cli_ctx.py" models --plugin "$REPO_ROOT" --config-file .claude/temper.config --source | grep '^task=')"
printf 'build:\n  grouped:\n    task-model: haiku\n' >> .claude/temper.config
assert_eq "9.8.4 5: an explicit build.grouped.task-model still wins" "haiku|haiku" "$(_tm)"

# --- 5. The plan gate fails when more than two tasks of one group declare the same production file ---
setup
_p5() { # _p5 <tasks.md>: pass|detail of the row "shared production files"
  printf '%s\n' "$1" > p5-tasks.md
  python3 -I "$REPO_ROOT/scripts/plan_rows.py" 15 4096 4096 "$(python3 -c "import sys, json; sys.path.insert(0, sys.argv[1]); import tasks_md; print(json.dumps(tasks_md.parse(sys.argv[2])))" "$REPO_ROOT/scripts" p5-tasks.md)" "$PWD" \
    | python3 -c "import json, sys; r = [json.loads(l) for l in sys.stdin if '\"shared production files\"' in l]; print('%s|%s' % (r[0]['pass'], r[0]['detail']) if r else 'no row')"
}
_p5task() { printf '### Task %s: step %s\n**File:** `%s`, `test/test_%s.py`\n**Depends:** %s\n**Test:** `true`\n**Cases:**\n- a\n- b\n- [ ] done\n\n' "$1" "$1" "$2" "$1" "$3"; }
_p5plan() { printf '**Integration:** `true`\n\n## Group G1: Core\n**Depends:** none\n**Validate:** `true`\n**Context:**\nThe core.\n\n'; }
assert_eq "9.8.4 5: three tasks of one group on the same production file fail the row, with a detail that says to merge them" \
  "False|G1: Task 1, Task 2 and Task 3 all declare src/core.py; merge them into one task" \
  "$(_p5 "$(_p5plan; _p5task 1 src/core.py none; _p5task 2 src/core.py "Task 1"; _p5task 3 src/core.py "Task 2")")"
assert_eq "9.8.4 5: two tasks on one file pass (they are ordered by Depends)" "True" \
  "$(_p5 "$(_p5plan; _p5task 1 src/core.py none; _p5task 2 src/core.py "Task 1")" | cut -d'|' -f1)"
assert_eq "9.8.4 5: a shared test file is not a production file" "True" \
  "$(_p5 "$(_p5plan; _p5task 1 test/test_x.py none; _p5task 2 test/test_x.py "Task 1"; _p5task 3 test/test_x.py "Task 2")" | cut -d'|' -f1)"
rm -f p5-tasks.md

# --- 4. The fresh review converges: a first round with a tests lens, then rechecks of the earlier findings only ---
setup
printf 'plan:\n  fresh-review: auto\n' >> .claude/temper.config
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state set complexity medium >/dev/null 2>&1
printf '## Context Map\n- use: intent.md - the scope\n- reviewed: auto - current\n\n## Blast Radius\n- none\n\n## Cross-Repo Search\n- not available: none\n' > .temper/specs/demo/plan.md
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "9.8.4 4: the first round runs four lenses, tests among them (which existing tests break, and which task updates them)" "1" \
  "$(nx "int('Lenses: readiness, zoom-out, comprehension, tests.' in d['agents'][0]['prompt'])")"
_f4() { "$TEMPER" evidence add --stage plan --phase fresh "$@" >/dev/null 2>&1; }
"$TEMPER" plan fresh start >/dev/null 2>&1
for l in readiness zoom-out comprehension tests; do _f4 --exit 0 --label PROVEN --claim "fresh review completed: $l A" $([[ $l == readiness ]] && echo "--value 1"); done
_f4 --claim "paraphrase: the demo runs twice and prints its output | a demo is one shell step run by the suite"
_f4 --severity high --claim "[readiness] Task 1: the case names no expected value"
_f4 --severity medium --claim "[tests] Task 1: the existing suite checks the old output and no task updates it"
"$TEMPER" state redo plan --reason "fresh review" >/dev/null 2>&1
printf -- '- the case expects exit 0\n' >> .temper/specs/demo/tasks.md
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "9.8.4 4: round 2 is a recheck: it lists the earlier findings and the changed task blocks, and runs no other lens" "1|1|1|1" \
  "$(nx "p = d['agents'][0]['prompt']; '%d|%d|%d|%d' % ('Lenses: recheck.' in p, 'Earlier findings (2): #' in p and 'the case names no expected value' in p, 'Changed task blocks: Task 1.' in p, 'Round: 2 of 3.' in p)")"
"$TEMPER" plan fresh start >/dev/null 2>&1
_f4 --exit 0 --label PROVEN --value 0 --claim "fresh review completed: recheck A"
assert_eq "9.8.4 4: a recheck that checked fewer earlier findings than the round has did not run" "False" \
  "$("$TEMPER" gate plan >/dev/null 2>&1; python3 -c "import json; print([r for r in json.load(open('.temper/gates.json'))['plan']['requirements'] if r['name'] == 'fresh review ran'][0]['pass'])")"
_f4 --exit 0 --label PROVEN --value 2 --claim "fresh review completed: recheck A"
_f4 --severity medium --claim "[tests] Task 1: the existing suite checks the old output and no task updates it"
assert_exit "9.8.4 4: a recheck that found the high fixed passes the plan gate; it keeps the earlier paraphrase, and a medium does not block" 0 "$TEMPER" gate plan
assert_eq "9.8.4 4: the medium finding goes to the builder of the task it names, as a note" "1" \
  "$(python3 - "$REPO_ROOT/scripts" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
import flow
r = flow.Run({"plugin": sys.argv[1], "cli": "temper", "config_file": ".claude/temper.config", "models": {}, "now": "", "setup": []})
print(int(any('no task updates it' in x for x in flow.Builder(r).review_notes().get(1, []))))
PY
)"

# --- 7c. temper output: the last output of a gate or a group gate, read only (the mod lets the session run the CLI, not printenv) ---
setup
python3 -c "
import json
rows = [{'claim': 'Group G1 validate', 'cmd': 'make test', 'exit_code': 1, 'phase': 'group', 'group': 'G1', 'executed_by': 'cli', 'ts': 't1',
         'output': 'collecting\nFAIL: alpha is missing\n', 'fail_lines': ['FAIL: alpha is missing']},
        {'claim': 'unit tests', 'cmd': 'pytest -q', 'exit_code': 1, 'phase': 'green', 'executed_by': 'cli', 'ts': 't2', 'output': 'E   assert 1 == 2\n1 failed'}]
json.dump(rows, open('.temper/evidence/build.json', 'w'))
g = json.load(open('.temper/gates.json')) if __import__('os').path.exists('.temper/gates.json') else {}
g['build'] = {'verdict': 'FAIL', 'requirements': [{'name': 'tests pass', 'pass': False, 'detail': 'the last test run failed'}]}
json.dump(g, open('.temper/gates.json', 'w'))"
OUT="$("$TEMPER" output G1 2>&1)"; RC=$?
assert_eq "9.8.4 7c: temper output G1 prints the group's last Validate run: its command, exit and output" "0|1|1|1" \
  "$RC|$(grep -c '^make test (exit 1)' <<<"$OUT")|$(grep -A1 '^What failed:' <<<"$OUT" | grep -c '^FAIL: alpha is missing')|$(grep -c '^collecting' <<<"$OUT")"
OUT="$("$TEMPER" output build 2>&1)"
assert_eq "9.8.4 7c: temper output build prints the gate's failed rows and the stage's last failed run with its output" "1|1|1" \
  "$(grep -c 'tests pass: the last test run failed' <<<"$OUT")|$(grep -c '^pytest -q (exit 1)' <<<"$OUT")|$(grep -c 'assert 1 == 2' <<<"$OUT")"
assert_exit "9.8.4 7c: a group with no recorded run says so and exits 1" 1 "$TEMPER" output G9
assert_eq "9.8.4 7c: temper output changes nothing" "same" \
  "$(a=$(cksum .temper/gates.json .temper/evidence/build.json); "$TEMPER" output build >/dev/null 2>&1; [[ "$a" == "$(cksum .temper/gates.json .temper/evidence/build.json)" ]] && echo same || echo changed)"

# --- 7d. An agent the tool ran in the background: its time is filled in when its completion notice arrives ---
setup; "$TEMPER" state init demo >/dev/null 2>&1; _base_known
"$TEMPER" usage add --stage plan --model opus --ms 1000 >/dev/null 2>&1
"$TEMPER" usage add --stage design --model opus --ms none >/dev/null 2>&1
"$TEMPER" usage add --stage build --model haiku --ms none --task 3 >/dev/null 2>&1
assert_exit "9.8.4 7d: usage add --fill puts the notice's time into the row recorded with none" 0 "$TEMPER" usage add --stage design --model opus --ms 5000 --fill
"$TEMPER" usage add --stage build --model haiku --ms 7000 --task 3 --fill >/dev/null 2>&1
assert_eq "9.8.4 7d: no row is added, each row recorded with none now has its time" "3|1000,5000,7000" \
  "$(python3 -c "import json; r = json.load(open('.temper/usage.json')); print('%d|%s' % (len(r), ','.join(str(x['ms']) for x in r)))")"
assert_eq "9.8.4 7d: the usage summary the report reads counts the filled time (it showed - for Design and Build)" "5000|7000" \
  "$(python3 "$REPO_ROOT/scripts/usage_ops.py" json .temper/usage.json | python3 -c "import json, sys; d = json.load(sys.stdin)['by_stage']; print('%s|%s' % (d['design']['ms'], d['build']['ms']))")"
assert_exit "9.8.4 7d: --fill with no row recorded with none adds the row" 0 "$TEMPER" usage add --stage check --model sonnet --ms 11 --fill
assert_eq "9.8.4 7d: (one row added)" "4" "$(python3 -c "import json; print(len(json.load(open('.temper/usage.json'))))")"

# --- 9.8.4 reverify: after a loop back to Build, the CLI reruns the scenario tests on the fixed tree ---
setup
_scen_rows() { python3 -c "import json; print(sum(1 for r in json.load(open('.temper/evidence/build.json')) if r.get('scenario') and r.get('executed_by') == 'cli'))" 2>/dev/null || echo 0; }
rm -f .temper/evidence/build.json
assert_exit "9.8.4 reverify: integrate on an integrated run reruns the scenario tests and succeeds" 0 "$TEMPER" integrate
assert_eq "9.8.4 reverify: one CLI-run row for each scenario of the intent" "2" "$(_scen_rows)"

# --- 9.8.4 bench: a task whose test needs a file it does not declare is blocked: no retry, no escalation, the group parks ---
m_setup <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`
**Depends:** none
**Test:** `false`
**Cases:**
- a holds
- a bad input is refused
- [ ] done

### Task 2: second
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b holds
- a bad input is refused
- [ ] done
TASKS
"$TEMPER" task start 1 >/dev/null 2>&1
assert_exit "9.8.4 blocked: a path the task declares itself is no block (refused)" 1 "$TEMPER" task blocked 1 --needs src/a.sh --reason "x"
assert_exit "9.8.4 blocked: the agent records the file its test needs outside the task" 0 \
  "$TEMPER" task blocked 1 --needs ./src/b.sh --reason "the test needs the b event, written in src/b.sh"
_bt() { python3 -c "import json,sys; d = json.load(open('.temper/groups.json')); print(eval(sys.argv[1]))" "$1"; }
assert_eq "9.8.4 blocked: recorded with the path and the task that declares it" "src/b.sh|[2]" "$(_bt "d['tasks']['1']['blocked']['needs'] + '|' + str(d['tasks']['1']['blocked']['owners'])")"
"$TEMPER" task test 1 --phase red >/dev/null 2>&1
"$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
assert_eq "9.8.4 blocked: its gate fails once and the group parks at once (no retry, no escalation), naming the file" "1|parked|1" \
  "$(_bt "'%d|%s|%d' % (len(d['tasks']['1']['attempts']), d['groups']['G1']['status'], 'needs src/b.sh' in d['groups']['G1']['parked_reason'])")"
"$TEMPER" group reopen G1 --task 1 >/dev/null 2>&1
assert_eq "9.8.4 blocked: running the task again clears the block" "False" "$(_bt "'blocked' in d['tasks']['1']")"

# --- 9.8.4 live check: the person's Context check answer does not make the fresh review stale (no empty recheck round) ---
setup
printf 'plan:\n  fresh-review: auto\n' >> .claude/temper.config
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state set complexity medium >/dev/null 2>&1
printf '## Context Map\n- use: intent.md - the scope\n- ignore: ledger/export.py: out of scope\n- reviewed: pending\n\n## Blast Radius\n- none\n\n## Cross-Repo Search\n- not available: none\n' > .temper/specs/demo/plan.md
"$TEMPER" plan fresh start >/dev/null 2>&1
for l in readiness zoom-out comprehension tests; do "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $l A" $([[ $l == readiness ]] && echo "--value 1") >/dev/null 2>&1; done
"$TEMPER" evidence add --stage plan --phase fresh --claim "paraphrase: the demo runs twice and prints its output | a demo is one shell step run by the suite" >/dev/null 2>&1
"$TEMPER" plan review --answer "As planned" >/dev/null 2>&1
assert_eq "9.8.4 live: the Context check answer wrote the map" "1" "$(grep -c 'reviewed: human' .temper/specs/demo/plan.md)"
assert_eq "9.8.4 live: after it, the fresh review still counts (not stale) and no reviewer is launched again" "True|0" \
  "$("$TEMPER" gate plan >/dev/null 2>&1; python3 -c "
import json; print([r for r in json.load(open('.temper/gates.json'))['plan']['requirements'] if r['name'] == 'fresh review ran'][0]['pass'])")|$(nx "sum(1 for a in d.get('agents') or [] if a['type'] == 'temper:temper-plan-review')")"
printf '\n- a changed step\n' >> .temper/specs/demo/tasks.md
assert_eq "9.8.4 live: a change of tasks.md still makes it stale" "False" \
  "$("$TEMPER" gate plan >/dev/null 2>&1; python3 -c "
import json; print([r for r in json.load(open('.temper/gates.json'))['plan']['requirements'] if r['name'] == 'fresh review ran'][0]['pass'])")"

# --- WP25: the plan gate row for a group with no Validate, and the one plan digest (U24) ---
_pv20() { # _pv20 <tasks.md text>: pass|G1 named of the row "group validate command" (scripts/plan_rows.py), or no row
  printf '%s\n' "$1" > pv-tasks.md
  python3 -I "$REPO_ROOT/scripts/plan_rows.py" 15 4096 2048 "$(python3 -c "import sys, json; sys.path.insert(0, sys.argv[1]); import tasks_md; print(json.dumps(tasks_md.parse(sys.argv[2])))" "$REPO_ROOT/scripts" pv-tasks.md)" "$PWD" \
    | python3 -c "import json, sys; r = [json.loads(l) for l in sys.stdin if '\"group validate command\"' in l]; print('%s|%s' % (r[0]['pass'], 'G1 named' if 'G1' in r[0]['detail'] else r[0]['detail']) if r else 'no row')"
}
setup
assert_eq "WP25 plan rows: group validate command fails a group with no Validate and passes the demo plan" \
  "no Validate=False|G1 named|demo=True" \
  "no Validate=$(_pv20 "$(sed '/^\*\*Validate:\*\*/d' .temper/specs/demo/tasks.md)")|demo=$(_pv20 "$(cat .temper/specs/demo/tasks.md)" | cut -d'|' -f1)"
rm -f pv-tasks.md
# U24: the digest of the approved plan has one definition, plan_digest of scripts/approval.py; the CLI's _plan_digest,
# plan_patch.py and the flow's plan_core_digest call it. A grep for the digest's pick of a task's Depends finds one
# file.
assert_eq "WP25 the three digests are one function (U24: a grep finds one definition)" \
  "definitions=scripts/approval.py|cli=calls it|patch=same|flow=same" \
  "definitions=$(cd "$REPO_ROOT" && grep -lE "[\"']depends[\"']: *t\[[\"']depends[\"']\]" scripts/*.py scripts/temper | paste -sd, -)|cli=$(awk '/^_plan_digest\(\) \{/{f=1} f{print} f&&/^}/{exit}' "$TEMPER" | grep -q 'approval.py" plan-digest' && echo 'calls it' || echo 'its own')|$(python3 -B - "$REPO_ROOT/scripts" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
os.chdir(sys.argv[1] + "/..")
import approval, flow_run, plan_patch, tasks_md
m = tasks_md.parse(os.path.join(sys.argv[1], "..", "templates", "example-tasks.md")) if os.path.isfile(
    os.path.join(sys.argv[1], "..", "templates", "example-tasks.md")) else None
if not m or not m.get("tasks"):
    m = {"tasks": [{"n": 1, "group": "G1", "files": ["src/a.sh"], "depends": [], "test": "true"}],
         "groups": [{"id": "G1", "depends": [], "validate": "true", "interfaces": [], "context": "x", "tasks": [1]}],
         "integration": "true"}
h = approval.plan_digest(m)
print("patch=%s|flow=%s" % ("same" if h and plan_patch.digest(m) == h else "other",
                            "same" if h and flow_run.Run.plan_core_digest(m) == h else "other"))
PY
)"

# --- WP25: a replan keeps the built tasks whose approved fields did not change (names replan:) ---
# Three groups built by the CLI's own calls: G1 (Task 1, then Task 2 depending on it), G2 (Task 3) and G3 (Task 4, the
# group depends on G2). A step back to Plan archives groups.json and moves each group branch to its kept ref; after the
# new approval the first Build action (`temper group keep`) restores each task whose files, Depends and Test are those
# of the archived plan, whose tasks it depends on are kept, and whose group's Depends (and the groups those name) are
# unchanged and fully kept. A call the CLI does not have yet stays inside $( ... ) or ends in || true.
T20="$(mktemp -d)"
_rp20() { # _rp20 [sed script]: the plan of the replan cases, changed by the sed script when one is given
  sed -e "${1:-}" <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`
**Depends:** none
**Test:** `test -f src/a.sh`
**Cases:**
- a holds
- a bad input is refused
- [ ] done

### Task 2: second
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `test -f src/b.sh`
**Cases:**
- b holds
- a bad input is refused
- [ ] done

## Group G2: Side
**Depends:** none
**Validate:** `true`
**Context:**
The side work.

### Task 3: third
**File:** `src/c.sh`
**Depends:** none
**Test:** `test -f src/c.sh`
**Cases:**
- c holds
- a bad input is refused
- [ ] done

## Group G3: Last
**Depends:** G2
**Validate:** `true`
**Context:**
The last work.

### Task 4: fourth
**File:** `src/d.sh`
**Depends:** none
**Test:** `test -f src/d.sh`
**Cases:**
- d holds
- a bad input is refused
- [ ] done
TASKS
}
_bt20() { # _bt20 <N> <file>: Task N built by the CLI's own calls: started, RED, the file in its worktree, GREEN, gated
  "$TEMPER" task start "$1" >/dev/null 2>&1; "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  mkdir -p ".claude/worktrees/temper-demo-T$1/src"; echo "echo $1" > ".claude/worktrees/temper-demo-T$1/$2"
  "$TEMPER" task test "$1" --phase green >/dev/null 2>&1; "$TEMPER" task gate "$1" --model m >/dev/null 2>&1
}
_built20() { # every task built and passed, every group checked; kept as an archive, restored on later calls
  if [[ -f "$T20/built.tar" ]]; then
    cd "$WORKDIR" || return 1
    find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; tar -xf "$T20/built.tar" -C "$WORKDIR"; return 0
  fi
  _rp20 | m_setup; "$TEMPER" group start G2 >/dev/null 2>&1
  _bt20 1 src/a.sh; _bt20 2 src/b.sh; _bt20 3 src/c.sh
  "$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group gate G2 >/dev/null 2>&1; "$TEMPER" group continue G2 >/dev/null 2>&1
  "$TEMPER" group start G3 >/dev/null 2>&1; _bt20 4 src/d.sh; "$TEMPER" group gate G3 >/dev/null 2>&1
  tar -cf "$T20/built.tar" -C "$WORKDIR" . 2>/dev/null
}
_t20() { python3 -c "import json,sys; d = json.load(open('.temper/groups.json')); print(eval(sys.argv[1]))" "$1" 2>/dev/null || echo none; }
_c20() { _t20 "'|'.join('%s=%s' % (n, (d.get('tasks', {}).get(n) or {}).get('commit', '')) for n in ('1', '2', '3', '4'))"; }
_replan20() { # _replan20 <sed script>: the step back to Plan, the new plan, approved, then the first Build actions after the
              # approval: the CLI's own calls, or the before calls of the agents it launches (up to four actions)
  "$TEMPER" state loop build plan --reason "the plan changes" >/dev/null 2>&1
  [[ -n "${_RP20_HOOK:-}" ]] && eval "$_RP20_HOOK"
  _rp20 "$1" > .temper/specs/demo/tasks.md
  gpass plan; _RP20_CARD="$("$TEMPER" card 2>/dev/null)"
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" acceptance skip --reason "the replan cases write no acceptance test" >/dev/null 2>&1
  local i calls c
  for i in 1 2 3 4; do
    calls="$(_ev "r = ((d.get('calls') or []) + [c for x in d.get('agents') or [] for c in x.get('before') or []]) if d.get('action') in ('auto', 'work') else []; chr(10).join(r)" "$("$TEMPER" next --json 2>/dev/null)")"
    [[ -n "$calls" ]] || break
    while IFS= read -r c; do [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1; done <<<"$calls"
  done
}
_st20() { # _st20 <N>...: "N=passed" or "N=not passed" for each task
  local n o=""; for n in "$@"; do o+="task$n=$([[ "$(_t20 "(d.get('tasks', {}).get('$n') or {}).get('status')")" == passed ]] && echo passed || echo 'not passed')|"; done
  echo "${o%|}"
}
_built20; _c20_before="$(_c20)"; _c1_20="$(_t20 "d['tasks']['1'].get('commit', '')")"
_replan20 's|^\*\*Test:\*\* `test -f src/b.sh`|**Test:** `test -s src/b.sh`|'
assert_eq "replan: Task 1 unchanged and Task 2 with a new Test line: the approval restores Task 1 as passed with its commit on the group branch, and Task 2 runs again" \
  "task1=passed|commit=on the group branch|task2=not passed|task3=passed|task4=passed" \
  "$(_st20 1)|commit=$([[ -n "$_c1_20" && "$(_t20 "(d.get('tasks', {}).get('1') or {}).get('commit', '')")" == "$_c1_20" ]] && git merge-base --is-ancestor "$_c1_20" temper/demo/G1 2>/dev/null && echo 'on the group branch' || echo lost)|$(_st20 2 3 4)"
assert_eq "replan: a group's gate verdict is kept only when every task of it is kept" "G1=not kept|G2=PASS|G3=PASS" \
  "$(_t20 "'|'.join('%s=%s' % (g, (d.get('groups', {}).get(g) or {}).get('gate', {}).get('verdict') or 'not kept') for g in ('G1', 'G2', 'G3'))" | sed 's/G1=PASS/G1=kept/')"
assert_eq "replan: the approval card says how many built tasks the replan keeps" "3 kept" "$(python3 -c "
import re, sys
print('3 kept' if any(re.search(r'\bkept\b|\bkeeps?\b', l, re.I) and re.search(r'(?<![\d.])3(?![\d.])', l) for l in sys.argv[1].splitlines()) else 'no line says it')" "$_RP20_CARD")"
_built20
_replan20 '/^## Group G2/,/^\*\*Depends:\*\*/s|^\*\*Depends:\*\* none|**Depends:** G1|'
assert_eq "replan: a changed group Depends restores nothing of that group or of the groups that depend on it" \
  "task1=passed|task2=passed|task3=not passed|task4=not passed" "$(_st20 1 2 3 4)"
_built20
# the kept ref of G1 moved back to the base of the feature branch: neither task's commit is in it any more
_RP20_HOOK='for _r in $(git for-each-ref --format="%(refname)" "refs/temper/kept/demo/"); do [[ "$_r" == */G1 ]] && git update-ref "$_r" "$(git rev-parse feature/demo)"; done'
_replan20 's|^\*\*Test:\*\* `test -f src/b.sh`|**Test:** `test -s src/b.sh`|'
_RP20_HOOK=""
assert_eq "replan: a kept task whose commit is no longer in the kept ref is not restored" "task1=not passed|task3=passed" "$(_st20 1 3)"
cd "$WORKDIR" || true
rm -rf "$T20"
