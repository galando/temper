# Release 9.8.0: what the benchmark found and what it led to (docs/evidence/bench-2026-11.md): the CLI finds its project from
# a subfolder, and the 9.8.0 gates and flow below.
# Sourced by test-temper.sh after temper-cases-14.sh (helpers: nx, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

# --- 1. Called from a subfolder, the CLI uses the project's .temper and never starts a second one ---
fresh
mkdir -p docs/decisions
assert_eq "9.8.0: temper called from docs/decisions reads the run of the project above it" "demo" \
  "$(cd docs/decisions && "$TEMPER" state get spec 2>/dev/null)"
(cd docs/decisions && "$TEMPER" state set complexity medium >/dev/null 2>&1)
assert_eq "9.8.0: and writes to it, never to docs/decisions/.temper" "medium|no" \
  "$("$TEMPER" state get complexity 2>/dev/null)|$([[ -d docs/decisions/.temper ]] && echo yes || echo no)"

# --- 2. Check is run by the CLI when it finds a test command; the agent stays for a stack it cannot read ---
_gc() { "$TEMPER" gate check 2>&1 || true; }   # the gate's rows; its exit (FAIL is 1) is not the pipe's under pipefail
_at_check() { # a run at Check, with the earlier gates passed
  fresh; gpass intent plan build review
  for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
}
_at_check
assert_eq "9.8.0: with no test command the CLI can find, Check is the agent as before" "work|1|0" \
  "$(nx "'|'.join([d['action'], str(len(d['agents'])), str(sum(1 for c in d['calls'] if 'check run' in c))])")"
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 80\n  commands:\n    test: python3 -m unittest discover -s unit -t .\n', 1)
open(p, 'w').write(s)
PYEOF
mkdir -p unit lib; : > unit/__init__.py; : > lib/__init__.py
cat > lib/calc.py <<'PYEOF'
def grade(score):
    return "pass"
PYEOF
cat > unit/test_calc.py <<'PYEOF'
import unittest
from lib import calc


class T(unittest.TestCase):
    def test_pass(self):
        self.assertEqual(calc.grade(90), "pass")
PYEOF
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
assert_eq "9.8.0: with a test command, Check is the CLI's check run then the gate, no agent" "work|0|check run|gate check" \
  "$(nx "'|'.join([d['action'], str(len(d['agents']))] + [c.split('temper ', 1)[1] for c in d['calls']])")"

# the change: a grade with bands, first tested well, then not
cat > lib/calc.py <<'PYEOF'
def grade(score):
    if score >= 90:
        return "A"
    if score >= 75:
        return "B"
    if score >= 60:
        return "C"
    return "F"
PYEOF
cat > unit/test_calc.py <<'PYEOF'
import unittest
from lib import calc


class T(unittest.TestCase):
    def test_bands(self):
        for s, g in [(90, "A"), (89, "B"), (75, "B"), (74, "C"), (60, "C"), (59, "F"), (100, "A"), (0, "F")]:
            self.assertEqual(calc.grade(s), g, s)
PYEOF
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: check run records the suite as a CLI run that passed" "0|cli" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/evidence/check.json')) if x['claim'].startswith('tests:')][-1]; print('%s|%s' % (r['exit_code'], r['executed_by']))")"
assert_eq "9.8.0: with no coverage command the coverage row names what to set" "yes" \
  "$(_gc | grep -q "recorded coverage 'none' vs threshold 80% (set check.commands.coverage" && echo yes || echo no)"
assert_eq "9.8.0: tests that pin every band catch the planted bugs: the mutation row passes" "yes" \
  "$(_gc | grep -qE '\[v\] mutation score >= threshold — (100|9[0-9]|8[0-9]|7[0-9])' && echo yes || echo no)"
cat > unit/test_calc.py <<'PYEOF'
import unittest
from lib import calc


class T(unittest.TestCase):
    def test_runs(self):
        self.assertIn(calc.grade(95), "ABCF")
PYEOF
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: a test that only runs the code misses the planted bugs: the mutation row fails" "yes" \
  "$(_gc | grep -q '\[x\] mutation score >= threshold' && echo yes || echo no)"

# --- 3. A fix's regression proof: the new test must fail on the code before the fix ---
fresh; "$TEMPER" state clear >/dev/null 2>&1; "$TEMPER" state init demo --feature "the bug" --command fix >/dev/null 2>&1
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 80\n  commands:\n    test: python3 -m unittest discover -s unit -t .\n', 1)
open(p, 'w').write(s)
PYEOF
mkdir -p unit lib; : > unit/__init__.py; : > lib/__init__.py
printf 'def total(a, b):\n    return a - b\n' > lib/money.py
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_nothing(self):\n        self.assertTrue(True)\n' > unit/test_base.py
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm "the bug" >/dev/null 2>&1
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
printf 'def total(a, b):\n    return a + b\n' > lib/money.py
printf 'import unittest\nfrom lib import money\n\n\nclass T(unittest.TestCase):\n    def test_total(self):\n        self.assertEqual(money.total(2, 3), 5)\n' > unit/test_money.py
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: a regression test that fails on the code before the fix proves it" "yes" \
  "$(_gc | grep -q '\[v\] regression proof — the new or changed tests (unit/test_money.py) fail on the code before the fix' && echo yes || echo no)"
printf 'import unittest\nfrom lib import money\n\n\nclass T(unittest.TestCase):\n    def test_total(self):\n        self.assertEqual(money.total(2, 0), 2)\n' > unit/test_money.py
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: a test that passes before the fix too proves nothing: the regression row fails" "yes" \
  "$(_gc | grep -q '\[x\] regression proof — the new or changed tests (unit/test_money.py) pass on the code before the fix too' && echo yes || echo no)"
