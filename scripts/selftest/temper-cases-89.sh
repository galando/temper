# Case file 89: round 2 of the adversarial review of 9.8.5 (reviewer 2): the fixes of rules 5 to 10 read again. Sourced by
# test-temper.sh; its helpers (fresh, gpass) are used here. Each check below fails on the code it was written against: it
# is the reproduction of one finding of the round, not a row of done.md. Each check stands on its own (its own setup).
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_r2r2_log() { # _r2r2_log <ERE>: how many entries of the rule log (the record the commit card lists) match the ERE
  python3 - "$1" <<'PY'
import json, re, sys
try:
    e = json.load(open(".temper/rule-log.json"))
except (OSError, ValueError):
    e = []
print(sum(1 for x in e if isinstance(x, dict) and re.search(sys.argv[1], "%s %s" % (x.get("kind"), x.get("what")))))
PY
}
_r2r2_next() { # action, then the calls of temper next, each after the word temper
  "$TEMPER" next --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('action'), '|'.join(c.split('temper ', 1)[-1] for c in d.get('calls') or []))" 2>/dev/null
}

_r2r2_repo() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_r2r2_g() { # _r2r2_g <python over g, the Check verdict of gates.json, that sets r>: prints r
  python3 - "$1" <<'PY'
import json, sys
try:
    g = json.load(open('.temper/gates.json')).get('check') or {}
except (OSError, ValueError):
    g = {}
row = lambda n: next((x for x in g.get('requirements') or [] if str(x.get('name', '')).startswith(n)), {})
r = None
exec(sys.argv[1])
print(r)
PY
}
_r2r2_gv() { python3 -c "import json; print(((json.load(open('.temper/groups.json'))['groups']['G1'].get('gate') or {}).get('verdict')) or 'none')" 2>/dev/null; }
_r2r2_used() { python3 -c "
import json
try:
    u = json.load(open('.temper/budget.json')).get('used') or []
except (OSError, ValueError, AttributeError):
    u = []
print(sum(1 for x in u if isinstance(x, dict) and x.get('key') == 'group:G1'))" 2>/dev/null; }
_r2r2_brow() { # _r2r2_brow <name prefix>: pass of that row of the Build verdict
  python3 - "$1" <<'PY'
import json, sys
try:
    g = json.load(open('.temper/gates.json')).get('build') or {}
except (OSError, ValueError):
    g = {}
print(next((x.get('pass') for x in g.get('requirements') or [] if str(x.get('name', '')).startswith(sys.argv[1])), 'none'))
PY
}

# --- rule 10 (fix 4bd2953): the rule's run of a timed out group check, in a run that asks at every stage ---
# The first time out of a group's check is no question in any mode (flow_build.group_failed: the CLI runs it again with
# twice the limit before it looks at r.armed()). 4bd2953 writes its entry with _rule_log, which rule_log.py keeps only
# while the run goes on by itself, so after "Ask me at every stage" the rule's move is in no entry the commit card lists
# (d1afce1 fixed the same gap for a repair with by_rule, and missed this path).
fresh
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'x' '' '### Task 1: first' '**File:** `src/p1.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- p' \
  '- [x] done' > .temper/specs/demo/tasks.md
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set run_mode interactive >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
python3 - <<'PY'
import json
g = {"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w1", "branch": "temper/demo/G1",
     "fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: true", "ran": True,
                          "timeout_s": 600}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}
json.dump(g, open(".temper/groups.json", "w"))
PY
_r2r2_a_next="$(_r2r2_next)"
"$TEMPER" group gate G1 --timeout-s 1200 >/dev/null 2>&1 || true
assert_eq "round 2 reviewer 2: the rule's run of a timed out group check with twice the limit is in the rule log in a run that asks at every stage" \
  "mode=interactive|rule's move=auto group gate G1 --timeout-s 1200|logged=1" \
  "mode=$("$TEMPER" state get run_mode 2>/dev/null)|rule's move=$_r2r2_a_next|logged=$(_r2r2_log 'G1')"

# --- rule 5 (fix cd38d16): the suite's own text, run as words with no shell, is another command ---
# cd38d16 counts a run under the suite's claim only when its recorded cmd is the suite's text. `temper evidence run`
# records "$*" of the words it ran with "$@", no shell, so the words of the suite's own text run another command: with
# the suite `echo FAIL: test_a; exit 1` (the CLI's run fails, through the shell), an agent's
# `evidence run --claim tests -- echo FAIL: test_a\; exit 1` runs echo (exit 0), records the suite's text, and passes the
# row `tests pass` on the tree the verdict names.
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_r2r2_c_before="$(_r2r2_g "r = '%s:%s' % (g.get('verdict'), row('tests pass').get('pass'))")"
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- echo FAIL: 'test_a;' exit 1 >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the words of the suite's text run with no shell are no run of the suite: tests pass stays failed" \
  "before=FAIL:False|after=False" \
  "before=$_r2r2_c_before|after=$(_r2r2_g "r = row('tests pass').get('pass')")"

# --- rule 5 (fix 2b8953d): a scenario's own Test: text, run as words with no shell, traces it ---
# The same gap in acceptance.scenario_runs: the scenario's Test: line is a shell command (`echo FAIL: first; false`, the
# CLI's run fails), and `evidence run --scenario first -- echo FAIL: 'first;' false` records that very text and exit 0.
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "true"\n' >> .claude/temper.config
sed -i '0,/  Test: true/s//  Test: echo FAIL: first; false/' .temper/specs/demo/intent.md
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_r2r2_d_before="$(_r2r2_g "r = '%s:%s' % (row('scenarios traced').get('pass'), row('acceptance evidence').get('pass'))")"
"$TEMPER" evidence run --stage check --scenario first --claim 'scenario: first' -- echo FAIL: 'first;' false >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the words of a scenario's Test: text run with no shell do not trace the scenario whose Test failed" \
  "before=False:False|after=False:False" \
  "before=$_r2r2_d_before|after=$(_r2r2_g "r = '%s:%s' % (row('scenarios traced').get('pass'), row('acceptance evidence').get('pass'))")"

# --- rule 9 (fix b238221): a failed group check checked again after a change no fix request paid for ---
# b238221 refuses `group fix G --commit` with no request open, so a fix commit always spends group:G. The check again
# itself spends nothing (`group gate G` with no flag), and the gate refuses only an uncommitted change to a tracked file
# (status --untracked-files=no): a file the agent adds in the group's worktree, uncommitted, makes Validate pass on the
# next `group gate G`, with no request, no commit and no repeat spent.
f9_tasks | m_setup
python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
for n in ("1", "2"):
    d.setdefault("tasks", {})[n] = {"status": "passed", "group": "G1"}
json.dump(d, open(".temper/groups.json", "w"))
p = ".temper/specs/demo/tasks.md"
text = open(p).read().replace("**Validate:** `true`", "**Validate:** `test -f src/fixed`")
open(p, "w").write(text)
for f in (".temper/groups.json", ".temper/build-state.json"):
    x = json.load(open(f)); x.pop("plan_hash", None); json.dump(x, open(f, "w"))
PY
"$TEMPER" group gate G1 >/dev/null 2>&1
_r2r2_e_first="$(_r2r2_gv)"
_r2r2_e_wt="$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['worktree'])" 2>/dev/null)"
mkdir -p "$_r2r2_e_wt/src"; : > "$_r2r2_e_wt/src/fixed"
"$TEMPER" group gate G1 >/dev/null 2>&1
_r2r2_e_again="$(_r2r2_gv)"
assert_eq "round 2 reviewer 2: a failed group check passed again after a change no fix request paid for spends a repeat or is refused" \
  "first=FAIL|again=refused or paid" \
  "first=$_r2r2_e_first|again=$([[ "$_r2r2_e_again" == PASS && "$(_r2r2_used)" == 0 ]] && echo "passed with no repeat paid for" || echo "refused or paid")"

# --- rule 5 (fix cd38d16): the view's tests marker still reads the run the gate no longer counts ---
# cd38d16 makes the row `tests pass` read only runs of the suite's own command. The view the mod draws
# (flow_view.check_markers) still takes the latest row of any claim that names tests, so after the CLI's run of the
# configured suite failed, an agent's `evidence run --claim tests -- true` draws the Check's tests as passed while the
# gate fails them (a8daac8 made the coverage marker read the CLI's measure only, and left this one).
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the view draws the Check's tests as the gate judged them, not from a run the gate does not count" \
  "gate=False|view=fail" \
  "gate=$(_r2r2_g "r = row('tests pass').get('pass')")|view=$(vw "next((x.get('state') for x in d.get('check_markers') or [] if x.get('name') == 'tests'), None)")"

