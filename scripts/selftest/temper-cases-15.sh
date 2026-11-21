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
_gb() { "$TEMPER" gate build 2>&1 || true; }   # WP23: the Build gate's rows, where the locked acceptance tests are read
_planted15() { # WP19: the planted bug score of the tree as it stands, which check ahead measures beside Review (Check plants
               # no bug): the state of .temper/evidence/mutation.json, then "all caught" or "survivors"
  rm -f .temper/evidence/mutation.json
  "$TEMPER" check ahead >/dev/null 2>&1
  local i
  for i in $(seq 1 300); do
    if [[ ! -f .temper/check/ahead.pid ]]; then
      [[ -f .temper/evidence/mutation.json ]] && ! grep -q '"state": *"running"' .temper/evidence/mutation.json && break
      [[ -f .temper/check/ahead.json && $i -gt 20 ]] && break
    fi
    sleep 0.2
  done
  python3 -c "
import json
try:
    m = json.load(open('.temper/evidence/mutation.json'))
except (OSError, ValueError):
    m = {}
ran, caught = m.get('ran') or 0, m.get('caught') or 0
print('%s|%s' % (m.get('state', 'no mutation.json'), 'all caught' if ran >= 3 and caught == ran else 'survivors' if m.get('survivors') else 'caught %s of %s' % (caught, ran)))"
}
# The shared fixture folder keeps what earlier case files left at its top level (CI runs them all in one folder): a
# section that reads the changed files or the stack clears it first, keeping the repository, the run and the README.
_clear_root() { [[ "$PWD" == "$WORKDIR" ]] || return 1; find . -mindepth 1 -maxdepth 1 ! -name .git ! -name .temper ! -name .claude ! -name README -exec rm -rf {} +; }
_at_check() { # a run at Check, with the earlier gates passed
  fresh; gpass intent plan build review
  for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
}
_at_check; _clear_root
sed -i 's/^\*\*Integration:\*\* `true`$/**Integration:** `manual`/' .temper/specs/demo/tasks.md   # WP23: no plan line either
assert_eq "9.8.0: with no test command the CLI can find, Check is the agent as before" "work|1|0" \
  "$(nx "'|'.join([d['action'], str(len(d['agents'])), str(sum(1 for c in d['calls'] if 'check run' in c))])")"
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  commands:\n    test: python3 -m unittest discover -s unit -t .\n', 1)   # WP19: no old key
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
assert_eq "9.8.0: with no coverage command the coverage row is not measured and names what to set" "yes" \
  "$(_gc | grep -c "\[?\] coverage — not measured: .*set check.commands.coverage" >/dev/null && echo yes || echo no)"
assert_eq "9.8.0: tests that pin every band catch the planted bugs: check ahead records each one caught" "measured|all caught" \
  "$(_planted15)"
cat > unit/test_calc.py <<'PYEOF'
import unittest
from lib import calc


class T(unittest.TestCase):
    def test_runs(self):
        self.assertIn(calc.grade(95), "ABCF")
PYEOF
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: a test that only runs the code misses planted bugs: check ahead names survivors, and no gate row names them" \
  "measured|survivors|0" "$(_planted15)|$(_gc | grep -c 'mutation')"

# --- 3. A fix's regression proof: the new test must fail on the code before the fix ---
fresh; "$TEMPER" state clear >/dev/null 2>&1; "$TEMPER" state init demo --feature "the bug" --command fix >/dev/null 2>&1; _base_known
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
  "$(_gc | grep -c '\[v\] regression proof — the new or changed tests (unit/test_money.py) fail on the code before the fix' >/dev/null && echo yes || echo no)"
printf 'import unittest\nfrom lib import money\n\n\nclass T(unittest.TestCase):\n    def test_total(self):\n        self.assertEqual(money.total(2, 0), 2)\n' > unit/test_money.py
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "9.8.0: a test that passes before the fix too proves nothing: the regression row fails" "yes" \
  "$(_gc | grep -c '\[x\] regression proof — the new or changed tests (unit/test_money.py) pass on the code before the fix too' >/dev/null && echo yes || echo no)"

# --- 4. Acceptance tests written from the intent before Build, by an agent that writes no code; Check runs them as locked ---
_at_build() { # the plan approved, Build not started (no group yet), an intent on file
  f9_tasks | m_setup
  "$TEMPER" group start G1 >/dev/null 2>&1   # m_setup started one: take it back off for a Build that has not begun
  rm -f .temper/groups.json
  f9_intent true true
}
_at_build
assert_eq "9.8.0: Build starts with the acceptance writer, before any task" "work|temper:temper-acceptance|acceptance start|0" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], a['before'][0].split('temper ', 1)[1], str(sum(1 for x in d['agents'] if x['type'] == 'temper:temper-build-task'))])")"
"$TEMPER" acceptance start >/dev/null 2>&1; "$TEMPER" acceptance start >/dev/null 2>&1
assert_eq "9.8.0: after two launches that did not lock, Build goes on without it" "no" \
  "$(nx "'yes' if any(a['type'] == 'temper:temper-acceptance' for a in d.get('agents', [])) else 'no'")"
assert_exit "9.8.0: acceptance lock needs a test file in the spec's acceptance folder" 1 "$TEMPER" acceptance lock --cmd "true"
mkdir -p .temper/specs/demo/acceptance
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01(self):\n        self.assertEqual(1 + 1, 2)\n' > .temper/specs/demo/acceptance/test_ac.py
assert_exit "9.8.0: acceptance lock keeps the digest and the command" 0 "$TEMPER" acceptance lock --cmd "python3 -m unittest discover -s .temper/specs/demo/acceptance -t .temper/specs/demo/acceptance"
assert_eq "9.8.0: a locked run launches no writer" "no" \
  "$(nx "'yes' if any(a['type'] == 'temper:temper-acceptance' for a in d.get('agents', [])) else 'no'")"
"$TEMPER" group start G1 >/dev/null 2>&1
assert_eq "9.8.0: each Build task is told where the acceptance tests are, and not to edit them" "no|yes" \
  "$(nx "'|'.join(['yes' if any(a['type'] == 'temper:temper-acceptance' for a in d.get('agents', [])) else 'no', 'yes' if any('acceptance/ holds the tests written from the intent' in a.get('prompt', '') for a in d.get('agents', [])) else 'no'])")"
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 80\n  commands:\n    test: "true"\n', 1)
open(p, 'w').write(s)
PYEOF
echo '[]' > .temper/evidence/build.json; "$TEMPER" check build-checks >/dev/null 2>&1
assert_eq "WP23: the checks when Build ends run the locked acceptance tests, and the Build gate reads that they pass" "yes" \
  "$(_gb | grep -c '\[v\] acceptance tests written before Build — they pass, unchanged since they were locked' >/dev/null && echo yes || echo no)"
printf '\n# a builder edits it\n' >> .temper/specs/demo/acceptance/test_ac.py
echo '[]' > .temper/evidence/build.json; "$TEMPER" check build-checks >/dev/null 2>&1
assert_eq "WP23: an acceptance test changed after the lock fails the Build gate, naming the file" "yes" \
  "$(_gb | grep -c '\[x\] acceptance tests written before Build — changed after they were locked: .temper/specs/demo/acceptance/test_ac.py' >/dev/null && echo yes || echo no)"

# --- 5. The scope row in every run with a plan; park-on-touch parks only for a file outside the plan ---
f9_tasks | m_setup
_clear_root
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
mkdir -p src unit docs/decisions; echo a > src/a.sh; echo t > unit/a_test.sh
_gcm() { "$TEMPER" gate commit 2>&1 || true; }
assert_eq "9.8.0: an interactive run's planned and test files are in scope" "yes" \
  "$(_gcm | grep -c '\[v\] blast radius — 2 changed, all declared' >/dev/null && echo yes || echo no)"
echo adr > docs/decisions/0001-x.md
assert_eq "9.8.0: an interactive run with a file nobody planned fails the scope row, naming it" "yes" \
  "$(_gcm | grep -c '\[x\] blast radius — changed outside declared files: docs/decisions/0001-x.md' >/dev/null && echo yes || echo no)"
"$TEMPER" evidence add --stage build --phase feedback --claim "drift docs/decisions/0001-x.md: Add to plan: the person wants the record" >/dev/null 2>&1
assert_eq "9.8.0: a file the person added to the plan at a Scope drift question is in scope" "yes" \
  "$(_gcm | grep -c '\[v\] blast radius — 3 changed, all declared' >/dev/null && echo yes || echo no)"
rm -rf docs
python3 - <<'PYEOF'
p = '.temper/specs/demo/tasks.md'; s = open(p).read()
s = s.replace('**File:** `src/a.sh`, `unit/a_test.sh`', '**File:** `src/a.sh`, `unit/a_test.sh`, `src/billing/rates.sh`', 1)
open(p, 'w').write(s)
PYEOF
_ran_unattended   # WP11: a run the person started at the approval, now at the commit gate
mkdir -p src/billing; echo r > src/billing/rates.sh
printf 'autonomy:\n  enabled: true\n  park-on-touch: ["**/billing/**"]\n' > .claude/temper.config
assert_eq "9.8.0: an unattended run's planned change to a park-on-touch path does not park" "yes" \
  "$(_gcm | grep -c '\[v\] sensitive paths' >/dev/null && echo yes || echo no)"
echo x > src/billing/other.sh
assert_eq "9.8.0: a change to a park-on-touch path outside the plan still parks" "yes" \
  "$(_gcm | grep -c '\[x\] sensitive paths — src/billing/other.sh matches \*\*/billing/\*\* and is not in the plan' >/dev/null && echo yes || echo no)"
"$TEMPER" state set run_mode interactive >/dev/null 2>&1   # a skip or a step back ended it: the run asks the person again
assert_eq "WP11: a run that went on by itself keeps that record, and the commit gate still holds it to park-on-touch after it ended" "true|yes" \
  "$("$TEMPER" state get ran_unattended)|$(_gcm | grep -c '\[x\] sensitive paths — src/billing/other.sh' >/dev/null && echo yes || echo no)"
assert_exit "9.8.0: the record is the CLI's: state set ran_unattended is refused" 1 "$TEMPER" state set ran_unattended false

# --- 6. The Context check names what the plan leaves out; an answer other than "As planned" sends Plan back with it ---
_fr_plan_ctx() { # a plan at Plan whose Context Map has an ignore and a gap and is not reviewed yet; WP13: under auto
                 # lines that short are folded into the approval (temper-cases-54.sh), so always keeps the check here
  fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  printf 'plan:\n  context-check: always\n' >> .claude/temper.config
  "$TEMPER" state set complexity simple >/dev/null 2>&1
  cat > .temper/specs/demo/plan.md <<'PEOF'
## Context Map
- use: src/ (3 files)
- ignore: ledger/export.py: refunds in exports are out of scope
- gap: no ticket or linked doc
- reviewed: pending

## Plan
PEOF
}
_fr_plan_ctx
assert_eq "9.8.0: the Context check names what is left out and not found, with As planned first" \
  "The plan leaves out: ledger/export.py: refunds in exports are out of scope. It could not find: no ticket or linked doc. Is that right?|As planned (Recommended)|Include what is left out|Something else|Carry forward" \
  "$(nx "q = d['context_check']; '|'.join([q['question']['question']] + [o['label'] for o in q['options']])")"
assert_eq "9.8.0: Include what is left out records it and sends Plan back (--redo); a typed answer does too" "yes|yes" \
  "$(nx "q = d['context_check']; ('yes' if q['options'][1]['calls'][0].endswith('--redo') else 'no') + '|' + ('yes' if q['answer'].endswith('--redo') else 'no')")"
assert_exit "9.8.0: plan review --redo records the answer" 0 "$TEMPER" plan review --answer "Include the export" --redo
assert_eq "9.8.0: the answer is the person's note for Plan, and the plan verdict is gone (Plan runs again)" "1|yes" \
  "$(python3 -c "import json; print(sum(1 for r in json.load(open('.temper/evidence/plan.json')) if r.get('claim') == 'Context check: Include the export'))")|$(python3 -c "import json; g=json.load(open('.temper/gates.json')); print('yes' if 'plan' not in g else 'no')" 2>/dev/null || echo yes)"

# --- 7. No Design on risk (WP14); risk kept by the CLI; the unattended run at the last question before Build ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set complexity medium >/dev/null 2>&1
assert_exit "9.8.0: risk is kept by the CLI (state set risk is refused)" 1 "$TEMPER" state set risk L
gpass plan
assert_eq "9.8.0: a medium plan at risk below H skips Design; the plan question offers the unattended run" \
  "Plan: the check passed. Approve the plan and continue to Build?|ask-every-stage,True|approve-run,False" \
  "$(nx "q = d['ask']; '|'.join([q['question']['question']] + ['%s,%s' % (o['id'], bool(o.get('recommended'))) for o in q['options'][:2]])")"
"$TEMPER" risk --raise H --reason "it moves money" >/dev/null 2>&1; fresh_reviewed   # reviewer A only: the round is not complete
assert_eq "WP14: at risk H a medium plan runs no Design, and before a complete fresh round the plan question does not offer the unattended run (WP12: the digests shown)" \
  "ask-every-stage,True|state advance plan_complete build|shown|no" \
  "$(nx "q = d['ask']; o = [x['id'] for x in q['options']] + [x['id'] for x in (q.get('more') or {}).get('options', [])]; c = q['options'][0]['calls'][-1]; '%s,%s' % (q['options'][0]['id'], bool(q['options'][0].get('recommended'))) + '|' + c.split('temper ', 1)[1].split(' --shown ')[0] + ('|shown' if ' --shown intent.md=' in c and ' --shown tasks.md=' in c else '|no digests') + '|' + ('yes' if 'approve-run' in o else 'no')")"
for _l15 in readiness zoom-out comprehension tests; do   # reviewer B completes the round of risk H
  "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $_l15 B" \
    $([[ $_l15 == readiness ]] && echo "--value $(grep -c '^### Task' .temper/specs/demo/tasks.md)") >/dev/null 2>&1
done
"$TEMPER" state set want_design true >/dev/null 2>&1   # the person asked for Design (the option run-design)
"$TEMPER" state advance plan_complete design >/dev/null 2>&1; gpass design
assert_eq "9.8.0: the Design question offers the unattended run, which arms and leaves Design with the digests shown (WP12)" \
  "approve-run|arm|state set run_mode autonomous|state advance design_complete build|shown" \
  "$(nx "o = [x for x in d['ask']['options'] if x['id'] == 'approve-run'][0]; c = o['calls'][1]; '|'.join([o['id'], o['move'], o['calls'][0].split('temper ', 1)[1].split(' --shown ')[0], c.split('temper ', 1)[1].split(' --shown ')[0], 'shown' if ' --shown intent.md=' in c and ' --shown tasks.md=' in c else 'no digests'])")"

# --- 8. A criterion validated by hand is confirmed by the person at Check; a deferred optional one needs no evidence ---
_at_check
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 0\n  commands:\n    test: "true"\n    coverage: echo "TOTAL 10 1 90%"\n', 1)
open(p, 'w').write(s)
p = '.temper/specs/demo/intent.md'; s = open(p).read()
s = s.replace('### Constraints', '- [ ] AC-09 [required]: the admin reads the report\n  Why: audit\n  Validate: manual - open the report and read it\n- [ ] AC-10 [optional]: a later nicety\n  Why: later\n  Validate: manual - read it\n  Deferred: not in this release\n\n### Constraints', 1)
open(p, 'w').write(s)
PYEOF
echo '[]' > .temper/evidence/check.json; "$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
assert_eq "9.8.0: the Check question asks the person to confirm the manual criterion, never the deferred optional one" "yes|Confirmed (Recommended)|confirm" \
  "$(nx "q = d['ask']; ('yes' if 'AC-09' in q['question']['question'] and 'your confirmation' in q['question']['question'] and 'AC-10' not in q['question']['question'] else 'no') + '|' + q['options'][0]['label'] + '|' + q['options'][0]['move']")"

# --- 9. The CLI's Check on a Node project: detection, node --test coverage, and mutation of JavaScript by text ---
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  _at_check
  _clear_root
  mkdir -p src test
  printf '{"name":"t","type":"module","scripts":{"test":"node --test --experimental-test-coverage"}}\n' > package.json
  printf 'export function grade(s) {\n  return "pass";\n}\n' > src/grade.js
  printf 'import test from "node:test";\nimport assert from "node:assert";\nimport { grade } from "../src/grade.js";\ntest("g", () => { assert.ok(grade(1)); });\n' > test/grade.test.js
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm "node base" >/dev/null 2>&1
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  python3 - <<'PYEOF'
import re
p = '.claude/temper.config'; s = open(p).read()
s = re.sub(r'\n  commands:\n(    .*\n)+', '\n', s)   # the sections above named Python commands: this project is detected
open(p, 'w').write(s)
PYEOF
  assert_eq "9.8.0: a Node project is detected, with node --test's own coverage" "node|node-test|True" \
    "$("$TEMPER" check detect | python3 -c "import json,sys; d=json.load(sys.stdin); print('%s|%s|%s' % (d['stack'], d['coverage']['kind'], d['mutation']))")"
  printf 'export function grade(s) {\n  if (s >= 90) return "A";\n  if (s >= 75) return "B";\n  return "F";\n}\n' > src/grade.js
  printf 'import test from "node:test";\nimport assert from "node:assert";\nimport { grade } from "../src/grade.js";\ntest("g", () => { for (const [s, g] of [[90,"A"],[89,"B"],[75,"B"],[74,"F"]]) assert.equal(grade(s), g); });\n' > test/grade.test.js
  echo '[]' > .temper/evidence/check.json; "$TEMPER" check run >/dev/null 2>&1
  assert_eq "9.8.0: Node: the suite passes, its coverage is read from node --test, and check ahead finds pinned bands catch the planted bugs" \
    "yes|yes|measured|all caught" \
    "$(_gc | grep -c '\[v\] tests pass' >/dev/null && echo yes || echo no)|$(_gc | grep -c '\[v\] coverage — .*100' >/dev/null && echo yes || echo no)|$(_planted15)"
  printf 'import test from "node:test";\nimport assert from "node:assert";\nimport { grade } from "../src/grade.js";\ntest("g", () => { assert.ok("ABF".includes(grade(95))); });\n' > test/grade.test.js
  echo '[]' > .temper/evidence/check.json; "$TEMPER" check run >/dev/null 2>&1
  assert_eq "9.8.0: Node: a test that only runs the code misses the planted bugs, which check ahead names" "measured|survivors" \
    "$(_planted15)"
else
  echo "SKIP: 9.8.0 Node cases (node or npm is not installed)"
fi

# --- 10. The text mutation engine: an operator in a string, a comment, a generic or an arrow is never a mutant ---
assert_eq "9.8.0: text mutants skip strings, comments, generics and arrows" "5|yes" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import check_run
src = '\n'.join(['// a comment: 90 < 100', 'const xs: Array<string> = [];', 'const f = (a) => a;', 'if (n >= 90 && ok === true) return "A < B";'])
m = check_run.text_mutants(src, {1, 2, 3, 4})
print('%d|%s' % (len(m), 'yes' if all('"A < B"' in s for _, s in m) else 'no'))
PYT
)"

# --- 11. temper go: the CLI runs its own steps and stops at an agent launch, a question or steps ---
_at_check
rm -rf lib unit src test package.json
python3 - <<'PYEOF'
import re
p = '.claude/temper.config'; s = open(p).read()
s = re.sub(r'\n  commands:\n(    .*\n)+', '\n', s)
s = s.replace('  coverage-threshold: 0\n', '  coverage-threshold: 80\n', 1)
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 0\n  commands:\n    test: "true"\n    coverage: echo "TOTAL 10 1 90%"\n', 1)
open(p, 'w').write(s)
PYEOF
echo '[]' > .temper/evidence/check.json; python3 -c "import json; p='.temper/gates.json'; d=json.load(open(p)); d.pop('check', None); json.dump(d, open(p,'w'))"
GO="$("$TEMPER" go 2>/dev/null)"
assert_eq "9.8.0: go at Check runs check run and the gate itself, then stops at the Commit question" "ask|check run,gate check|Commit (Recommended)" \
  "$(printf '%s' "$GO" | python3 -c "import json,sys; d=json.load(sys.stdin); print('%s|%s|%s' % (d['action'], ','.join(c.split('temper ', 1)[1] for c in d['ran']), d['ask']['options'][0]['label']))")"
assert_eq "9.8.0: go's answer is compact: no guard, view or restart" "none" \
  "$(printf '%s' "$GO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(k for k in ('guard','view','restart','run') if k in d) or 'none')")"

# --- 12. One agent per chain; independent tasks stay parallel; a chain task gated already is not gated again ---
f9_tasks | m_setup
rm -f .temper/groups.json; f9_intent true true
"$TEMPER" acceptance skip --reason "the chain cases" >/dev/null 2>&1
"$TEMPER" group start G1 >/dev/null 2>&1
assert_eq "9.8.0: Task 2 depends on Task 1: one agent builds both, in order, and gates each" "1|1,2|task start 1|task gate 1 --model|task gate 2 --model" \
  "$(nx "a = d['agents']; x = a[0]; '|'.join([str(len(a)), ','.join(str(n) for n in x['tasks']), x['before'][0].split('temper ', 1)[1], ' '.join(x['after'][1].split('temper ', 1)[1].split()[:4]), ' '.join(x['after'][2].split('temper ', 1)[1].split()[:4])])")"
assert_eq "9.8.0: the chain agent's prompt names the tasks in order and its model" "yes|yes" \
  "$(nx "p = d['agents'][0]['prompt']; ('yes' if 'Tasks: 1, 2 (a chain' in p else 'no') + '|' + ('yes' if '\nModel: ' in p else 'no')")"
assert_exit "9.8.0: task gate --if-running on a task that is not running does nothing and succeeds" 0 "$TEMPER" task gate 2 --model haiku --if-running
assert_exit "9.8.0: without --if-running it still refuses" 1 "$TEMPER" task gate 2 --model haiku
python3 - <<'PYEOF'
import json
p = '.temper/groups.json'; d = json.load(open(p))
d['groups']['G1']['status'] = 'parked'; d['groups']['G1']['parked_reason'] = 'Task 1 failed 3 attempts'
json.dump(d, open(p, 'w'))
PYEOF
assert_eq "9.8.0: in a group a sibling's failure parked, --if-running on a task never started does nothing and succeeds" "0|1" \
  "$("$TEMPER" task gate 2 --model haiku --if-running >/dev/null 2>&1; echo $?)|$("$TEMPER" task gate 2 --model haiku --if-running 2>&1 | grep -c 'nothing to gate')"
assert_eq "9.8.0: without --if-running a parked group still refuses, naming the park" "1|1" \
  "$("$TEMPER" task gate 2 --model haiku >/dev/null 2>&1; echo $?)|$("$TEMPER" task gate 2 --model haiku 2>&1 | grep -c 'is parked')"
python3 - <<'PYEOF'
import json
p = '.temper/groups.json'; d = json.load(open(p))
d['groups']['G1']['status'] = 'running'; d['groups']['G1'].pop('parked_reason', None)
json.dump(d, open(p, 'w'))
PYEOF
python3 - <<'PYEOF'
p = '.temper/specs/demo/tasks.md'; s = open(p).read()
s = s.replace('**File:** `src/b.sh`, `unit/b_test.sh`\n**Depends:** Task 1', '**File:** `src/b.sh`, `unit/b_test.sh`\n**Depends:** none', 1)
open(p, 'w').write(s)
PYEOF
assert_eq "9.8.0: independent tasks with no shared file keep an agent each, launched together" "2|1|2" \
  "$(nx "a = d['agents']; '%d|%s|%s' % (len(a), ','.join(str(n) for n in a[0]['tasks']), ','.join(str(n) for n in a[1]['tasks']))")"

# --- 13. The CLI drafts the commit message ---
fresh; gpass intent plan build review check commit; _at commit
"$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --html >/dev/null 2>&1
mkdir -p src; echo "the feature" > src/feature_x.sh   # uncommitted code: the commit carries it, with a feature message
assert_eq "9.8.0: the commit step carries a message drafted from the intent's title, no placeholder" "yes|no" \
  "$(nx "s = [x for x in d.get('steps', []) if ' spec commit ' in x]; ('yes' if s and \" spec commit 'feat(demo): \" in s[0] else 'no') + '|' + ('yes' if any('{' in x for x in s) else 'no')")"

# --- 14. A wrong locked acceptance test has a way out; a step back carries what failed; Design's task changes; scope at commit ---
# (the benchmark's costliest runs: a locked test the code could not pass, Build sent back twice without the failing output)
f9_tasks | m_setup
rm -f .temper/groups.json; f9_intent true true
mkdir -p .temper/specs/demo/acceptance
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01(self):\n        self.assertEqual(1 + 1, 2)\n' > .temper/specs/demo/acceptance/test_ac.py
ACMD="python3 -m unittest discover -s .temper/specs/demo/acceptance -t .temper/specs/demo/acceptance"
"$TEMPER" acceptance lock --cmd "$ACMD" >/dev/null 2>&1
assert_exit "9.8.0: a lock is taken once: a builder cannot lock a test again after changing it" 1 "$TEMPER" acceptance lock --cmd "$ACMD"
assert_exit "9.8.0: only with a reason does the person reopen it" 1 "$TEMPER" acceptance reopen
printf '\n# a builder edits it\n' >> .temper/specs/demo/acceptance/test_ac.py
echo 'x' > .temper/specs/demo/acceptance/test_extra.py
assert_exit "9.8.0: acceptance restore puts the locked files back" 0 "$TEMPER" acceptance restore
assert_eq "9.8.0: restored as locked: the edit is gone, the file added after the lock too" "no|no" \
  "$(grep -q 'a builder edits it' .temper/specs/demo/acceptance/test_ac.py && echo yes || echo no)|$([[ -f .temper/specs/demo/acceptance/test_extra.py ]] && echo yes || echo no)"
# WP23: the locked tests run when Build ends, so a failing one is met at the Build gate and asked there
gfail build "acceptance tests written before Build" "changed after they were locked: .temper/specs/demo/acceptance/test_ac.py"
assert_eq "WP23: a changed locked test at the Build gate: the first option puts it back, and Build is checked again" "restore-tests|recommended|acceptance restore|gate build" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o.get('id'), 'recommended' if o.get('recommended') else 'not recommended', o['calls'][0].split('temper ', 1)[1], o['calls'][-1].split('temper ', 1)[1]])")"
gfail build "acceptance tests written before Build" "FAIL: test_ac01 (T.test_ac01) AssertionError: 404 != 403"
bash -c "$(nx "d['agents'][0]['after'][-1]")" >/dev/null 2>&1   # the triage agent gave no verdict
_ids15() { nx "o = d['ask']['options'] + (d['ask'].get('more') or {}).get('options', []); ','.join(sorted('%s%s' % (x.get('id'), '*' if x.get('recommended') else '') for x in o if x.get('id') in ('redo', 'correct-test')))"; }
assert_eq "WP23: a failing locked test at the Build gate with no triage verdict: Build mends the code first, or the person says the test is wrong" "correct-test,redo*" \
  "$(_ids15)"
"$TEMPER" state redo build --reason "acceptance tests written before Build: FAIL: test_ac01 (T.test_ac01) AssertionError: 404 != 403" >/dev/null 2>&1
gfail build "acceptance tests written before Build" "FAIL: test_ac01 (T.test_ac01) AssertionError: 404 != 403"
assert_eq "WP23: after a fix pass left the locked test failing, correcting the test is the recommended way" "correct-test*,redo" \
  "$(_ids15)"
assert_eq "WP23: correcting a test at the Build gate asks for the person's reason and reopens the lock with it" "yes|acceptance reopen --reason '{reason}'" \
  "$(nx "o = next((x for x in (d.get('ask') or {}).get('options', []) + ((d.get('ask') or {}).get('more') or {}).get('options', []) if x.get('id') == 'correct-test'), {}); ('yes' if o.get('reason') else 'no') + '|' + ' '.join(c.split('temper ', 1)[-1] for c in o.get('calls') or [])")"
"$TEMPER" acceptance reopen --reason "The test asks for what the intent does not say" >/dev/null 2>&1
assert_eq "WP23: reopened at Build, the writer corrects the test the failure names, then integrate and the Build gate run" "work|temper:temper-acceptance|yes|yes|integrate|gate build" \
  "$(nx "a = (d.get('agents') or [{}])[0]; af = [c.split('temper ', 1)[-1] for c in a.get('after') or ['', '']]; '|'.join([d['action'], str(a.get('type')), 'yes' if 'Correction: the person says a locked test is wrong (The test asks for what the intent does not say)' in a.get('prompt', '') else 'no', 'yes' if '404 != 403' in a.get('prompt', '') else 'no', af[-2], af[-1]])")"
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 80\n  commands:\n    test: "true"\n', 1)
open(p, 'w').write(s)
PYEOF
echo '[]' > .temper/evidence/build.json; "$TEMPER" check build-checks >/dev/null 2>&1
assert_eq "WP23: reopened and not locked again, the Build gate fails the acceptance row" "yes" \
  "$(_gb | grep -c '\[x\] acceptance tests written before Build — reopened to correct a test' >/dev/null && echo yes || echo no)"
printf '\n# corrected against the intent\n' >> .temper/specs/demo/acceptance/test_ac.py
assert_exit "9.8.0: a reopened lock is locked again" 0 "$TEMPER" acceptance lock --cmd "$ACMD"
echo '[]' > .temper/evidence/build.json; "$TEMPER" check build-checks >/dev/null 2>&1
assert_eq "WP23: the corrected tests pass at the Build gate, and the row names the person's reason" "yes" \
  "$(_gb | grep -c '\[v\] acceptance tests written before Build — they pass, as the person corrected them after the lock (The test asks for what the intent does not say)' >/dev/null && echo yes || echo no)"
assert_exit "9.8.0: and it is locked once more" 1 "$TEMPER" acceptance lock --cmd "$ACMD"
gpass build review; "$TEMPER" state advance build_complete review >/dev/null 2>&1; "$TEMPER" state advance review_complete check >/dev/null 2>&1
# The corrected tests fail again (a measured run: a second wrong test): the acceptance row alone fails. The tests row reads
# the suite's runs only, so the person still gets the triage and the way to correct a test, not a step back to Build
# that cannot make right code pass a wrong test. The row carries executed_by cli, as check_run.py writes it (WP30-3).
cat > .temper/evidence/check.json <<'JSON'
[{"claim": "acceptance (written before Build), corrected after the lock: The test asks for what the intent does not say", "cmd": "x", "exit_code": 1,
  "output": "FAIL: test_ac05 AssertionError: 401 != 423", "executed_by": "cli"}]
JSON
ev_green check "tests: the suite (run by the CLI)"   # WP30: the suite's run, made by the CLI (a claimed one counts nowhere)
assert_eq "9.8.0: a corrected acceptance run that fails again fails its own row, never the tests row" "yes|yes" \
  "$(_gc | grep -c '\[v\] tests pass' >/dev/null && echo yes || echo no)|$(_gc | grep -c '\[x\] acceptance tests written before Build' >/dev/null && echo yes || echo no)"

# a step back from Check carries the failing output to Build's fix pass (WP19: the planted bug score is no row of Check,
# so no surviving mutant goes with it)
rm -f .temper/feedback-loops.json
cat > .temper/evidence/check.json <<'JSON'
[{"claim": "acceptance (written before Build)", "cmd": "x", "exit_code": 1, "output": "FAIL: test_ac08 AssertionError: 404 != 200"}]
JSON
"$TEMPER" state loop check build --reason "The check found a real problem" >/dev/null 2>&1
assert_eq "9.8.0: the step back keeps the failing test's output" "yes" \
  "$(python3 -c "
import json; f = json.load(open('.temper/feedback-loops.json'))['active_loops'][0]['findings']; j = ' '.join(f)
print('yes' if '404 != 200' in j else 'no')")"
python3 -c "
import json, re; ids = re.findall(r'^## Group (G[0-9]+)', open('.temper/specs/demo/tasks.md').read(), re.M)
json.dump({'version': 1, 'slug': 'demo', 'groups': {g: {'status': 'passed', 'gate': {'verdict': 'PASS'}} for g in ids},
           'integration': {'verdict': 'PASS'}}, open('.temper/groups.json', 'w'))"   # the fix pass: the groups are built and merged (WP28: no built_before)
assert_eq "9.8.0: the fix pass is told the acceptance tests are locked, and to report a wrong one instead of editing it" "yes" \
  "$(nx "'yes' if any('The acceptance tests are locked: change the code, never a test' in a['prompt'] for a in d.get('agents', [])) else 'no'")"

# Design changed the approved tasks: the Design question says so, and Continue approves them with the design
f9_tasks | m_setup
gpass design
_at design
python3 - <<'PYEOF'
p = '.temper/specs/demo/tasks.md'; s = open(p).read()
s = s.replace('**File:** `src/a.sh`, `unit/a_test.sh`', '**File:** `src/a.sh`, `unit/a_test.sh`, `src/floor.sh`', 1)
open(p, 'w').write(s)
PYEOF
assert_eq "9.8.0: the Design question names the changed tasks and what Continue does with them" "yes" \
  "$(nx "'yes' if 'the check passed. Design changed the plan' in d['ask']['question']['question'] and 'Continue approves them with the design. Continue to Build?' in d['ask']['question']['question'] else 'no'")"
assert_eq "9.8.0: and says what changed, from the tasks kept at the plan gate" "yes" \
  "$(nx "'yes' if '(tasks.md: Task 1 gains src/floor.sh)' in d['ask']['question']['question'] else 'no'")"
"$TEMPER" state advance design_complete build >/dev/null 2>&1
rm -f .temper/groups.json
assert_exit "9.8.0: after Continue, Build starts on the changed tasks (no 'the approved plan changed')" 0 "$TEMPER" group start G1

# files outside the plan at the commit gate: the person adds them to the plan there
fresh; f9_tasks > .temper/specs/demo/tasks.md
gpass intent plan build review check; _at commit
gfail commit "blast radius" "changed outside declared files: ledger/export.py, docs/x.md"
assert_eq "9.8.0: the commit gate's scope failure offers Add to plan first, recording each file as the person's drift answer" "Add to plan (Recommended)|drift|evidence add --stage build --phase feedback --claim 'drift ledger/export.py: Add to plan: the person, at the commit gate'|gate commit" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['label'], o['move'], o['calls'][0].split('temper ', 1)[1], o['calls'][-1].split('temper ', 1)[1]])")"

# --- 15. Check runs while Review reads; Design on a fully specified plan; the triage; the rules checklist; states ---
f9_tasks | m_setup
rm -f .temper/groups.json; f9_intent true true
python3 - <<'PYEOF'
p = '.claude/temper.config'; s = open(p).read()
s = s.replace('  coverage-threshold: 80\n', '  coverage-threshold: 80\n  commands:\n    test: "true"\n', 1)
open(p, 'w').write(s)
PYEOF
# WP22: the suite leaves a .coverage file the project does not ignore, and counts its runs in the project folder (the
# planted bugs of check ahead run it in folders of their own, which this count leaves out)
printf 'pwd -P >> "%s"\necho x > .coverage\necho ok\n' "$WORKDIR/.git/count15" > .git/cov15.sh
sed -i "s|^    test: \"true\"$|    test: \"bash $WORKDIR/.git/cov15.sh\"|" .claude/temper.config
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
assert_eq "9.8.0: the Review agent's launch first starts check ahead in the background (in a feature run the planted bugs only)" "yes" \
  "$(nx "'yes' if any(c.endswith('temper check ahead') for c in d['agents'][0].get('before', [])) else 'no'")"
_ahead15() { # check ahead, then a wait for its end: the planted bug score it writes last, no longer running
  local i
  rm -f .temper/evidence/mutation.json
  "$TEMPER" check ahead >/dev/null 2>&1
  for i in $(seq 1 300); do
    [[ -f .temper/evidence/mutation.json ]] && ! grep -q '"state": *"running"' .temper/evidence/mutation.json && return 0
    sleep 0.2
  done
  return 1
}
_runs15() { if [[ -f .git/count15 ]]; then grep -cx "$WORKDIR" .git/count15 | tr -d ' '; else echo 0; fi; }
_reused15() { python3 -c "
import json
rows = [r for r in json.load(open('.temper/evidence/check.json')) if 'tests: the suite' in r.get('claim', '')]
print('yes' if rows and rows[-1].get('reused') else 'no')" 2>/dev/null || echo 'no row'; }
# WP23 (mechanism 10): a feature run's store is warm from integrate (its checks, check build-checks), and check ahead
# beside Review plants bugs only
: > .git/count15; "$TEMPER" check build-checks >/dev/null 2>&1
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "WP23: with a suite that leaves .coverage, Check uses the run integrate made: one suite run in all, and the suite row of check run says reused" \
  "runs=1|reused=yes" "runs=$(_runs15)|reused=$(_reused15)"
_ahead15; _ah15="$(_runs15)"
mkdir -p src; echo "changed after" > src/later.sh
echo '[]' > .temper/evidence/check.json
"$TEMPER" check run >/dev/null 2>&1
assert_eq "WP22: check ahead on the same tree runs nothing; a tree changed since that run is measured again by check run, and its row is not reused" \
  "ahead again=1|changed=2|reused=no" "ahead again=$_ah15|changed=$(_runs15)|reused=$(_reused15)"
rm -f src/later.sh .coverage .git/cov15.sh .git/count15

# Design (WP14): a complex plan goes on to Build whatever Intent asked and whatever its risk; the person's ask adds it
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set complexity complex >/dev/null 2>&1; gpass plan
assert_eq "9.8.0: complex, nothing asked at Intent, risk below H: the plan goes on to Build, no Design" "Plan: the check passed. Approve the plan and continue to Build?" \
  "$(nx "d['ask']['question']['question']")"
"$TEMPER" state set want_design true >/dev/null 2>&1
assert_eq "WP14: complex and the person asked for Design: Design runs" "Continue to Design (Recommended)" "$(nx "d['ask']['options'][0]['label']")"
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set complexity complex >/dev/null 2>&1; gpass plan; "$TEMPER" risk --raise H --reason "it moves money" >/dev/null 2>&1
fresh_reviewed
assert_eq "WP14: complex at risk H runs no Design when nothing was asked (WP12: the digests shown)" "ask-every-stage,True|state advance plan_complete build|shown" \
  "$(nx "o = d['ask']['options'][0]; c = o['calls'][-1]; '%s,%s' % (o['id'], bool(o.get('recommended'))) + '|' + c.split('temper ', 1)[1].split(' --shown ')[0] + ('|shown' if ' --shown intent.md=' in c and ' --shown tasks.md=' in c else '|no digests')")"
fresh
cat > .temper/specs/demo/intent.md <<'INT'
**Status:** draft

## Problem
The demo.

### Success Criteria
- [ ] AC-01 [required]: alpha works
  Why: a
  Validate: manual - check it

### Open Questions

- Blocking: Who may run it? choices: Admins only | Clerks and admins (house rule) | Anyone
INT
assert_eq "WP14: the Intent gate fails on the open question and records nothing for Design (intent_asked is gone)" "FAIL|" \
  "$("$TEMPER" gate intent >/dev/null 2>&1; python3 -c "import json; print(json.load(open('.temper/gates.json'))['intent']['verdict'])")|$("$TEMPER" state get intent_asked 2>/dev/null)"
assert_eq "9.8.0: a choice marked (house rule) is listed first, as the recommended answer" "Who may run it? choices: Clerks and admins (house rule) | Admins only | Anyone" \
  "$(nx "d['blocking'][0]")"
assert_eq "9.8.0: a draft intent with no Rules covered section fails the rules checklist row, naming every item" "yes" \
  "$({ "$TEMPER" gate intent 2>&1 || true; } | grep -c 'rules checklist covered — ### Rules covered has no asked, assumed or not applicable line for: Who, When, How much, Exempt, States, Where it shows, Exceptions' >/dev/null && echo yes || echo no)"
printf '\n### Rules covered\n\n- Who: asked\n- When: not applicable (no time rule)\n- How much: not applicable\n- Exempt: not applicable (every run is reported)\n- States: assumed (none change)\n- Where it shows: assumed\n' >> .temper/specs/demo/intent.md
assert_eq "9.8.0: an item left out still fails the row" "yes" \
  "$({ "$TEMPER" gate intent 2>&1 || true; } | grep -c 'line for: Exceptions$' >/dev/null && echo yes || echo no)"
printf -- '- Exceptions: asked (twice, gone)\n' >> .temper/specs/demo/intent.md
assert_eq "9.8.0: every item covered: the row passes" "yes" \
  "$({ "$TEMPER" gate intent 2>&1 || true; } | grep -c '\[v\] rules checklist covered' >/dev/null && echo yes || echo no)"

# the triage of a failing locked test sets which option the Check question recommends
f9_tasks | m_setup
rm -f .temper/groups.json; f9_intent true true
mkdir -p .temper/specs/demo/acceptance
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01(self):\n        self.assertEqual(1 + 1, 2)\n' > .temper/specs/demo/acceptance/test_ac.py
ACMD="python3 -m unittest discover -s .temper/specs/demo/acceptance -t .temper/specs/demo/acceptance"
"$TEMPER" acceptance lock --cmd "$ACMD" >/dev/null 2>&1
# WP23: at the Build gate, where integrate ran the locked tests
gfail build "acceptance tests written before Build" "FAIL: test_ac01 AssertionError: 1 != 2"
assert_eq "WP23: a failing locked test at the Build gate is first triaged by an agent that changes nothing" "work|temper:temper-acceptance|yes|acceptance triaged --reason" \
  "$(nx "a = (d.get('agents') or [{}])[0]; '|'.join([d['action'], str(a.get('type')), 'yes' if 'Triage: a locked acceptance test fails at Build' in a.get('prompt', '') else 'no', ' '.join((a.get('after') or ['temper none'])[-1].split('temper ', 1)[-1].split()[:3])])")"
STAMP="$(nx "d['agents'][0]['after'][-1]")"
"$TEMPER" acceptance triage --reason "test: its helper reads the list answer in the wrong shape" >/dev/null 2>&1
bash -c "$STAMP" >/dev/null 2>&1
assert_eq "9.8.0: the triage says the test is wrong: correcting it is recommended, and the question says why" "Correct the acceptance test (Recommended)|yes" \
  "$(nx "d['ask']['options'][0]['label'] + '|' + ('yes' if 'The triage says the test looks wrong: its helper reads the list answer in the wrong shape' in d['ask']['question']['question'] else 'no')")"
"$TEMPER" acceptance triage --reason "code: the route answers 200 where AC-01 says 403" >/dev/null 2>&1
bash -c "$STAMP" >/dev/null 2>&1
assert_eq "WP23: the triage says the code is wrong: no question; the CLI's own fix pass comes next" "fix pass" \
  "$(nx "'fix pass' if d['action'] in ('auto', 'work') and (any(a['type'] == 'temper:temper-build' for a in d.get('agents') or []) or any('state redo build' in c for c in d.get('calls') or [])) else d['action']")"
gfail build "acceptance tests written before Build" "FAIL: test_ac01 AssertionError: another failure"
assert_eq "9.8.0: a new failure gets a new triage" "work|temper:temper-acceptance|triage" \
  "$(nx "a = (d.get('agents') or [{}])[0]; '|'.join([d['action'], str(a.get('type')), 'triage' if 'Triage: a locked acceptance test fails at Build' in a.get('prompt', '') else 'no triage'])")"

# every state the intent lists is named in an acceptance test
f9_tasks | m_setup
rm -f .temper/groups.json; f9_intent true true
printf '\n**States:** active, canceled\n' >> .temper/specs/demo/intent.md
mkdir -p .temper/specs/demo/acceptance
printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01_active(self):\n        self.assertEqual("active", "active")\n' > .temper/specs/demo/acceptance/test_ac.py
assert_eq "9.8.0: the lock refuses tests that never name a listed state" "1|yes" \
  "$("$TEMPER" acceptance lock --cmd "$ACMD" >/dev/null 2>&1; echo $?)|$({ "$TEMPER" acceptance lock --cmd "$ACMD" 2>&1 || true; } | grep -c 'no acceptance test names the state(s) canceled' >/dev/null && echo yes || echo no)"
printf '    def test_ac02_canceled_reads_back(self):\n        self.assertEqual("canceled", "canceled")\n' >> .temper/specs/demo/acceptance/test_ac.py
assert_exit "9.8.0: with a test for each state, it locks" 0 "$TEMPER" acceptance lock --cmd "$ACMD"

# --- 9.8.0: the words of a question match the run (from the flow explainer's read of every question) ---
# More options lists what is behind it, also after Make a small change went in or Teach Me went out
fresh; gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim "src/demo.sh:3 a name is not trimmed" --severity medium >/dev/null 2>&1
gpass review
assert_eq "9.8.0: More options at Review names exactly the options behind it" "same|1" \
  "$(nx "m = [o for o in d['ask']['options'] if o['label'] == 'More options'][0]; ('same' if m['description'] == ', '.join(o['label'] for o in d['ask']['more']['options']) else m['description'])")|$(nx "str(sum(1 for o in d['ask']['more']['options'] if o['label'] == 'Make a small change'))")"
# a fix run says Fix where a /temper:temper run says Build, and Save for later names /temper:fix
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1; _base_known
mkdir -p .temper/specs/demo-bug; printf '# Root cause\nx\n' > .temper/specs/demo-bug/rca.md
_at fix; gpass build fix rca
assert_eq "9.8.0: a fix run's Fix question: the Fix agent makes a change, and Save for later names /temper:fix" "1|1|0" \
  "$(nx "o = {x['label']: x for x in d['ask']['options']}; '|'.join([str(int('the Fix agent makes it, and Fix is checked again' in o['Change something']['description'])), str(int('/temper:fix takes it up again' in o['Save for later']['description'])), str(int('Build' in o['Change something']['description']))])")"
_at review; "$TEMPER" evidence add --stage review --claim "src/demo.sh:3 the input is not checked" --severity critical >/dev/null 2>&1
gfail review "no blocking findings" "1 open finding"
assert_eq "9.8.0: a fix run's failed Review asks to loop back to Fix, as its first option does" "1|Loop back to Fix (Recommended)" \
  "$(nx "str(int(d['ask']['question']['question'].endswith('Loop back to Fix?'))) + '|' + d['ask']['options'][0]['label']")"
_at check; gpass review check
assert_eq "9.8.0: a fix run's small change says there is no loop back to Fix" "1|0" \
  "$(nx "o = [x for x in d['ask']['options'] + d['ask'].get('more', {}).get('options', []) if x['label'] == 'Make a small change'][0]; str(int('no loop back to Fix' in o['description'])) + '|' + str(int('Build' in o['description']))")"
assert_eq "9.8.0: the page question is gone from the CLI (the page is written with no question)" "0" "$(_flow_text | grep -c 'def page_question')"
setup

# --- 9.8.0: earlier attempts' branches leave `git branch`, and old ones are dropped (state clear) ---
setup; [[ "$PWD" == "$WORKDIR" ]] || exit 1   # a fresh repository: no branch or kept ref of an earlier case file counts
rm -rf .git; git init -q .; git config user.email t@example.com; git config user.name T
git commit -q --allow-empty -m base
"$TEMPER" state init demo >/dev/null 2>&1; _base_known
git branch temper/demo/replan-20200101T000000Z/G1; git branch "temper/demo/replan-$(date -u +%Y%m%dT%H%M%SZ)/G2"
git branch temper/demo/earlier-20200101T000000Z/T1; git branch temper/demo/G3
git worktree add -q .claude/worktrees/kept-probe temper/demo/earlier-20200101T000000Z/T1 2>/dev/null
out="$("$TEMPER" state clear 2>&1)"
assert_eq "tidy: earlier attempts' branches leave git branch for refs/temper/kept, and the run says so" "1|2" \
  "$(printf '%s' "$out" | grep -c '^OK: 2 branch(es) of earlier attempts moved out of git branch')|$(git for-each-ref 'refs/temper/kept/demo/' | wc -l | tr -d ' ')"
assert_eq "tidy: a branch checked out in a worktree stays, and a branch of the run itself is not touched" "yes|yes" \
  "$(git show-ref --verify --quiet refs/heads/temper/demo/earlier-20200101T000000Z/T1 && echo yes || echo no)|$(git show-ref --verify --quiet refs/heads/temper/demo/G3 && echo yes || echo no)"
git worktree remove --force .claude/worktrees/kept-probe
"$TEMPER" state init demo >/dev/null 2>&1; _base_known
out="$("$TEMPER" state clear 2>&1)"
assert_eq "tidy: a kept attempt older than 30 days is dropped, a recent one stays" "1|no|yes|yes" \
  "$(printf '%s' "$out" | grep -c 'earlier attempt(s) kept more than 30 days dropped')|$(git show-ref --quiet refs/temper/kept/demo/replan-20200101T000000Z/G1 && echo yes || echo no)|$(git for-each-ref --format=x 'refs/temper/kept/demo/replan-*/G2' | grep -q x && echo yes || echo no)|$(git show-ref --quiet refs/temper/kept/demo/earlier-20200101T000000Z/T1 && echo yes || echo no)"
printf 'build:\n  grouped:\n    keep-days: 0\n' >> .claude/temper.config
git update-ref refs/temper/kept/demo/replan-20200101T000000Z/G9 HEAD
"$TEMPER" state init demo >/dev/null 2>&1; _base_known; "$TEMPER" state clear >/dev/null 2>&1
assert_eq "tidy: keep-days 0 keeps every kept attempt" "yes" "$(git show-ref --quiet refs/temper/kept/demo/replan-20200101T000000Z/G9 && echo yes || echo no)"
setup; [[ "$PWD" == "$WORKDIR" ]] || exit 1; rm -rf .git; git init -q .
