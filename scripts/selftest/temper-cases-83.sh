# Case file 83: review 3 of the adversarial review of 9.8.5, rules 5 and 6. Sourced by test-temper.sh; its helpers (fresh,
# gpass, _at, vw) are used here. Each assertion is a reproduction: it failed on the code under review, and the commit
# that added it fixed it.
_repo83() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_g83() { # _g83 <python over g, the Check verdict of gates.json, that sets r>: prints r
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

# --- rule 5: the suite the CLI ran failed on this tree; a CLI run of a command an agent chose stands in for it ---
fresh; _repo83; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_t83_tree="$(_g83 "r = g.get('tree')")"
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "review 3: tests pass is not passed by a run of true when the CLI's run of the configured suite failed on the tree the verdict names" \
  "verdict=FAIL|tests=False|same tree=True" \
  "verdict=$(_g83 "r = g.get('verdict')")|tests=$(_g83 "r = row('tests pass').get('pass')")|same tree=$([[ "$(_g83 "r = g.get('tree')")" == "$_t83_tree" ]] && echo True || echo False)"

# --- rule 5: a scenario whose own Test: command failed is traced by a CLI run of another command ---
fresh; _repo83; sed -i '0,/  Test: true/s//  Test: false/' .temper/specs/demo/intent.md
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1
"$TEMPER" evidence run --stage check --scenario first --claim 'scenario: first' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "review 3: a scenario whose Test: command failed in the CLI's run is not traced by a run of another command" \
  "scenarios=False|acceptance=False" \
  "scenarios=$(_g83 "r = row('scenarios traced').get('pass')")|acceptance=$(_g83 "r = row('acceptance evidence').get('pass')")"

# --- rules 5 and 6: a coverage value an agent typed with evidence add turns a coverage not measured into passed ---
fresh; _repo83; printf 'check:\n  commands:\n    test: "true"\n' >> .claude/temper.config   # no coverage command
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_c83_before="$(_g83 "r = row('coverage').get('state')")"
"$TEMPER" evidence add --stage check --claim 'coverage' --value 95 >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "review 3: a coverage value recorded with evidence add passes no coverage row: what the CLI measured, not measured, stays" \
  "before=not measured|after=None:not measured|view=not measured" \
  "before=$_c83_before|after=$(_g83 "r = '%s:%s' % (row('coverage').get('pass'), row('coverage').get('state'))")|view=$(vw "next((x.get('state') for x in d.get('checks') or [] if str(x.get('name', '')).startswith('coverage')), None)")"

# --- rule 5: a Check verdict names a tree on which the suite never ran; the pass it counts is of the tree before ---
_py83() { # a git repository with a Python module and a unittest suite (the stack Check detects), declared by the plan
  rm -rf .git src unit; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src unit; : > unit/__init__.py; printf 'def f():\n    return 1\n' > src/demo.py
  printf 'import unittest\nclass T(unittest.TestCase):\n    def test_f(self):\n        self.assertTrue(True)\n' > unit/test_demo.py
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
  sed -i '0,/Validate: scenario — traced to a test below/s//Validate: code — `true`/' .temper/specs/demo/intent.md
  sed -i '/^\*\*Integration:\*\*/d; s#`src/demo.sh`#`src/demo.py`#' .temper/specs/demo/tasks.md
}
fresh; _py83; gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_s83_t1="$(_g83 "r = '%s:%s' % (g.get('verdict'), g.get('tree'))")"
rm -rf unit; printf 'def f():\n    return 2\n' > src/demo.py   # the change removes the suite: Check finds no test command
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_s83_t2="$(_g83 "r = '%s:%s' % (g.get('verdict'), g.get('tree'))")"
"$TEMPER" state advance check_complete commit >/dev/null 2>&1; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "review 3: a Check verdict never names a tree on which no suite ran, from a pass of the tree before" \
  "first=PASS|second=FAIL|commit=FAIL" \
  "first=${_s83_t1%%:*}|second=$([[ "${_s83_t2#*:}" != "${_s83_t1#*:}" ]] && echo "${_s83_t2%%:*}" || echo same-tree)|commit=$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['commit']['verdict'])")"

# --- rule 6: acceptance tests that never ran (the writer's skip) are shown as passed ---
fresh; _repo83; printf 'check:\n  commands:\n    test: "true"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" acceptance skip --reason 'the writer locked no test' >/dev/null 2>&1
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
assert_eq "review 3: acceptance tests that were skipped, never run, are not a passed row of the Check verdict" \
  "not passed" \
  "$(_g83 "x = row('acceptance tests'); r = 'not passed' if x and x.get('pass') is not True and x.get('state') in ('skipped', 'not measured') else 'passed=%s:%s' % (x.get('pass'), x.get('detail'))")"

# --- rule 5: a verdict outside a git repository names no tree ---
