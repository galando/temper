# Case file 45 (WP07): rules 7 to 11 and the rows of pull request 115 in docs/plans/one-go/done.md. Sourced by
# test-temper.sh; its helpers (fresh, gpass, gfail, m_setup, nx, vw, labels, _unattended) are used here. The first word of
# every assertion is the token of its row; a token still expected to fail is a line of scripts/selftest/expected-fail.txt.
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_x45() { # _x45 <python code over d, the JSON of temper next, that sets r>: prints r
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def q(d):
    return (d.get("ask") or {}).get("question") or {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def ids(d):
    return [o.get("id") for o in opts(d)]
def calls(d):
    return list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]
r = None
exec(sys.argv[1])
print(r)
PY
}
_row45() { # _row45 <stage> <row name>: pass of that row of the stage's verdict in gates.json, or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else ("%s:%s" % (r.get("pass"), r.get("state")) if r.get("state") else str(r.get("pass"))))
PY
}
_verdict45() { python3 -c "import json,sys; print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict', 'none'))" "$1" 2>/dev/null || echo none; }
_gjson45() { # _gjson45 <python expression over g, the groups.json>: prints it
  python3 -c "import json,sys; g = json.load(open('.temper/groups.json')); print(eval(sys.argv[1]))" "$1" 2>/dev/null || echo none
}
_repo45() { # a fresh git repository under the run: every file but the run's own in one commit, on the run's branch
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_nogit45() { (cd "$WORKDIR" && rm -rf .git src); }

_stop45() { # _stop45 [ERE]: "stop" when next is a question or a recorded stop (the park call) and no call of the CLI's own
            # action matches the ERE; else what next does
  python3 - "${1:-}" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
bad = re.compile(sys.argv[1]) if sys.argv[1] else None
try:
    d = json.loads(sys.argv[2])
except ValueError:
    print("no next")
    sys.exit(0)
a = d.get("action")
calls = list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]
short = ",".join(re.sub(r"^\S*/temper ", "", c)[:60] for c in calls[:2]) or ",".join(str(x.get("type")) for x in d.get("agents") or [])
if a in ("auto", "work") and bad and any(bad.search(c) for c in calls):
    print("%s runs %s" % (a, short))
elif a == "ask" or (a == "auto" and calls and all(re.search(r"\spark\s", c) and "--end" not in c for c in calls)):
    print("stop")
else:
    print("%s %s" % (a, short))
PY
}
_park45() { # runs the call of next when next is the recorded stop (an auto park call); prints yes or no
  local c ran=no
  while IFS= read -r c; do
    [[ -n "$c" ]] && { bash -c "$c" >/dev/null 2>&1; ran=yes; }
  done < <(_x45 "r = '\n'.join(c for c in d.get('calls') or [] if re.search(r'\spark\s', c) and '--end' not in c) if d.get('action') == 'auto' else ''")
  echo "$ran"
}
_runopt45() { # _runopt45 <option id>: runs the calls of that option of the question next asks, the typed parts filled
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1
  done < <(_x45 "o = opt(d, '$1') or {}; r = '\n'.join(c.replace('{reason}', 'a reason').replace('{answer}', 'the person') for c in o.get('calls') or [])")
}
_ledger45() { # _ledger45 <stage> <python expression over e, the entries of the stage's ledger>
  python3 -c "import json,sys; e = json.load(open('.temper/evidence/%s.json' % sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null || echo none
}
_tasks45() { # _tasks45 <Validate> <Integration> <Test>: the demo plan, one group, one task with those commands
  printf '%s\n' '# Tasks: demo' '' "**Integration:** \`$2\`" '' '## Group G1: Core' '**Depends:** none' "**Validate:** \`$1\`" \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    "**Test:** \`$3\`" '**Cases:**' '- a holds' '- [x] done'
}
_done45() { # _done45 <file>...: Review's completion row, naming the files read where the CLI takes the list (WP18)
  local f args=()
  for f in "$@"; do args+=(--read "$f"); done
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC "${args[@]}" >/dev/null 2>&1 \
    || "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC >/dev/null 2>&1
}
_review45() { # _review45 <severity>: a grouped run of a git repository, approved, built and integrated by the CLI's own calls,
              # at a failed Review with one finding of that severity on src/demo.sh; the completion row names the files read
  fresh; _repo45; sed -i '/block-on/d' .claude/temper.config
  printf 'a=1\nb=2\nc=3\n' > src/demo_test.sh; git add src/demo_test.sh; git commit -q -m tests
  git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  _tasks45 true true true > .temper/specs/demo/tasks.md
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  python3 - "$(git rev-parse HEAD)" <<'PY'
import json, sys
d = {"version": 1, "slug": "demo", "cli_commits": [],
     "groups": {"G1": {"status": "passed", "worktree": "", "branch": "temper/demo/G1", "confirmed": True, "gate": {"verdict": "PASS"}}},
     "tasks": {"1": {"status": "passed", "group": "G1"}},
     "integration": {"verdict": "PASS", "reason": "", "group": None, "files": [], "ts": "x", "head": sys.argv[1], "merged": True}}
json.dump(d, open(".temper/groups.json", "w"))
PY
  # the tests Build ran first failing, then passing (a built run's ledger: Build's gate runs again on it after a repair)
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase red -- false >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase green -- true >/dev/null 2>&1
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity "$1" --label PROVEN >/dev/null 2>&1
  _done45 src/demo.sh src/demo_test.sh
  "$TEMPER" gate review >/dev/null 2>&1
}
_resolved45() { _ledger45 review "'resolved' if (e[0].get('resolved') or {}).get('fixed_by') else 'open'"; }

_check45() { # a run at Check, every stage before it passed
  fresh; gpass intent plan build review
  for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
}

# --- D36a, D36b: rule 7, tests first, and the tests that gate the code are locked before the code ---
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' '**Context:**' \
  'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- a holds' \
  '- [ ] done' | m_setup
"$TEMPER" task start 1 >/dev/null 2>&1
mkdir -p .claude/worktrees/temper-demo-T1/src; echo built > .claude/worktrees/temper-demo-T1/src/a.sh
"$TEMPER" task test 1 --phase green >/dev/null 2>&1
_d36a_out="$("$TEMPER" task gate 1 --model haiku 2>&1)"; _d36a_rc=$?
assert_eq "D36a a task gate with a passing run and no failing run before it is refused" "refused|not passed" \
  "$([[ $_d36a_rc -ne 0 ]] && grep -q '^FAIL' <<<"$_d36a_out" && echo refused || echo "rc $_d36a_rc")|$([[ "$(m_field 1 status)" == passed ]] && echo passed || echo 'not passed')"

_tasks45 true true true | m_setup
"$TEMPER" acceptance start >/dev/null 2>&1
mkdir -p .temper/specs/demo/acceptance; printf 'exit 1\n' > .temper/specs/demo/acceptance/accept_test.sh
"$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1
_d36b_lock="$(python3 -c "import json; f = json.load(open('.temper/evidence/acceptance-lock.json')).get('files') or {}; print('locked' if len(f.get('.temper/specs/demo/acceptance/accept_test.sh', '')) == 64 else 'not locked')" 2>/dev/null || echo 'not locked')"
printf 'exit 0\n' > .temper/specs/demo/acceptance/accept_test.sh
python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d["groups"]["G1"].update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "D36b a locked acceptance test changed after the lock fails the Build gate, before Review" "locked|row=False|build=FAIL|at build" \
  "$_d36b_lock|row=$(_row45 build 'acceptance tests written before Build')|build=$(_verdict45 build)|at $("$TEMPER" state get next_stage 2>/dev/null)"

# --- D37a, D37b, D37c, D37f: rule 8, a finding is resolved only by the CLI, for its own repair commit, after a recheck ---
_review45 high
_d37a_rc="$("$TEMPER" evidence resolve --stage review --id 1 --fixed-by 'no such commit' >/dev/null 2>&1; echo $?)"
"$TEMPER" gate review >/dev/null 2>&1
assert_eq "D37a evidence resolve with a note in the place of a commit is refused, and the Review gate stays FAIL on the finding" \
  "refused|FAIL|no blocking findings=False|open" \
  "$([[ "$_d37a_rc" != 0 ]] && echo refused || echo taken)|$(_verdict45 review)|no blocking findings=$(_row45 review 'no blocking findings')|$(_resolved45)"

_review45 high
echo 'echo by hand' > src/demo.sh; git commit -q --no-verify -am 'a fix by hand'
_d37b_hand="$("$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$(git rev-parse HEAD)" >/dev/null 2>&1 && echo taken || echo refused)"
_review45 high
echo 'note' > .temper/specs/demo/notes.md; git add -f .temper/specs/demo/notes.md; git commit -q --no-verify -m 'a commit of the CLI'
python3 -c "import json, subprocess; p = '.temper/groups.json'; d = json.load(open(p)); d.setdefault('cli_commits', []).append(subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE).stdout.decode().strip()); json.dump(d, open(p, 'w'))"
_d37b_cli="$("$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$(git rev-parse HEAD)" >/dev/null 2>&1 && echo taken || echo refused)"
_review45 high
"$TEMPER" repair start --stage review >/dev/null 2>&1 || true
echo 'echo fixed >&2; exit 1' > src/demo.sh
"$TEMPER" repair commit >/dev/null 2>&1 || true
_d37b_norecheck="$("$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$(git rev-parse HEAD)" >/dev/null 2>&1 && echo taken || echo refused)"
assert_eq "D37b evidence resolve is refused for a commit the CLI did not record as its repair, and while no recheck row follows it" \
  "by hand=refused|not a repair=refused|no recheck=refused|open" \
  "by hand=$_d37b_hand|not a repair=$_d37b_cli|no recheck=$_d37b_norecheck|$(_resolved45)"

_review45 high
_d37c_head="$(git rev-parse HEAD)"
"$TEMPER" repair start --stage review >/dev/null 2>&1 || true
printf 'a=1\nc=3\n' > src/demo_test.sh; echo 'echo fixed >&2; exit 1' > src/demo.sh
"$TEMPER" repair commit >/dev/null 2>&1 || true
assert_eq "D37c a repair that removes a line of a test file is not committed or resolved: the run asks and shows the line" \
  "not committed|repair.stop|shows b=2|open" \
  "$([[ "$(git rev-parse HEAD)" == "$_d37c_head" ]] && echo 'not committed' || echo committed)|$(_x45 "r = (d.get('ask') or {}).get('id')")|$(_x45 "r = 'shows b=2' if 'b=2' in json.dumps(d.get('ask') or {}) else 'no line'")|$(_resolved45)"

_review45 high
"$TEMPER" repair start --stage review >/dev/null 2>&1 || true
echo 'echo fixed >&2; exit 1' > src/demo.sh
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN >/dev/null 2>&1
"$TEMPER" repair commit >/dev/null 2>&1 || true
"$TEMPER" repair close >/dev/null 2>&1 || true
_d37f_early="$(_resolved45)"
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN >/dev/null 2>&1
"$TEMPER" repair close >/dev/null 2>&1 || true
_d37f_nomark="$(_resolved45)"
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done \
  < <(_x45 "r = '\n'.join(c for a in d.get('agents') or [] for c in a.get('before') or [])")
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN >/dev/null 2>&1
_done45 src/demo.sh
"$TEMPER" repair close >/dev/null 2>&1 || true
assert_eq "D37f a recheck row written before the repair commit, or before the recheck's launch mark, resolves nothing; one in order does" \
  "before the commit=open|before the mark=open|in order=resolved" \
  "before the commit=$_d37f_early|before the mark=$_d37f_nomark|in order=$(_resolved45)"

# --- D38a, D38b, D38c, D38e: rule 9, every repeat is counted against one budget ---
_used45() { # _used45 [key [kind]]: the entries of the budget record, of that key and kind when given
  python3 - "${1:-}" "${2:-}" <<'PY'
import json, sys
try:
    u = json.load(open(".temper/budget.json")).get("used") or []
except (OSError, ValueError, AttributeError):
    u = []
print(sum(1 for x in u if (not sys.argv[1] or x.get("key") == sys.argv[1]) and (not sys.argv[2] or x.get("kind") == sys.argv[2])))
PY
}
_sum45() { cat .temper/budget.json .temper/build-state.json .temper/groups.json 2>/dev/null | cksum; }
_groups45() { # _groups45 <n>: a run at Build whose plan has n groups, each started and each with a failed check
  fresh
  python3 - "$1" <<'PY'
import json, sys
n = int(sys.argv[1])
t = ["# Tasks: demo", "", "**Integration:** `true`"]
g = {"version": 1, "slug": "demo", "groups": {}, "tasks": {}}
for i in range(1, n + 1):
    t += ["", "## Group G%d: Part %d" % (i, i), "**Depends:** none", "**Validate:** `true`", "**Context:**", "x", "",
          "### Task %d: part %d" % (i, i), "**File:** `src/p%d.sh`" % i, "**Depends:** none", "**Test:** `true`", "**Cases:**", "- p", "- [x] done"]
    g["groups"]["G%d" % i] = {"status": "running", "worktree": "w%d" % i, "branch": "temper/demo/G%d" % i, "fails": 1,
                              "gate": {"verdict": "FAIL", "reason": "group G%d Validate failed (exit 1): true" % i, "ran": True, "fail_lines": ["x"]}}
    g["tasks"][str(i)] = {"status": "passed", "group": "G%d" % i}
open(".temper/specs/demo/tasks.md", "w").write("\n".join(t) + "\n")
json.dump(g, open(".temper/groups.json", "w"))
PY
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
}
fresh; gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gfail review "no blocking findings" "1 open high finding"; "$TEMPER" state loop review build --reason 'a finding' >/dev/null 2>&1
_d38a_kinds="step back=$(_used45 gate:review 'step back')"
_check45
gfail check "tests pass" "the latest run of a test command failed: unit"; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1
_d38a_kinds+="|run again=$(_used45 gate:check 'run again')"
_groups45 1; "$TEMPER" group fix G1 >/dev/null 2>&1
_d38a_kinds+="|group fix=$(_used45 group:G1 'group fix')"
"$TEMPER" group fix G1 >/dev/null 2>&1
_d38a_before="$(_sum45)"; _d38a_out="$("$TEMPER" group fix G1 2>&1)"; _d38a_rc=$?
assert_eq "D38a each kind of repeat spends one, and a third repeat for one failure is refused and writes nothing" \
  "step back=1|run again=1|group fix=1|third=1:BLOCKED:unchanged" \
  "$_d38a_kinds|third=$_d38a_rc:$(head -1 <<<"$_d38a_out" | cut -d: -f1):$([[ "$(_sum45)" == "$_d38a_before" ]] && echo unchanged || echo written)"

_groups45 4
for _g in G1 G1 G2 G2 G3 G3; do "$TEMPER" group fix "$_g" >/dev/null 2>&1; done
_d38b_before="$(_sum45)"; _d38b_out="$("$TEMPER" group fix G4 2>&1)"; _d38b_rc=$?
assert_eq "D38b the seventh repeat of a run is refused and writes nothing" "six=6|seventh=1:BLOCKED:unchanged" \
  "six=$(_used45)|seventh=$_d38b_rc:$(head -1 <<<"$_d38b_out" | cut -d: -f1):$([[ "$(_sum45)" == "$_d38b_before" ]] && echo unchanged || echo written)"

_check45
for _i in 1 2; do gfail check "tests pass" "the latest run of a test command failed: unit"; "$TEMPER" state redo check --reason 'again' >/dev/null 2>&1; done
gfail check "tests pass" "the latest run of a test command failed: unit"
_d38c_n="$(_used45)"
TEMPER_BUDGET=off "$TEMPER" state redo check --reason 'the variable says off' >/dev/null 2>&1; _d38c_env=$?
"$TEMPER" state redo check --reason 'the flag says so' --no-budget >/dev/null 2>&1; _d38c_arg=$?
gfail check "tests pass" "the latest run of a test command failed: unit"
_d38c_next="$(_x45 "a = d.get('ask') or {}
bad = [c for o in opts(d) for c in o.get('calls') or [] if re.search(r' state (redo check|loop check \\w+)', c)]
r = '%s:%s:%s' % (d.get('action'), a.get('id'), 'no refused call' if not bad else 'offers a refused call')")"
assert_eq "D38c no variable and no argument exempts a call; at the limit next is the question run.budget and offers no refused call" \
  "env=1|arg=1|count=2:2|ask:run.budget:no refused call" "env=$_d38c_env|arg=$_d38c_arg|count=$_d38c_n:$(_used45)|$_d38c_next"
# A run whatever the reuse store holds is the counted `check run --fresh` only: an inherited TEMPER_FRESH and the flag on
# `check build-checks` run nothing a kept pass holds, and spend nothing.
_check45; rm -rf .git src; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T
mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
printf 'check:\n  commands:\n    test: "echo run >> .temper/count45"\n' >> .claude/temper.config
_n45() { if [[ -f .temper/count45 ]]; then wc -l < .temper/count45 | tr -d ' '; else echo 0; fi; }
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" check run >/dev/null 2>&1; _d38c_kept="kept=$(_n45):$(_used45)"
TEMPER_FRESH=1 "$TEMPER" check run >/dev/null 2>&1; _d38c_kept+="|variable=$(_n45):$(_used45)"
"$TEMPER" check build-checks --fresh >/dev/null 2>&1; _d38c_kept+="|build-checks=$(_n45):$(_used45)"
assert_eq "D38c an inherited TEMPER_FRESH and check build-checks --fresh run nothing a kept pass holds and spend nothing" \
  "kept=1:0|variable=1:0|build-checks=1:0" "$_d38c_kept"
rm -rf .git src

_check45
printf 'fix:\n  max-loops: 9\nfeedback:\n  enabled: false\n' >> .claude/temper.config
sed -i 's/max-per-type: 2/max-per-type: 9/; s/max-total-loops: 4/max-total-loops: 99/; s/max-stages: 12/max-stages: 99/' .claude/temper.config
for _i in 1 2; do gfail check "tests pass" "the latest run of a test command failed: unit"; "$TEMPER" state redo check --reason 'again' >/dev/null 2>&1; done
gfail check "tests pass" "the latest run of a test command failed: unit"
_d38e_out="$("$TEMPER" state redo check --reason 'a third time' 2>&1)"; _d38e_rc=$?
_d38e_readers="$(grep -lE 'max-per-type|max-loops|max-total-loops|max-stages|feedback\.enabled' "$TEMPER" $(find "$REPO_ROOT/scripts" "$REPO_ROOT/scripts/guards" -maxdepth 1 -type f \( -name '*.py' -o -name '*.sh' \)) 2>/dev/null | sed "s|^$REPO_ROOT/||" | paste -sd, -)"
assert_eq "D38e the old loop keys are read by nothing: set high they change no refusal, and no script names them" \
  "third=1:BLOCKED|readers=none" "third=$_d38e_rc:$(head -1 <<<"$_d38e_out" | cut -d: -f1)|readers=${_d38e_readers:-none}"

# --- D39c, D39d: rule 10, every stop is a question or a recorded stop, and the commit card lists what a rule decided ---
# WP25: the amendment needs the plan it amends approved and its group started, so the run is a git repository at Build
# with this plan approved (m_setup), started at the approval as approve-run starts it (_ran_unattended). Each task has
# two cases, so the plan passes every static row the amendment runs on its result.
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' '**Context:**' 'x' '' \
  '### Task 1: first' '**File:** `src/other.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- a' '- a bad input is refused' '- [ ] done' '' \
  '### Task 2: second' '**File:** `src/demo.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- b' '- a bad input is refused' '- [ ] done' | m_setup
_ran_unattended
"$TEMPER" plan amend task 2 --add-file src/other.sh >/dev/null 2>&1 || true   # Task 1, before it, declares the file
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
_done45 src/demo.sh src/other.sh
gpass review; "$TEMPER" state advance review_complete check >/dev/null 2>&1
gfail check "tests pass" "the latest run of a test command failed: unit"; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1
"$TEMPER" park --verdict PARKED-NEEDS-DECISION --reason 'the stop of case D39c' >/dev/null 2>&1
"$TEMPER" park --end --answer continue >/dev/null 2>&1 || true
python3 - <<'PY'
import json
p = ".temper/gates.json"
d = json.load(open(p))
d["check"] = {"verdict": "PASS", "requirements": [{"name": "tests pass", "pass": True, "detail": "the suite passed"},
              {"name": "coverage", "pass": None, "state": "not measured", "detail": "not measured: no coverage tool for this stack"}]}
json.dump(d, open(p, "w"))
PY
"$TEMPER" state advance check_complete commit >/dev/null 2>&1
# WP25: the commit card is the card of the commit question; the run gets there by the commit gate and its own stop
"$TEMPER" gate commit >/dev/null 2>&1; _park45 >/dev/null
_d39c_card="$("$TEMPER" card 2>/dev/null)"
assert_eq "D39c the commit card lists an amendment by rule, a carried Medium finding, a check not measured, a stop with its answer and the budget used" \
  "amend|medium|not measured|stop|answer|budget" "$(python3 - "$_d39c_card" <<'PY'
import re, sys
t = sys.argv[1]
lines = t.splitlines()
print("|".join([
    "amend" if any("src/other.sh" in l and re.search(r"amend|added", l, re.I) for l in lines) else "no amendment",
    "medium" if "a missing null check" in t else "no medium",
    "not measured" if re.search(r"coverage[^\n]*not measured|not measured[^\n]*coverage", t) else "no not measured",
    "stop" if "the stop of case D39c" in t else "no stop",
    "answer" if re.search(r"answer", t, re.I) else "no answer",
    "budget" if re.search(r"(repeat|budget)[^\n]*\d", t, re.I) else "no budget"]))
PY
)"

_d39d() { # _d39d <stop>: its state in an unattended run; the recorded stop is run; then whether the rule log holds it and what next does
  _nogit45
  case "$1" in
    gate.failed) _unattended build; gfail build "RED then GREEN" "have red=0 green=0" ;;
    review.unfinished) _unattended review; gfail review "review completed" "no review completed row" ;;
    check.setup) _unattended check
      "$TEMPER" evidence add --stage check --claim 'tests: the suite (run by the CLI)' --exit 1 >/dev/null 2>&1
      "$TEMPER" evidence add --stage check --claim 'setup fault: the JDK is 21 and pom.xml needs 24' --exit 1 >/dev/null 2>&1
      gfail check "tests pass" "the latest run of a test command failed: the suite" ;;
  esac
  local st; st="$("$TEMPER" state get next_stage 2>/dev/null)"
  printf 'park=%s,' "$(_park45)"
  printf 'log=%s,' "$(python3 -c "
import json, sys
try:
    e = json.load(open('.temper/rule-log.json'))
except (OSError, ValueError):
    e = []
e = e.get('entries', []) if isinstance(e, dict) else e
print('yes' if any(isinstance(x, dict) and x.get('kind') == 'stop' and x.get('stage') == sys.argv[1] for x in e) else 'no')" "$st")"
  printf 'next=%s' "$(_x45 "r = '%s:%s' % (d.get('action'), d.get('stage'))")"
}
_d39d_got=""; _d39d_want=""
for _s in gate.failed review.unfinished check.setup; do
  _st="${_s%%.*}"; _st="${_st/gate/build}"
  _d39d_want+="$_s=park=yes,log=yes,next=ask:$_st|"; _d39d_got+="$_s=$(_d39d "$_s")|"
done
assert_eq "D39d every stop of an unattended run is a recorded stop in the rule log, then the stage's question" "$_d39d_want" "$_d39d_got"

# --- D41 (M1): a fix that breaks the Integration suite after a pass does not strand the run ---
printf '%s\n' '# Tasks: demo' '' '**Integration:** `test ! -e src/broken`' '' '## Group G1: Core' '**Depends:** none' \
  '**Validate:** `true`' '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' \
  '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done' | m_setup
"$TEMPER" state set branch feature/demo >/dev/null 2>&1
python3 - <<'PY'
import json, subprocess
head = subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE).stdout.decode().strip()
d = json.load(open('.temper/groups.json'))
d['groups'] = {'G1': {'status': 'passed', 'worktree': '', 'branch': 'temper/demo/G1', 'confirmed': True, 'gate': {'verdict': 'PASS'}}}
d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}}
d['integration'] = {'verdict': 'PASS', 'reason': '', 'group': None, 'files': [], 'ts': 'x', 'head': head}
json.dump(d, open('.temper/groups.json', 'w'))
PY
# the first passing integrate deleted the group's branch and worktree, as at the head
git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -v "^$WORKDIR\$" | while read -r _w; do git worktree remove --force "$_w" >/dev/null 2>&1; done
git branch -D temper/demo/G1 >/dev/null 2>&1
mkdir -p src; echo broken > src/broken; git add src/broken; git commit -q -m 'a fix that breaks the suite'
_d41_out1="$("$TEMPER" integrate 2>&1)"; _d41_rc1=$?
_d41_first="rc=$_d41_rc1|$(_gjson45 "g['integration'].get('verdict')"):merged=$(_gjson45 "g['integration'].get('merged')")"
"$TEMPER" gate build >/dev/null 2>&1
_d41_gate="$(_row45 build integration)"
_d41_next="$(_x45 "r = '%s:%s' % (d.get('action'), d.get('stage'))")"
git rm -q src/broken; git commit -q -m 'the repair'
_d41_out2="$("$TEMPER" integrate 2>&1)"
_d41_out3="$("$TEMPER" integrate 2>&1)"
_d41_again="$(_gjson45 "g['integration'].get('verdict')")"
_d41_merge="$(grep -c 'not something we can merge' <<<"$_d41_out1$_d41_out2$_d41_out3")"
assert_eq "D41 a suite broken after a pass fails and asks at Build, and passes again once the code is repaired" \
  "first=rc=0|FAIL:merged=True|integration=False|next=ask:build|repaired=PASS|merge errors=0" \
  "first=$_d41_first|integration=$_d41_gate|next=$_d41_next|repaired=$_d41_again|merge errors=$_d41_merge"

# --- D42 (M2): a passed Review with an open Medium finding keeps every way on in reach ---
_check45; python3 - <<'PY'
import json
d = json.load(open(".temper/build-state.json")); d["next_stage"] = "review"; json.dump(d, open(".temper/build-state.json", "w"), indent=2)
PY
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
_done45; gpass review
assert_eq "D42 a passed Review with an open Medium finding keeps Accept a finding, Grill Me, Teach Me, Make a small change and Save for later in reach" \
  "accept-finding,grill-me,save,small-change,teach-me|empty More=0" "$(_x45 "
def walk(q, seen, dead):
    for o in (q or {}).get('options') or []:
        seen.add(o.get('id'))
        if o.get('kind') == 'more' and not ((q.get('more') or {}).get('options')):
            dead.append(1)
    if q.get('more'):
        walk(q['more'], seen, dead)
seen, dead = set(), []
walk(d.get('ask') or {}, seen, dead)
want = ['accept-finding', 'grill-me', 'save', 'small-change', 'teach-me']
r = '%s|empty More=%d' % (','.join(x for x in want if x in seen), len(dead))")"

# --- D43, D44, D46 (M3, M4, M6): an unattended run launches the group fix, never steps back to Plan, stops for the person ---
_ugroup45() { # _ugroup45 <group G1 fields>: an unattended run at Build whose group G1 check failed
  _unattended build
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "$1" > .temper/groups.json
}
_nogit45; _ugroup45 '"fails": 1, "fix": {"requested": "x"}, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "D43 in an unattended run the group fix agent is launched after a failed group check" "work:temper:temper-build" \
  "$(_x45 "r = '%s:%s' % (d.get('action'), ','.join(str(a.get('type')) for a in d.get('agents') or []))")"
_ugroup45 '"fails": 2, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
_d44_stop="$(_stop45 'state loop \S+ (plan|intent)|state set next_stage (plan|intent)')"; _park45 >/dev/null
assert_eq "D44 an unattended run never steps back to Plan: it stops and asks" "stop|at build|ask" \
  "$_d44_stop|at $("$TEMPER" state get next_stage 2>/dev/null)|$(_x45 "r = d.get('action')")"
_unattended check; sed -i '0,/Validate: scenario/s//Validate: manual/' .temper/specs/demo/intent.md
gfail check "acceptance evidence" "AC-01 has no supported passing evidence row"
_d46_stop="$(_stop45 'state loop check \S+|state redo')"; _park45 >/dev/null
assert_eq "D46 a criterion only the person can confirm stops an unattended run with the confirmation first; it never loops back to Build" \
  "stop|at check|confirm:True" \
  "$_d46_stop|at $("$TEMPER" state get next_stage 2>/dev/null)|$(_x45 "o = (opts(d) or [{}])[0]; r = '%s:%s' % (o.get('id'), o.get('recommended'))")"

# --- D47a, D47b (M7): no brief records a claimed test run; a run the CLI makes passes the test row ---
assert_eq "D47a no brief or reference page records a test run as a claim with evidence add --exit" "0" "$(python3 - "$REPO_ROOT" <<'PY'
import os, re, sys
n = 0
for d in ("agents", "reference"):
    for f in sorted(os.listdir(os.path.join(sys.argv[1], d))):
        if not f.endswith(".md"):
            continue
        text = re.sub(r"\\\n\s*", " ", open(os.path.join(sys.argv[1], d, f), encoding="utf-8").read())
        n += sum(1 for l in text.splitlines() if "evidence add" in l and "--exit" in l and re.search(r"--claim [\"']?tests\b", l))
print(n)
PY
)"
_check45; sed -i '/claimed-runs/d; /^evidence:/d' .claude/temper.config
"$TEMPER" evidence run --stage check --claim "tests" -- true >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_d47b_run="$(_row45 check 'tests pass')"
_check45; sed -i '/claimed-runs/d; /^evidence:/d' .claude/temper.config
"$TEMPER" evidence add --stage check --claim "tests" --cmd true --exit 0 --label PROVEN >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_d47b_claim="$(_row45 check 'tests pass')"
_check45; sed -i 's/^check:$/check:\n  commands:\n    test: "true"/' .claude/temper.config
python3 - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p)); d["adhoc_done"] = {"stage": "check", "reason": "x", "files": ["src/a.sh"], "doc_only": False, "steps": ["check", "commit"]}
json.dump(d, open(p, "w"), indent=2)
PY
assert_eq "D47b a test run the CLI made passes the test row, a claimed one does not, and a small change at Check is checked by the CLI" \
  "run=True|claim=False|small change=check run,gate check,no agent" \
  "run=$_d47b_run|claim=$_d47b_claim|small change=$(_x45 "cs = ' '.join(d.get('calls') or [])
r = ','.join(['check run' if ' check run' in cs else 'no check run', 'gate check' if ' gate check' in cs else 'no gate check',
              'no agent' if not d.get('agents') else 'agent ' + str(d['agents'][0].get('type'))])")"

# --- D48a, D48b (M8): the config reader merges a repeated key; no empty key of the template hides a documented block ---
fresh
assert_eq "D48a every documented block of the template, uncommented, is read whole: no empty key hides it" "none hidden" "$(python3 - "$REPO_ROOT/templates/temper.config.default" "$TEMPER" <<'PY'
import re, subprocess, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
hidden = []
i = 0
while i < len(lines):
    m = re.match(r"^# ([a-z][a-z-]*):\s*$", lines[i])
    if not m:
        i += 1
        continue
    j = i + 1
    while j < len(lines) and re.match(r"^#   ", lines[j]):
        j += 1
    block = [l[2:] for l in lines[i:j]]
    text = "\n".join(lines[:i] + block + lines[j:]) + "\n"
    open(".claude/temper.config", "w").write(text)
    path = [m.group(1)]
    for l in block[1:]:
        k = re.match(r"^( +)([a-z][a-z-]*):\s*([^#]*?)\s*(#.*)?$", l)
        if not k:
            continue
        depth = len(k.group(1)) // 2
        path = path[:depth] + [k.group(2)]
        if k.group(3) and not k.group(3).startswith("["):
            want = k.group(3).strip("\"'")
            got = subprocess.run([sys.argv[2], "config", "get", ".".join(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip()
            if got != want:
                hidden.append("%s=%r" % (".".join(path), got))
    i = j
print("; ".join(hidden) or "none hidden")
PY
)"
fresh; printf 'autonomy:\n  park-on-touch: ["**/auth/**", "**/payment/**"]\n  max-blast-radius: 15\nreview:\n  block-on: [critical]\nautonomy:\n  max-groups: 3\n' > .claude/temper.config
assert_eq "D48b a key written twice is merged: a second autonomy block keeps the first one's keys" '["**/auth/**", "**/payment/**"]|15|3' \
  "$("$TEMPER" config get autonomy.park-on-touch 2>/dev/null | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n").split("\x1f")))')|$("$TEMPER" config get autonomy.max-blast-radius 2>/dev/null)|$("$TEMPER" config get autonomy.max-groups 2>/dev/null)"

# --- D49 (M9): a code bug that prints Connection refused is not held as an environment fault for good ---
_tasks45 true true faketest45 | sed 's/^- \[x\] done/- [ ] done/' | m_setup
# WP21: only a sure sign is an environment fault at a task gate: here the config declares a service that does not answer
printf 'setup:\n  services:\n    db45: 127.0.0.1:1\n' >> .claude/temper.config
mkdir -p "$WORKDIR/.git/bin45"
printf '#!/usr/bin/env bash\nif [[ "$(cat "$(dirname "$0")/mode")" == red ]]; then echo "AssertionError: expected 3, got 2"; else echo "java.net.ConnectException: Connection refused"; fi\nexit 1\n' > "$WORKDIR/.git/bin45/faketest45"
chmod +x "$WORKDIR/.git/bin45/faketest45"; export PATH="$WORKDIR/.git/bin45:$PATH"
"$TEMPER" task start 1 >/dev/null 2>&1
echo red > "$WORKDIR/.git/bin45/mode"; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
mkdir -p .claude/worktrees/temper-demo-T1/src; echo built > .claude/worktrees/temper-demo-T1/src/demo.sh
echo conn > "$WORKDIR/.git/bin45/mode"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
_d49_first="$(_x45 "r = '%s:%s' % (next((o.get('id') for o in opts(d) if o.get('recommended')), 'none'), 'it-is-the-code' in ids(d))")"
_runopt45 "${_d49_first%%:*}"
_d49_again="$(_x45 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), 'none')")"
_d49_tries="$(m_field 1 attempts | python3 -c "import sys, ast; print(len(ast.literal_eval(sys.stdin.read().strip() or '[]')))")"
_runopt45 it-is-the-code
assert_eq "D49 Connection refused at a task gate: it-is-the-code is offered and spends the attempt, and the same fault twice is not the same recommendation" \
  "offered=True|again=save|attempt spent=yes" \
  "offered=${_d49_first#*:}|again=$_d49_again|attempt spent=$([[ "$(m_field 1 attempts | python3 -c "import sys, ast; print(len(ast.literal_eval(sys.stdin.read().strip() or '[]')))")" -gt "$_d49_tries" ]] && echo yes || echo no)"
export PATH="${PATH#"$WORKDIR/.git/bin45:"}"

# --- D50 (M10): an environment fault at Check does not recommend the same repair twice ---
_setup45() { # the Check of the demo run met a fault of the environment
  "$TEMPER" evidence add --stage check --claim "tests: the suite (run by the CLI)" --cmd "bash scripts/temper-check.sh" --exit 4 >/dev/null 2>&1
  "$TEMPER" evidence add --stage check --claim "setup fault: no Postgres answering on 127.0.0.1:5432" --cmd "bash scripts/temper-check.sh" --exit 1 >/dev/null 2>&1
  gfail check "tests pass" "the latest run of a test command failed"
}
_check45; _setup45
_d50_first="$(_x45 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), 'none')")"
_runopt45 "$_d50_first"; [[ "$("$TEMPER" state get next_stage 2>/dev/null)" == check ]] || _at check; _setup45
assert_eq "D50 the same fault of the environment at Check, after a run again, recommends Save for later and not the same repair" \
  "again=save|$_d50_first not recommended" \
  "again=$(_x45 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), 'none')")|$_d50_first $(_x45 "o = opt(d, '$_d50_first') or {}; r = 'recommended' if o.get('recommended') else 'not recommended'")"

# --- D51 (M11): when only the commit gate's own row fails, an option runs the gate again ---
_check45; gpass check; "$TEMPER" state advance check_complete commit >/dev/null 2>&1
gfail commit "park-on-touch paths" "src/auth/login.ts is under a park-on-touch pattern (**/auth/**)"
assert_eq "D51 only the commit gate's own row failed: the first option is check-again, and it runs the commit gate" "check-again|gate commit" \
  "$(_x45 "o = (opts(d) or [{}])[0]; r = '%s|%s' % (o.get('id'), re.sub(r'^\S*/temper ', '', (o.get('calls') or ['none'])[-1]))")"

# --- D53a, D53b (M13): a setup block reaches the config only by an answer that shows it whole; no environment agent ---
_check45; mkdir -p backend scripts
printf '<project><build><plugins><plugin><configuration><rules><requireJavaVersion><version>[24,)</version></requireJavaVersion></rules></configuration></plugin></plugins></build></project>\n' > backend/pom.xml
printf '#!/usr/bin/env bash\n[[ "$1" == --export ]] && echo "export JAVA_HOME=/opt/jdk24"\n' > scripts/ensure-jdk24.sh; chmod +x scripts/ensure-jdk24.sh
"$TEMPER" evidence add --stage check --claim "tests: the suite (run by the CLI)" --cmd "mvn verify" --exit 1 >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim "setup fault: needs JDK [24,) (found 21.0.12)" --cmd "mvn verify" --exit 1 >/dev/null 2>&1
gfail check "tests pass" "the latest run of a test command failed"
_d53_block="$("$TEMPER" doctor --propose 2>/dev/null | sed -n '/^setup:/,/^[^ ]/p' | grep -E '^(setup:|  )')"
assert_eq "D53a the question that offers the setup block shows every line of it, and only its answer writes the block" \
  "offered|whole|no other writer" "$(python3 - "$_d53_block" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
block = [l for l in sys.argv[1].splitlines() if l.strip()]
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
a = d.get("ask") or {}
text = (a.get("question") or {}).get("question", "")
opts = list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
writers = [o for o in opts if any("doctor" in c and "--write" in c for c in o.get("calls") or [])]
auto = [c for c in d.get("calls") or [] if "doctor" in c and "--write" in c]
print("|".join(["offered" if writers and block else "not offered",
                "whole" if block and all(l.strip() in text for l in block) else "not whole",
                "no other writer" if not auto and all(o.get("id") == "add-setup" for o in writers) else "another writer"]))
PY
)"
# (WP21: the option id and the state key of the environment agent are gone; their names are built from two parts)
_d53b_check="$(_x45 "r = 'agent offered' if 'find-' + 'setup' in ids(d) or any('env' + '_agent' in c for o in opts(d) for c in o.get('calls') or []) else 'no agent offered'")"
# M10 and M13 (c): Check ran again and met the same fault. Save for later is recommended, and while the block is still
# offered the question still shows every line of it
python3 - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p)); d["redo"] = {"stage": "check", "reason": "SETUP: needs JDK [24,) (found 21.0.12)", "ts": "2026-01-01T00:00:00Z"}
json.dump(d, open(p, "w"), indent=2)
PY
assert_eq "D53a the same SETUP fault after Check ran again still offers the block and shows every line of it" \
  "recommended=save|offered|whole" "$(python3 - "$_d53_block" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
block = [l for l in sys.argv[1].splitlines() if l.strip()]
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
a = d.get("ask") or {}
text = (a.get("question") or {}).get("question", "")
opts = list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
print("|".join(["recommended=%s" % next((o.get("id") for o in opts if o.get("recommended")), "none"),
                "offered" if block and any(o.get("id") == "add-setup" for o in opts) else "not offered",
                "whole" if block and all(l.strip() in text for l in block) else "not whole"]))
PY
)"
rm -rf backend scripts
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
gfail plan "tasks have a test" "Task 1 has no Test: line"   # WP21: the plan gate runs no command; any failed row
_d53b_plan="$(_x45 "r = 'agent offered' if 'find-' + 'setup' in ids(d) or any('env' + '_agent' in c for o in opts(d) for c in o.get('calls') or []) else 'no agent offered'")"
_key45="env"; _key45+="_agent"; "$TEMPER" state set "$_key45" requested >/dev/null 2>&1 || true
assert_eq "D53b the environment agent is not offered, and a saved request for it launches nothing" \
  "check=no agent offered|plan=no agent offered|requested=no agent" \
  "check=$_d53b_check|plan=$_d53b_plan|requested=$(_x45 "r = 'agent' if any(a.get('type') == 'temper:temper-' + 'env' for a in d.get('agents') or []) else 'no agent'")"

# --- D55, D56a, D56b, D57d, D99a, D99b (M15, M16, F4): a command the plan wrote ---
_plan45() { # _plan45 <Validate> <Integration> <Test> <scenario Test>: a run at Plan in a git repository, the plan written, no
            # gate run yet. $C45 is a program that appends its first word to $L45, so a case counts what ran.
  fresh; _repo45
  mkdir -p "$WORKDIR/.git/c45"; C45="$WORKDIR/.git/c45/count"; L45="$WORKDIR/.git/c45/log"; : > "$L45"
  printf '#!/bin/sh\necho "$1" >> %s\n' "$L45" > "$C45"; chmod +x "$C45"
  _tasks45 "$1" "$2" "$3" | sed 's/^- \[x\] done/- [ ] done/' > .temper/specs/demo/tasks.md
  sed -i "s|^  Test: true\$|  Test: $4|" .temper/specs/demo/intent.md
  gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  rm -f .temper/gates.json; gpass intent
}
_after45() { # the after calls of the planner's launch, as the session runs them once the agent returned
  _x45 "r = '\n'.join(c for a in d.get('agents') or [] if a.get('type') == 'temper:temper-plan' for c in a.get('after') or [])"
}
_runafter45() { # _runafter45 <calls>: runs them, the CLI's background run kept in the foreground
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] && TEMPER_BASELINE_FOREGROUND=1 bash -c "$c" >/dev/null 2>&1
  done <<<"$1"
}
_count45() { grep -c "^$1\$" "$L45" 2>/dev/null; }

_plan45 'C V' 'C I' 'C T' 'C S'
sed -i "s|\`C |\`$C45 |g" .temper/specs/demo/tasks.md; sed -i "s|Test: C S|Test: $C45 S|" .temper/specs/demo/intent.md
_d99_after="$(_after45)"
"$TEMPER" gate plan >/dev/null 2>&1
_d99a_gate="$(wc -l < "$L45" | tr -d ' ')"; _d57d_gate="T=$(_count45 T),S=$(_count45 S)"; : > "$L45"
_runafter45 "$_d99_after"
assert_eq "D57d no task Test and no scenario Test of the plan runs before Build" "gate:T=0,S=0|after the planner:T=0,S=0" \
  "gate:$_d57d_gate|after the planner:T=$(_count45 T),S=$(_count45 S)"
assert_eq "D99a the plan gate runs no command; after the planner returned each Validate and the Integration line ran at most once, no Test" \
  "gate ran=0|V<=1|I<=1|T=0|S=0" \
  "gate ran=$_d99a_gate|V$([[ $(_count45 V) -le 1 ]] && echo '<=1' || echo "=$(_count45 V)")|I$([[ $(_count45 I) -le 1 ]] && echo '<=1' || echo "=$(_count45 I)")|T=$(_count45 T)|S=$(_count45 S)"

_plan45 'sleep 3' true true true   # WP21: Build's limit for a Validate, TEMPER_TASK_TEST_TIMEOUT_S=1 below
sed -i 's/^- a holds$/- a holds\n- an empty input holds/' .temper/specs/demo/tasks.md   # the plan gate passes: plan.command is asked
_d55_after="$(_after45)"
TEMPER_TASK_TEST_TIMEOUT_S=1 _runafter45 "${_d55_after:-x gate plan}"
TEMPER_TASK_TEST_TIMEOUT_S=1 "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "D55 a plan command slower than its limit is never an environment fault and never launches an agent" "no environment fault|no agent" \
  "$(python3 - "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
texts = [json.dumps(d.get("ask") or {}), d.get("say") or ""]
for f in (".temper/gates.json", ".temper/evidence/baseline.json"):
    try:
        texts.append(open(f).read())
    except OSError:
        pass
env = any(re.search(r"environment fault|\"class\": \"environment\"", t, re.I) for t in texts)
a = d.get("ask") or {}
opts = list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
agent = d.get("agents") or [o for o in opts if o.get("id") == "find-" + "setup" or any("env" + "_agent" in c for c in o.get("calls") or [])]
print("%s|%s" % ("environment fault" if env else "no environment fault", "agent" if agent else "no agent"))
PY
)"
_d99b_q="$(_x45 "a = d.get('ask') or {}
calls = [c for o in opts(d) for c in o.get('calls') or []]
r = '%s|first=%s|change=%s|skip=%s|setup=%s|agents=%d' % (a.get('id'), (opts(d) or [{}])[0].get('id'),
    'yes' if any('plan patch' in c for c in calls) or any(o.get('kind') == 'type' for o in opts(d)) else 'no',
    'yes' if any('baseline skip' in c and '{reason}' in c for c in calls) else 'no',
    'yes' if any('doctor' in c and '--write' in c for c in calls) else 'no', len(d.get('agents') or []))")"
assert_eq "D99b a Validate slower than its limit is a time out: plan.command offers more time first, another command and a skip with a reason, no setup block, no agent" \
  "result=timeout|plan.command|first=more-time|change=yes|skip=yes|setup=no|agents=0" \
  "result=$(python3 -c "import json; print(','.join(sorted(set(v.get('result', '') for v in (json.load(open('.temper/evidence/baseline.json')).get('plan') or {}).values()))))" 2>/dev/null || echo none)|$_d99b_q"

_plan45 'MARK' true true true
M45="$WORKDIR/.git/c45/repaired"
# the task gets its second case (the plan gate asks two), so the plan gate passes and the Validate is what fails
sed -i 's/^- a holds$/- a holds\n- an empty input holds/' .temper/specs/demo/tasks.md
sed -i "s|\`MARK\`|\`$C45 V; test -e $M45 \|\| { echo 'java.net.ConnectException: Connection refused'; exit 1; }\`|" .temper/specs/demo/tasks.md
_runafter45 "$(_after45)"; "$TEMPER" gate plan >/dev/null 2>&1
_d56_n="$(_count45 V)"
assert_eq "D56b the failed plan question offers check-again" "plan:check-again" \
  "$(_x45 "r = '%s:%s' % (d.get('stage'), 'check-again' if 'check-again' in ids(d) else 'no check-again')")"
touch "$M45"
# WP21: the plan gate runs no command, so the check that runs it again is the option check-again: its calls, as the
# person's answer runs them (M16: no stored failure is returned)
while IFS= read -r _c45; do
  [[ -n "$_c45" ]] && TEMPER_BASELINE_FOREGROUND=1 bash -c "$_c45" >/dev/null 2>&1
done < <(_x45 "r = '\n'.join(next((o.get('calls') or [] for o in opts(d) if o.get('id') == 'check-again'), []))")
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "D56a after the environment was repaired the check runs the command again and passes: no stored failure is returned" \
  "ran again|passed" \
  "$([[ "$(_count45 V)" -gt "$_d56_n" ]] && echo 'ran again' || echo 'not run again')|$(python3 -c "
import json
g = json.load(open('.temper/gates.json')).get('plan') or {}
try:
    b = json.load(open('.temper/evidence/baseline.json')).get('plan') or {}
except (OSError, ValueError):
    b = {}
bad = [k for k, v in b.items() if v.get('result') in ('fail', 'timeout')]
print('passed' if g.get('verdict') == 'PASS' and not bad else 'failed')" 2>/dev/null || echo failed)"

# --- D57a, D57b, D57c (F1, F2, F3) ---
_check45; python3 - <<'PY'
import json
d = json.load(open(".temper/build-state.json")); d["next_stage"] = "review"; json.dump(d, open(".temper/build-state.json", "w"), indent=2)
PY
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
_done45; gpass review
_d57a_rec="$(_x45 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), 'none')")"
_unattended review
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
_done45; gpass review
_d57a_rule="$(_x45 "r = 'loops' if any(re.search(r' state (loop|redo) ', c) for c in calls(d)) else 'no loop'")"
_unattended commit
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
_done45; gpass commit; _park45 >/dev/null
assert_eq "D57a a Medium finding is listed at the commit question and starts no loop by rule" \
  "recommended=continue|unattended=no loop|commit question lists it" \
  "recommended=$_d57a_rec|unattended=$_d57a_rule|$(_x45 "t = json.dumps(d.get('ask') or {}) + json.dumps(d.get('card') or {})
r = 'commit question lists it' if (d.get('ask') or {}).get('id') == 'commit.confirm' and ('a missing null check' in t or '1 medium' in t) else 'not listed at %s' % (d.get('ask') or {}).get('id')")"

fresh; f9_tasks > .temper/specs/demo/tasks.md
printf '# Design\n\n## Areas of Concern\n\n### Which schedule does a job use\n\nThe plan says 24 hours.\n\nowner: the person\n' > .temper/specs/demo/design.md
python3 - <<'PY'
p = '.temper/specs/demo/intent.md'
s = open(p).read()
open(p, 'w').write(s.replace('### Open Questions\n', '### Open Questions\n\n- Blocking: Design: Which schedule does a job use? choices: its own | 24 hours\n', 1))
PY
gpass intent plan; "$TEMPER" state set want_design true >/dev/null 2>&1 || true
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1
# WP14: plan_complete is refused while a Blocking question is open, so the question is answered before the plan is left
"$TEMPER" intent answer 'Design: Which schedule does a job use?' 'its own' >/dev/null 2>&1
"$TEMPER" state advance plan_complete design >/dev/null 2>&1
"$TEMPER" gate design >/dev/null 2>&1; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "D57b an answered Design question passes the row tasks agree with decisions with a note, and no step back is recommended" \
  "True|names the answer|not back" "$(python3 -c "
import json
g = json.load(open('.temper/gates.json'))
r = [x for s in ('design', 'plan') for x in (g.get(s) or {}).get('requirements') or [] if x.get('name') == 'tasks agree with decisions']
print('%s|%s' % (all(x.get('pass') is True for x in r) and bool(r), 'names the answer' if any('Which schedule' in str(x.get('detail')) for x in r) else 'no note'))")|$(_x45 "r = 'back' if next((o.get('id') for o in opts(d) if o.get('recommended')), '') == 'back' else 'not back'")"

_review45 high
assert_eq "D57c a High finding blocks Review by default" "FAIL|no blocking findings=False" "$(_verdict45 review)|no blocking findings=$(_row45 review 'no blocking findings')"
