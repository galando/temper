# case-helpers-5.sh: the helper functions and constants of temper-cases-5.sh, so temper-cases-6.sh runs on its own
# (9.8.5). Made by make-helpers-5.sh; do not edit by hand. temper-cases-6.sh sources it when the helpers are not defined.
gp_base() { # write the valid two-group fixture to the demo spec's tasks.md (a plan not built yet, so no groups.json)
  rm -f .temper/groups.json
  cat > .temper/specs/demo/tasks.md <<'GP'
# Tasks: demo

**Integration:** `bash run-all.sh`

## Group G1: Core
**Depends:** none
**Validate:** `bash unit/g1.sh`
**Interfaces:** `src/a.sh` — `a_main`
**Context:**
Shared notes for G1. Use bash.

### Task 1: Alpha
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `bash unit/a_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

### Task 2: Beta
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `bash unit/b_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

## Group G2: Edge
**Depends:** none
**Validate:** `bash unit/g2.sh`
**Context:**
Notes for G2.

### Task 3: Gamma
**File:** `src/c.sh`
**Depends:** none
**Test:** `bash unit/c_test.sh`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done
GP
}
gp_mut() { # gp_mut <old> <new>: a fixture edit; a recorded plan digest (H3) is dropped, as if re-approved
  gp_tamper "$1" "$2" || return 1
  local f
  for f in .temper/groups.json .temper/build-state.json; do
    [[ -f "$f" ]] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); d.pop('plan_hash', None)
json.dump(d, open(sys.argv[1], 'w'))" "$f"
  done
  return 0
}
gp_tamper() { # gp_tamper <old> <new>: replace the first occurrence in the demo tasks.md, keeping groups.json as is
  python3 - "$1" "$2" <<'PY'
import sys
p = '.temper/specs/demo/tasks.md'
s = open(p).read()
assert sys.argv[1] in s, 'fixture text not found: ' + sys.argv[1]
open(p, 'w').write(s.replace(sys.argv[1], sys.argv[2], 1))
PY
}
gp_setup() { setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base; mkdir -p unit; : > unit/b_test.sh; : > unit/c_test.sh; }
gp_gate() { "$TEMPER" gate plan 2>&1; }
gp_has() { gp_gate | grep -c -- "$1" | tr -d ' '; }
sg_setup() { setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base; }
sg_groups() { # sg_groups <json>: write .temper/groups.json the way a started run would hold it
  printf '%s\n' "$1" > .temper/groups.json
}
SG_RUN='"G1":{"status":"running","worktree":".claude/worktrees/temper-demo-G1","branch":"temper/demo/G1"},"G2":{"status":"running","worktree":".claude/worktrees/temper-demo-G2","branch":"temper/demo/G2"}'
sg_state() { # sg_state <tasks-json> [groups-json]: both groups started, plus per-task state
  sg_groups "{\"version\":1,\"slug\":\"demo\",\"groups\":{${2:-$SG_RUN}},\"tasks\":$1}"
}
sg_ready() { # the ready task numbers, comma separated, in the order printed
  "$TEMPER" schedule 2>/dev/null | python3 -c "
import json, sys
print(','.join(str(json.loads(l)['task']) for l in sys.stdin if l.strip().startswith('{') and 'task' in json.loads(l)))"
}
sg_last() { "$TEMPER" schedule 2>/dev/null | tail -1; }
sg_amodel() { # sg_amodel <task-model>: agent_model of the first ready line under that task-model
  sg_setup; printf '  grouped:\n    task-model: %s\n' "$1" >> .claude/temper.config; sg_state '{}'
  "$TEMPER" schedule | head -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['agent_model'])"
}
sw_setup() { # sg_setup + a fresh repository with one commit, on the run's feature branch
  sg_setup
  rm -rf .git README; git init -q . 2>/dev/null
  git config user.email t@example.com; git config user.name T
  echo base > README; git add README; git commit -q -m base
  git checkout -q -B feature/demo
}
sw_head() { git rev-parse HEAD; }
sw_field() { # sw_field <G> <field>
  python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['groups'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"
}
ST_WT=".claude/worktrees/temper-demo-G1"
T1W=".claude/worktrees/temper-demo-T1"   # one worktree per task: Task N works in temper-demo-T<N>
st_setup() { # sw_setup + the upstream gates ADR 0009 asks for + both groups started
  sw_setup
  printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
  # the declared Test: commands are controllable from outside the worktree: ST_EXIT is the exit, ST_SLEEP
  # hangs, ST_LONG prints a long output, ST_ENV prints the names of the variables the command was given
  local t="bash -c 'echo boom; pwd; [ -z \"\$ST_ENV\" ] || env | cut -d= -f1; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"
  gp_mut '`bash unit/a_test.sh`' "\`$t\`"; gp_mut '`bash unit/b_test.sh`' "\`$t\`"; gp_mut '`bash unit/c_test.sh`' "\`$t\`"
  [[ -z "${ST_PRE:-}" ]] || eval "$ST_PRE"   # a case may edit the plan before the first group start
  "$TEMPER" group start G1 >/dev/null 2>&1; "$TEMPER" group start G2 >/dev/null 2>&1
}
st_field() { # st_field <task> <field>
  python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['tasks'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"
}
st_rows() { # st_rows <task>: the ledger rows of one task as phase:exit,phase:exit
  python3 -c "
import json,sys
rows=json.load(open('.temper/evidence/build.json'))
print(','.join('%s:%s' % (r['phase'], r['exit_code']) for r in rows if r.get('task')==int(sys.argv[1])))" "$1" 2>/dev/null
}
st_twt() { # st_twt [path]: the worktree a task agent writes in: the running task that declares the path, else the most
          # recently started running task, each in its own worktree; with none running, G1's worktree
  python3 - "${1:-}" "$ST_WT" <<'PY'
import json, re, sys
path, fallback = sys.argv[1], sys.argv[2]
try:
    d = json.load(open('.temper/groups.json'))
except Exception:
    d = {}
files, n = {}, None
try:
    for l in open('.temper/specs/demo/tasks.md'):
        m = re.match(r'^###\s+Task\s+(\d+)\s*:', l)
        if m: n = int(m.group(1))
        elif n is not None and l.startswith('**File:**'):
            files[n] = re.findall(r'`([^`]+)`', l)
except Exception:
    pass
import os
def made(w):  # started_at has one-second resolution; two tasks started in the same second are told apart by when
    try:      # their worktree was made (its .git file is written once, by git worktree add)
        return os.stat(os.path.join(w, '.git')).st_mtime_ns
    except OSError:
        return 0
run = sorted(((v.get('started_at') or '', made(v.get('worktree')), int(k), v.get('worktree')) for k, v in (d.get('tasks') or {}).items()
              if v.get('status') == 'running' and v.get('worktree')), reverse=True)
own = [w for _, _, k, w in run if path and path in files.get(k, [])]
print(own[0] if own else (run[0][3] if run else fallback))
PY
}
st_edit() { # st_edit <task-file-relative-path>: write a file into the running task's worktree (st_twt)
  # Only ever inside the selftest's throwaway folder: a case that left the folder would
  # otherwise write into the repository it runs from.
  local here top; here="$(pwd -P)"; top="$(cd "$WORKDIR" && pwd -P)"
  [[ "$here" == "$top" || "${here#"$top"/}" != "$here" ]] || { echo "st_edit refused: cwd $(pwd) is outside WORKDIR" >&2; return 1; }
  local w; w="$(st_twt "$1")"
  mkdir -p "$w/$(dirname "$1")"; echo "work $1" > "$w/$1"
}
st_unticked() { # the number of unticked boxes in the demo tasks.md
  grep -c '^- \[ \]' .temper/specs/demo/tasks.md
}
st_fail() { # st_fail <red-exit|none> <green-exit|none> [more ledger shape]: start 1, record, gate; prints the output
  "$TEMPER" task start 1 >/dev/null 2>&1
  [[ "$1" != "none" ]] && ST_EXIT=$1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  st_edit src/a.sh
  [[ "$2" != "none" ]] && ST_EXIT=$2 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  "$TEMPER" task gate 1 --model m 2>&1
}
st_pass_ready() { "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; }
st_nextcount() { printf '%s\n' "$1" | grep -c '^NEXT:'; }
st_attempt() { # st_attempt <model> <ms>: start Task 1, write a declared file and a stray one, no RED: a FAIL
  "$TEMPER" task start 1 >/dev/null 2>&1
  st_edit src/a.sh; st_edit stray.txt
  "$TEMPER" task gate 1 --model "$1" --ms "$2" 2>&1
}
gg_setup() { # st_setup + a controllable G1 Validate command (GV_EXIT is its exit)
  st_setup
  gp_mut '`bash unit/g1.sh`' "\`bash -c 'echo validating; pwd; exit \${GV_EXIT:-0}'\`"
}
gg_pass() { # gg_pass <task> <file>: drive one task through RED, an edit, GREEN and its gate
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  st_edit "$2"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --ms 5 >/dev/null 2>&1
}
gg_g() { # gg_g <group> <field>
  python3 -c "
import json,sys
v=json.load(open('.temper/groups.json'))['groups'][sys.argv[1]]
for k in sys.argv[2].split('.'):
    v=(v or {}).get(k,'') if isinstance(v,dict) else ''
print(v)" "$1" "$2"
}
gg_ready_g1() { "$TEMPER" schedule | python3 -c "
import json,sys
print(','.join('%d@%d' % (r['task'], r['attempt']) for r in (json.loads(l) for l in sys.stdin if l.startswith('{')) if r.get('group')=='G1'))"; }

# PASS path
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "group gate: every task passed and Validate exits 0 -> PASS (exit 0)" "0|1" "$rc|$(printf '%s' "$out" | grep -c '^PASS: group G1')"
assert_eq "group gate: the Validate command ran in the worktree" "1" "$(printf '%s\n' "$out" | grep -c "^$PWD/$ST_WT\$")"
assert_eq "group gate: verdict, status and finished_at are recorded" "PASS|passed|1" \
  "$(gg_g G1 gate.verdict)|$(gg_g G1 status)|$([[ -n "$(gg_g G1 finished_at)" ]] && echo 1 || echo 0)"
assert_eq "group gate: a build row is tagged with the group, executed by the CLI" "G1|cli|0" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/evidence/build.json')) if x.get('group')=='G1' and not x.get('task')][-1]; print('%s|%s|%s' % (r['group'],r['executed_by'],r['exit_code']))")"
assert_eq "group gate: the group row is not a task RED/GREEN row (gate build counts unchanged)" "0" \
  "$(python3 -c "import json; print(len([x for x in json.load(open('.temper/evidence/build.json')) if x.get('group')=='G1' and not x.get('task') and x.get('phase') in ('red','green')]))")"

# one task not passed -> FAIL, Validate never runs
gg_setup; gg_pass 1 src/a.sh
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "group gate: a task that has not passed fails the group, naming it (exit 1)" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL:.*Task 2')"
assert_eq "group gate: Validate did not run and no gate verdict PASS is stored" "0|" \
  "$(printf '%s' "$out" | grep -c validating)|$(gg_g G1 gate.verdict | grep PASS)"

# Validate exits 1 -> FAIL, group stays running
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
out="$(GV_EXIT=1 "$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "group gate: Validate exit 1 -> FAIL naming the exit (exit 1)" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL:.*exit 1')"
assert_eq "group gate: a failing Validate leaves the group running with a FAIL verdict" "running|FAIL" "$(gg_g G1 status)|$(gg_g G1 gate.verdict)"
assert_eq "group gate: the failing run is recorded as a row" "1" \
  "$(python3 -c "import json; print(len([x for x in json.load(open('.temper/evidence/build.json')) if x.get('group')=='G1' and not x.get('task') and x.get('exit_code')==1]))")"
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "group gate: a later run with Validate green flips the verdict to PASS" "0|PASS" "$rc|$(gg_g G1 gate.verdict)"
assert_exit "group gate: an unknown group exits 1" 1 "$TEMPER" group gate G9
assert_exit "group gate: a malformed group id exits 1" 1 "$TEMPER" group gate foo
setup; gp_base; printf 'build:\n  mode: grouped\n' >> .claude/temper.config
assert_exit "group gate: a group that was never started exits 1" 1 "$TEMPER" group gate G1

# Change at a group gate: reopen only the named task (D-02)
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh; "$TEMPER" group gate G1 >/dev/null 2>&1
T1COMMIT="$(st_field 1 commit)"
out="$("$TEMPER" group reopen G1 --task 2 --feedback 1 2>&1)"; rc=$?
assert_eq "group reopen: exits 0 and says OK" "0|1" "$rc|$(printf '%s' "$out" | grep -c '^OK:')"
assert_eq "group reopen: only Task 2 of G1 is unticked (G2's Task 3 was never ticked)" "2|1" \
  "$(st_unticked | tr -d ' ')|$(awk '/^### Task 2:/{f=1} /^## Group G2/{f=0} f' .temper/specs/demo/tasks.md | grep -c '^- \[ \]')"
assert_eq "group reopen: Task 2 is pending at attempt 1 with its history moved aside" "pending|0|1" \
  "$(st_field 2 status)|$(python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['tasks']['2']['attempts']))")|$(python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['tasks']['2']['attempts_prior']))")"
assert_eq "group reopen: Task 1 keeps its passed gate and its ticked box" "passed|$T1COMMIT" "$(st_field 1 status)|$(st_field 1 commit)"
assert_eq "group reopen: the group gate is cleared" "" "$(gg_g G1 gate.verdict)"
assert_eq "group reopen: Task 2's file is reverted, Task 1's file stays" "no|yes" \
  "$([[ -e "$ST_WT/src/b.sh" ]] && echo yes || echo no)|$([[ -e "$ST_WT/src/a.sh" ]] && echo yes || echo no)"
assert_eq "group reopen: one revert commit touching only Task 2's file" "revert(demo): reopen Task 2|src/b.sh" \
  "$(git -C "$ST_WT" log -1 --format=%s)|$(git -C "$ST_WT" show --name-only --format= HEAD)"
assert_eq "group reopen: the worktree is clean" "" "$(git -C "$ST_WT" status --porcelain)"
assert_eq "group reopen: the feedback id is recorded on the task" "1" \
  "$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['tasks']['2']['reopened'][0]['feedback'])")"
assert_eq "group reopen: the schedule offers only Task 2 of G1, at attempt 1" "2@1" "$(gg_ready_g1)"
assert_eq "group reopen: Task 2 can pass again and the group gate re-runs" "0|PASS" \
  "$(gg_pass 2 src/b.sh; "$TEMPER" group gate G1 >/dev/null 2>&1; echo $?)|$(gg_g G1 gate.verdict)"

# two tasks, plus the refusals
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
assert_exit "group reopen: two --task flags reopen both" 0 "$TEMPER" group reopen G1 --task 1 --task 2
assert_eq "group reopen: both boxes are unticked and G2's is untouched" "3" "$(st_unticked)"
gg_setup; gg_pass 1 src/a.sh
assert_exit "group reopen: a task of another group exits 1" 1 "$TEMPER" group reopen G1 --task 3
assert_exit "group reopen: no --task exits 1" 1 "$TEMPER" group reopen G1
assert_exit "group reopen: an unknown task exits 1" 1 "$TEMPER" group reopen G1 --task 99
"$TEMPER" task start 2 >/dev/null 2>&1
assert_exit "group reopen: a running task exits 1" 1 "$TEMPER" group reopen G1 --task 2
gg_setup; gg_pass 1 src/a.sh; printf '{"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
assert_exit "group reopen: the CLI commit checks the upstream gates (ADR 0009, exit 3)" 3 "$TEMPER" group reopen G1 --task 1
# a reopen un-parks the group so the named task can run again
gg_setup
for i in 1 2 3; do "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task gate 1 --model m >/dev/null 2>&1; done
assert_eq "group reopen: the group is parked after three failures" "parked" "$(gg_g G1 status)"
assert_exit "group reopen: reopening a parked task exits 0" 0 "$TEMPER" group reopen G1 --task 1
assert_eq "group reopen: the group runs again and the task is offered at attempt 1" "running|1@1" "$(gg_g G1 status)|$(gg_ready_g1)"
setup

# --- Grouped Build (9.7.0): integration (temper integrate) and the build gate's integration row ---
# Scenarios: Integration merges every passed group and verifies the result; A merge conflict stops the
# run before Review [AC-10]. Every case runs in the throwaway folder's own git repository.
gi_setup() { # both groups started, G1/G2 Validate and the Integration suite controllable (GI_EXIT)
  rm -rf src unit shared.txt   # files an earlier case merged into the shared throwaway folder
  gg_setup
  gp_mut '`bash unit/g2.sh`' '`true`'
  gp_mut '`bash run-all.sh`' "\`bash -c 'echo integrating; pwd; ls src; exit \${GI_EXIT:-0}'\`"
  "$TEMPER" group start G2 >/dev/null 2>&1
}
gi_pass() { # gi_pass <task> <group> <file> <content>: RED, edit in the task's own worktree, GREEN, task gate
  local wt=".claude/worktrees/temper-demo-T$1"
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  mkdir -p "$wt/$(dirname "$3")"; printf '%s\n' "$4" > "$wt/$3"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --ms 5 >/dev/null 2>&1
}
gi_all() { # every task passed and both group gates PASS
  gi_setup
  gi_pass 1 G1 src/a.sh 'a_main() { :; }'; gi_pass 2 G1 src/b.sh 'b_main() { :; }'
  gi_pass 3 G2 src/c.sh 'c_main() { :; }'
  "$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group gate G2 >/dev/null 2>&1
}
gi_int() { python3 -c "
import json,sys
v=json.load(open('.temper/groups.json')).get('integration') or {}
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(v if not isinstance(v,list) else ','.join(v))" "$1"; }
gi_gate_row() { "$TEMPER" gate build 2>&1 | grep -c "integration"; }

gi_all; BASE="$(git rev-parse HEAD)"
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: two clean groups merge and verify -> exit 0 and PASS" "0|1" "$rc|$(printf '%s' "$out" | grep -c '^PASS: integrated')"
assert_eq "integrate: one --no-ff merge commit per group, in order, on the feature branch" "merge(demo): group G2|merge(demo): group G1" \
  "$(git log --merges --format=%s | sed -n 1p)|$(git log --merges --format=%s | sed -n 2p)"
assert_eq "integrate: every group's files are on the feature branch" "yes|yes|yes" \
  "$([[ -f src/a.sh && -f src/b.sh ]] && echo yes || echo no)|$([[ -f src/c.sh ]] && echo yes || echo no)|$([[ "$(git rev-parse --abbrev-ref HEAD)" == feature/demo ]] && echo yes || echo no)"
assert_eq "integrate: the suite ran in the project folder, after the worktrees were removed" "1|1|0" \
  "$(printf '%s\n' "$out" | grep -c "^$PWD\$")|$(printf '%s\n' "$out" | grep -c '^integrating$')|$(git worktree list --porcelain | grep -c 'worktrees/temper-demo-G')"
assert_eq "integrate: the worktree folders are gone and the group branches are deleted" "no|no|0" \
  "$([[ -d .claude/worktrees/temper-demo-G1 ]] && echo yes || echo no)|$([[ -d .claude/worktrees/temper-demo-G2 ]] && echo yes || echo no)|$(git branch --list 'temper/demo/*' | wc -l | tr -d ' ')"
assert_eq "integrate: the suite run is a CLI-executed build row tagged integration" "integration|cli|0" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/evidence/build.json')) if x.get('phase')=='integration'][-1]; print('%s|%s|%s' % (r['phase'],r['executed_by'],r['exit_code']))")"
assert_eq "integrate: the integration row is not a task RED/GREEN row" "0" \
  "$(python3 -c "import json; print(len([x for x in json.load(open('.temper/evidence/build.json')) if x.get('phase') in ('red','green') and not x.get('task')]))")"
assert_eq "integrate: groups.json records the PASS verdict" "PASS" "$(gi_int verdict)"
assert_eq "integrate: gate build shows an integration row" "1" "$(gi_gate_row)"
assert_eq "integrate: the integration row is PASS" "1" "$("$TEMPER" gate build 2>&1 | grep -c 'integration — groups merged')"
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a second run after PASS is a no-op that exits 0" "0|1" "$rc|$(printf '%s' "$out" | grep -c 'already integrated')"

# a group gate that has not passed stops it before any merge
gi_all; "$TEMPER" group reopen G2 --task 3 >/dev/null 2>&1; HEAD0="$(git rev-parse HEAD)"
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a group whose gate has not passed -> exit 1 naming it" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL:.*G2')"
assert_eq "integrate: nothing was merged" "$HEAD0" "$(git rev-parse HEAD)"
assert_eq "integrate: gate build FAILs on the integration row" "1" "$("$TEMPER" gate build 2>&1 | grep -c 'FAIL.*integration\|integration.*FAIL\|integration.*not run')"

# the suite fails: FAIL, branches kept for diagnosis
gi_all
out="$(GI_EXIT=1 "$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a failing suite -> exit 1 naming the exit" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL:.*exit 1')"
assert_eq "integrate: verdict FAIL is stored and the group branches are kept" "FAIL|2" "$(gi_int verdict)|$(git branch --list 'temper/demo/*' | wc -l | tr -d ' ')"
assert_eq "integrate: gate build is FAIL on the integration row" "1" "$("$TEMPER" gate build 2>&1 | grep -c 'FAIL.*integration\|integration.*FAIL')"
assert_eq "integrate: a rerun after the suite is fixed flips the verdict to PASS" "0|PASS" "$("$TEMPER" integrate >/dev/null 2>&1; echo $?)|$(gi_int verdict)"

# live run 11: a passing Validate or suite prints only its last 12 lines into the main conversation; a failing one all
gi_setup
gp_mut "\`bash -c 'echo validating; pwd; exit \${GV_EXIT:-0}'\`" "\`bash -c 'seq 1 40; exit \${GV_EXIT:-0}'\`"
gp_mut "\`bash -c 'echo integrating; pwd; ls src; exit \${GI_EXIT:-0}'\`" "\`bash -c 'seq 101 140; exit \${GI_EXIT:-0}'\`"
gi_pass 1 G1 src/a.sh 'a_main() { :; }'; gi_pass 2 G1 src/b.sh 'b_main() { :; }'; gi_pass 3 G2 src/c.sh 'c_main() { :; }'
nums() { printf '%s\n' "$1" | grep -x '[0-9][0-9]*' | sed -n '1p;$p' | paste -sd'-' -; printf '%s\n' "$1" | grep -cx '[0-9][0-9]*'; }
out="$(GV_EXIT=1 "$TEMPER" group gate G1 2>&1)"
assert_eq "group gate: a failing Validate prints all of its output" "1-40|40|0" "$(nums "$out" | paste -sd'|' -)|$(printf '%s\n' "$out" | grep -c 'not shown')"
out="$("$TEMPER" group gate G1 2>&1)"
assert_eq "group gate: a passing Validate prints its last 12 lines and says how many it left out" "29-40|12|1|1" \
  "$(nums "$out" | paste -sd'|' -)|$(printf '%s\n' "$out" | grep -cx '\[the first 28 lines of the passing output are not shown\]')|$(printf '%s\n' "$out" | grep -c '^PASS: group G1')"
"$TEMPER" group gate G2 >/dev/null 2>&1
out="$(GI_EXIT=1 "$TEMPER" integrate 2>&1)"
assert_eq "integrate: a failing suite prints all of its output" "101-140|40|0" "$(nums "$out" | paste -sd'|' -)|$(printf '%s\n' "$out" | grep -c 'not shown')"
out="$("$TEMPER" integrate 2>&1)"
assert_eq "integrate: a passing suite prints its last 12 lines, and its row keeps the output" "129-140|12|1|1" \
  "$(nums "$out" | paste -sd'|' -)|$(printf '%s\n' "$out" | grep -c '^PASS: integrated')|$(python3 -c "import json; r=[x for x in json.load(open('.temper/evidence/build.json')) if x.get('phase')=='integration'][-1]; print(int(r['output'].startswith('101')))")"
unset -f nums

# an Interfaces literal that is missing from the merged tree
gi_all; gp_mut '`src/a.sh` — `a_main`' '`src/a.sh` — `a_missing`'
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a missing interface literal -> exit 1 naming it" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: interface missing: a_missing in src/a.sh')"
assert_eq "integrate: the interface FAIL is stored" "FAIL" "$(gi_int verdict)"

# a merge conflict stops the run before Review
gi_all
echo one > .claude/worktrees/temper-demo-G1/shared.txt; git -C .claude/worktrees/temper-demo-G1 add shared.txt; git -C .claude/worktrees/temper-demo-G1 commit -q -m g1shared
echo two > .claude/worktrees/temper-demo-G2/shared.txt; git -C .claude/worktrees/temper-demo-G2 add shared.txt; git -C .claude/worktrees/temper-demo-G2 commit -q -m g2shared
# D-08 review M5: integrate refuses a group branch holding a commit the CLI did not record, so the fixture records its two hand
# commits as the CLI's own (the conflict, not the refusal, is what this case is about)
python3 - "$(git -C .claude/worktrees/temper-demo-G1 rev-parse HEAD)" "$(git -C .claude/worktrees/temper-demo-G2 rev-parse HEAD)" <<'PY'
import json, sys
d = json.load(open('.temper/groups.json'))
d.setdefault('cli_commits', []).extend(sys.argv[1:])
json.dump(d, open('.temper/groups.json', 'w'))
PY
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a conflicting pair aborts with the cause (exit 1)" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: merge conflict: G2 in shared.txt')"
assert_eq "integrate: the merge was aborted, the tree is clean, G1 stays merged" "|1" \
  "$(git status --porcelain | grep -v '^??')|$(git log --merges --format=%s | grep -c 'group G1')"
assert_eq "integrate: groups.json records the group and files" "FAIL|G2|shared.txt" "$(gi_int verdict)|$(gi_int group)|$(gi_int files)"
assert_eq "integrate: the worktrees are kept for diagnosis and the suite never ran" "2|0" \
  "$(git worktree list --porcelain | grep -c 'worktrees/temper-demo-G')|$(printf '%s' "$out" | grep -c integrating)"
assert_eq "integrate: gate build FAILs on integration" "1" "$("$TEMPER" gate build 2>&1 | grep -c 'FAIL.*integration\|integration.*FAIL')"

# refusals
gi_all; git checkout -q -B main
assert_exit "integrate: the protected branch main is refused (exit 3)" 3 "$TEMPER" integrate
assert_eq "integrate: on main the refusal names the run's branch to switch to" "1" \
  "$("$TEMPER" integrate 2>&1 | grep -c "switch to the run's branch 'feature/demo'")"
gi_all; git checkout -q -B other
assert_exit "integrate: a branch that is not the run's feature branch exits 1" 1 "$TEMPER" integrate
gi_all; printf '{"intent":{"verdict":"PASS"}}\n' > .temper/gates.json; HEAD0="$(git rev-parse HEAD)"
assert_exit "integrate: the CLI merge checks the upstream gates first (ADR 0009, exit 3)" 3 "$TEMPER" integrate
assert_eq "integrate: the refused run merged nothing" "$HEAD0" "$(git rev-parse HEAD)"
gi_all; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_exit "integrate: autonomy lets the local integration merge run (design resolution 1a)" 0 "$TEMPER" integrate
setup; rm -f .temper/specs/demo/tasks.md .temper/groups.json
assert_exit "integrate: a run without tasks.md exits 1" 1 "$TEMPER" integrate
assert_eq "integrate: a run without tasks.md (a /temper:fix run) has no integration row in gate build" "0" "$("$TEMPER" gate build 2>&1 | grep -c integration)"

# --- Grouped Build (9.7.0): max-blast-radius at the autonomy commit gate (D-01) ---
# Scenario: Autonomy commit gate in grouped mode compares changes to the declared union [AC-11]
gc_setup() { # gc_setup <grouped|fix>: autonomous run, max-blast-radius 3, four declared files changed
  gp_setup
  [[ "$1" != "fix" ]] || rm -f .temper/specs/demo/tasks.md   # a /temper:fix run has no tasks.md
  sed 's/max-blast-radius: 15/max-blast-radius: 3/' .claude/temper.config > .claude/temper.config.new && mv .claude/temper.config.new .claude/temper.config
  "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
  # setup keeps the work tree, so the four files an earlier gc_setup left would be committed into this
  # base with the same content and stop counting as changes. Clear them first so every call starts from
  # the same tree.
  rm -rf src unit
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -q -m base >/dev/null 2>&1
  mkdir -p src unit
  for f in src/a.sh unit/a_test.sh src/b.sh src/c.sh; do echo "x" > "$f"; done
}
gc_row() { "$TEMPER" gate commit 2>&1 | grep 'blast radius'; }
gr_json() { "$TEMPER" group report --json 2>/dev/null | python3 -c "
import json,sys
v=json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v)" "$1"; }
gg_setup
# Task 1 fails twice (haiku, haiku) then passes on the escalation model; Task 2 passes at once
for a in 1 2; do
  "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task gate 1 --model claude-haiku-5-5 --ms 1000 >/dev/null 2>&1
done
"$TEMPER" task start 1 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model sonnet --ms 3000 >/dev/null 2>&1
gg_pass 2 src/b.sh
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "group report: the time is totalled per model across every attempt" '{"claude-haiku-5-5": 2005, "sonnet": 3000}' "$(gr_json ms_by_model)"
assert_eq "group report: attempts per task carry model and outcome" "3|1" \
  "$(gr_json attempts | python3 -c "import json,sys; a=json.load(sys.stdin); print(len(a['1']))")|$(gr_json attempts | python3 -c "import json,sys; a=json.load(sys.stdin); print(len(a['2']))")"
assert_eq "group report: attempt rows keep model, outcome and ms" "sonnet|PASS|3000" \
  "$(gr_json attempts | python3 -c "import json,sys; r=json.load(sys.stdin)['1'][-1]; print('%s|%s|%s' % (r['model'],r['outcome'],r['ms']))")"
assert_eq "group report: one escalation (Task 1 ran a third attempt)" "1" "$(gr_json escalations)"
assert_eq "group report: no parked group, no open review findings" "[]|0" "$(gr_json parked)|$(gr_json review_findings_open)"
assert_eq "group report: wall time is recorded for the passed group only" "yes|no" \
  "$(gr_json wall_ms_by_group | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if isinstance(d.get('G1'),int) and d['G1']>=0 else 'no')")|$(gr_json wall_ms_by_group | python3 -c "import json,sys; print('yes' if 'G2' in json.load(sys.stdin) else 'no')")"
assert_eq "group report: total Build wall time is a number" "yes" \
  "$(gr_json build_wall_ms | python3 -c "import sys; print('yes' if sys.stdin.read().strip().isdigit() else 'no')")"
assert_eq "group report: a group's wall time spans first start to gate PASS" "ok" \
  "$(python3 - <<'PY'
import json, calendar, time
d = json.load(open('.temper/groups.json'))['groups']['G1']
f = lambda s: calendar.timegm(time.strptime(s, '%Y-%m-%dT%H:%M:%SZ'))
print('ok' if d['finished_at'] and f(d['finished_at']) >= f(d['started_at']) else 'bad')
PY
)"
"$TEMPER" evidence add --stage review --claim "null deref in a.sh" --severity high >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim "style nit" --severity low >/dev/null 2>&1
assert_eq "group report: open review findings are counted from the review ledger" "2" "$(gr_json review_findings_open)"
"$TEMPER" evidence resolve --stage review --id 2 --fixed-by "abc" >/dev/null 2>&1
assert_eq "group report: a resolved finding is no longer open" "1" "$(gr_json review_findings_open)"
out="$("$TEMPER" group report 2>&1)"; rc=$?
assert_eq "group report: the text form prints exit 0 and the headline numbers, and no token count" "0|1|1|0" \
  "$rc|$(printf '%s' "$out" | grep -c 'moved to the stronger model after two failed attempts: 1')|$(printf '%s' "$out" | grep -c 'claude-haiku-5-5 2 s, sonnet 3 s')|$(printf '%s' "$out" | grep -ci 'token')"
# parked group
gg_setup
for i in 1 2 3; do "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task gate 1 --model m >/dev/null 2>&1; done
assert_eq "group report: a parked group is listed" '["G1"]' "$(gr_json parked)"
# archive
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh; "$TEMPER" group gate G1 >/dev/null 2>&1
"$TEMPER" gate plan >/dev/null 2>&1
"$TEMPER" state archive >/dev/null 2>&1
assert_eq "state archive: gate-ledger.json gets a grouped block with the report and the models" "1|claude-haiku-5-5|sonnet|2" \
  "$(python3 -c "
import json
g=json.load(open('.temper/specs/demo/gate-ledger.json')).get('grouped') or {}
print('%s|%s|%s|%s' % (1 if g else 0, g.get('task_model'), g.get('escalation_model'), len(g.get('attempts') or {})))")"
assert_eq "state archive: the grouped block carries ms_by_model" "1" \
  "$(python3 -c "import json; print(1 if json.load(open('.temper/specs/demo/gate-ledger.json'))['grouped']['ms_by_model'] else 0)")"
setup; sw_setup >/dev/null 2>&1; setup; rm -f .temper/groups.json
"$TEMPER" gate plan >/dev/null 2>&1; "$TEMPER" state archive >/dev/null 2>&1
assert_eq "state archive: a run with no groups.json (a /temper:fix run) has no grouped block" "0" \
  "$(python3 -c "import json; print(1 if 'grouped' in json.load(open('.temper/specs/demo/gate-ledger.json')) else 0)" 2>/dev/null || echo 0)"
for sub in 'schedule' 'group <start|gate|reopen|continue>' 'group report' 'task <start|show|test|gate|blocked>' 'integrate' 'model task' 'task-escalation'; do
  assert_eq "help documents: $sub" "1" "$("$TEMPER" --help | grep -cF -- "$sub")"
done
assert_eq "header comment documents the grouped subcommands" "1|1|1|1" \
  "$(grep -c '^#   temper schedule' "$TEMPER")|$(grep -c '^#   temper group' "$TEMPER")|$(grep -c '^#   temper task' "$TEMPER")|$(grep -c '^#   temper integrate' "$TEMPER")"
setup

# --- Whole-flow usage (9.7.0, intent D-07): temper usage add, the report section, the archive ---
# Scenario: Run state records the numbers the cost comparison needs [AC-12]
us_json() { "$TEMPER" report --json 2>/dev/null | python3 -c "
import json,sys
v=json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    v=v.get(k,'') if isinstance(v,dict) else ''
print(json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v)" "$1"; }
setup
assert_exit "usage add: a recorded row exits 0" 0 "$TEMPER" usage add --stage plan --model sonnet --ms 4000
"$TEMPER" usage add --stage build --model claude-haiku-5-5 --ms 2000 --task 4 >/dev/null 2>&1
"$TEMPER" usage add --stage build --model sonnet >/dev/null 2>&1
assert_eq "usage add: rows land in .temper/usage.json with the task and group" "3|4" \
  "$(python3 -c "import json; r=json.load(open('.temper/usage.json')); print('%d|%s' % (len(r), r[1].get('task')))")"
assert_eq "usage add: a missing value is recorded as null and never blocks" "None|None" \
  "$(python3 -c "import json; r=json.load(open('.temper/usage.json'))[2]; print('%s|%s' % (r['ms'], r.get('group')))")"
assert_exit "usage add: an unknown stage exits 1" 1 "$TEMPER" usage add --stage commit --model sonnet
assert_exit "usage add: a stage name that is not on the list exits 1" 1 "$TEMPER" usage add --stage ../x --model sonnet
assert_exit "usage add: a non-numeric --ms exits 1" 1 "$TEMPER" usage add --stage plan --model sonnet --ms lots
assert_exit "usage add: a missing --stage exits 1" 1 "$TEMPER" usage add --model sonnet
assert_exit "usage add: an unknown flag exits 1" 1 "$TEMPER" usage add --stage plan --bogus 1
assert_eq "usage add: all four value flags may be absent (a null row)" "0|4" \
  "$("$TEMPER" usage add --stage check >/dev/null 2>&1; echo $?)|$(python3 -c "import json; print(len(json.load(open('.temper/usage.json'))))")"
assert_eq "report --json: usage totals ms and rows, skipping nulls, and no token count" "6000|4|" \
  "$(us_json usage.total.ms)|$(us_json usage.total.rows)|$(us_json usage.total.tokens)"
assert_eq "report --json: usage per stage" "2000|2" \
  "$(us_json usage.by_stage.build.ms)|$(us_json usage.by_stage.build.rows)"
assert_eq "report --json: usage per model" "4000|2000" \
  "$(us_json usage.by_model.sonnet.ms)|$(us_json usage.by_model.claude-haiku-5-5.ms)"
out="$("$TEMPER" report 2>&1)"
assert_eq "report: the text form has a usage section with the stages and the total, and no token count" "1|1|1|0" \
  "$(printf '%s' "$out" | grep -c '^Usage')|$(printf '%s' "$out" | grep -c 'build.* 2000 ')|$(printf '%s' "$out" | grep -c 'total.* 6000$')|$(printf '%s' "$out" | grep -ci 'token')"
assert_eq "usage add: a count an older after call passes is read by nothing" "0|no" \
  "$("$TEMPER" usage add --stage check --token-count 5 --ms 1 >/dev/null 2>&1; echo $?)|$(python3 -c "import json; print('yes' if any('tokens' in r for r in json.load(open('.temper/usage.json'))) else 'no')")"
setup
assert_eq "report --json: a run with no usage rows has no usage key" "" "$(us_json usage)"
assert_eq "report: a run with no usage rows prints no usage section" "0" "$("$TEMPER" report 2>&1 | grep -c '^Usage')"
# grouped task attempts count once
gg_setup
"$TEMPER" usage add --stage plan --model sonnet --ms 10 >/dev/null 2>&1
for a in 1 2; do "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task gate 1 --model claude-haiku-5-5 --ms 1000 >/dev/null 2>&1; done
"$TEMPER" task start 1 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model sonnet --ms 3000 >/dev/null 2>&1
assert_eq "task gate: every attempt (failed and passed) writes one task usage row" "3|3" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/usage.json')) if x['stage']=='task']; print(len(r))")|$(python3 -c "import json; r=[x for x in json.load(open('.temper/usage.json')) if x['stage']=='task' and x.get('task')==1 and x.get('group')=='G1']; print(len(r))")"
assert_eq "report --json: grouped attempts count once in the totals (5000 task + 10 plan)" "5010" "$(us_json usage.total.ms)"
assert_eq "report --json: the task stage total is the attempts once" "5000|2" \
  "$(us_json usage.by_stage.task.ms)|$(python3 -c "import json; print(len([x for x in json.load(open('.temper/usage.json')) if x['stage']=='task' and x['model']=='claude-haiku-5-5']))")"
"$TEMPER" task start 2 >/dev/null 2>&1; "$TEMPER" task gate 2 --model m >/dev/null 2>&1
assert_eq "task gate: no --model/--ms still writes a null usage row" "4" \
  "$(python3 -c "import json; print(len([x for x in json.load(open('.temper/usage.json')) if x['stage']=='task']))")"
assert_eq "group report: still totals from groups.json (unchanged by the usage file)" '{"claude-haiku-5-5": 2000, "sonnet": 3000}' "$(gr_json ms_by_model)"
"$TEMPER" gate plan >/dev/null 2>&1; "$TEMPER" state archive >/dev/null 2>&1
assert_eq "state archive: gate-ledger.json keeps the usage section" "5000|10" \
  "$(python3 -c "import json; u=json.load(open('.temper/specs/demo/gate-ledger.json'))['usage']; print('%s|%s' % (u['by_stage']['task']['ms'], u['by_stage']['plan']['ms']))" 2>/dev/null)"
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "state clear: removes the usage file" "0" "$([[ -f .temper/usage.json ]] && echo 1 || echo 0)"
assert_eq "help documents: usage add" "1" "$("$TEMPER" --help | grep -cF -- 'usage add')"
assert_eq "header comment documents temper usage" "1" "$(grep -c '^#   temper usage' "$TEMPER")"
setup

# --- Grouped Build (9.7.0): the slim task brief ---
# Scenario: The task launch payload stays within its byte budget [AC-05]
TB="$REPO_ROOT/agents/build-task.md"
TB_MAX="$(grep -m1 '^TASK_BRIEF_MAX_BYTES=' "$TEMPER" | sed 's/^[^=]*=//' | tr -dc '0-9')"
assert_eq "task brief: agents/build-task.md exists" "1" "$([[ -f "$TB" ]] && echo 1 || echo 0)"
assert_eq "task brief: within TASK_BRIEF_MAX_BYTES (read from the script)" "1" \
  "$([[ -f "$TB" && -n "$TB_MAX" && "$(wc -c < "$TB" | tr -d ' ')" -le "$TB_MAX" ]] && echo 1 || echo 0)"
assert_eq "task brief: frontmatter name and model" "temper-build-task|claude-haiku-5-5" \
  "$(awk '/^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); a=$0} n==1 && /^model:/{sub(/^model:[[:space:]]*/,""); b=$0} END{print a "|" b}' "$TB" 2>/dev/null)"
assert_eq "model task reads the brief frontmatter as the default" "claude-haiku-5-5" "$(setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; "$TEMPER" model task)"
assert_eq "plugin.json lists ./agents/build-task.md" "1" "$(python3 -c "import json; print(int('./agents/build-task.md' in json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['agents']))")"
# Scenario: Grouped logic stays in the briefs and the CLI [AC-05]
assert_eq "task brief: says the CLI draws its panel (9.8.0), and states the plugin folder rule" "1|1" \
  "$(grep -c 'Your panel is drawn by the CLI.*temper panel task' "$TB" 2>/dev/null | head -1 | sed 's/^[1-9][0-9]*$/1/')|$(grep -c 'Plugin folder' "$TB" 2>/dev/null | sed 's/^[1-9][0-9]*$/1/')"
assert_eq "task brief: names every CLI command it relies on" "3" \
  "$(for c in 'task show' 'task test' '--phase red'; do grep -qF -- "$c" "$TB" 2>/dev/null && echo x; done | wc -l | tr -d ' ')"
assert_eq "task brief: never points at an orchestrator file" "0" "$(grep -c 'commands/temper.md' "$TB" 2>/dev/null | tr -d ' ')"
assert_eq "model --all has 10 lines with the task brief present" "11" "$(setup; "$TEMPER" model --all | wc -l | tr -d ' ')"
setup

# --- Grouped Build (9.7.0): plan brief, plan reference and templates for grouped output ---
# Scenarios: A three-level grouped plan passes the plan gate; Task and escalation models resolve from
# config with defaults [AC-02, AC-06]. The grouped example in templates/tasks.md must pass the gate.
TPL="$REPO_ROOT/templates/tasks.md"
gp_setup
awk '/^<!-- grouped-example:begin/{f=1;next} /^<!-- grouped-example:end/{f=0} f' "$TPL" > .temper/specs/demo/tasks.md
assert_eq "template: the grouped example is non-empty" "yes" "$([[ -s .temper/specs/demo/tasks.md ]] && echo yes || echo no)"
assert_exit "template: the grouped example passes temper gate plan in grouped mode" 0 "$TEMPER" gate plan
assert_eq "template: the grouped example declares groups, Integration, Interfaces and Context" "4" \
  "$(for k in '^## Group G1' '^\*\*Integration:\*\*' '^\*\*Interfaces:\*\*' '^\*\*Context:\*\*'; do grep -qE -- "$k" .temper/specs/demo/tasks.md && echo x; done | wc -l | tr -d ' ')"
assert_eq "plan brief: one step points at the grouped format, and none at a build.mode" "1|0" \
  "$(grep -c 'in the grouped format' "$REPO_ROOT/agents/plan.md" | tr -d ' ')|$(grep -c 'config get build.mode' "$REPO_ROOT/agents/plan.md" | tr -d ' ')"
assert_eq "plan reference: documents the grouped format, budgets and pack distilling" "4" \
  "$(for k in '^## Grouped tasks' '4096' '2048' 'distil'; do grep -qE -- "$k" "$REPO_ROOT/reference/plan.md" && echo x; done | wc -l | tr -d ' ')"
assert_eq "config default: commented build block names every grouped key" "4" \
  "$(for k in '^# build:' 'task-model' 'escalation-model' 'max-parallel'; do grep -qE -- "$k" "$REPO_ROOT/templates/temper.config.default" && echo x; done | wc -l | tr -d ' ')"
setup

# --- the orchestrator is a loop over temper next (ADR 0013); grouped Build's loop is the CLI's ---
OT="$REPO_ROOT/commands/temper.md"
OF="$REPO_ROOT/commands/fix.md"
# /temper:build is a door into the orchestrator (ADR 0012): it reads commands/temper.md and enters at Build.
assert_eq "orchestrator: the loop runs temper go (9.8.0), and /temper:build is a door into it" "1|1" \
  "$(grep -c 'scripts/temper go` and do what its `action` says' "$OT" | sed 's/^[1-9][0-9]*$/1/')|$(grep -qF 'commands/temper.md' "$REPO_ROOT/commands/build.md" && grep -qF 'Entering at a stage' "$REPO_ROOT/commands/build.md" && echo 1 || echo 0)"
assert_eq "orchestrator: the page names no grouped command and no stage brief (temper next gives them)" "0" \
  "$(for c in 'group start' 'temper schedule' 'task start' 'task gate' 'group gate' 'temper integrate' 'agents/build-task.md' 'agents/plan.md'; do grep -qF -- "$c" "$OT" && echo x; done | wc -l | tr -d ' ')"
assert_eq "orchestrator: an agent's after calls run with its time filled in, and no agent id or token count" "yes|0|0" \
  "$(tr '\n' ' ' < "$OT" | tr -s ' ' | grep -qF 'run its `after` calls: `{ms}` (how long the agent ran, in milliseconds) comes from the Agent result' && echo yes || echo no)|$(grep -c '{agent}' "$OT")|$(grep -ciE 'subagent_tokens|token_count' "$OT")"
assert_eq "orchestrator: fix.md records the RCA launch, and the loop records the rest" "yes|yes" \
  "$(grep -qF 'usage add --stage rca' "$OF" && echo yes || echo no)|$(grep -qF 'scripts/temper next --json' "$OF" && echo yes || echo no)"
assert_eq "orchestrator-patterns: the run files list groups.json and usage.json" "2" \
  "$(for k in 'groups.json' 'usage.json'; do grep -qF -- "$k" "$REPO_ROOT/reference/orchestrator-patterns.md" && echo x; done | wc -l | tr -d ' ')"
assert_eq "autonomy.md: narrowed invariant and group rules" "4" \
  "$(for k in 'final feature commit' 'never pushes' 'answered Continue' 'max-blast-radius'; do grep -qiF -- "$k" "$REPO_ROOT/reference/autonomy.md" && echo x; done | wc -l | tr -d ' ')"
assert_eq "config default: hardcoded invariant states the narrowed wording" "yes|0" \
  "$(grep -qiF 'final feature commit' "$REPO_ROOT/templates/temper.config.default" && echo yes || echo no)|$(grep -c 'NEVER commits, pushes, or merges' "$REPO_ROOT/templates/temper.config.default" | tr -d ' ')"
setup

# --- Grouped Build (9.7.0), review loop 1: the task gate verdict and its restore path [H1, H2, H5, M2] ---
# H1: the verdict reads the LAST run of the attempt, so a failing REFACTOR re-run cannot ride on an earlier green
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
HEADBEFORE="$(git -C "$ST_WT" rev-parse HEAD)"
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "H1: a failing green re-run after a passing one fails the gate and names the final run" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: .*final run')"
assert_eq "H1: the broken state is not committed or ticked" "$HEADBEFORE|3|failed" "$(git -C "$ST_WT" rev-parse HEAD)|$(st_unticked)|$(st_field 1 status)"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_exit "H1: red, green, green (a passing re-run) still passes" 0 "$TEMPER" task gate 1 --model m
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
assert_exit "H1: a failing run after the green fails the gate" 1 "$TEMPER" task gate 1 --model m

# H2: a commit made inside the worktree cannot hide an undeclared file
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit stray.txt
git -C "$T1W" add stray.txt; git -C "$T1W" commit -q -m "sneaky" 2>/dev/null
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "H2: an undeclared file committed in the worktree fails the gate and names it" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: undeclared change: stray.txt')"
assert_eq "H2: the failure also names the commit the CLI did not make" "1" "$(printf '%s' "$out" | grep -c 'not made by the CLI')"
assert_eq "H2: the task is not ticked" "3" "$(st_unticked)"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; git -C "$T1W" add src/a.sh; git -C "$T1W" commit -q -m "own commit" 2>/dev/null
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "H2: a declared file committed by hand still fails (not a CLI commit)" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'not made by the CLI')"

# H5: the commit hook writes .temper/gates.json inside the worktree; that is not an undeclared change
case_hook() { # case_hook <shell line>: a native pre-commit hook that runs the line, for every commit of this case's
  # repository and its worktrees. It sits in a folder of the case's own in the git folder, which core.hooksPath names by
  # its absolute path (as Temper's installer does), never in git's default hook folder; sw_setup removes it with .git.
  local hd; hd="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/case-gate"; mkdir -p "$hd"
  printf '#!/bin/sh\n%s\nexit 0\n' "$1" > "$hd/pre-commit"; chmod +x "$hd/pre-commit"
  git config core.hooksPath "$hd"
}
h5_hook() { case_hook 'mkdir -p .temper && echo "{}" > .temper/gates.json'; }   # writes run state in the commit's own top folder, as the real hook does
st_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'; h5_hook
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit src/b.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
assert_exit "H5: the first of two parallel tasks passes and is committed by the CLI" 0 "$TEMPER" task gate 1 --model m
out="$("$TEMPER" task gate 2 --model m 2>&1)"; rc=$?
assert_eq "H5: the second parallel task, still running, then PASSes" "0|1" "$rc|$(printf '%s' "$out" | grep -c '^PASS: Task 2')"
assert_eq "H5: the second commit holds only its own file" "src/b.sh" "$(git -C "$ST_WT" show --name-only --format= "$(st_field 2 commit)")"
# a model-written file in the worktree's .temper/ is ignored too, but a real undeclared file still fails
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit .temper/gates.json; st_edit stray.txt; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"
assert_eq "H5: only the real undeclared file is named, not .temper/" "1|0" \
  "$(printf '%s' "$out" | grep -c '^FAIL: undeclared change: stray.txt$')|$(printf '%s' "$out" | grep -c '\.temper')"

# M2: a FAIL discards the attempt's worktree with every change in it; the group worktree is untouched
st_setup; echo pre > "$ST_WT/pre.txt"; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit stray.txt; echo edited >> "$T1W/README"
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model m >/dev/null 2>&1
assert_eq "M2: the failed attempt's worktree is gone, the group worktree keeps its own dirty file and README" "no|pre|base" \
  "$([[ -d $T1W ]] && echo yes || echo no)|$(cat "$ST_WT/pre.txt")|$(cat "$ST_WT/README")"
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
assert_eq "M2: the next attempt's worktree has none of the earlier attempt's files" "no|no|base" \
  "$([[ -e $T1W/stray.txt ]] && echo yes || echo no)|$([[ -e $T1W/src/a.sh ]] && echo yes || echo no)|$(cat "$T1W/README")"
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "M2: the retry then passes without the earlier stray file" "0|src/a.sh" "$rc|$(git -C "$ST_WT" show --name-only --format= "$(st_field 1 commit)")"
setup

# H3: the approved plan is hashed at the first group start; a later change refuses the run's commands
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
assert_exit "H3: an unchanged plan lets the running task test" 0 env ST_EXIT=0 "$TEMPER" task test 1 --phase green
gp_tamper 'echo boom;' 'echo hacked;'
out="$(ST_EXIT=0 "$TEMPER" task test 1 --phase green 2>&1)"; rc=$?
assert_eq "H3: a swapped **Test:** refuses task test, naming the plan change" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'plan.*changed')"
assert_exit "H3: a swapped **Test:** refuses task gate" 1 "$TEMPER" task gate 1 --model m
assert_exit "H3: a swapped **Test:** refuses task start" 1 "$TEMPER" task start 3
assert_exit "H3: a swapped **Test:** refuses group gate" 1 "$TEMPER" group gate G1
assert_exit "H3: a swapped **Test:** refuses integrate" 1 "$TEMPER" integrate
assert_eq "H3: the refused task gate recorded no attempt" "running" "$(st_field 1 status)"
gp_tamper 'echo hacked;' 'echo boom;'
assert_exit "H3: restoring the approved text lets the run continue" 0 env ST_EXIT=0 "$TEMPER" task test 1 --phase green
st_setup; gp_tamper '**File:** `src/b.sh`' '**File:** `src/b.sh`, `src/zzz.sh`'
assert_exit "H3: a widened **File:** refuses task start" 1 "$TEMPER" task start 3
st_setup; st_pass_ready
assert_exit "H3: the CLI's own box tick is not a plan change (task gate passes)" 0 "$TEMPER" task gate 1 --model m
assert_exit "H3: after the tick the next task still starts" 0 "$TEMPER" task start 2

# H4: glob characters in **File:** are refused by the grouped plan gate; every check compares exact paths
gp_setup; gp_mut '**File:** `src/c.sh`' '**File:** `src/*.sh`'
assert_exit "H4: a glob in **File:** fails the grouped plan gate" 1 "$TEMPER" gate plan
assert_eq "H4: the failing row names Task 3 and the path" "1" "$(gp_has 'Task 3.*src/\*\.sh')"
gp_setup; gp_mut '**File:** `src/c.sh`' '**File:** `src/c?.sh`'
assert_exit "H4: a ? in **File:** fails the grouped plan gate" 1 "$TEMPER" gate plan
ST_PRE="gp_mut '\`src/a.sh\`, \`unit/a_test.sh\`' '\`src/*.sh\`, \`unit/a_test.sh\`'" st_setup
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "H4: the task verdict compares exact paths (src/a.sh is not src/*.sh)" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'undeclared change: src/a.sh')"
ST_PRE=""
gc_setup grouped; gp_mut '**File:** `src/b.sh`' '**File:** `src/*.sh`'
assert_eq "H4: the autonomy commit gate compares exact paths too" "1" "$(gc_row | grep -c 'changed outside declared files: .*src/b.sh')"
setup

# --- Grouped Build (9.7.0), review loop 1: locking, atomic run-file writes and recorded shas [M1, L1, L2, L3, A1] ---
slow_hook() { case_hook "sleep $1"; }   # sleeps $1 seconds, so a commit is observably in flight
lock_owner() { cat .temper/.lock/owner 2>/dev/null || echo none; }

# A1: a commit the task agent makes itself, with the CLI's subject format, is still not the CLI's
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit stray.txt
git -C "$T1W" add src/a.sh stray.txt; git -C "$T1W" commit -q -m "feat(demo): Task 1 Alpha [G1]" 2>/dev/null
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model m 2>&1)"; rc=$?
assert_eq "A1: a hand-made commit with the CLI's subject format fails the task gate" "1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'not made by the CLI')|$(printf '%s' "$out" | grep -c 'undeclared change: stray.txt')"
assert_eq "A1: the task is not ticked" "3" "$(st_unticked)"
# the CLI's own commit is recorded as a sha, so the next task in the same worktree still passes
st_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit src/b.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model m >/dev/null 2>&1
assert_eq "A1: the CLI records the sha of its task commit (the group branch fast-forwards to it)" "$(git -C "$ST_WT" rev-parse HEAD)" "$(st_field 1 commit)"
assert_exit "A1: a sibling that started earlier passes past the CLI's recorded commit" 0 "$TEMPER" task gate 2 --model m

# M1: the task commit and the tick run under the lock; parallel gates both land
st_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'; slow_hook 1
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit src/b.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model m >"$WORKDIR/g1.out" 2>&1 & GP1=$!
sleep 0.5
assert_eq "M1: the lock is held while the task commit runs" "yes" "$([[ -d .temper/.lock ]] && echo yes || echo no)"
"$TEMPER" task gate 2 --model m >"$WORKDIR/g2.out" 2>&1 & GP2=$!
wait $GP1; R1=$?; wait $GP2; R2=$?
assert_eq "M1: two parallel gates both PASS (no index.lock race)" "0|0" "$R1|$R2"
assert_eq "M1: both ticks land and both shas are recorded" "1|2" \
  "$(st_unticked)|$(python3 -c "import json; t=json.load(open('.temper/groups.json'))['tasks']; print(len([k for k in ('1','2') if t[k].get('commit')]))")"
assert_eq "M1: the lock is released and no temp file is left" "no|0" \
  "$([[ -e .temper/.lock ]] && echo yes || echo no)|$(find .temper .temper/specs -maxdepth 2 -name '*.tmp*' | wc -l | tr -d ' ')"

# L1: an interrupted holder frees its lock (trap); a release never removes a lock someone else now owns
st_setup; slow_hook 2
st_pass_ready
"$TEMPER" task gate 1 --model m >/dev/null 2>&1 & GP1=$!
sleep 0.7
kill -TERM "$GP1" 2>/dev/null; wait "$GP1" 2>/dev/null
assert_eq "L1: a terminated holder leaves no lock behind and does not tick the task" "no|3" \
  "$([[ -e .temper/.lock ]] && echo yes || echo no)|$(st_unticked)"
st_setup; slow_hook 1.5
st_pass_ready
"$TEMPER" task gate 1 --model m >/dev/null 2>&1 & GP1=$!
sleep 0.6
rm -rf .temper/.lock; mkdir .temper/.lock; echo other-holder > .temper/.lock/owner
wait "$GP1"
assert_eq "L1: a lock taken over by another holder is not released by the first one" "other-holder" "$(lock_owner)"
rm -rf .temper/.lock
# stale break: many writers racing for one stale lock lose no row and leave the lock free
setup; mkdir -p .temper/evidence .temper/.lock
python3 -c "import os,time; t=time.time()-120; os.utime('.temper/.lock',(t,t))"
for i in $(seq 1 16); do "$TEMPER" evidence add --stage build --claim "stale race $i" --phase red >/dev/null 2>&1 & done
wait
assert_eq "L1: 16 writers racing a stale lock land 16 rows and release the lock" "16|no" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))" 2>/dev/null || echo invalid)|$([[ -e .temper/.lock ]] && echo yes || echo no)"

# L2: evidence resolve/accept and the gate verdict write under the lock, atomically
setup; mkdir -p .temper/evidence
for i in 1 2 3 4 5 6 7 8; do "$TEMPER" evidence add --stage review --claim "finding $i" --severity high >/dev/null 2>&1; done
mkdir .temper/.lock
out="$(TEMPER_LOCK_WAIT_S=1 TEMPER_LOCK_MAX_S=2 "$TEMPER" evidence resolve --stage review --id 1 --fixed-by abc 2>&1)"
assert_eq "L2: evidence resolve waits on the lock, then fails without writing (9.8.5, Q9)" "1" "$(printf '%s' "$out" | grep -c 'FAIL.*lock.*nothing was written')"
out="$(TEMPER_LOCK_WAIT_S=1 TEMPER_LOCK_MAX_S=2 "$TEMPER" evidence accept --stage review --id 2 --reason ok 2>&1)"
assert_eq "L2: evidence accept waits on the lock, then fails without writing (9.8.5, Q9)" "1" "$(printf '%s' "$out" | grep -c 'FAIL.*lock.*nothing was written')"
out="$(TEMPER_LOCK_WAIT_S=1 TEMPER_LOCK_MAX_S=2 "$TEMPER" gate review 2>&1)"
assert_eq "L2: the gate verdict write waits on the lock, then fails without writing (9.8.5, Q9)" "1" "$(printf '%s' "$out" | grep -c 'FAIL.*lock.*nothing was written')"
rmdir .temper/.lock
L2_LOCK_BEFORE="$([[ -e .temper/.lock ]] && echo held || echo free)"
for i in 3 4 5 6 7 8; do "$TEMPER" evidence resolve --stage review --id "$i" --fixed-by "fix $i" > ".temper/l2.$i.out" 2>&1 & done
wait
l2_n="$(python3 -c "import json; print(len([e for e in json.load(open('.temper/evidence/review.json')) if e.get('resolved') and e['claim'] != 'finding 1']))")"
# a miss prints what each writer said and whether the lock was free before they started (an intermittent loss is read, not guessed)
[[ "$l2_n" == "6" ]] || l2_n="$l2_n (lock before: $L2_LOCK_BEFORE; $(cat .temper/l2.*.out | tr '\n' ' ' | cut -c1-600))"
rm -f .temper/l2.*.out
assert_eq "L2: six parallel resolves lose none" "6" "$l2_n"
l2_left="$([[ -e .temper/.lock ]] && echo yes || echo no)"
[[ "$l2_left" == "no" ]] || l2_left="yes (owner: $(cat .temper/.lock/owner 2>/dev/null || echo none); $(ls -la .temper/.lock 2>&1 | tr '\n' ' ' | cut -c1-300))"
assert_eq "L2: the lock is released and no temp file is left" "no|0" "$l2_left|$(find .temper -name '*.tmp*' | wc -l | tr -d ' ')"

# L3: the ready check and the start write share one lock, so a start never overwrites a state that changed
# while it waited for the lock (here: another process finished Task 2 in the meantime)
st_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'
( mkdir .temper/.lock
  sleep 1.2
  python3 -c "
import json
d = json.load(open('.temper/groups.json')); d['tasks']['2'] = {'status': 'passed', 'group': 'G1', 'attempt': 1, 'attempts': []}
json.dump(d, open('.temper/groups.json', 'w'))"
  rmdir .temper/.lock ) & LP=$!
sleep 0.2
"$TEMPER" task start 2 >"$WORKDIR/s2.out" 2>&1; rc=$?
wait $LP
assert_eq "L3: a start whose ready check went stale while it waited is refused and the state is kept" "1|passed" "$rc|$(st_field 2 status)"
setup

# --- Grouped Build (9.7.0): review loop 1, M3 / M4 / L4 ---
# M3: reopening Task N restores N's files to its start; a later task (Depends: N) that shares a file stays
# passed with its edit reverted unless it is reopened too. The CLI refuses and names it; reopening both
# restores dependents first, so the shared file ends at its content before either task.
gg_setup; gp_mut '**File:** `src/b.sh`' '**File:** `src/b.sh`, `src/a.sh`'
gg_pass 1 src/a.sh
"$TEMPER" task start 2 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
st_edit src/b.sh; echo "work two" >> ".claude/worktrees/temper-demo-T2/src/a.sh"; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
"$TEMPER" task gate 2 --model m >/dev/null 2>&1
HEAD0="$(git -C "$ST_WT" rev-parse HEAD)"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "M3 reopen: Task 1 alone is refused when passed Task 2 (Depends: Task 1) edits src/a.sh, naming Task 2" "1|1" \
  "$rc|$(printf '%s' "$out" | grep -c '^FAIL:.*Task 2.*src/a.sh.*--task 2')"
assert_eq "M3 reopen: the refusal changed nothing (head, Task 1 and Task 2 stay passed)" "$HEAD0|passed|passed" \
  "$(git -C "$ST_WT" rev-parse HEAD)|$(st_field 1 status)|$(st_field 2 status)"
out="$("$TEMPER" group reopen G1 --task 1 --task 2 2>&1)"; rc=$?
assert_eq "M3 reopen: naming both tasks succeeds" "0" "$rc"
assert_eq "M3 reopen: both tasks' files are back to before either ran (dependent restored first)" "no|no" \
  "$([[ -e "$ST_WT/src/a.sh" ]] && echo yes || echo no)|$([[ -e "$ST_WT/src/b.sh" ]] && echo yes || echo no)"
assert_eq "M3 reopen: the worktree is clean and both tasks are pending" "|pending|pending" \
  "$(git -C "$ST_WT" status --porcelain)|$(st_field 1 status)|$(st_field 2 status)"
# a dependent that shares no file does not block the reopen
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
assert_exit "M3 reopen: a dependent with disjoint files does not block reopening Task 1" 0 "$TEMPER" group reopen G1 --task 1

# M4: concurrent `task test` runs each land their own row (the evidence write is serialized)
gg_setup
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 3 >/dev/null 2>&1
for i in 1 2 3 4; do
  ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1 &
  ST_EXIT=1 "$TEMPER" task test 3 --phase red >/dev/null 2>&1 &
done
wait
assert_eq "M4 parallel task test: all 8 rows land, 4 per task, and the ledger is valid JSON" "8|4|4" \
  "$(python3 -c "
import json
r = json.load(open('.temper/evidence/build.json'))
print('%d|%d|%d' % (len(r), len([x for x in r if x.get('task') == 1]), len([x for x in r if x.get('task') == 3])))" 2>/dev/null || echo invalid)"
assert_eq "M4 parallel task test: the lock is released and no temp file is left" "no|0" \
  "$([[ -e .temper/.lock ]] && echo yes || echo no)|$(find .temper -name '*.tmp*' | wc -l | tr -d ' ')"

# L4: after an integration FAIL the worktrees are gone but the group branches stay; group start attaches a
# fresh worktree to the existing branch so a Change (reopen) can run, and a later integrate PASSes
gi_all
GI_EXIT=1 "$TEMPER" integrate >/dev/null 2>&1
assert_eq "L4: after the suite FAIL the worktree folder is gone and the branch is kept" "no|yes" \
  "$([[ -d .claude/worktrees/temper-demo-G1 ]] && echo yes || echo no)|$(git show-ref --verify --quiet refs/heads/temper/demo/G1 && echo yes || echo no)"
out="$("$TEMPER" group start G1 2>&1)"; rc=$?
assert_eq "L4: group start G1 recreates the worktree on the existing branch (exit 0)" "0|yes|temper/demo/G1" \
  "$rc|$([[ -d .claude/worktrees/temper-demo-G1 ]] && echo yes || echo no)|$(git -C .claude/worktrees/temper-demo-G1 rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_exit "L4: a Change can reopen a task in the recreated worktree" 0 "$TEMPER" group reopen G1 --task 2
gi_pass 2 G1 src/b.sh 'b_main() { :; } # second try'
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "L4: integrate after the Change merges the new commit and PASSes" "0|PASS" "$("$TEMPER" integrate >/dev/null 2>&1; echo $?)|$(gi_int verdict)"

# --- Grouped Build (9.7.0), review loop 2: reopen vs a running sibling, stale branches [R2, R3, R5] ---
# R2: a group reopen's revert is the reopened task's change, not a running sibling's undeclared one
gg_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'
gg_pass 1 src/a.sh
"$TEMPER" task start 2 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
assert_exit "R2: reopening Task 1 while Task 2 runs succeeds" 0 "$TEMPER" group reopen G1 --task 1
st_edit src/b.sh; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 2 --model m 2>&1)"; rc=$?
assert_eq "R2: the running sibling PASSes past the reopen revert" "0|1" "$rc|$(printf '%s' "$out" | grep -c '^PASS: Task 2')"
assert_eq "R2: the reverted file stays reverted (not re-applied by a restore)" "no" "$([[ -e $ST_WT/src/a.sh ]] && echo yes || echo no)"
assert_eq "R2: the sibling's commit holds only its own file" "src/b.sh" "$(git -C "$ST_WT" show --name-only --format= "$(st_field 2 commit)")"

# R3: an existing group branch is reused only when this run recorded it; a stale one (an earlier attempt of the same run
# name) is moved aside with its commits, and the group starts fresh (9.8.0; it was refused until then)
gi_all
GI_EXIT=1 "$TEMPER" integrate >/dev/null 2>&1
rm -f .temper/groups.json
git checkout -q feature/demo 2>/dev/null
old="$(git rev-parse temper/demo/G1)"
out="$("$TEMPER" group start G1 2>&1)"; rc=$?
assert_eq "R3: a stale branch from an earlier run is moved aside, named, and the group starts" "0|1" \
  "$rc|$(printf '%s' "$out" | grep -c '^NOTE: branch temper/demo/G1, left by an earlier attempt, moved aside to refs/temper/kept/demo/earlier-')"
assert_eq "R3: the earlier attempt's commits are kept, out of git branch" "$old|0" \
  "$(git for-each-ref --format='%(objectname)' 'refs/temper/kept/demo/earlier-*/G1')|$(git branch --list 'temper/demo/earlier-*' | wc -l | tr -d ' ')"
assert_eq "R3: the fresh branch is not the abandoned run's (no group commits on it)" "0" \
  "$(git log --format=%s feature/demo..temper/demo/G1 | wc -l | tr -d ' ')"

# L5 (9.8.0, from a run on a person's machine): an earlier attempt of the same run name left worktree records whose
# folders are gone, and its group and task branches; the run started over goes past them, and git names none any more
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1
rm -rf .claude/worktrees; rm -f .temper/groups.json
assert_eq "L5: before: git names three worktrees whose folders are gone" "3" "$(git worktree list --porcelain | grep -c '^prunable')"
assert_exit "L5: group start G1 goes past the leftovers" 0 "$TEMPER" group start G1
assert_exit "L5: group start G2 goes past the leftovers" 0 "$TEMPER" group start G2
out="$("$TEMPER" task start 1 2>&1)"; rc=$?
assert_eq "L5: task start 1 goes past them, naming the branch it moved aside" "0|1" \
  "$rc|$(printf '%s' "$out" | grep -c '^NOTE: branch temper/demo/T1, left by an earlier attempt')"
assert_eq "L5: the task worktree is made on its branch, and no record without a folder is left" "temper/demo/T1|0" \
  "$(git -C "$T1W" rev-parse --abbrev-ref HEAD)|$(git worktree list --porcelain | grep -c '^prunable')"
# this run's own group worktree whose folder went comes back on its branch, at its tip, when the next task starts
st_setup; gg_pass 1 src/a.sh
tip="$(git rev-parse temper/demo/G1)"
rm -rf .claude/worktrees/temper-demo-G1
assert_exit "L5: Task 2 starts although its group's folder went" 0 "$TEMPER" task start 2
assert_eq "L5: the group worktree is back on its branch, at its tip" "temper/demo/G1|$tip" \
  "$(git -C "$ST_WT" rev-parse --abbrev-ref HEAD)|$(git -C "$ST_WT" rev-parse HEAD)"
# a leftover worktree with uncommitted work is never removed: refused (exit 3), the work where it was
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; echo wip > "$T1W/wip.txt"
rm -f .temper/groups.json; "$TEMPER" group start G1 >/dev/null 2>&1; "$TEMPER" group start G2 >/dev/null 2>&1
out="$("$TEMPER" task start 1 2>&1)"; rc=$?
assert_eq "L5: a leftover worktree with uncommitted work refuses task start (exit 3), naming it" "3|1" \
  "$rc|$(printf '%s' "$out" | grep -c "^FAIL: $T1W holds uncommitted work")"
assert_eq "L5: the uncommitted work is where it was" "wip" "$(cat "$T1W/wip.txt" 2>/dev/null)"

# R5: group reopen refuses a plan that changed after approval, like every other grouped command
st_setup; gg_pass 1 src/a.sh
gp_tamper 'echo boom;' 'echo hacked;'
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "R5: a changed plan refuses group reopen, naming the plan change" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'plan.*changed')"
assert_eq "R5: the refused reopen changed nothing" "passed" "$(st_field 1 status)"
setup

# --- Grouped Build (9.7.0), final review: shared worktree, reopen excuse, lock [F4-F7] ---
f_add_t4() { # a fourth, independent G1 task (src/d.sh) with its own controllable test
  gp_mut '### Task 2: Beta' '### Task 4: Delta
**File:** `src/d.sh`
**Depends:** none
**Test:** `bash -c '"'"'exit ${ST_EXIT:-0}'"'"'`
**Cases:**
- the normal input gives the expected result
- an empty input is refused
- [ ] done

### Task 2: Beta'
}
f_setup() { ST_PRE=f_add_t4 st_setup; ST_PRE=""; gp_mut '**Depends:** Task 1' '**Depends:** none'; }
f_tree() { git -C "$ST_WT" ls-tree -r --name-only HEAD | paste -sd, -; }
