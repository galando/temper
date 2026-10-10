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

# --- Grouped Build (9.7.0): group worktrees (temper group start) ---
# Scenario: Each group gets its own worktree off the feature branch [AC-04, AC-09]
# Every case runs in the throwaway folder's own git repository, never in this repository's.
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

sw_setup; BASE="$(sw_head)"
assert_exit "group start G1 exits 0" 0 "$TEMPER" group start G1
assert_exit "group start G2 exits 0" 0 "$TEMPER" group start G2
assert_eq "group start: the worktree folder exists for each group" "yes|yes" \
  "$([[ -d .claude/worktrees/temper-demo-G1 ]] && echo yes || echo no)|$([[ -d .claude/worktrees/temper-demo-G2 ]] && echo yes || echo no)"
assert_eq "group start: git lists both worktrees" "2" "$(git worktree list --porcelain | grep -c 'worktrees/temper-demo-G')"
assert_eq "group start: each worktree is on its group branch" "temper/demo/G1|temper/demo/G2" \
  "$(git -C .claude/worktrees/temper-demo-G1 rev-parse --abbrev-ref HEAD)|$(git -C .claude/worktrees/temper-demo-G2 rev-parse --abbrev-ref HEAD)"
assert_eq "group start: both worktrees start at the feature branch HEAD" "$BASE|$BASE" \
  "$(git -C .claude/worktrees/temper-demo-G1 rev-parse HEAD)|$(git -C .claude/worktrees/temper-demo-G2 rev-parse HEAD)"
assert_eq "group start: info/exclude holds the worktrees folder exactly once" "1" \
  "$(grep -cx '/.claude/worktrees/' "$(git rev-parse --git-common-dir)/info/exclude")"
assert_eq "group start: .gitignore is never written" "no" "$([[ -e .gitignore ]] && echo yes || echo no)"
assert_eq "group start: the main checkout status does not list the worktrees" "0" "$(git status --porcelain | grep -c 'worktrees')"
assert_eq "group start: groups.json records worktree, branch, base and status" \
  ".claude/worktrees/temper-demo-G1|temper/demo/G1|$BASE|running" \
  "$(sw_field G1 worktree)|$(sw_field G1 branch)|$(sw_field G1 base_sha)|$(sw_field G1 status)"
assert_eq "group start: groups.json records the slug and feature branch" "demo|feature/demo" \
  "$(python3 -c "import json; d=json.load(open('.temper/groups.json')); print(d['slug']+'|'+d['feature_branch'])")"
assert_eq "group start: the run is valid JSON with the earlier task state kept" "1" \
  "$(python3 -c "import json; d=json.load(open('.temper/groups.json')); print(1 if d.get('version')==1 and isinstance(d.get('tasks'),dict) else 0)")"
# idempotent
assert_exit "group start: a second start of the same group exits 0" 0 "$TEMPER" group start G1
assert_eq "group start: the second start reuses the worktree (still two)" "2" "$(git worktree list --porcelain | grep -c 'worktrees/temper-demo-G')"
assert_eq "group start: the second start keeps the base" "$BASE" "$(sw_field G1 base_sha)"
assert_eq "group start: the exclude line is not written twice" "1" "$(grep -cx '/.claude/worktrees/' "$(git rev-parse --git-common-dir)/info/exclude")"

# the native pre-commit hook lets a commit in a group worktree through (no run state there)
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo work > .claude/worktrees/temper-demo-G1/work.txt
git -C .claude/worktrees/temper-demo-G1 add work.txt
assert_exit "group start: a commit in a group worktree passes the native pre-commit hook" 0 \
  git -C .claude/worktrees/temper-demo-G1 commit -q -m "feat(demo): work"

# a group that depends on G1 starts from G1's branch merged in, once G1 passed its group gate
sw_setup; gp_mut '## Group G2: Edge
**Depends:** none' '## Group G2: Edge
**Depends:** G1'
"$TEMPER" group start G1 >/dev/null 2>&1
echo g1work > .claude/worktrees/temper-demo-G1/g1.txt
git -C .claude/worktrees/temper-demo-G1 add g1.txt; git -C .claude/worktrees/temper-demo-G1 commit -q -m "g1" 2>/dev/null
out="$("$TEMPER" group start G2 2>&1)"; rc=$?
assert_eq "group start: a group behind an unpassed group gate is refused (exit 1) and names it" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'G1')"
assert_eq "group start: the refused group made no worktree" "no" "$([[ -d .claude/worktrees/temper-demo-G2 ]] && echo yes || echo no)"
python3 - <<'PY'
import json
d = json.load(open('.temper/groups.json'))
d['groups']['G1']['gate'] = {'verdict': 'PASS'}
json.dump(d, open('.temper/groups.json', 'w'))
PY
assert_exit "group start: once G1's gate passed, G2 starts" 0 "$TEMPER" group start G2
assert_eq "group start: the dependent worktree holds the file G1 committed" "g1work" "$(cat .claude/worktrees/temper-demo-G2/g1.txt 2>/dev/null)"
assert_eq "group start: the dependent base is a merge of the feature HEAD and G1" "2" \
  "$(git -C .claude/worktrees/temper-demo-G2 rev-list --parents -n 1 "$(sw_field G2 base_sha)" | awk '{print NF-1}')"
assert_eq "group start: the dependent base_sha is the worktree HEAD" "$(git -C .claude/worktrees/temper-demo-G2 rev-parse HEAD)" "$(sw_field G2 base_sha)"

# refusals
sw_setup
assert_exit "group start: an unknown group exits 1" 1 "$TEMPER" group start G9
assert_exit "group start: no group argument exits 1" 1 "$TEMPER" group start
assert_exit "group start: an unknown group subcommand exits 1" 1 "$TEMPER" group frobnicate
git checkout -q -b other
assert_exit "group start: off the run's feature branch exits 1" 1 "$TEMPER" group start G1
git checkout -q feature/demo
mkdir -p .claude/worktrees/temper-demo-G1; echo squatter > .claude/worktrees/temper-demo-G1/x
assert_exit "group start: a folder at the worktree path that is not this worktree exits 3" 3 "$TEMPER" group start G1
assert_eq "group start: the squatting folder is left alone" "squatter" "$(cat .claude/worktrees/temper-demo-G1/x)"
sw_setup; "$TEMPER" state init demo --branch main >/dev/null 2>&1; git checkout -q -B main
assert_exit "group start: the main branch is refused (exit 3)" 3 "$TEMPER" group start G1
assert_eq "group start: the refused main run made no worktree" "no" "$([[ -d .claude/worktrees/temper-demo-G1 ]] && echo yes || echo no)"
# grouped off
setup; gp_base
assert_exit "grouped off: group start exits 1" 1 "$TEMPER" group start G1
assert_eq "grouped off: group start writes no groups.json" "no" "$([[ -e .temper/groups.json ]] && echo yes || echo no)"
setup

# --- Grouped Build (9.7.0): task lifecycle (task start / show / test / gate) ---
# Scenarios: A task with its own RED then GREEN and only declared files passes its gate; A task gate
# fails without its own RED before GREEN; An undeclared file change fails the task gate; The task
# launch payload stays within its byte budget [AC-05, AC-07, AC-08, AC-09]
# Every case runs in the throwaway folder's own git repository, never in this repository's.
ST_WT=".claude/worktrees/temper-demo-G1"
st_setup() { # sw_setup + the upstream gates ADR 0009 asks for + both groups started
  sw_setup
  printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
  # the declared Test: commands are controllable from outside the worktree: ST_EXIT is the exit, ST_SLEEP
  # hangs, ST_LONG prints a long output
  local t="bash -c 'echo boom; pwd; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"
  gp_mut '`bash tests/a_test.sh`' "\`$t\`"; gp_mut '`bash tests/b_test.sh`' "\`$t\`"; gp_mut '`bash tests/c_test.sh`' "\`$t\`"
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
st_edit() { # st_edit <task-file-relative-path>: write a file into G1's worktree
  mkdir -p "$ST_WT/$(dirname "$1")"; echo "work $1" > "$ST_WT/$1"
}
st_unticked() { # the number of unticked boxes in the demo tasks.md
  grep -c '^- \[ \]' .temper/specs/demo/tasks.md
}

# task start
st_setup; BASE="$(git -C "$ST_WT" rev-parse HEAD)"; echo pre > "$ST_WT/pre.txt"
assert_exit "task start 1 exits 0" 0 "$TEMPER" task start 1
assert_eq "task start: status running, attempt 1, start_sha = the worktree HEAD" "running|1|$BASE" \
  "$(st_field 1 status)|$(st_field 1 attempt)|$(st_field 1 start_sha)"
assert_eq "task start: the snapshot holds a hash for the dirty file" "1" \
  "$(python3 -c "import json; d=json.load(open('.temper/groups.json'))['tasks']['1']['snapshot']; print(1 if len(d.get('pre.txt',''))==64 else 0)")"
assert_eq "task start: the task is bound to its group" "G1" "$(st_field 1 group)"
assert_exit "task start: a task that is already running exits 1" 1 "$TEMPER" task start 1
out="$("$TEMPER" task start 2 2>&1)"; rc=$?
assert_eq "task start: a task behind an unpassed Depends exits 1 and names it" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'Task 2 is not ready.*Task 1')"
assert_exit "task start: an unknown task exits 1" 1 "$TEMPER" task start 99
assert_exit "task start: no task number exits 1" 1 "$TEMPER" task start
sw_setup; printf '{"plan":{"verdict":"PASS"}}\n' > .temper/gates.json
assert_exit "task start: a group that was not started exits 1" 1 "$TEMPER" task start 1

# task show
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1
SHOW="$("$TEMPER" task show 1)"
assert_eq "task show: the header names task, group, attempt and title" "1" "$(printf '%s\n' "$SHOW" | grep -c '^TASK 1 (group G1, attempt 1): Alpha$')"
assert_eq "task show: the worktree and project lines are absolute" "1|1" \
  "$(printf '%s\n' "$SHOW" | grep -c "^WORKTREE: $PWD/$ST_WT\$")|$(printf '%s\n' "$SHOW" | grep -c "^PROJECT:  $PWD\$")"
assert_eq "task show: the declared files line" "1" "$(printf '%s\n' "$SHOW" | grep -c '^DECLARED FILES: src/a.sh, tests/a_test.sh$')"
assert_eq "task show: the task block and the group context are inside" "1|1|1" \
  "$(printf '%s\n' "$SHOW" | grep -c '^--- TASK ---$')|$(printf '%s\n' "$SHOW" | grep -c 'Test:\*\* `bash -c .echo boom')|$(printf '%s\n' "$SHOW" | grep -c 'Shared notes for G1')"
assert_eq "task show: another group's context is not inside" "0" "$(printf '%s\n' "$SHOW" | grep -c 'Notes for G2')"
assert_eq "task show: a first attempt has no previous-attempt section" "0" "$(printf '%s\n' "$SHOW" | grep -c 'PREVIOUS ATTEMPT')"
assert_exit "task show: an unknown task exits 1" 1 "$TEMPER" task show 99

# task test
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1
out="$(ST_EXIT=3 "$TEMPER" task test 1 --phase red)"; rc=$?
assert_eq "task test: the command's exit is the exit and its output is shown" "3|1" "$rc|$(printf '%s' "$out" | grep -c boom)"
"$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_eq "task test: rows carry phase and exit" "red:3,green:0" "$(st_rows 1)"
assert_eq "task test: the row is tagged task, group, attempt and executed_by" "1|G1|1|cli" \
  "$(python3 -c "import json; r=json.load(open('.temper/evidence/build.json'))[0]; print('%s|%s|%s|%s' % (r['task'],r['group'],r['attempt'],r['executed_by']))")"
assert_eq "task test: the claim is a test claim of the build stage" "1" \
  "$(python3 -c "import json; print(1 if 'test' in json.load(open('.temper/evidence/build.json'))[0]['claim'].lower() else 0)")"
assert_eq "task test: the command ran with the worktree as its cwd" "$PWD/$ST_WT" "$("$TEMPER" task test 1 --phase green | sed -n 2p)"
assert_exit "task test: a phase other than red or green exits 1" 1 "$TEMPER" task test 1 --phase blue
assert_exit "task test: a missing phase exits 1" 1 "$TEMPER" task test 1
assert_exit "task test: a task that is not running exits 1" 1 "$TEMPER" task test 3 --phase red
assert_eq "task test: a refused call records no row" "0" "$(st_rows 3 | tr -cd ',' | wc -c | tr -d ' ')"
ST_SLEEP=5 TEMPER_TASK_TEST_TIMEOUT_S=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; rc=$?
assert_eq "task test: a hung command is killed and exits 124" "124" "$rc"
assert_eq "task test: the timed-out run is recorded with exit 124" "124" \
  "$(python3 -c "import json; print(json.load(open('.temper/evidence/build.json'))[-1]['exit_code'])")"

# task test runs the task's own declared Test: command (design Resolution 3); a substituted one is refused
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1
out="$("$TEMPER" task test 1 --phase red -- false 2>&1)"; rc=$?
assert_eq "task test: a substituted command is refused (exit 1) naming the declared one" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'declared')"
assert_exit "task test: a substituted green command is refused too" 1 "$TEMPER" task test 1 --phase green -- true
assert_eq "task test: a refused substitution records no row" "" "$(st_rows 1)"
st_edit src/a.sh
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "task gate: false-for-RED and true-for-GREEN substitution cannot pass the gate" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: no green run')"
assert_eq "task gate: the substituted attempt is not committed or ticked" "3|failed" "$(st_unticked)|$(st_field 1 status)"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1
DECL="bash -c 'echo boom; pwd; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"
ST_EXIT=2 "$TEMPER" task test 1 --phase red -- "$DECL" >/dev/null 2>&1; rc=$?
assert_eq "task test: the declared command itself after -- is accepted, exit passed through" "2|red:2" "$rc|$(st_rows 1)"
assert_eq "task test: the row records the declared command" "1" \
  "$(python3 -c "import json; r=json.load(open('.temper/evidence/build.json'))[-1]; print(1 if 'echo boom' in r['cmd'] else 0)")"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh
"$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_exit "task gate: RED and GREEN of the declared command pass the gate" 0 "$TEMPER" task gate 1

# task gate: the pass path
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; BASE="$(st_field 1 start_sha)"
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit tests/a_test.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "task gate: RED then GREEN with declared files only passes" "0|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c '^PASS: Task 1')|$(printf '%s' "$out" | grep -c '^NEXT: schedule')"
assert_eq "task gate: the status is passed" "passed" "$(st_field 1 status)"
assert_eq "task gate: only Task 1's box is ticked" "2" "$(st_unticked)"
assert_eq "task gate: Task 1's own box is the ticked one" "1" "$(awk '/^### Task 1:/{f=1} /^### Task 2:/{f=0} f' .temper/specs/demo/tasks.md | grep -c '^- \[x\]')"
assert_eq "task gate: one commit on the group branch, subject names task and group" "feat(demo): Task 1 Alpha [G1]" \
  "$(git -C "$ST_WT" log -1 --format=%s)"
assert_eq "task gate: the commit holds exactly the declared files" "src/a.sh,tests/a_test.sh" \
  "$(git -C "$ST_WT" show --name-only --format= HEAD | sort | paste -sd, -)"
assert_eq "task gate: the commit is on top of the start sha" "$BASE" "$(git -C "$ST_WT" rev-parse HEAD~1)"
assert_eq "task gate: the verdict goes to groups.json, not gates.json" "0" "$(grep -c '"task"' .temper/gates.json)"
assert_eq "task gate: the dependent task is now offered" "2,3" "$(sg_ready)"
assert_exit "task gate: a task that already passed exits 1" 1 "$TEMPER" task gate 1

# task gate: the dirty file that was there before the start is not this task's change
st_setup; echo pre > "$ST_WT/pre.txt"; "$TEMPER" task start 1 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_exit "task gate: a file that was dirty before the start and is unchanged passes" 0 "$TEMPER" task gate 1
assert_eq "task gate: the pre-existing file is not committed" "src/a.sh" "$(git -C "$ST_WT" show --name-only --format= HEAD)"

# task gate: sibling tasks in one worktree
st_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit src/b.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
assert_exit "task gate: a sibling's file in the shared worktree is not an undeclared change" 0 "$TEMPER" task gate 1
assert_eq "task gate: the first task's commit leaves the sibling's file alone" "src/a.sh" "$(git -C "$ST_WT" show --name-only --format= HEAD)"
assert_exit "task gate: the sibling then passes with its own file" 0 "$TEMPER" task gate 2
assert_eq "task gate: the sibling's commit holds its own file" "src/b.sh" "$(git -C "$ST_WT" show --name-only --format= HEAD)"

# task gate: FAIL reasons
st_fail() { # st_fail <red-exit|none> <green-exit|none> [more ledger shape]: start 1, record, gate; prints the output
  "$TEMPER" task start 1 >/dev/null 2>&1
  [[ "$1" != "none" ]] && ST_EXIT=$1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  st_edit src/a.sh
  [[ "$2" != "none" ]] && ST_EXIT=$2 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  "$TEMPER" task gate 1 2>&1
}
NEEDRED='need a failing run before a passing run for this task and attempt'
st_setup; out="$(st_fail none 0)"; rc=$?
assert_eq "task gate: GREEN only fails (exit 1) naming the missing RED" "1|1" "$rc|$(printf '%s' "$out" | grep -c "^FAIL: $NEEDRED")"
assert_eq "task gate: a failed task is not ticked, not committed, and its status is failed" "3|failed|0" \
  "$(st_unticked)|$(st_field 1 status)|$(git -C "$ST_WT" log --oneline | grep -c Task)"
assert_eq "task gate: the failed attempt is recorded" "1" "$(python3 -c "import json; a=json.load(open('.temper/groups.json'))['tasks']['1']['attempts']; print(len(a) if a[0]['outcome']=='FAIL' else 0)")"
st_setup; out="$(st_fail 1 none)"; rc=$?
assert_eq "task gate: RED only fails with the no-green reason" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: no green run for this task and attempt')"
st_setup; out="$(st_fail none none)"
assert_eq "task gate: no runs at all fails with the no-green reason" "1" "$(printf '%s' "$out" | grep -c '^FAIL: no green run')"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "task gate: GREEN before RED fails" "1" "$(printf '%s' "$out" | grep -c "^FAIL: $NEEDRED")"
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 3 >/dev/null 2>&1
ST_EXIT=1 "$TEMPER" task test 3 --phase red >/dev/null 2>&1; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "task gate: another task's RED does not count" "1" "$(printf '%s' "$out" | grep -c "^FAIL: $NEEDRED")"
# a RED from an earlier attempt does not count for the next one
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; "$TEMPER" task gate 1 >/dev/null 2>&1
assert_exit "task start: a failed task can be started again" 0 "$TEMPER" task start 1
assert_eq "task start: the second start is attempt 2" "2" "$(st_field 1 attempt)"
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "task gate: attempt 2 does not reuse attempt 1's RED" "1" "$(printf '%s' "$out" | grep -c "^FAIL: $NEEDRED")"
# undeclared change
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; HEADBEFORE="$(git -C "$ST_WT" rev-parse HEAD)"
ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; st_edit stray.txt
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "task gate: an undeclared file fails the gate and names it" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: undeclared change: stray.txt')"
assert_eq "task gate: the undeclared change is not committed or ticked" "$HEADBEFORE|3" "$(git -C "$ST_WT" rev-parse HEAD)|$(st_unticked)"
# an edit to a file that was already dirty at the start is a change too
st_setup; echo pre > "$ST_WT/pre.txt"; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
echo changed > "$ST_WT/pre.txt"; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_eq "task gate: a pre-dirty file edited during the task is undeclared" "1" "$("$TEMPER" task gate 1 2>&1 | grep -c 'undeclared change: pre.txt')"
assert_exit "task gate: a task that was never started exits 1" 1 "$TEMPER" task gate 3

# ADR 0009: the CLI's own commit checks the upstream gates the native hook cannot see in a worktree
st_pass_ready() { "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1; }
st_setup; st_pass_ready; HEADBEFORE="$(git -C "$ST_WT" rev-parse HEAD)"; printf '{"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "task gate: no plan verdict refuses the commit (exit 3) and names the stage" "3|1" "$rc|$(printf '%s' "$out" | grep -c 'plan')"
assert_eq "task gate: the refused commit changed nothing" "$HEADBEFORE|3|running" "$(git -C "$ST_WT" rev-parse HEAD)|$(st_unticked)|$(st_field 1 status)"
printf '{"plan":{"verdict":"PASS"}}\n' > .temper/gates.json
assert_exit "task gate: the intent verdict is required while intent.md exists (exit 3)" 3 "$TEMPER" task gate 1
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json; echo '# Design' > .temper/specs/demo/design.md
assert_exit "task gate: the design verdict is required while design.md exists (exit 3)" 3 "$TEMPER" task gate 1
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"},"design":{"verdict":"FAIL"}}\n' > .temper/gates.json
printf '[{"stage":"design","reason":"accepted risk","ts":"2026-01-01T00:00:00Z"}]\n' > .temper/overrides.json
assert_exit "task gate: a human override satisfies an upstream gate" 0 "$TEMPER" task gate 1

# the launch payload stays within its byte budget
st_setup; python3 - <<'PY'
p = '.temper/specs/demo/tasks.md'
s = open(p).read().replace('Shared notes for G1. Use bash.', '\n'.join('c' * 60 + str(i) for i in range(64)))
open(p, 'w').write(s)
PY
"$TEMPER" task start 1 >/dev/null 2>&1; ST_LONG=1 ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
"$TEMPER" task gate 1 >/dev/null 2>&1; "$TEMPER" task start 1 >/dev/null 2>&1
SHOW="$("$TEMPER" task show 1)"
assert_eq "task show: a retry carries the previous attempt with its reason" "1|1" \
  "$(printf '%s\n' "$SHOW" | grep -c '^--- PREVIOUS ATTEMPT ---$')|$(printf '%s\n' "$SHOW" | grep -c 'no green run for this task and attempt')"
assert_eq "task show: the previous attempt shows 20 lines of output and no more" "1" \
  "$(n=$(printf '%s\n' "$SHOW" | grep -c '^line '); [[ $n -ge 19 && $n -le 20 ]] && echo 1 || echo "$n")"
assert_eq "task show: the whole payload is at most 6000 bytes" "1" "$([[ "$(printf '%s' "$SHOW" | wc -c | tr -d ' ')" -le 6000 ]] && echo 1 || echo 0)"
assert_eq "task show: the group context is kept whole inside the budget" "64" "$(printf '%s\n' "$SHOW" | grep -c '^cccccccccc')"

# grouped off: every task subcommand exits 1 and writes nothing
setup; gp_base
assert_exit "grouped off: task start exits 1" 1 "$TEMPER" task start 1
assert_exit "grouped off: task show exits 1" 1 "$TEMPER" task show 1
assert_exit "grouped off: task test exits 1" 1 "$TEMPER" task test 1 --phase red
assert_exit "grouped off: task gate exits 1" 1 "$TEMPER" task gate 1
assert_eq "grouped off: no groups.json is written" "no" "$([[ -e .temper/groups.json ]] && echo yes || echo no)"
assert_exit "an unknown task subcommand exits 1" 1 "$TEMPER" task frobnicate
setup
