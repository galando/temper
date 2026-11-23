# Release 9.8.5 case file 29: sourced by test-temper.sh after temper-cases-28.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (S6): a plan patch changes one command line, keeps the passed tasks, and spends no loop ---
_pp() { # _pp: a run at Build with group G1 started (the plan approved, its hash recorded). WP25: each task has two cases,
       # so the plan passes every static row a patch runs on its result
  f9_tasks | sed '/^- [ab] holds$/a - a bad input is refused' | m_setup
}
_pp
assert_eq "9.8.5 patch: plan_patch's digest is the CLI's own _plan_digest" "$(python3 -c "import json; print(json.load(open('.temper/build-state.json')).get('plan_hash') or json.load(open('.temper/groups.json')).get('plan_hash'))")" \
  "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import plan_patch, tasks_md; print(plan_patch.digest(tasks_md.parse('.temper/specs/demo/tasks.md')))" "$REPO_ROOT/scripts")"
loops_before="$(cat .temper/feedback-loops.json 2>/dev/null | cksum)"
OUT="$("$TEMPER" plan patch G1 --cmd 'bash run-g1.sh' 2>&1)"; rc=$?
assert_eq "9.8.5 patch: the group's Validate line changes, the plan hash follows, the group check is cleared, the ledger row is kept" "0|1|True|True" \
  "$rc|$(grep -c '^\*\*Validate:\*\* `bash run-g1.sh`' .temper/specs/demo/tasks.md)|$(python3 -I -c "
import json, sys; sys.path.insert(0, sys.argv[1]); import plan_patch, tasks_md
print(json.load(open('.temper/build-state.json'))['plan_hash'] == plan_patch.digest(tasks_md.parse('.temper/specs/demo/tasks.md')))" "$REPO_ROOT/scripts")|$(grep -q 'plan patch: G1 Validate' .temper/evidence/plan.json && echo True || echo False)"
assert_eq "9.8.5 patch: no loop is spent" "$loops_before" "$(cat .temper/feedback-loops.json 2>/dev/null | cksum)"
assert_eq "9.8.5 patch: Build reads the patched plan as the approved one" "0" \
  "$("$TEMPER" group gate G1 --timeout-s 30 2>&1 | grep -c 'the approved plan changed')"
sed -i '0,/^\*\*File:\*\* `src\/a.sh`/s//**File:** `src\/other.sh`/' .temper/specs/demo/tasks.md
assert_exit "9.8.5 patch: a tasks.md that differs in more than the line is refused" 1 "$TEMPER" plan patch G1 --cmd 'true'
assert_exit "9.8.5 patch: a command with a backquote is refused" 1 "$TEMPER" plan patch integration --cmd 'echo `x`'

# --- the group question offers the patch first when the cause is the command ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", "fails": 1, "fix_tries": 1, "fix_empty": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: bash slow.sh", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "9.8.5 patch: after an empty fix, Change the group's command is first and recommended, and asks for the command" \
  "Change the group's command (Recommended)|plan patch G1 --cmd '{answer}'|Group command" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['label']] + [c.split('temper ', 1)[1] for c in o['calls']] + [o['answer_question']['header']])")"

# --- WP25: the plan amendment by rule and the plan patch, the person's (names amend: and patch:) ---
# `temper plan amend task N --add-file F [--failure ID]` (scripts/plan_amend.py) only adds to Task N a file another task
# of its own group declares: the CLI writes the File line and the Depends entry itself, compares the result with the
# plan field by field, runs the static rows on it, spends one repeat (key task:N, kind plan amend) and reopens the task.
# `temper plan patch` stays the person's: a command line, or a file outside the approved set (task N --add-file F).
# Neither writes the approved record; both append to .temper/evidence/amendments.json. A call the CLI does not have yet
# stays inside $( ... ) or ends in || true, so the file always runs to its end.
T29="$(mktemp -d)"   # the fixtures this block builds most, kept as archives; removed at the end of the file
_save29() { tar -cf "$T29/$1.tar" -C "$WORKDIR" . 2>/dev/null; }
_load29() { # _load29 <name>: the case folder as _save29 kept it (1 when none is kept)
  [[ -f "$T29/$1.tar" ]] || return 1
  cd "$WORKDIR" || return 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  tar -xf "$T29/$1.tar" -C "$WORKDIR"
}
_amplan29() { # _amplan29 [pad]: the plan of these cases; it passes every static row. G1 holds Task 1 (a production file,
              # a test file, a file under the sensitive auth folder and one under the acceptance folder of the spec) and
              # Task 2 (Depends none); G2 holds Task 3. With pad a case of Task 2 is long enough that its block is 2040
              # bytes: one more file and one Depends entry take it over the limit of 2048 (the row task block budget)
  python3 -B - "${1:-}" "$REPO_ROOT/scripts" <<'PY'
import os, sys, tempfile
sys.path.insert(0, sys.argv[2])
import tasks_md
text = """# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`, `unit/a_test.sh`, `src/auth/login.sh`, `.temper/specs/demo/acceptance/accept_demo.sh`
**Depends:** none
**Test:** `test -f src/a.sh`
**Cases:**
- a holds
- a bad input is refused
- [ ] done

### Task 2: second
**File:** `src/b.sh`
**Depends:** none
**Test:** `test -f src/b.sh`
**Cases:**
- b holds
- a bad input is refusedPAD
- [ ] done

## Group G2: Later
**Depends:** G1
**Validate:** `true`
**Context:**
The later work.

### Task 3: third
**File:** `src/c.sh`
**Depends:** none
**Test:** `test -f src/c.sh`
**Cases:**
- c holds
- a bad input is refused
- [ ] done"""
def block(t):
    fd, p = tempfile.mkstemp(suffix=".md")
    with os.fdopen(fd, "w") as f:
        f.write(t)
    try:
        return next(x["block_bytes"] for x in tasks_md.parse(p)["tasks"] if x["n"] == 2)
    finally:
        os.unlink(p)
pad = ""
if sys.argv[1]:
    pad = ", and so on" + " and on" * ((2040 - block(text.replace("PAD", ", and so on"))) // 7)
    pad += "." * (2040 - block(text.replace("PAD", pad)))
print(text.replace("PAD", pad))
PY
}
_built29() { # _built29 <N> <file>: Task N built by the CLI's own calls: started, RED, the file in its worktree, GREEN, gated
  "$TEMPER" task start "$1" >/dev/null 2>&1; "$TEMPER" task test "$1" --phase red >/dev/null 2>&1
  mkdir -p ".claude/worktrees/temper-demo-T$1/$(dirname "$2")"; echo "echo $1" > ".claude/worktrees/temper-demo-T$1/$2"
  "$TEMPER" task test "$1" --phase green >/dev/null 2>&1; "$TEMPER" task gate "$1" --model m >/dev/null 2>&1
}
_blocked29() { # _blocked29: Task 2 records that its test needs src/a.sh (Task 1 declares it) and is gated: G1 parks
  "$TEMPER" task start 2 >/dev/null 2>&1
  "$TEMPER" task blocked 2 --needs src/a.sh --reason 'the test of b needs the a event, written in src/a.sh' >/dev/null 2>&1
  "$TEMPER" task test 2 --phase red >/dev/null 2>&1; "$TEMPER" task gate 2 --model m >/dev/null 2>&1
}
_am29() { # _am29 [pad]: Task 1 built and passed, Task 2 blocked on src/a.sh and G1 parked; kept as "am" ("pad" with pad)
  _load29 "am${1:-}" && return 0
  _amplan29 "${1:-}" | m_setup; _built29 1 src/a.sh; _blocked29
  _save29 "am${1:-}"
}
_snap29() { # what a refused call must leave as it was: tasks.md, the approved record, the amendments, the budget, the
            # run state's plan_hash and approved_files, and groups.json's plan_hash
  cat .temper/specs/demo/tasks.md .temper/evidence/approved-tasks.json .temper/evidence/amendments.json \
    .temper/budget.json 2>/dev/null | cksum
  python3 -c "
import json
s = json.load(open('.temper/build-state.json'))
try:
    g = json.load(open('.temper/groups.json'))
except (OSError, ValueError):
    g = {}
print(s.get('plan_hash'), s.get('approved_files'), g.get('plan_hash'))" 2>/dev/null
}
_try29() { # _try29 <ERE> <words of temper plan ...>: "refused" when the call exits non zero, its output names the reason
           # (the ERE, read without case) and every file of _snap29 is as it was; else what happened
  local ere="$1" before out rc; shift
  before="$(_snap29)"
  out="$("$TEMPER" plan "$@" 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$before" == "$(_snap29)" ]] && grep -Eiq -- "$ere" <<<"$out"; then echo refused
  elif [[ $rc -eq 0 ]]; then echo taken
  elif [[ "$before" != "$(_snap29)" ]]; then echo "rc=$rc and something changed"
  else echo "rc=$rc: $(head -1 <<<"$out")"; fi
}
_g29() { python3 -c "import json,sys; d = json.load(open('.temper/groups.json')); print(eval(sys.argv[1]))" "$1" 2>/dev/null || echo none; }
_parse29() { python3 -c "import json,sys; sys.path.insert(0, sys.argv[1]); import tasks_md; print(json.dumps(tasks_md.parse('.temper/specs/demo/tasks.md')))" "$REPO_ROOT/scripts"; }
_fields29() { # _fields29 <parsed plan before>: every field of every task and group, and the Integration line, that
              # differs between that plan and tasks.md now, one "Task N <field> + <item>" or "- <item>" a line, sorted
  python3 - "$1" "$(_parse29)" <<'PY'
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
out = []
def diff(name, x, y):
    for k in sorted(set(x) | set(y)):
        if k in ("block", "block_bytes", "context_bytes", "done"):
            continue
        u, v = x.get(k), y.get(k)
        if u == v:
            continue
        if isinstance(u, list) and isinstance(v, list):
            out.extend("%s %s + %s" % (name, k, i) for i in v if i not in u)
            out.extend("%s %s - %s" % (name, k, i) for i in u if i not in v)
        else:
            out.append("%s %s: %r -> %r" % (name, k, u, v))
ta, tb = {t["n"]: t for t in a["tasks"]}, {t["n"]: t for t in b["tasks"]}
for n in sorted(set(ta) | set(tb)):
    diff("Task %s" % n, ta.get(n, {}), tb.get(n, {}))
ga, gb = {g["id"]: g for g in a["groups"]}, {g["id"]: g for g in b["groups"]}
for g in sorted(set(ga) | set(gb)):
    diff(g, ga.get(g, {}), gb.get(g, {}))
if a.get("integration") != b.get("integration"):
    out.append("Integration: %r -> %r" % (a.get("integration"), b.get("integration")))
print("|".join(sorted(out)) or "no change")
PY
}

# amend: each refusal (the call exits non zero, names its reason, and writes nothing)
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; _amplan29 > .temper/specs/demo/tasks.md
assert_eq "amend: refused when the plan is not approved" "refused" "$(_try29 'approv' amend task 2 --add-file src/a.sh)"
_am29; sed -i 's|^\*\*Test:\*\* `test -f src/c.sh`|**Test:** `test -s src/c.sh`|' .temper/specs/demo/tasks.md
assert_eq "amend: refused when tasks.md differs from the current plan" "refused" \
  "$(_try29 'differ|changed|approved plan' amend task 2 --add-file src/a.sh)"
_am29
assert_eq "amend: refused for a file no other task of the group declares" "refused" \
  "$(_try29 'declare|no task|no other task|own' amend task 2 --add-file src/new.sh)"
assert_eq "amend: refused for a file only a task of another group declares" "refused" \
  "$(_try29 'group|G2' amend task 2 --add-file src/c.sh)"
assert_eq "amend: refused for a test file another task declares" "refused" "$(_try29 'test' amend task 2 --add-file unit/a_test.sh)"
assert_eq "amend: refused for a file under the acceptance folder of the spec" "refused" \
  "$(_try29 'accept' amend task 2 --add-file .temper/specs/demo/acceptance/accept_demo.sh)"
assert_eq "amend: refused for a file under a sensitive path" "refused" \
  "$(_try29 'sensitive|park-on-touch' amend task 2 --add-file src/auth/login.sh)"
python3 -c "
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['approved_files'] = [f for f in d.get('approved_files') or [] if f != 'src/a.sh']
json.dump(d, open(p, 'w'), indent=2)"
assert_eq "amend: refused for a file that is not in approved_files" "refused" "$(_try29 'approved' amend task 2 --add-file src/a.sh)"
_am29
python3 -c "
import json
rid = json.load(open('.temper/build-state.json')).get('run_id') or ''
e = {'key': 'task:2', 'kind': 'task again', 'stage': 'build', 'why': 'task retry 2', 'ts': '2026-01-01T00:00:00Z'}
json.dump({'v': 1, 'run': rid, 'used': [e, dict(e)], 'grants': []}, open('.temper/budget.json', 'w'), indent=1)"
assert_eq "amend: refused when the budget has no room" "refused" "$(_try29 'budget|BLOCKED|repeat|limit' amend task 2 --add-file src/a.sh)"
_amplan29 | m_setup; "$TEMPER" task start 2 >/dev/null 2>&1
assert_eq "amend: refused while the task is running" "refused" "$(_try29 'running' amend task 2 --add-file src/a.sh)"
_amplan29 | m_setup; _built29 2 src/b.sh
assert_eq "amend: refused for a task that passed" "refused" "$(_try29 'passed' amend task 2 --add-file src/a.sh)"
_am29 pad
assert_eq "amend: refused when a static row fails on the result, and tasks.md is byte equal to before" "refused" \
  "$(_try29 'task block budget|bytes' amend task 2 --add-file src/a.sh)"

# amend: the amendment itself, on Task 2 blocked on src/a.sh (Task 1 declares it, passed, its commit on the group
# branch).
# The group carries the marks of an earlier failed fix, which the reopen resets.
_am29
python3 -c "
import json
p = '.temper/groups.json'
d = json.load(open(p)); d['groups']['G1'].update(fails=1, fix_tries=1, fix_empty=1)
json.dump(d, open(p, 'w'), indent=2)"
_a29_plan="$(_parse29)"; _a29_hash="$(python3 -c "import json; print(json.load(open('.temper/build-state.json')).get('plan_hash'))")"
_a29_c1="$(_g29 "d['tasks']['1'].get('commit', '')")"; _a29_rec="$(cksum < .temper/evidence/approved-tasks.json)"
_a29_budget="$(python3 -c "import json; print(len(json.load(open('.temper/budget.json')).get('used') or []))" 2>/dev/null || echo 0)"
_a29_out="$("$TEMPER" plan amend task 2 --add-file src/a.sh 2>&1)"; _a29_rc=$?
assert_eq "amend: the result adds one file and one Depends entry and nothing else" \
  "rc=0|Task 2 depends + 1|Task 2 files + src/a.sh" "rc=$_a29_rc|$(_fields29 "$_a29_plan")"
assert_eq "amend: the ledger row says amended by rule and never the person" "row=1|label=not PERSON|person=0" "$(python3 - <<'PY'
import json
try:
    rows = [r for r in json.load(open(".temper/evidence/plan.json")) if isinstance(r, dict)]
except (OSError, ValueError):
    rows = []
mine = [r for r in rows if "plan amended by rule: Task 2 gains src/a.sh (Task 1 declares it)" in str(r.get("claim"))]
print("row=%d|label=%s|person=%d" % (len(mine), "PERSON" if any(r.get("label") == "PERSON" for r in mine) else "not PERSON",
                                     sum(1 for r in mine if "person" in str(r.get("claim")).lower())))
PY
)"
assert_eq "amend: the task is reopened and the owner's work is kept" \
  "task2=reopened|group=not parked|marks=0,0,0|task1=passed|commit=on the group branch" \
  "task2=$(_g29 "'reopened' if d['tasks']['2'].get('status') not in ('failed', 'passed', 'running') and 'blocked' not in d['tasks']['2'] else d['tasks']['2'].get('status')")|group=$(_g29 "'parked' if d['groups']['G1'].get('status') == 'parked' else 'not parked'")|marks=$(_g29 "','.join(str(d['groups']['G1'].get(k) or 0) for k in ('fails', 'fix_tries', 'fix_empty'))")|task1=$(_g29 "d['tasks']['1'].get('status')")|commit=$([[ -n "$_a29_c1" && "$_a29_c1" == "$(_g29 "d['tasks']['1'].get('commit', '')")" ]] && git merge-base --is-ancestor "$_a29_c1" temper/demo/G1 2>/dev/null && echo 'on the group branch' || echo lost)"
assert_eq "amend: plan_hash moved in the state and in groups.json" "moved|state=digest|groups=digest" "$(python3 - "$_a29_hash" "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[2])
import approval, tasks_md
now = approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md"))
s = json.load(open(".temper/build-state.json")).get("plan_hash")
g = json.load(open(".temper/groups.json")).get("plan_hash")
print("%s|state=%s|groups=%s" % ("moved" if now != sys.argv[1] else "not moved", "digest" if s == now else "other",
                                  "digest" if g == now else "other"))
PY
)"
assert_eq "amend: the call spends one repeat of the budget, the key task:2 and the kind plan amend" "task:2,plan amend" \
  "$(python3 -c "
import json, sys
u = (json.load(open('.temper/budget.json')).get('used') or [])[int(sys.argv[1]):]
print(';'.join('%s,%s' % (x.get('key'), x.get('kind')) for x in u) or 'nothing spent')" "$_a29_budget" 2>/dev/null || echo 'nothing spent')"
assert_eq "amend: amendments.json gains one entry with the two hashes and the reopened task; the approved record stays" \
  "1|amend|Task 2 gains src/a.sh|before=old|after=new|reopened=[2]|record=same" "$(python3 - "$_a29_hash" <<'PY'
import json, sys
try:
    d = [e for e in json.load(open(".temper/evidence/amendments.json")) if isinstance(e, dict)]
except (OSError, ValueError):
    d = []
e = d[-1] if d else {}
now = json.load(open(".temper/build-state.json")).get("plan_hash")
print("%d|%s|%s|before=%s|after=%s|reopened=%s" % (len(d), e.get("kind"), e.get("what"),
      "old" if e.get("hash_before") == sys.argv[1] else e.get("hash_before"), "new" if e.get("hash_after") == now and now != sys.argv[1] else e.get("hash_after"),
      e.get("reopened")))
PY
)|record=$([[ "$_a29_rec" == "$(cksum < .temper/evidence/approved-tasks.json)" ]] && echo same || echo changed)"

# patch: the person's change of the plan
_pp
python3 -c "
import json
p = '.temper/groups.json'
d = json.load(open(p))
d['groups']['G1'].update(fails=1, fix_tries=1, fix_empty=1, gate={'verdict': 'FAIL', 'reason': 'group G1 Validate failed', 'ran': True})
json.dump(d, open(p, 'w'), indent=2)"
"$TEMPER" plan patch G1 --cmd 'bash run-g1.sh' >/dev/null 2>&1; _p29_rc=$?
assert_eq "patch: fix_empty, fix_tries and fails are reset" "rc=0|fails=0|fix_tries=0|fix_empty=0|gate=none" \
  "rc=$_p29_rc|$(_g29 "'|'.join('%s=%s' % (k, d['groups']['G1'].get(k) or 0) for k in ('fails', 'fix_tries', 'fix_empty')) + '|gate=' + str((d['groups']['G1'].get('gate') or {}).get('verdict', 'none'))")"
assert_eq "patch: the ledger row does not say by the person" "row=1|person=0|label=not PERSON" "$(python3 - <<'PY'
import json, re
try:
    rows = [r for r in json.load(open(".temper/evidence/plan.json")) if isinstance(r, dict)]
except (OSError, ValueError):
    rows = []
mine = [r for r in rows if re.search(r"^plan patch: G1 Validate: .*true.* -> .*bash run-g1\.sh", str(r.get("claim")))]
pat = [r for r in rows if str(r.get("claim")).startswith("plan patch")]
print("row=%d|person=%d|label=%s" % (len(mine), sum(1 for r in pat if "person" in str(r.get("claim")).lower()),
                                     "PERSON" if any(r.get("label") == "PERSON" for r in pat) else "not PERSON"))
PY
)"
_pp; sed -i '/^\*\*Validate:\*\*/d' .temper/specs/demo/tasks.md
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
h = approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md"))   # the plan as approved had no Validate line
for p in (".temper/build-state.json", ".temper/groups.json"):
    d = json.load(open(p)); d["plan_hash"] = h; json.dump(d, open(p, "w"), indent=2)
PY
"$TEMPER" plan patch G1 --cmd 'bash v.sh' >/dev/null 2>&1; _p29_rc=$?
assert_eq "patch: a missing Validate line is inserted" "rc=0|**Validate:** \`bash v.sh\`|plan_hash=digest" \
  "rc=$_p29_rc|$(awk '/^## Group G1/{g=1} g && d {print; exit} g && /^\*\*Depends:\*\*/{d=1}' .temper/specs/demo/tasks.md)|plan_hash=$(python3 -c "
import json, sys; sys.path.insert(0, sys.argv[1]); import approval, tasks_md
print('digest' if json.load(open('.temper/build-state.json')).get('plan_hash') == approval.plan_digest(tasks_md.parse('.temper/specs/demo/tasks.md')) else 'other')" "$REPO_ROOT/scripts")"
# patch: a Validate line that is there with no backquoted command (empty, or prose) is replaced, not left beside a
# second one the plan would still read as its command (R4-7)
_broken29() { # _broken29 <line>: _pp with G1's Validate line replaced by <line>, the approved hash following it
  _pp
  python3 - "$1" <<'PY'
import sys
p = ".temper/specs/demo/tasks.md"
s = open(p).read()
i = s.index("**Validate:**")
open(p, "w").write(s[:i] + sys.argv[1] + s[s.index("\n", i):])
PY
  python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
h = approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md"))
for p in (".temper/build-state.json", ".temper/groups.json"):
    d = json.load(open(p)); d["plan_hash"] = h; json.dump(d, open(p, "w"), indent=2)
PY
}
_v29() { # G1's Validate line(s) as they stand: how many, and the first
  printf '%s line(s), first: %s' \
    "$(awk '/^## Group G1/{g=1; next} /^## /{g=0} g && /^\*\*Validate:\*\*/{c++} END{print c+0}' .temper/specs/demo/tasks.md)" \
    "$(awk '/^## Group G1/{g=1; next} /^## /{g=0} g && /^\*\*Validate:\*\*/{print; exit}' .temper/specs/demo/tasks.md)"
}
_broken29 '**Validate:**'
"$TEMPER" plan patch G1 --cmd 'bash v.sh' >/dev/null 2>&1; _p29_e_rc=$?; _p29_e="$(_v29)"
_broken29 '**Validate:** run the suite'
"$TEMPER" plan patch G1 --cmd 'bash v.sh' >/dev/null 2>&1; _p29_p_rc=$?; _p29_p="$(_v29)"
assert_eq "patch: a Validate line with no backquoted command, empty or prose, is replaced by the patched one" \
  "empty=0|1 line(s), first: **Validate:** \`bash v.sh\`|prose=0|1 line(s), first: **Validate:** \`bash v.sh\`" \
  "empty=$_p29_e_rc|$_p29_e|prose=$_p29_p_rc|$_p29_p"
_amplan29 | m_setup; _built29 1 src/a.sh
_p29_before="$(_g29 "d['tasks']['1'].get('status')")"
"$TEMPER" plan patch task 1 --cmd 'test -s src/a.sh' >/dev/null 2>&1; _p29_rc=$?
assert_eq "patch: a changed Test line reopens its passed task" "before=passed|rc=0|after=reopened" \
  "before=$_p29_before|rc=$_p29_rc|after=$(_g29 "'reopened' if d['tasks']['1'].get('status') not in ('passed', 'running', 'failed') else d['tasks']['1'].get('status')")"
_amplan29 | m_setup
assert_eq "patch: a failed static row refuses the patch and restores the file" "refused" \
  "$(_try29 'task test command|not declared|does not exist' patch task 1 --cmd 'bash unit/missing_test.sh')"
_amplan29 | m_setup
_p29_out="$("$TEMPER" plan patch task 2 --add-file src/new.sh 2>&1)"; _p29_rc=$?
assert_eq "patch: --add-file takes a file outside the approved set and adds it to approved_files" \
  "rc=0|line=1|approved=True|hash=digest|entry=patch" \
  "rc=$_p29_rc|line=$(grep -A1 '^### Task 2' .temper/specs/demo/tasks.md | grep '^\*\*File:\*\*' | grep -c '`src/new.sh`')|$(python3 - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
s = json.load(open(".temper/build-state.json"))
try:
    e = [x for x in json.load(open(".temper/evidence/amendments.json")) if isinstance(x, dict)]
except (OSError, ValueError):
    e = []
print("approved=%s|hash=%s|entry=%s" % ("src/new.sh" in (s.get("approved_files") or []),
      "digest" if s.get("plan_hash") == approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md")) else "other",
      ",".join(str(x.get("kind")) for x in e) or "none"))
PY
)"
# the question that offers a patch shows the command as the plan has it, and the commit card shows the new one word
# for word
_pp; sed -i 's|^\*\*Validate:\*\* `true`|**Validate:** `bash slow-g1.sh --all`|' .temper/specs/demo/tasks.md
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
h = approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md"))   # the plan as approved holds the slow command
for p in (".temper/build-state.json", ".temper/groups.json"):
    d = json.load(open(p)); d["plan_hash"] = h; json.dump(d, open(p, "w"), indent=2)
p = ".temper/groups.json"
d = json.load(open(p))
d["groups"]["G1"].update(status="running", fails=1, fix_tries=1, fix_empty=1,
                         gate={"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s", "ran": True, "timeout_s": 600,
                               "fail_lines": ["x"]})
d.setdefault("tasks", {}).update({"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}})
json.dump(d, open(p, "w"), indent=2)
PY
_p29_q="$(nx "o = next((x for x in d['ask']['options'] if any(' plan patch ' in c for c in x.get('calls') or [])), None); 'patch offered' if o else 'no patch'; ('patch offered' if o else 'no patch') + '|' + ('old command shown' if 'bash slow-g1.sh --all' in d['ask']['question']['question'] else 'old command not shown')")"
_p29_call="$(nx "o = next(x for x in d['ask']['options'] if any(' plan patch ' in c for c in x.get('calls') or [])); next(c for c in o['calls'] if ' plan patch ' in c)" 2>/dev/null)"
[[ "$_p29_call" == *"plan patch "* ]] && bash -c "${_p29_call//\{answer\}/bash fast-g1.sh --quick}" >/dev/null 2>&1
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
gpass review; "$TEMPER" state advance review_complete check >/dev/null 2>&1
gpass check   # the run asks at every stage: check.pass carries the commit card (scripts/card.py kind_of)
assert_eq "patch: the question and the card show the command word for word" \
  "patch offered|old command shown|patched|card shows the new command" \
  "$_p29_q|$(grep -c '^\*\*Validate:\*\* `bash fast-g1.sh --quick`' .temper/specs/demo/tasks.md | sed 's/^1$/patched/;s/^0$/not patched/')|$("$TEMPER" card 2>/dev/null | grep -cF 'bash fast-g1.sh --quick' >/dev/null && echo 'card shows the new command' || echo 'card does not show it')"

# amend: a file only a later task of the group declares is the plan's (Loop back to Plan), not the rule's
_amplan29 | m_setup; "$TEMPER" task start 1 >/dev/null 2>&1
"$TEMPER" task blocked 1 --needs src/b.sh --reason 'the test of a needs the b event, written in src/b.sh' >/dev/null 2>&1
"$TEMPER" task test 1 --phase red >/dev/null 2>&1; "$TEMPER" task gate 1 --model m >/dev/null 2>&1
assert_eq "amend: refused for a file only a later task of the group declares, and the run asks with Loop back to Plan first" \
  "refused|ask:back" "$(_try29 'later task' amend task 1 --add-file src/b.sh)|$(nx "d['action'] + ':' + str(((d.get('ask') or {}).get('options') or [{}])[0].get('id'))")"
# amend: a step back to Plan keeps plan_hash until the new approval; the amendment waits for that approval
_am29; "$TEMPER" state loop build plan --reason 'the plan changes' >/dev/null 2>&1
assert_eq "amend: refused after a step back to Plan, before the new approval" "refused" \
  "$(_try29 'at Plan' amend task 2 --add-file src/a.sh)"
# amend: a new approval starts the list of the plan since the approval again (the card lists amendments.json)
_am29; "$TEMPER" plan amend task 2 --add-file src/a.sh >/dev/null 2>&1
_a29_n="$(python3 -c "import json; print(len(json.load(open('.temper/evidence/amendments.json'))))" 2>/dev/null || echo 0)"
"$TEMPER" state loop build plan --reason 'the plan changes' >/dev/null 2>&1
gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "amend: a new approval of the plan leaves no change of the plan before it in amendments.json" "before=1|after=0" \
  "before=$_a29_n|after=$(python3 -c "import json; print(len(json.load(open('.temper/evidence/amendments.json'))))" 2>/dev/null || echo 0)"
# patch: a passed task whose Test line changes is reopened by the CLI's group reopen; when that reopen cannot run (the
# group has no worktree any more), the patch is refused before it writes or spends anything
_amplan29 | m_setup; _built29 1 src/a.sh
git worktree remove --force "$(_g29 "d['groups']['G1'].get('worktree', '')")" >/dev/null 2>&1
python3 -c "
import json
p = '.temper/groups.json'
d = json.load(open(p)); d['groups']['G1'].pop('worktree', None)
json.dump(d, open(p, 'w'), indent=2)"
assert_eq "patch: a changed Test line whose passed task cannot be reopened is refused, and nothing is written or spent" "refused|task1=passed" \
  "$(_try29 'not started|reopen' patch task 1 --cmd 'test -s src/a.sh')|task1=$(_g29 "d['tasks']['1'].get('status')")"
# patch (lane E, RE8): the reopen's other refusals are checked before the patch writes too: a commit on the group's branch
# the CLI did not record, and an upstream gate the reopen commit needs (ADR 0009)
_amplan29 | m_setup; _built29 1 src/a.sh
_p29_wt="$(_g29 "d['groups']['G1'].get('worktree', '')")"
echo human > "$_p29_wt/human.txt"
git -C "$_p29_wt" add human.txt >/dev/null 2>&1; git -C "$_p29_wt" -c user.email=h@example.com -c user.name=H commit -qm 'a commit by a human' >/dev/null 2>&1
_p29_foreign="$(_try29 'did not record|nobody accepted' patch task 1 --cmd 'test -s src/a.sh')"
_amplan29 | m_setup; _built29 1 src/a.sh
python3 -c "
import json
p = '.temper/gates.json'; d = json.load(open(p)); d['plan'] = {'verdict': 'FAIL', 'requirements': [{'name': 'x', 'pass': False, 'detail': 'x'}]}
json.dump(d, open(p, 'w'))"
_p29_up="$(_try29 'upstream|ADR 0009' patch task 1 --cmd 'test -s src/a.sh')"
assert_eq "patch: a changed Test line whose reopen would meet an unrecorded commit or an unmet upstream gate is refused, and nothing is written or spent" \
  "foreign=refused|upstream=refused|task1=passed" "foreign=$_p29_foreign|upstream=$_p29_up|task1=$(_g29 "d['tasks']['1'].get('status')")"
# patch: a group with no Validate line and no group Depends line gets the line in its own head, not in a task's block
_pp; sed -i -e '/^\*\*Validate:\*\*/d' -e '/^## Group G1/,/^### /{/^\*\*Depends:\*\*/d}' .temper/specs/demo/tasks.md
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
h = approval.plan_digest(tasks_md.parse(".temper/specs/demo/tasks.md"))   # the plan as approved: G1 has neither line
for p in (".temper/build-state.json", ".temper/groups.json"):
    d = json.load(open(p)); d["plan_hash"] = h; json.dump(d, open(p, "w"), indent=2)
PY
"$TEMPER" plan patch G1 --cmd 'bash v.sh' >/dev/null 2>&1; _p29_rc=$?
assert_eq "patch: a missing Validate line of a group with no Depends line goes into the group's head" "rc=0|G1=bash v.sh|in a task=0" \
  "rc=$_p29_rc|G1=$(_parse29 | python3 -c "import json,sys; print(json.load(sys.stdin)['groups'][0]['validate'])")|in a task=$(sed -n '/^### Task/,$p' .temper/specs/demo/tasks.md | grep -c '^\*\*Validate:\*\*')"
# patch: --add-file of a path with no dot and no slash (Makefile) is written so the plan reads it as a file
_amplan29 | m_setup
"$TEMPER" plan patch task 2 --add-file Makefile >/dev/null 2>&1; _p29_rc=$?
assert_eq "patch: --add-file of a file with no dot and no slash is a file of the task as the plan reads it" "rc=0|files=src/b.sh,Makefile|hash=digest" \
  "rc=$_p29_rc|files=$(_parse29 | python3 -c "import json,sys; print(','.join(next(t for t in json.load(sys.stdin)['tasks'] if t['n'] == 2)['files']))")|hash=$(python3 -c "
import json, sys; sys.path.insert(0, sys.argv[1]); import approval, tasks_md
print('digest' if json.load(open('.temper/build-state.json')).get('plan_hash') == approval.plan_digest(tasks_md.parse('.temper/specs/demo/tasks.md')) else 'other')" "$REPO_ROOT/scripts")"
# patch: the group question's Change the group's command runs the new command once on the base before its check
_pp
python3 -B - <<'PY'
import json
p = ".temper/groups.json"
d = json.load(open(p))
d["groups"]["G1"].update(status="running", fails=1, fix_tries=1, fix_empty=1,
                         gate={"verdict": "FAIL", "reason": "group G1 Validate failed", "ran": True, "fail_lines": ["x"]})
d.setdefault("tasks", {}).update({"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}})
json.dump(d, open(p, "w"), indent=2)
json.dump({"result": "pass", "plan": {}}, open(".temper/evidence/baseline.json", "w"))
PY
_p29_calls="$(nx "o = next(x for x in d['ask']['options'] if x.get('id') == 'change-command'); chr(10).join(o['calls'])" 2>/dev/null)"
while IFS= read -r _c; do [[ "$_c" == *temper* ]] && bash -c "${_c//\{answer\}/bash v29.sh}" >/dev/null 2>&1; done <<<"$_p29_calls"
assert_eq "patch: after Change the group's command the new command runs once on the base before the group is checked" \
  "auto|baseline plan" "$(nx "d['action'] + '|' + ' '.join(c.split(' ', 1)[1] if ' ' in c else c for c in d.get('calls') or [])")"
cd "$WORKDIR" || true
rm -rf "$T29"
