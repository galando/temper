# --- Grouped Build (9.7.0): config keys and task model resolution ---
# Scenario: Grouped mode off keeps the per-task Build unchanged [AC-01]
setup
assert_eq "grouped off (no build.mode): model --all prints exactly the 8 stage lines" "8" "$("$TEMPER" model --all | wc -l | tr -d ' ')"
printf 'build:\n  mode: per-task\n' >> .claude/temper.config
assert_eq "grouped off (build.mode: per-task): model --all prints exactly the 8 stage lines" "8" "$("$TEMPER" model --all | wc -l | tr -d ' ')"
assert_eq "grouped off: model --all has no task= line" "0" "$("$TEMPER" model --all | grep -c '^task')"

# Scenario: Task and escalation models resolve from config with defaults [AC-06, AC-01]
setup
printf 'build:\n  mode: grouped\n' >> .claude/temper.config
assert_eq "model task defaults to claude-haiku-5-5" "claude-haiku-5-5" "$("$TEMPER" model task)"
assert_eq "model task-escalation defaults to sonnet" "sonnet" "$("$TEMPER" model task-escalation)"
assert_eq "grouped on: model --all appends task= and task-escalation=" "10|task=claude-haiku-5-5|task-escalation=sonnet" \
  "$("$TEMPER" model --all | wc -l | tr -d ' ')|$("$TEMPER" model --all | grep '^task=')|$("$TEMPER" model --all | grep '^task-escalation=')"
setup
printf 'build:\n  mode: grouped\n  grouped:\n    task-model: haiku\n    escalation-model: opus\n' >> .claude/temper.config
assert_eq "configured task and escalation models win" "haiku|opus" "$("$TEMPER" model task)|$("$TEMPER" model task-escalation)"
setup

# --- Grouped Build (9.7.0): serialized writes to shared run files ---
# Scenario: Parallel evidence writes lose no rows [AC-04]
setup
mkdir -p .temper/evidence
for i in 1 2 3 4 5 6 7 8; do
  "$TEMPER" evidence add --stage build --claim "Task $(( (i + 1) / 2 )) run $i" --phase red >/dev/null 2>&1 &
done
wait
assert_eq "parallel evidence add: all 8 rows land and the ledger is valid JSON" "8" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))" 2>/dev/null || echo invalid)"
assert_eq "parallel evidence add: the lock folder is released" "no" "$([[ -e .temper/.lock ]] && echo yes || echo no)"
assert_eq "parallel evidence add: no temp file is left behind" "0" "$(find .temper -name '*.tmp*' | wc -l | tr -d ' ')"

# a lock left by a crashed holder is broken once it is older than 30 s
setup
mkdir -p .temper/evidence .temper/.lock
python3 -c "import os,time; t=time.time()-120; os.utime('.temper/.lock',(t,t))"
out="$("$TEMPER" evidence add --stage build --claim "after stale lock" 2>&1)"; rc=$?
assert_eq "stale lock: the write succeeds without a warning" "0|0" "$rc|$(printf '%s' "$out" | grep -c WARN)"
assert_eq "stale lock: the row is recorded and the lock is gone" "1|no" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$([[ -e .temper/.lock ]] && echo yes || echo no)"

# a fresh lock held by someone else: fail open after the wait, warn, never release it
setup
mkdir -p .temper/evidence .temper/.lock
out="$(TEMPER_LOCK_WAIT_S=1 "$TEMPER" evidence add --stage build --claim "while locked" 2>&1)"; rc=$?
assert_eq "held lock: writes anyway with a WARN after the wait" "0|1" "$rc|$(printf '%s' "$out" | grep -c 'WARN.*lock')"
assert_eq "held lock: the row is recorded and the foreign lock is left alone" "1|yes" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$([[ -d .temper/.lock ]] && echo yes || echo no)"

# the lock folder is on the symlink refusal list
setup
mkdir -p .temper/evidence "$WORKDIR/lock-target"
ln -s "$WORKDIR/lock-target" .temper/.lock
assert_exit "a symlinked .temper/.lock is refused" 3 "$TEMPER" evidence add --stage build --claim "via link"
rm -f .temper/.lock

# --- Grouped Build (9.7.0): grouped tasks.md parser and the grouped plan-gate checks ---
# Scenarios: A three-level grouped plan passes the plan gate; The plan gate rejects a task with no
# declared files and a group with no context; Overlapping files between tasks that can run together
# are rejected; A group larger than max-blast-radius is rejected at plan time [AC-02, AC-03, AC-05, AC-11]
gp_base() { # write the valid two-group fixture to the demo spec's tasks.md
  cat > .temper/specs/demo/tasks.md <<'GP'
# Tasks: demo

**Integration:** `bash run-all.sh`

## Group G1: Core
**Depends:** none
**Validate:** `bash tests/g1.sh`
**Interfaces:** `src/a.sh` — `a_main`
**Context:**
Shared notes for G1. Use bash.

### Task 1: Alpha
**File:** `src/a.sh`, `tests/a_test.sh`
**Depends:** none
**Test:** `bash tests/a_test.sh`
- [ ] done

### Task 2: Beta
**File:** `src/b.sh`
**Depends:** Task 1
**Test:** `bash tests/b_test.sh`
- [ ] done

## Group G2: Edge
**Depends:** none
**Validate:** `bash tests/g2.sh`
**Context:**
Notes for G2.

### Task 3: Gamma
**File:** `src/c.sh`
**Depends:** none
**Test:** `bash tests/c_test.sh`
- [ ] done
GP
}
gp_mut() { # gp_mut <old> <new>: replace the first occurrence in the demo tasks.md
  python3 - "$1" "$2" <<'PY'
import sys
p = '.temper/specs/demo/tasks.md'
s = open(p).read()
assert sys.argv[1] in s, 'fixture text not found: ' + sys.argv[1]
open(p, 'w').write(s.replace(sys.argv[1], sys.argv[2], 1))
PY
}
gp_setup() { setup; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base; }
gp_gate() { "$TEMPER" gate plan 2>&1; }
gp_has() { gp_gate | grep -c -- "$1" | tr -d ' '; }

gp_setup
assert_exit "grouped plan: a valid two-group plan passes the plan gate" 0 "$TEMPER" gate plan
assert_eq "grouped plan: the grouped plan row names both groups" "1" "$(gp_has '2 groups: G1 (2 tasks), G2 (1 tasks)')"

gp_setup; gp_mut '**File:** `src/b.sh`
' ''
assert_exit "grouped plan: a task with no **File:** fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the failing row names Task 2" "1" "$(gp_has 'Task 2: no declared files')"

gp_setup; gp_mut '**Context:**
Notes for G2.
' ''
assert_exit "grouped plan: a group with no **Context:** fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the failing row names G2" "1" "$(gp_has 'G2: no group context')"

gp_setup; gp_mut '**Test:** `bash tests/b_test.sh`
' ''
assert_exit "grouped plan: a task with no **Test:** fails (per-task scoped test command)" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the failing row names Task 2's missing test command" "1" "$(gp_has 'Task 2: no test command')"

gp_setup; gp_mut '**Integration:** `bash run-all.sh`
' ''
assert_exit "grouped plan: a missing **Integration:** line fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the failing row says so" "1" "$(gp_has 'no \*\*Integration:\*\* line')"

# overlap: two tasks that can run together must declare disjoint files
gp_setup; gp_mut '**File:** `src/c.sh`' '**File:** `src/a.sh`'
assert_exit "grouped plan: overlapping files in tasks that can run together fail" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the overlap row names the file and both tasks" "1" "$(gp_has 'file ownership overlap: src/a.sh in Task 1 and Task 3')"
gp_setup; gp_mut '**File:** `src/c.sh`' '**File:** `./src/a.sh`'
assert_eq "grouped plan: a leading ./ does not hide an overlap" "1" "$(gp_has 'file ownership overlap: src/a.sh in Task 1 and Task 3')"
gp_setup; gp_mut '**File:** `src/b.sh`' '**File:** `src/a.sh`'
assert_exit "grouped plan: the same file in tasks ordered by Depends is allowed" 0 "$TEMPER" gate plan
gp_setup; gp_mut '**File:** `src/c.sh`' '**File:** `src/a.sh`'; gp_mut '## Group G2: Edge
**Depends:** none' '## Group G2: Edge
**Depends:** G1'
assert_exit "grouped plan: the same file in a group that depends on the other group is allowed" 0 "$TEMPER" gate plan

# group size against autonomy.max-blast-radius (G1 declares 3 files)
gp_setup; sed 's/max-blast-radius: 15/max-blast-radius: 3/' .claude/temper.config > .claude/temper.config.new && mv .claude/temper.config.new .claude/temper.config
assert_exit "grouped plan: a group at max-blast-radius passes" 0 "$TEMPER" gate plan
gp_setup; sed 's/max-blast-radius: 15/max-blast-radius: 2/' .claude/temper.config > .claude/temper.config.new && mv .claude/temper.config.new .claude/temper.config
assert_exit "grouped plan: a group over max-blast-radius fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the row says to split the group" "1" "$(gp_has 'G1 declares 3 files > autonomy.max-blast-radius=2: split the group')"

# budgets
gp_setup; gp_mut 'Shared notes for G1. Use bash.' "$(python3 -c "print('x' * 4200)")"
assert_exit "grouped plan: a context over 4096 bytes fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the context budget row names G1" "1" "$(gp_has 'G1: context 42[0-9][0-9] bytes > 4096')"
gp_setup; gp_mut '### Task 2: Beta' "### Task 2: Beta
$(python3 -c "print('y' * 1600)")"
assert_exit "grouped plan: a task block over 1536 bytes fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the task block budget row names Task 2" "1" "$(gp_has 'Task 2: block 1[67][0-9][0-9] bytes > 1536')"

# dependency graph
gp_setup; gp_mut '**Depends:** none
**Test:** `bash tests/a_test.sh`' '**Depends:** Task 2
**Test:** `bash tests/a_test.sh`'
assert_exit "grouped plan: a Depends cycle fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the cycle row names the loop" "1" "$(gp_has 'Depends cycle: Task 1 -> Task 2 -> Task 1')"
gp_setup; gp_mut '**Depends:** Task 1' '**Depends:** Task 9'
assert_exit "grouped plan: a Depends on an unknown task fails" 1 "$TEMPER" gate plan
assert_eq "grouped plan: the row names the unknown task" "1" "$(gp_has 'Task 2 depends on unknown Task 9')"
gp_setup; gp_mut '## Group G2: Edge
**Depends:** none' '## Group G2: Edge
**Depends:** G7'
assert_eq "grouped plan: a group Depends on an unknown group fails" "1|1" "$("$TEMPER" gate plan >/dev/null 2>&1; echo $? | sed 's/^0$/0/')|$(gp_has 'G2 depends on unknown G7')"

# grouped off: the same grouped tasks.md leaves the plan gate output unchanged
setup; gp_base
assert_exit "grouped off: a grouped tasks.md changes nothing in the plan gate (per-task rules only)" 0 "$TEMPER" gate plan
assert_eq "grouped off: no grouped rows appear" "0" "$(gp_has 'grouped plan\|declared files\|group context\|file ownership')"
gp_mut '**File:** `src/b.sh`
' ''
assert_exit "grouped off: a missing **File:** is not checked" 0 "$TEMPER" gate plan
setup

# --- Grouped Build (9.7.0): grouped run state and the ready set (temper schedule) ---
# Scenarios: The ready set holds only tasks with met dependencies and disjoint files; Grouped mode
# off keeps the per-task Build unchanged [AC-03, AC-04, AC-01]
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

# before any group started: nothing is ready, work remains
sg_setup
assert_exit "schedule: no groups.json yet exits 0" 0 "$TEMPER" schedule
assert_eq "schedule: nothing is ready before a group starts" "" "$(sg_ready)"
assert_eq "schedule: a waiting line says work remains" "1" "$(sg_last | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(1 if d.get('done') is False and d.get('waiting') else 0)")"
assert_eq "schedule: schedule writes nothing" "no" "$([[ -e .temper/groups.json ]] && echo yes || echo no)"

# both groups started, no task started: the tasks with no Depends are ready
sg_setup; sg_state '{}'
assert_eq "schedule: independent tasks of started groups are ready, ordered by task" "1,3" "$(sg_ready)"
assert_eq "schedule: a ready line carries task, group, worktree, project, model and attempt" \
  '{"task": 1, "group": "G1", "title": "Alpha", "worktree": ".claude/worktrees/temper-demo-G1", "project": "'"$PWD"'", "model": "claude-haiku-5-5", "attempt": 1}' \
  "$("$TEMPER" schedule | head -1)"

# a task whose Depends is not passed waits; a running task is not offered again
sg_setup; sg_state '{"1":{"group":"G1","status":"running","attempt":1}}'
assert_eq "schedule: a running task is not offered and its dependent waits" "3" "$(sg_ready)"

# the files of a running task are excluded
sg_setup; gp_mut '**File:** `src/c.sh`' '**File:** `src/a.sh`'; sg_state '{"1":{"group":"G1","status":"running","attempt":1}}'
assert_eq "schedule: a task sharing a file with a running task is not offered" "" "$(sg_ready)"
assert_eq "schedule: the waiting line names the overlapping task" "1" "$(sg_last | grep -c 'Task 3.*Task 1')"
# two ready tasks that share a file: only the first is offered
sg_setup; gp_mut '**File:** `src/c.sh`' '**File:** `./src/a.sh`'; sg_state '{}'
assert_eq "schedule: of two ready tasks sharing a file only the first is offered" "1" "$(sg_ready)"

# after Task 1 passes its dependent appears
sg_setup; sg_state '{"1":{"group":"G1","status":"passed","attempt":1}}'
assert_eq "schedule: after Task 1 passed, Task 2 and Task 3 are ready" "2,3" "$(sg_ready)"

# a group whose Depends group has not passed its group gate waits
sg_setup; gp_mut '## Group G2: Edge
**Depends:** none' '## Group G2: Edge
**Depends:** G1'; sg_state '{"1":{"group":"G1","status":"passed","attempt":1}}'
assert_eq "schedule: a group behind an unpassed group gate offers none of its tasks" "2" "$(sg_ready)"
sg_state '{"1":{"group":"G1","status":"passed","attempt":1}}' '"G1":{"status":"running","worktree":".claude/worktrees/temper-demo-G1","gate":{"verdict":"PASS"}},"G2":{"status":"running","worktree":".claude/worktrees/temper-demo-G2"}'
assert_eq "schedule: once G1's group gate passed, G2's task is offered" "2,3" "$(sg_ready)"

# a group that has not started (no worktree) offers nothing; a parked group offers nothing
sg_setup; sg_state '{}' '"G1":{"status":"running","worktree":".claude/worktrees/temper-demo-G1"}'
assert_eq "schedule: a group with no worktree offers no task" "1" "$(sg_ready)"
sg_setup; sg_state '{}' '"G1":{"status":"parked","worktree":".claude/worktrees/temper-demo-G1","parked_reason":"Task 1 failed 3 attempts"},"G2":{"status":"running","worktree":".claude/worktrees/temper-demo-G2"}'
assert_eq "schedule: a parked group is skipped while another group is still offered" "3" "$(sg_ready)"
assert_eq "schedule: the waiting line is absent while tasks are ready" "0" "$("$TEMPER" schedule | grep -c waiting)"
sg_state '{}' '"G1":{"status":"parked","worktree":".claude/worktrees/temper-demo-G1"},"G2":{"status":"parked","worktree":".claude/worktrees/temper-demo-G2"}'
assert_eq "schedule: with every group parked the last line lists them" "1" "$(sg_last | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(1 if d.get('parked')==['G1','G2'] and d.get('done') is False else 0)")"

# attempt and model: a failed task is offered again with its next attempt; attempt 3 uses the escalation model
sg_setup; sg_state '{"1":{"group":"G1","status":"failed","attempt":1,"attempts":[{"n":1,"outcome":"FAIL"}]}}'
assert_eq "schedule: attempt 2 is offered on the task model" "claude-haiku-5-5|2" \
  "$("$TEMPER" schedule | head -1 | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print('%s|%s' % (d['model'], d['attempt']))")"
sg_state '{"1":{"group":"G1","status":"failed","attempt":2,"attempts":[{"n":1,"outcome":"FAIL"},{"n":2,"outcome":"FAIL"}]}}'
assert_eq "schedule: attempt 3 is offered on the escalation model" "sonnet|3" \
  "$("$TEMPER" schedule | head -1 | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print('%s|%s' % (d['model'], d['attempt']))")"

# max-parallel caps the launchable set (default 4, configurable)
sg_setup; printf '  grouped:\n    max-parallel: 1\n' >> .claude/temper.config; sg_state '{}'
assert_eq "schedule: max-parallel 1 offers a single task" "1" "$(sg_ready)"
sg_state '{"3":{"group":"G2","status":"running","attempt":1}}'
assert_eq "schedule: a running task counts against max-parallel" "" "$(sg_ready)"
assert_eq "schedule: the waiting line names the cap" "1" "$(sg_last | grep -c 'max-parallel')"
sg_setup; sg_state '{}'
assert_eq "schedule: the default cap of 4 does not hold back 2 tasks" "1,3" "$(sg_ready)"

# every group passed its group gate: done
sg_setup; sg_state '{"1":{"group":"G1","status":"passed"},"2":{"group":"G1","status":"passed"},"3":{"group":"G2","status":"passed"}}' \
  '"G1":{"status":"passed","worktree":"w1","gate":{"verdict":"PASS"}},"G2":{"status":"passed","worktree":"w2","gate":{"verdict":"PASS"}}'
assert_eq "schedule: every group passed ends with the integrate line" '{"done": true, "next": "temper integrate"}' "$(sg_last)"
assert_eq "schedule: done offers no task" "" "$(sg_ready)"

# groups.json is CLI-owned run state: a symlink is refused and state clear removes it
sg_setup; sg_state '{}'
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "state clear removes groups.json" "no" "$([[ -e .temper/groups.json ]] && echo yes || echo no)"
sg_setup; mkdir -p "$WORKDIR/gj-target"; echo '{}' > "$WORKDIR/gj-target/g.json"; ln -s "$WORKDIR/gj-target/g.json" .temper/groups.json
assert_exit "a symlinked .temper/groups.json is refused" 3 "$TEMPER" schedule
rm -f .temper/groups.json

# grouped off: exits 1, prints the reason, writes nothing
setup; gp_base; sg_state '{}'
out="$("$TEMPER" schedule 2>&1)"; rc=$?
assert_eq "grouped off: schedule exits 1 and names build.mode" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'grouped mode is off (build.mode)')"
assert_eq "grouped off: schedule prints no JSON line" "0" "$(printf '%s' "$out" | grep -c '^{')"
setup
