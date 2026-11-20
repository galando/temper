# Case file 60 (WP19): checks judged against the project. Coverage is judged by one rule in a fixed order
# (`python3 scripts/check_run.py coverage-verdict`); a measurement that was not taken is a third state of a gate
# row (`"pass": null`, `"state": "not measured"`) in every gate, printer, view and question; the key
# check.coverage-threshold counts only when the project's config holds it; and the planted bug score is information
# beside Review: `check ahead` writes .temper/evidence/mutation.json, `check run` plants no bug, and no row of Check
# names it. Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, _at, _unattended, nx, vw) are used here.
# Token: w19.
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_repo60() { # a git repository under the run: one source file in one commit, the run's own files left out
  rm -rf .git src lib unit Cargo.toml; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_nokey60() { sed -i '/^  coverage-threshold:/d' .claude/temper.config; }   # the project's config holds no old key
_cmds60() { # _cmds60 <test command> [coverage command]: check.commands at the top of the config's check block
  python3 -B - "$1" "${2:-}" <<'PY'
import sys
p = ".claude/temper.config"
s = open(p).read()
lines = "  commands:\n    test: \"%s\"\n" % sys.argv[1] + ("    coverage: \"%s\"\n" % sys.argv[2] if sys.argv[2] else "")
s = s.replace("check:\n", "check:\n" + lines, 1) if "\ncheck:\n" in "\n" + s else s + "check:\n" + lines
open(p, "w").write(s)
PY
}
_x60() { # _x60 <python code over d, the JSON of temper next, that sets r>: prints r
  python3 -B - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def section(card, sid):
    return next((s for s in (card or {}).get("sections") or [] if s.get("id") == sid), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
_row60() { # _row60 <stage> <name>: the row of that exact name in gates.json, as pass:state (pass alone with no state)
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("no row" if r is None else ("%s:%s" % (r.get("pass"), r.get("state")) if "state" in r else str(r.get("pass"))))
PY
}
_verdict60() { python3 -B -c "import json; print(json.load(open('.temper/gates.json')).get('$1', {}).get('verdict'))" 2>/dev/null; }
_cov_line60() { # printed rows on stdin: "not measured" when each coverage line is marked [?] and says so, else one
  python3 -B -c "
import re, sys
ls = [l.strip() for l in sys.stdin.read().splitlines() if re.match(r'\s*\[.\] coverage\b', l)]
if not ls:
    print('no coverage line')
elif all(l.startswith('[?]') and 'not measured' in l for l in ls):
    print('not measured')
else:
    print(ls[0][:160])"
}
_cargo60() { # a project with only a Cargo.toml (no coverage tool for the stack) and a fake cargo on PATH that exits 0
  printf '[package]\nname = "demo"\nversion = "0.1.0"\n' > Cargo.toml
  mkdir -p .temper/bin60; printf '#!/bin/sh\nexit 0\n' > .temper/bin60/cargo; chmod +x .temper/bin60/cargo
}
_py60() { # a Python change on top of a base commit: lib/calc.py gains bands, unit/test_calc.py pins each one
  rm -rf lib unit; mkdir -p lib unit; : > lib/__init__.py; : > unit/__init__.py
  printf 'def grade(score):\n    return "pass"\n' > lib/calc.py
  printf 'import unittest\nfrom lib import calc\n\n\nclass T(unittest.TestCase):\n    def test_pass(self):\n        self.assertEqual(calc.grade(90), "pass")\n' > unit/test_calc.py
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m 'the base of the change'
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  printf 'def grade(score):\n    if score >= 90:\n        return "A"\n    if score >= 75:\n        return "B"\n    if score >= 60:\n        return "C"\n    return "F"\n' > lib/calc.py
  cat > unit/test_calc.py <<'PYEOF'
import unittest
from lib import calc


class T(unittest.TestCase):
    def test_bands(self):
        for s, g in [(90, "A"), (89, "B"), (75, "B"), (74, "C"), (60, "C"), (59, "F"), (100, "A"), (0, "F")]:
            self.assertEqual(calc.grade(s), g, s)
PYEOF
}

# --- 1. the rule, one pure function: each row of the spec's table fed to check_run.py coverage-verdict ---
# The input is one JSON object a call, on standard input: {"measure": {"total", "command", "exit", "hint"}, "base",
# "changed": {"ran", "missed"} or null, "threshold"}. `command` is false when the stack has no coverage command, `exit`
# is the exit of the coverage run (127: the program could not start), `changed` counts the changed executable lines
# that ran and that were missed (null: no line data), `threshold` is the key's value (null: the config holds none).
# The output is the verdict as one JSON object on its last line: {"state", "rule", "value", "floor", "why"}.
_rule60="$(python3 -B - "$REPO_ROOT/scripts/check_run.py" <<'PY'
import json, subprocess, sys
HINT = "set check.commands.coverage (cargo llvm-cov) to measure coverage"
def m(total=None, command=True, exit=0):
    return {"total": total, "command": command, "exit": exit, "hint": "" if command else HINT}
rows = [
    ("a", {"measure": m(70.0), "base": 71, "changed": {"ran": 10, "missed": 2}, "threshold": None}, "srf"),
    ("b", {"measure": m(90.0), "base": 92, "changed": {"ran": 17, "missed": 3}, "threshold": None}, "sf"),
    ("c", {"measure": m(70.0), "base": 71, "changed": {"ran": 6, "missed": 6}, "threshold": None}, "sr"),
    ("d", {"measure": m(70.4), "base": 71, "changed": {"ran": 5, "missed": 4}, "threshold": None}, "sr"),
    ("e", {"measure": m(69.9), "base": 71, "changed": None, "threshold": None}, "sr"),
    ("f", {"measure": m(80.0), "base": None, "changed": {"ran": 10, "missed": 2}, "threshold": None}, "base"),
    ("g", {"measure": m(None, command=False, exit=None), "base": 71, "changed": None, "threshold": None}, "hint"),
    ("h", {"measure": m(55.0), "base": None, "changed": None, "threshold": 80}, "sr"),
    ("i", {"measure": m(None, command=False, exit=None), "base": None, "changed": None, "threshold": 80}, "s"),
    ("j", {"measure": m(None, exit=127), "base": 71, "changed": None, "threshold": None}, "s"),
]
out = []
for name, row, show in rows:
    p = subprocess.run([sys.executable, "-B", sys.argv[1], "coverage-verdict"], input=json.dumps(row),
                       capture_output=True, text=True)
    try:
        v = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        out.append("%s=no verdict" % name)
        continue
    f = v.get("floor")
    parts = [str(v.get("state"))]
    if "r" in show:
        parts.append(str(v.get("rule")))
    if "f" in show:
        parts.append("%g" % f if isinstance(f, (int, float)) else str(f))
    if show == "base":
        parts.append("no base value" if str(v.get("why", "")).startswith("no base value") else "why: %s" % v.get("why"))
    if show == "hint":
        parts.append("hint" if HINT in str(v.get("why", "")) else "why: %s" % v.get("why"))
    out.append("%s=%s" % (name, "/".join(parts)))
print("|".join(out))
PY
)"
assert_eq "w19 rule table: each row of the table gives its state, its rule and its floor" \
  "a=pass/changed lines/71|b=pass/80|c=fail/changed lines|d=pass/total|e=fail/total|f=not measured/no base value|g=not measured/hint|h=fail/threshold|i=not measured|j=not measured" \
  "$_rule60"

# --- 2. a project with no coverage tool: the coverage row is the third state, and the gate passes ---
fresh; _repo60; _nokey60; _cargo60
gpass intent plan build review; _at check
PATH="$WORKDIR/.temper/bin60:$PATH" "$TEMPER" check run >/dev/null 2>&1
_gate60="$(PATH="$WORKDIR/.temper/bin60:$PATH" "$TEMPER" gate check 2>&1)"
assert_eq "w19 no tool is the third state: the gate passes, the row coverage is pass null and not measured, printed [?]" \
  "PASS|None:not measured|[?]" \
  "$(_verdict60 check)|$(_row60 check coverage)|$(python3 -B -c "
import re, sys
l = next((x.strip() for x in sys.argv[1].splitlines() if re.match(r'\s*\[.\] coverage\b', x)), '')
print(l[:3] or 'no coverage line')" "$_gate60")"

# --- 3. with that ledger, no printer, view or question marks the row passed, and each says not measured ---
_view60() { # the view's checks and check_markers entry of coverage: "not measured" when it says so and is not passed
  vw "c = next((x for x in d.get('checks') or [] if x.get('name') == 'coverage'), None); m = next((x for x in d.get('check_markers') or [] if x.get('name') == 'coverage'), None); ('checks=' + ('not measured' if c and c.get('pass') is not True and c.get('state') == 'not measured' else str(c)[:120])) + '|markers=' + ('not measured' if m and m.get('state') not in ('pass', 'fail') and 'not measured' in str(m.get('detail')) else str(m)[:120])"
}
_commit60="$(_x60 "s = section(d.get('card'), 'coverage'); t = [str(x.get('text', '')) for x in (s or {}).get('rows') or []]
r = '%s:%s' % ((d.get('ask') or {}).get('id'), 'not measured' if t and any('not measured' in x for x in t) and not any(re.search(r'\bpass(ed)?\b', x) for x in t) else 'card: %s' % t)")"
assert_eq "w19 no printer says pass: the gate, --brief, the report, the view and the commit question say not measured" \
  "gate=not measured|brief=not measured|report=not measured|checks=not measured|markers=not measured|commit=check.pass:not measured" \
  "gate=$(_cov_line60 <<<"$_gate60")|brief=$(PATH="$WORKDIR/.temper/bin60:$PATH" "$TEMPER" gate check --brief 2>&1 | _cov_line60)|report=$("$TEMPER" report 2>&1 | _cov_line60)|$(_view60)|commit=$_commit60"

# --- the run the person started at the approval moves on past a coverage not measured; no rule repairs it ---
_unattended check; _repo60; _nokey60; _cargo60
PATH="$WORKDIR/.temper/bin60:$PATH" "$TEMPER" check run >/dev/null 2>&1
PATH="$WORKDIR/.temper/bin60:$PATH" "$TEMPER" gate check >/dev/null 2>&1
assert_eq "w19 a coverage not measured moves the unattended run on to the commit, with no stop and no repair" "auto|True" \
  "$(nx "d['action'] + '|' + str(any(c.endswith('state advance check_complete commit') for c in d.get('calls') or []))")"
rm -f Cargo.toml

# --- 4. the old key counts only when the project's config holds it; its failed row says where the 80 comes from ---
fresh; _repo60; _cmds60 true "echo 'TOTAL 100 45 55%'"   # the fixture's config holds check.coverage-threshold: 80
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_key60="$(python3 -B - <<'PY'
import json
e = json.load(open(".temper/gates.json")).get("check") or {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == "coverage"), {})
t = str(r.get("detail", ""))
said = "names the key, the value and the way out" if all(w in t for w in ("check.coverage-threshold", "80", "55", "remove")) else t[:200]
print("%s:%s:%s" % (e.get("verdict"), r.get("pass"), said))
PY
)"
fresh; _repo60; _nokey60; _cmds60 true "echo 'TOTAL 100 45 55%'"
printf '{"result": "green", "coverage": 55}\n' > .temper/evidence/baseline.json   # the base value, as WP20 writes it
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
assert_eq "w19 the old key: a total of 55 fails the key's 80 and the row names the key; with no key, 55 on a base of 55 passes" \
  "key=FAIL:False:names the key, the value and the way out|nokey=PASS:True" "key=$_key60|nokey=$(_verdict60 check):$(_row60 check coverage)"
fresh; _repo60; _nokey60; _cmds60 true "echo 'TOTAL 100 45 55%'"   # a total and no baseline: not measured
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "w19 a total with no base value, before gate check: check_markers says not measured, not pass" \
  "markers=not measured" "$(_view60 | sed 's/^.*|markers=/markers=/')"
_headed60() { # _headed60 <commit>: a green baseline of total 55 that ran on that commit, then check run and gate check
  printf '{"result": "green", "coverage": 55, "head": "%s"}\n' "$1" > .temper/evidence/baseline.json
  "$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1; _row60 check coverage
}
fresh; _repo60; _nokey60; _cmds60 true "echo 'TOTAL 100 45 55%'"
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1; gpass intent plan build review; _at check
_on_base60="$(_headed60 "$(git rev-parse HEAD)")"
echo 'echo merged' >> src/demo.sh; git commit -qam 'a merge of the work'   # the baseline taken again after integrate
assert_eq "w19 the base value is the baseline's only when it ran on the run's base commit: else coverage is not measured" \
  "base=True|later=None:not measured" "base=$_on_base60|later=$(_headed60 "$(git rev-parse HEAD)")"
assert_eq "w19 the old key: the template and the plugin's own config hold no coverage-threshold line" "0|0" \
  "$(grep -c '^ *coverage-threshold:' "$REPO_ROOT/templates/temper.config.default")|$(grep -c '^ *coverage-threshold:' "$REPO_ROOT/.claude/temper.config")"

# --- 5. a planted bug score in Check's ledger is no row of the gate and fails nothing ---
fresh
"$TEMPER" evidence add --stage check --claim "tests" --exit 0 >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim "coverage" --value 90 >/dev/null 2>&1
"$TEMPER" evidence add --stage check --scenario "first" --claim "scenario: first" --exit 0 --cmd "pytest -k first" >/dev/null 2>&1
"$TEMPER" evidence add --stage check --scenario "second" --claim "scenario: second" --exit 0 --cmd "pytest -k second" >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim "mutation score" --value 40 >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "w19 mutation is no row: a mutation score of 40 in Check's ledger gives no row that names mutation, and PASS" \
  "rows=0|PASS" \
  "rows=$(python3 -B -c "
import json
e = json.load(open('.temper/gates.json')).get('check') or {}
print(sum(1 for x in e.get('requirements') or [] if 'mutation' in str(x.get('name', '')).lower()))")|$(_verdict60 check)"

# --- a failed coverage row is a measured drop, a defect of the code: no Run Check again for it ---
fresh; gpass intent plan build review; _at check
gfail check "coverage" "recorded coverage 'none' vs threshold 80%"
# WP24: a defect of the code is repaired in its stage first (Repair again, while the budget allows); the loop back stays
assert_eq "WP24 w19 a failed coverage row is no measurement gap: the repair in the stage first, the loop back offered, and no Run Check again" \
  "repair-again,True|back offered|0" \
  "$(nx "o = d['ask']['options'][0]; a = d['ask']['options'] + d['ask'].get('more', {}).get('options', []); '%s,%s' % (o['id'], bool(o.get('recommended'))) + '|' + ('back offered' if any(x['id'] == 'back' for x in a) else 'no back') + '|' + str(sum(1 for x in a if x['label'].startswith('Run Check again')))")"

# --- the suite's owner one folder down: the report's paths are that folder's, and the changed lines still match ---
_owned60() { # _owned60 <folder>: ran/missed of check_run.line_data for the owner suite_owner finds, against HEAD
  python3 -B - "$REPO_ROOT/scripts" "$(git rev-parse HEAD)" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import check_run
o = check_run.suite_owner(os.getcwd(), {}, "")
d = check_run.line_data(os.getcwd(), o.get("det") or {}, sys.argv[2])
print("%s/%s" % (d.get("ran"), d.get("missed")) if d else d)
PY
}
fresh; _repo60; rm -rf app web; mkdir -p app/lib app/.temper/check
printf 'module example.com/app\n' > app/go.mod; seq 1 13 | sed 's/^/\/\/ line /' > app/lib/x.go
printf 'mode: set\nexample.com/app/lib/x.go:1.1,4.2 1 1\nexample.com/app/lib/x.go:5.1,13.2 1 0\n' > app/.temper/check/cover.out
_go60="$(_owned60)"; rm -rf app; mkdir -p web/src web/.temper/check/coverage
printf '{"scripts": {"test": "vitest run"}, "devDependencies": {"vitest": "1"}}\n' > web/package.json
seq 1 13 | sed 's/^/\/\/ line /' > web/src/y.js
{ echo 'SF:src/y.js'; for n in $(seq 1 13); do echo "DA:$n,$((n <= 4))"; done; echo end_of_record; } > web/.temper/check/coverage/lcov.info
assert_eq "w19 a suite owned one folder down: the changed lines of its Go profile and its lcov report are judged (4 ran, 9 not)" \
  "go=4/9|lcov=4/9" "go=$_go60|lcov=$(_owned60)"
rm -rf app web

# --- 6. check run plants no bug: on a green suite with changed lines, the suite runs once ---
fresh; _repo60; _nokey60; _py60
rm -f .git/count60; _cmds60 "echo run >> $WORKDIR/.git/count60; python3 -m unittest discover -s unit -t ."
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1
assert_eq "w19 check run plants no bug: the counter of the test command holds one line after check run" "1" \
  "$( (wc -l < .git/count60) 2>/dev/null | tr -d ' ' || echo 0)"

# --- 7. the planted bugs run only when three runs of the suite fit the budget; check ahead says why when not ---
fresh; _repo60; _nokey60; _py60
rm -f .git/count60
_cmds60 "cksum < lib/calc.py >> $WORKDIR/.git/count60; sleep 1; python3 -m unittest discover -s unit -t ."
gpass intent plan build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
_real60="$(cksum < lib/calc.py)"
"$TEMPER" check build-checks >/dev/null 2>&1   # WP23 trap 9: the suite's time is the one integrate's run left in the store
TEMPER_MUTATION_BUDGET_S=2 "$TEMPER" check ahead >/dev/null 2>&1
_mut_done60() { # waits as _ahead_done of case 15 does: the background run has ended and left its file
  local i
  for i in $(seq 1 150); do
    if [[ ! -f .temper/check/ahead.pid ]]; then
      [[ -f .temper/evidence/mutation.json ]] && ! grep -q '"state": *"running"' .temper/evidence/mutation.json && return 0
      [[ -f .temper/check/ahead.json && $i -gt 20 ]] && return 1
    fi
    sleep 0.2
  done
  return 1
}
_mut_done60
assert_eq "w19 three must fit: with a 2 s budget and a 1 s suite, check ahead writes not run with a reason and plants no bug" \
  "not run|reason|planted=0" \
  "$(python3 -B -c "
import json
try:
    m = json.load(open('.temper/evidence/mutation.json'))
except (OSError, ValueError):
    m = {}
print('%s|%s' % (m.get('state', 'no mutation.json'), 'reason' if str(m.get('why') or '').strip() else 'no reason'))")|planted=$(grep -cvxF "$_real60" .git/count60 2>/dev/null)"
assert_eq "w19 three must fit: check_markers carries the planted bugs as an entry mutation of state info" "info" \
  "$("$TEMPER" next --json >/dev/null 2>&1; vw "next((x.get('state') for x in d.get('check_markers') or [] if x.get('name') == 'mutation'), 'no mutation entry')")"
rm -rf lib unit .temper/bin60
