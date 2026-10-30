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
  "$(python3 -I "$REPO_ROOT/scripts/task_rows.py" all-tasks <(printf '## Group G1: A\n**Depends:** none\n\n### Task 1: a\n**File:** `a.py`\n**Test:** `true`\n**Cases:**\n- x\n\n### Task 2: b\n**File:** `b.py`\n**Test:** `true`\n**Cases:**\n- y\n- [x] done\n') /dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['pass'])")"
