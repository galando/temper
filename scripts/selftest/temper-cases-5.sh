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

# retry -> escalate -> park (D-03), restore on FAIL, usage recording
st_nextcount() { printf '%s\n' "$1" | grep -c '^NEXT:'; }
st_attempt() { # st_attempt <model> <tokens> <ms>: start Task 1, write a declared file and a stray one, no RED: a FAIL
  "$TEMPER" task start 1 >/dev/null 2>&1
  st_edit src/a.sh; st_edit stray.txt
  "$TEMPER" task gate 1 --model "$1" --tokens "$2" --ms "$3" 2>&1
}
st_setup
out="$(st_attempt claude-haiku-5-5 2100 41000)"; rc=$?
assert_eq "retry: attempt 1 FAIL prints exactly one NEXT line, retry on the task model" "1|NEXT: retry Task 1 on claude-haiku-5-5" \
  "$(st_nextcount "$out")|$(printf '%s\n' "$out" | grep '^NEXT:')"
assert_eq "retry: the declared file the failed attempt wrote is restored (removed)" "no" "$([[ -e "$ST_WT/src/a.sh" ]] && echo yes || echo no)"
assert_eq "retry: an undeclared file is left alone" "yes" "$([[ -e "$ST_WT/stray.txt" ]] && echo yes || echo no)"
assert_eq "retry: the group is not parked after one failure and Task 1 is offered again" "running|attempt 2" \
  "$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['status'])")|attempt $("$TEMPER" schedule | python3 -c "
import json,sys
print(next(json.loads(l)['attempt'] for l in sys.stdin if l.startswith('{') and json.loads(l).get('task')==1))")"
out="$(st_attempt claude-haiku-5-5 1900 39000)"
assert_eq "retry: attempt 2 FAIL prints one NEXT line, escalate on the escalation model" "1|NEXT: escalate Task 1 on sonnet" \
  "$(st_nextcount "$out")|$(printf '%s\n' "$out" | grep '^NEXT:')"
assert_eq "retry: the schedule offers the escalation model for attempt 3" "sonnet|3" \
  "$("$TEMPER" schedule | python3 -c "
import json,sys
r=next(json.loads(l) for l in sys.stdin if l.startswith('{') and json.loads(l).get('task')==1)
print('%s|%s' % (r['model'], r['attempt']))")"
out="$(st_attempt sonnet 5200 90000)"; rc=$?
assert_eq "retry: attempt 3 FAIL prints one NEXT line, park the group, exit 1" "1|1|NEXT: park group G1" \
  "$rc|$(st_nextcount "$out")|$(printf '%s\n' "$out" | grep '^NEXT:')"
assert_eq "park: the group is parked with a reason naming the task" "parked|1" \
  "$(python3 -c "import json; g=json.load(open('.temper/groups.json'))['groups']['G1']; print(g['status'])")|$(python3 -c "import json; g=json.load(open('.temper/groups.json'))['groups']['G1']; print(1 if 'Task 1' in g.get('parked_reason','') and '3' in g.get('parked_reason','') else 0)")"
assert_eq "park: the schedule stops offering G1 tasks and still offers G2" "3" "$(sg_ready)"
out="$("$TEMPER" task start 1 2>&1)"; rc=$?
assert_eq "park: a fourth attempt cannot start (exit 1, names the parked group)" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'parked')"
assert_eq "usage: three attempts carry model, outcome, reason, tokens and ms" \
  "claude-haiku-5-5/FAIL/2100/41000,claude-haiku-5-5/FAIL/1900/39000,sonnet/FAIL/5200/90000" \
  "$(python3 -c "
import json
a=json.load(open('.temper/groups.json'))['tasks']['1']['attempts']
assert all(x['reason'] for x in a)
print(','.join('%s/%s/%s/%s' % (x['model'],x['outcome'],x['tokens'],x['ms']) for x in a))")"
# the other group is unaffected and can still pass
"$TEMPER" task start 3 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 3 --phase red >/dev/null 2>&1
mkdir -p "$ST_WT/../temper-demo-G2/src" 2>/dev/null; echo c > ".claude/worktrees/temper-demo-G2/src/c.sh"
ST_EXIT=0 "$TEMPER" task test 3 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 3 --model claude-haiku-5-5 --tokens 10 --ms 5 2>&1)"
assert_eq "park: a task in the other group still passes and prints only NEXT: schedule" "0|NEXT: schedule" \
  "$(printf '%s\n' "$out" | grep -c '^FAIL')|$(printf '%s\n' "$out" | grep '^NEXT:')"

# restore puts a tracked declared file back to its start content
st_setup
mkdir -p "$ST_WT/src"; echo original > "$ST_WT/src/a.sh"
git -C "$ST_WT" add src/a.sh >/dev/null 2>&1; git -C "$ST_WT" -c user.name=t -c user.email=t@t commit -q -m seed >/dev/null 2>&1
"$TEMPER" task start 1 >/dev/null 2>&1; echo changed > "$ST_WT/src/a.sh"
"$TEMPER" task gate 1 --model claude-haiku-5-5 >/dev/null 2>&1
assert_eq "retry: a tracked declared file is restored to its start content" "original" "$(cat "$ST_WT/src/a.sh")"
assert_eq "retry: tokens and ms are optional (recorded as null)" "None|None" \
  "$(python3 -c "import json; a=json.load(open('.temper/groups.json'))['tasks']['1']['attempts'][0]; print('%s|%s' % (a['tokens'],a['ms']))")"
# a passing gate prints no retry/escalate/park line
st_setup; "$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1; st_edit src/a.sh
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 --model claude-haiku-5-5 --tokens 7 --ms 9 2>&1)"
assert_eq "usage: a PASS records tokens and ms and prints only NEXT: schedule" "7/9|NEXT: schedule" \
  "$(python3 -c "import json; a=json.load(open('.temper/groups.json'))['tasks']['1']['attempts'][0]; print('%s/%s' % (a['tokens'],a['ms']))")|$(printf '%s\n' "$out" | grep '^NEXT:')"

# grouped off: every task subcommand exits 1 and writes nothing
setup; gp_base
assert_exit "grouped off: task start exits 1" 1 "$TEMPER" task start 1
assert_exit "grouped off: task show exits 1" 1 "$TEMPER" task show 1
assert_exit "grouped off: task test exits 1" 1 "$TEMPER" task test 1 --phase red
assert_exit "grouped off: task gate exits 1" 1 "$TEMPER" task gate 1
assert_eq "grouped off: no groups.json is written" "no" "$([[ -e .temper/groups.json ]] && echo yes || echo no)"
assert_exit "an unknown task subcommand exits 1" 1 "$TEMPER" task frobnicate
setup

# --- Grouped Build (9.7.0): group gate and Change at a group gate ---
# Scenarios: A group gate passes when every task gate passed and the group tests pass; Change at a
# group gate reruns only the named tasks [AC-09, D-02]
gg_setup() { # st_setup + a controllable G1 Validate command (GV_EXIT is its exit)
  st_setup
  gp_mut '`bash tests/g1.sh`' "\`bash -c 'echo validating; pwd; exit \${GV_EXIT:-0}'\`"
}
gg_pass() { # gg_pass <task> <file>: drive one task through RED, an edit, GREEN and its gate
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  st_edit "$2"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --tokens 10 --ms 5 >/dev/null 2>&1
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
  rm -rf src tests shared.txt   # files an earlier case merged into the shared throwaway folder
  gg_setup
  gp_mut '`bash tests/g2.sh`' '`true`'
  gp_mut '`bash run-all.sh`' "\`bash -c 'echo integrating; pwd; ls src; exit \${GI_EXIT:-0}'\`"
  "$TEMPER" group start G2 >/dev/null 2>&1
}
gi_pass() { # gi_pass <task> <group-worktree-name> <file> <content>: RED, edit, GREEN, task gate
  local wt=".claude/worktrees/temper-demo-$2"
  "$TEMPER" task start "$1" >/dev/null 2>&1
  ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  mkdir -p "$wt/$(dirname "$3")"; printf '%s\n' "$4" > "$wt/$3"
  ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1
  "$TEMPER" task gate "$1" --model claude-haiku-5-5 --tokens 10 --ms 5 >/dev/null 2>&1
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

# an Interfaces literal that is missing from the merged tree
gi_all; gp_mut '`src/a.sh` — `a_main`' '`src/a.sh` — `a_missing`'
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "integrate: a missing interface literal -> exit 1 naming it" "1|1" "$rc|$(printf '%s' "$out" | grep -c '^FAIL: interface missing: a_missing in src/a.sh')"
assert_eq "integrate: the interface FAIL is stored" "FAIL" "$(gi_int verdict)"

# a merge conflict stops the run before Review
gi_all
echo one > .claude/worktrees/temper-demo-G1/shared.txt; git -C .claude/worktrees/temper-demo-G1 add shared.txt; git -C .claude/worktrees/temper-demo-G1 commit -q -m g1shared
echo two > .claude/worktrees/temper-demo-G2/shared.txt; git -C .claude/worktrees/temper-demo-G2 add shared.txt; git -C .claude/worktrees/temper-demo-G2 commit -q -m g2shared
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
gi_all; git checkout -q -B other
assert_exit "integrate: a branch that is not the run's feature branch exits 1" 1 "$TEMPER" integrate
gi_all; printf '{"intent":{"verdict":"PASS"}}\n' > .temper/gates.json; HEAD0="$(git rev-parse HEAD)"
assert_exit "integrate: the CLI merge checks the upstream gates first (ADR 0009, exit 3)" 3 "$TEMPER" integrate
assert_eq "integrate: the refused run merged nothing" "$HEAD0" "$(git rev-parse HEAD)"
gi_all; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_exit "integrate: autonomy lets the local integration merge run (design resolution 1a)" 0 "$TEMPER" integrate
setup
assert_exit "integrate: grouped mode off exits 1" 1 "$TEMPER" integrate
assert_eq "integrate: grouped off keeps gate build without an integration row" "0" "$("$TEMPER" gate build 2>&1 | grep -c integration)"
