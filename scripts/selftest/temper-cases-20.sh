# Release 9.8.4: the faults one failed run of a complex feature exposed (8 criteria, about 30 files, risk H). Sourced by
# test-temper.sh after temper-cases-19.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

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
assert_eq "9.8.4 2b: and records the request" "True" "$(_g1 "bool((g.get('fix') or {}).get('requested'))")"
WT="$(_g1 "g['worktree']")"; mkdir -p "$WT/src"; echo ok > "$WT/src/ok.txt"
assert_exit "9.8.4 2b: group fix --commit commits the fix agent's work on the group branch as the CLI's own commit" 0 "$TEMPER" group fix G1 --commit
assert_eq "9.8.4 2b: the commit is recorded as the CLI's, the request is done, and the worktree is clean" "True|False|0" \
  "$(python3 -c "
import json, subprocess
d = json.load(open('.temper/groups.json')); g = d['groups']['G1']
head = subprocess.run(['git', '-C', g['worktree'], 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
print('%s|%s' % (head in d.get('cli_commits', []), 'fix' in g))")|$(git -C "$WT" status --porcelain | grep -vc '^?? .temper/' )"
assert_exit "9.8.4 2b: the group gate passes on the fixed tree" 0 "$TEMPER" group gate G1
assert_exit "9.8.4 2b: group fix is refused on a group whose gate did not fail" 1 "$TEMPER" group fix G1

# --- 1. The plan gate fails when a test file a group's Validate runs is edited by a task of a later group ---
setup
mkdir -p tests scripts/selftest
printf 'def test_a():\n    assert True\n' > tests/test_core.py
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
  "False|G1's Validate runs tests/test_core.py, which Task 2 of G2 edits" \
  "$(_p1 "$(_p1tasks "python3 -m pytest tests/test_core.py -q" tests/test_core.py)" | cut -d: -f1)"
assert_eq "9.8.4 1: a folder the Validate runs counts (pytest tests/)" "False" "$(_p1 "$(_p1tasks "pytest tests/" tests/test_core.py)" | cut -d'|' -f1)"
assert_eq "9.8.4 1: a file the Validate's own script sources counts (a selftest that runs case files)" \
  "False|G1's Validate runs scripts/selftest/cases-8.sh, which Task 2 of G2 edits" \
  "$(_p1 "$(_p1tasks "bash scripts/selftest/run.sh" scripts/selftest/cases-8.sh)" | cut -d: -f1)"
assert_eq "9.8.4 1: a new test file a later group writes is no conflict (G1 cannot run a file that does not exist yet)" "True" \
  "$(_p1 "$(_p1tasks "pytest tests/" tests/test_new.py)" | cut -d'|' -f1)"
assert_eq "9.8.4 1: a Validate that runs other files passes" "True" "$(_p1 "$(_p1tasks "pytest tests/test_other.py" tests/test_core.py)" | cut -d'|' -f1)"
rm -rf tests scripts p1-tasks.md

# --- 3b. After a loop back that changes plan.md or tasks.md, the fresh review gets one more round past its cap ---
setup
printf 'plan:\n  fresh-review: auto\n  fresh-review-rounds: 1\n' >> .claude/temper.config
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
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
_p5task() { printf '### Task %s: step %s\n**File:** `%s`, `tests/test_%s.py`\n**Depends:** %s\n**Test:** `true`\n**Cases:**\n- a\n- b\n- [ ] done\n\n' "$1" "$1" "$2" "$1" "$3"; }
_p5plan() { printf '**Integration:** `true`\n\n## Group G1: Core\n**Depends:** none\n**Validate:** `true`\n**Context:**\nThe core.\n\n'; }
assert_eq "9.8.4 5: three tasks of one group on the same production file fail the row, with a detail that says to merge them" \
  "False|G1: Task 1, Task 2 and Task 3 all declare src/core.py; merge them into one task" \
  "$(_p5 "$(_p5plan; _p5task 1 src/core.py none; _p5task 2 src/core.py "Task 1"; _p5task 3 src/core.py "Task 2")")"
assert_eq "9.8.4 5: two tasks on one file pass (they are ordered by Depends)" "True" \
  "$(_p5 "$(_p5plan; _p5task 1 src/core.py none; _p5task 2 src/core.py "Task 1")" | cut -d'|' -f1)"
assert_eq "9.8.4 5: a shared test file is not a production file" "True" \
  "$(_p5 "$(_p5plan; _p5task 1 tests/test_x.py none; _p5task 2 tests/test_x.py "Task 1"; _p5task 3 tests/test_x.py "Task 2")" | cut -d'|' -f1)"
rm -f p5-tasks.md
