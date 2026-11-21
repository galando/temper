# Case file 84: review 4 of the adversarial review of 9.8.5, rules 7 and 8 (the lock on the acceptance tests, evidence
# resolve and temper repair close, the repair commit, the recheck and the revert). Sourced by test-temper.sh; its helpers
# (fresh, gpass, m_setup, m_field) are used here. Every assertion name starts with "review 4:".
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file (as case file 45 builds its projects) ---
_tasks84() { # _tasks84 <Validate> <Integration> <Test>: the demo plan, one group, one task with those commands
  printf '%s\n' '# Tasks: demo' '' "**Integration:** \`$2\`" '' '## Group G1: Core' '**Depends:** none' "**Validate:** \`$1\`" \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    "**Test:** \`$3\`" '**Cases:**' '- a holds' '- [x] done'
}
_row84() { # _row84 <stage> <row name>: pass of that row of the stage's verdict in gates.json, or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else str(r.get("pass")))
PY
}
_verdict84() { python3 -c "import json,sys; print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict', 'none'))" "$1" 2>/dev/null || echo none; }
_built84() { # the group and its task passed, as the CLI's group gate leaves them
  python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d["groups"]["G1"].update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
}
_x84() { # _x84 <python code over d, the JSON of temper next, that sets r>: prints r
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
r = None
exec(sys.argv[1])
print(r)
PY
}
_ledger84() { # _ledger84 <stage> <python expression over e, the entries of the stage's ledger>
  python3 -c "import json,sys; e = json.load(open('.temper/evidence/%s.json' % sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null || echo none
}
_done84() { # _done84 <file>...: Review's completion row, naming the files read
  local f args=()
  for f in "$@"; do args+=(--read "$f"); done
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC "${args[@]}" >/dev/null 2>&1 \
    || "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC >/dev/null 2>&1
}
_review84() { # _review84 <severity>: as case file 45's _review45: a grouped run of a git repository, approved, built and
              # integrated by the CLI's own calls, at a failed Review with one finding of that severity on src/demo.sh
  fresh
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
  sed -i '/block-on/d' .claude/temper.config
  printf 'a=1\nb=2\nc=3\n' > src/demo_test.sh; git add src/demo_test.sh; git commit -q -m tests
  git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  _tasks84 true true true > .temper/specs/demo/tasks.md
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  python3 - "$(git rev-parse HEAD)" <<'PY'
import json, sys
d = {"version": 1, "slug": "demo", "cli_commits": [],
     "groups": {"G1": {"status": "passed", "worktree": "", "branch": "temper/demo/G1", "confirmed": True, "gate": {"verdict": "PASS"}}},
     "tasks": {"1": {"status": "passed", "group": "G1"}},
     "integration": {"verdict": "PASS", "reason": "", "group": None, "files": [], "ts": "x", "head": sys.argv[1], "merged": True}}
json.dump(d, open(".temper/groups.json", "w"))
PY
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase red -- false >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase green -- true >/dev/null 2>&1
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity "$1" --label PROVEN >/dev/null 2>&1
  _done84 src/demo.sh src/demo_test.sh
  "$TEMPER" gate review >/dev/null 2>&1
}
_acc84() { # a run at Build whose acceptance test (exit 1) is locked
  _tasks84 true true true | m_setup
  "$TEMPER" acceptance start >/dev/null 2>&1
  mkdir -p .temper/specs/demo/acceptance; printf 'exit 1\n' > .temper/specs/demo/acceptance/accept_test.sh
  "$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1
}


# --- rule 7 (row D36): a locked acceptance test changed after the lock is locked again through `acceptance skip` ---
# A lock is taken once (check_run.acc_lock refuses a second one), but `acceptance skip` overwrites the lock record with a
# skip, and the lock call after it is taken as a first lock: a builder changes a locked test and locks it again, and the
# Build gate's row says the tests are unchanged since they were locked. Neither call is an option of any question.
_acc84
printf 'exit 0\n' > .temper/specs/demo/acceptance/accept_test.sh
_r84_skip="$("$TEMPER" acceptance skip --reason 'no tests' >/dev/null 2>&1 && echo taken || echo refused)"
_r84_relock="$("$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1 && echo taken || echo refused)"
_built84
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 4: R7a a locked acceptance test changed after the lock is not locked again through skip: skip and the second lock are refused, the Build row fails" \
  "skip=refused|lock=refused|row=False" \
  "skip=$_r84_skip|lock=$_r84_relock|row=$(_row84 build 'acceptance tests written before Build')"


# --- rule 7 (row D36: "locked by digest before the first task gate"): a lock taken after a task passed its gate ---
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' '**Context:**' \
  'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' '**Test:** `test -f src/a.sh`' '**Cases:**' \
  '- a holds' '- [ ] done' | m_setup
"$TEMPER" task start 1 >/dev/null 2>&1
"$TEMPER" task test 1 --phase red >/dev/null 2>&1
mkdir -p .claude/worktrees/temper-demo-T1/src; echo built > .claude/worktrees/temper-demo-T1/src/a.sh
"$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
_r84_task="$(m_field 1 status)"
"$TEMPER" acceptance start >/dev/null 2>&1
mkdir -p .temper/specs/demo/acceptance; printf 'exit 0\n' > .temper/specs/demo/acceptance/accept_test.sh
_r84_late="$("$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1 && echo taken || echo refused)"
_built84
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 4: R7b acceptance tests locked after a task passed its gate are refused, or fail the Build row: tests come first" \
  "task=passed|lock=refused|row=not passed" \
  "task=$_r84_task|lock=$_r84_late|row=$([[ "$(_row84 build 'acceptance tests written before Build')" == True ]] && echo passed || echo 'not passed')"


# --- rule 7 for a repair (ADR 0021: "for a finding marked proof: test, the CLI ran a RED before the fix and a GREEN after
# it on unchanged test files"): the fixer fixes first, then records as RED a command that fails without running the test ---
_review84 high
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo exits 0 on error' --severity high --proof test --label PROVEN >/dev/null 2>&1
_done84 src/demo.sh src/demo_test.sh
"$TEMPER" gate review >/dev/null 2>&1
"$TEMPER" repair start --stage review >/dev/null 2>&1 || true
echo 'echo fixed >&2; exit 1' > src/demo.sh
"$TEMPER" repair test 3 --phase red -- sh -c 'exit 1' src/demo_test.sh >/dev/null 2>&1 || true
"$TEMPER" repair test 3 --phase green -- sh src/demo_test.sh >/dev/null 2>&1 || true
"$TEMPER" repair commit >/dev/null 2>&1 || true
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done \
  < <(_x84 "r = '\n'.join(c for a in d.get('agents') or [] for c in a.get('before') or [])")
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'recheck #3: fixed' --exit 0 --label PROVEN >/dev/null 2>&1
_done84 src/demo.sh
"$TEMPER" repair close >/dev/null 2>&1 || true
assert_eq "review 4: R7c a behaviour finding (proof test) is not resolved by a RED run after the fix that never ran the test" \
  "#3 open" "#3 $(_ledger84 review "'resolved' if (e[2].get('resolved') or {}).get('fixed_by') else 'open'")"
