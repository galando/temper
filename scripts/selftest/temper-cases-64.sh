# Case file 64 (WP23): the checks run when Build ends, and one failure record. `temper integrate` runs, through one call
# of `check_run.py build-checks`, the suite in the owner's run text with its coverage, each scenario test and the locked
# acceptance tests, into the Build ledger; the Build gate reads the acceptance and coverage rows; Check reuses what
# integrate ran on the same tree. A failure there picks its next step by its class: the triage first for a locked
# acceptance test, in every mode; the setup question for a fault of the environment, and no fix agent. Every failure is
# one typed record in .temper/evidence/failures.json that a step back does not erase.
# Sourced by test-temper.sh; its helpers (fresh, setup, gpass, gfail, _at, m_setup, _base_known) are used here, and the
# builders below are this file's own. Token: w23. Every program of this file logs its runs in a folder of the git folder
# (outside every work tree, so a log line never changes a digest). A call the CLI does not have yet stays inside
# $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
P64="$WORKDIR/.git/p64"   # the programs of this file and their log; m_setup and a new repository remove the git folder,
                          # so each builder calls _progs64 after it
_x64() { # _x64 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More question, opt(d, i) the one with that id, short(c) a call without the
         # path of the CLI, text(d) the question's text, rec(d) the id of the recommended option
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
def text(d):
    return str(((d.get("ask") or {}).get("question") or {}).get("question", ""))
def rec(d):
    return next((o.get("id") for o in opts(d) if o.get("recommended") is True), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
_progs64() { # the programs of this file in $P64 (inside .git, so no file of the tree); each logs its runs to $P64/log.
             # suite: the project's suite; with `cov` it prints a coverage total ($P64/cov, 90 when absent). As
             # $P64/suite.mode says it passes, fails (one fail line, exit 1) or meets a setup line that fails (exit 125).
             # scen NAME: a scenario test, which passes
  mkdir -p "$P64"; : > "$P64/log"; rm -f "$P64/suite.mode" "$P64/cov" "$P64/acc"
  cat > "$P64/suite" <<SH
#!/bin/sh
echo suite >> "$P64/log"
case "\$(cat "$P64/suite.mode" 2>/dev/null)" in
  env) echo "temper-setup: FAIL (exit 1)"; exit 125 ;;
  fail) echo "FAIL: test_total expected 3, got 4"; exit 1 ;;
esac
echo ok
[ "\${1:-}" = cov ] && echo "TOTAL 100 10 \$(cat "$P64/cov" 2>/dev/null || echo 90)%"
exit 0
SH
  printf '#!/bin/sh\necho "scenario $1" >> "%s/log"\necho ok\n' "$P64" > "$P64/scen"
  chmod +x "$P64/suite" "$P64/scen"
}
_n64() { # _n64 <first words>: how many runs the log holds of them
  if [[ -f "$P64/log" ]]; then grep -cx -- "$1" "$P64/log" | tr -d ' '; else echo 0; fi
}
_cmds64() { # _cmds64 [no-coverage]: the config's test command, and its coverage command unless asked not to, in the
            # check block of the case config (whose coverage-threshold stays 80)
  python3 -B - "$P64" "${1:-}" <<'PY'
import sys
p = ".claude/temper.config"
s = open(p).read()
lines = '  commands:\n    test: "%s/suite"\n' % sys.argv[1]
if sys.argv[2] != "no-coverage":
    lines += '    coverage: "%s/suite cov"\n' % sys.argv[1]
s = s.replace("  coverage-threshold: 80\n", "  coverage-threshold: 80\n" + lines, 1)
open(p, "w").write(s)
PY
}
_intent64() { # the two scenarios of the demo intent run this file's scenario test, each under its own name
  python3 -B - "$P64" <<'PY'
import sys
p = ".temper/specs/demo/intent.md"
s = open(p).read()
s = s.replace("  Test: true\n", "  Test: %s/scen first\n" % sys.argv[1], 1).replace("  Test: true\n", "  Test: %s/scen second\n" % sys.argv[1], 1)
open(p, "w").write(s)
PY
  # the approval binds the intent as the run approved it: the case's own Test lines are part of what was approved
  python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, subprocess, sys
p = ".temper/build-state.json"
d = json.load(open(p))
if "intent_hash" in d:
    d["intent_hash"] = subprocess.run([sys.executable, sys.argv[1] + "/approval.py", "digest", ".temper/specs/demo/intent.md"],
                                      capture_output=True, text=True).stdout.strip()
    json.dump(d, open(p, "w"), indent=2)
PY
}
_acc64() { # the locked acceptance test: it logs its run, and fails while $P64/acc says fail (meets a setup line that
           # fails, exit 125, while it says env; exits 125 with no SETUP marker while it says bare)
  mkdir -p .temper/specs/demo/acceptance
  printf 'echo acceptance >> "%s/log"\nif [ "$(cat "%s/acc" 2>/dev/null)" = env ]; then echo "temper-setup: FAIL (exit 1)"; exit 125; fi\nif [ "$(cat "%s/acc" 2>/dev/null)" = bare ]; then echo "the database did not start"; exit 125; fi\nif [ "$(cat "%s/acc" 2>/dev/null)" = fail ]; then echo "FAIL: test_ac01 expected the field stage"; exit 1; fi\necho ok\n' \
    "$P64" "$P64" "$P64" "$P64" > .temper/specs/demo/acceptance/test_acc64.sh
  "$TEMPER" acceptance lock --cmd "bash .temper/specs/demo/acceptance/test_acc64.sh" >/dev/null 2>&1
}
_passed64() { # group G1 passed and continued, every task passed (as the group gate and the person leave them)
  python3 -B - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
for g in d.get("groups", {}).values():
    g.update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
}
_tasks64() { # _tasks64 [Validate]: the demo plan, one group and one task; its Integration line is `true`
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' \
    "**Validate:** \`${1:-true}\`" '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' \
    '**Depends:** none' '**Test:** `true`' '**Cases:**' '- a holds' '- [ ] done'
}
_run64() { # _run64 [no-coverage]: a one group run at Build on its feature branch, its group passed, the acceptance test
           # locked, the test runs of its task recorded, ready for `temper integrate`; the log starts empty
  _tasks64 | m_setup
  _progs64; _cmds64 "${1:-}"; _intent64; _acc64; _passed64
  "$TEMPER" evidence add --stage build --phase red --claim 'unit tests' --cmd 'true' --exit 1 >/dev/null 2>&1
  "$TEMPER" evidence add --stage build --phase green --claim 'unit tests' --cmd 'true' --exit 0 >/dev/null 2>&1
  : > "$P64/log"
}
_integ64() { "$TEMPER" integrate >/dev/null 2>&1 || true; }
_iv64() { python3 -B -c "import json; print((json.load(open('.temper/groups.json')).get('integration') or {}).get('verdict'))" 2>/dev/null; }
_gate64() { # _gate64 <stage> <python expression over e, that stage's entry of gates.json, rows its requirements,
            # failed the names of its failed rows, row(n) the row of that name or {}>: after `temper gate <stage>`
  "$TEMPER" gate "$1" >/dev/null 2>&1
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
rows = [x for x in e.get("requirements") or [] if isinstance(x, dict)]
failed = [x.get("name") for x in rows if x.get("pass") is False]
def row(n):
    return next((x for x in rows if x.get("name") == n), {})
print(eval(sys.argv[2]))
PY
}
_ledger64() { # _ledger64 <stage> <python expression over rows, the ledger of that stage, and kind(x): suite, coverage,
              # scenario, acceptance, regression or None>
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    rows = [x for x in json.load(open(".temper/evidence/%s.json" % sys.argv[1])) if isinstance(x, dict)]
except (OSError, ValueError):
    rows = []
def kind(x):
    c = str(x.get("claim") or "")
    if c == "Integration suite" or c.startswith("tests: the suite"):
        return "suite"
    if c == "coverage":
        return "coverage"
    if x.get("phase") == "scenario":
        return "scenario"
    if c.startswith("acceptance (written before Build)"):
        return "acceptance"
    if c == "regression proof":
        return "regression"
    return None
print(eval(sys.argv[2]))
PY
}
FIELDS64="id ts stage scope check cmd exit ran_by tree setup limit_s key class kind class_by why fail_lines row n step resolved"
_rec64() { # _rec64 <python expression over f, the records of .temper/evidence/failures.json ([] when absent), with
           # FIELDS the fields of the format and CLASSES the five classes>
  python3 -B - "$1" "$FIELDS64" <<'PY'
import json, sys
try:
    f = json.load(open(".temper/evidence/failures.json"))
except (OSError, ValueError):
    f = []
f = [x for x in f if isinstance(x, dict)] if isinstance(f, list) else []
FIELDS = sys.argv[2].split()
CLASSES = ("environment", "command", "plan", "code", "not measured")
def whole(x):
    miss = [k for k in FIELDS if k not in x]
    return "all fields" if not miss else "missing %s" % ",".join(miss)
print(eval(sys.argv[1]))
PY
}
_spent64() { python3 -B -c "
import json
try:
    d = json.load(open('.temper/budget.json'))
except (OSError, ValueError):
    d = {}
print(sum(1 for x in d.get('used') or [] if isinstance(x, dict) and x.get('key') == 'gate:build'))" 2>/dev/null; }
_calls64() { # _calls64 <newline separated calls>: runs each as the CLI or the person would ({ms} and {reason} filled in),
             # in the foreground, and stops at the first that fails
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{ms\}/1000}"; c="${c//\{reason\}/the test asks for what the intent does not say}"
    TEMPER_BASELINE_FOREGROUND=1 bash -c "$c" >/dev/null 2>&1 || break
  done <<<"$1"
}
_opt64() { _calls64 "$(_x64 "o = opt(d, '$1') or {}
r = '\n'.join(o.get('calls') or [])")"; }   # _opt64 <option id>: the person's answer, the calls of that option
_steps64() { # follows the CLI's own steps from here, at most three: an auto action runs its calls; a launch runs its
             # agents' before calls and ends the walk, as does a question. Prints what the walk met: the agent types, or
             # ask:<question id>
  local i n kind
  for i in 1 2 3; do
    n="$("$TEMPER" next --json 2>/dev/null)"
    kind="$(_x64 "r = d.get('action')" "$n")"
    if [[ "$kind" == auto ]]; then
      _calls64 "$(_x64 "r = '\n'.join(d.get('calls') or [])" "$n")"
      continue
    fi
    if [[ "$kind" == work && "$(_x64 "r = len(d.get('agents') or [])" "$n")" != 0 ]]; then
      _calls64 "$(_x64 "r = '\n'.join(c for a in d.get('agents') or [] for c in a.get('before') or [])" "$n")"
      _x64 "r = ','.join(a.get('type', '') for a in d.get('agents') or [])" "$n"
      return 0
    fi
    if [[ "$kind" == work ]]; then
      _calls64 "$(_x64 "r = '\n'.join(d.get('calls') or [])" "$n")"
      continue
    fi
    _x64 "r = 'ask:%s' % (d.get('ask') or {}).get('id') if d.get('action') == 'ask' else d.get('action')" "$n"
    return 0
  done
  echo "no end in three steps"
}
_armed64() { # the run as one the person started at the approval leaves it: it goes on by itself at Build
  python3 -B - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p))
d.update(run_mode="autonomous", unattended_from="plan")
d.pop("parked", None)
json.dump(d, open(p, "w"), indent=2)
PY
}

# --- w23 what integrate runs: the suite in the owner's run text, coverage, each scenario test, the acceptance tests ---
_run64; _integ64
_w1="order=$(_ledger64 build "','.join(k for k in (kind(x) for x in rows) if k)")"
_w1+="|suite=$(_ledger64 build "next(('%s,plan %s' % ('owner' if '$P64/suite cov' in str(x.get('cmd')) else 'not the owner (%s)' % x.get('cmd'), x.get('plan_cmd')) for x in rows if kind(x) == 'suite'), 'no suite row')")"
_w1+="|runs=suite $(_n64 suite),first $(_n64 'scenario first'),second $(_n64 'scenario second'),acceptance $(_n64 acceptance)"
assert_eq "w23 what integrate runs: the Build ledger holds the suite in the owner's run text (the plan's line in plan_cmd), a coverage row, one row per scenario test and the acceptance row, in this order; each ran once" \
  "order=suite,coverage,scenario,scenario,acceptance|suite=owner,plan true|runs=suite 1,first 1,second 1,acceptance 1" "$_w1"

# --- w23 the Build gate reads them: the acceptance row and the coverage row, with the names Check uses ---
_run64; echo fail > "$P64/acc"; _integ64
_w2="acceptance=$(_iv64):$(_gate64 build "'%s:%s' % (e.get('verdict'), ','.join(failed))")"
_run64; echo 50 > "$P64/cov"; _integ64
_w2+="|coverage drop=$(_iv64):$(_gate64 build "'%s:%s' % (e.get('verdict'), ','.join(failed))")"
_run64 no-coverage; _integ64
_w2+="|not measured=$(_iv64):$(_gate64 build "'%s:%s:%s' % (e.get('verdict'), ','.join(failed), '%s,%s' % (row('coverage').get('pass'), row('coverage').get('state')) if row('coverage') else 'no coverage row')")"
assert_eq "w23 the Build gate reads them: a failing acceptance test leaves integrate PASS and fails the Build gate on its row; a coverage drop fails it on coverage; coverage not measured does not" \
  "acceptance=PASS:FAIL:acceptance tests written before Build|coverage drop=PASS:FAIL:coverage|not measured=PASS:PASS::None,not measured" "$_w2"

# --- w23 Check reuses: on the tree integrate left, check run runs nothing; after an edit every check runs ---
_run64; _integ64
gpass build review; _at check
_r0="$(grep -c . "$P64/log" | tr -d ' ')"
"$TEMPER" check run >/dev/null 2>&1
_w3="same tree=$(( $(grep -c . "$P64/log" | tr -d ' ') - _r0 )) runs"
_w3+="|rows=$(_ledger64 check "','.join('%s%s' % (kind(x), '+' if x.get('reused') and x.get('tree') else '-') for x in rows if kind(x))")"
: > "$P64/log"; echo edited >> README
"$TEMPER" check run >/dev/null 2>&1
_w3+="|edited=suite $(_n64 suite),first $(_n64 'scenario first'),second $(_n64 'scenario second'),acceptance $(_n64 acceptance)"
assert_eq "w23 Check reuses: on the tree integrate left check run runs no command and records the suite, coverage, scenario and acceptance rows as reused with their tree; after one edit of a tracked file every one of them runs" \
  "same tree=0 runs|rows=suite+,coverage+,scenario+,scenario+,acceptance+|edited=suite 1,first 1,second 1,acceptance 1" "$_w3"
# the plan's Integration line owns the suite when the config and detect name none: at Check too, so Check runs through the
# CLI and reuses integrate's run of it, and never ends for want of a test command
_tasks64 | sed "s|^\*\*Integration:\*\* \`true\`\$|**Integration:** \`$P64/suite\`|" | m_setup
_progs64; _intent64; _acc64; _passed64
"$TEMPER" evidence add --stage build --phase red --claim 'unit tests' --cmd 'true' --exit 1 >/dev/null 2>&1
"$TEMPER" evidence add --stage build --phase green --claim 'unit tests' --cmd 'true' --exit 0 >/dev/null 2>&1
: > "$P64/log"; _integ64; gpass build review; _at check
_w3b="next=$(_x64 "r = 'the CLI runs Check' if any(short(c).startswith('check run') for c in d.get('calls') or []) else '%s:%s' % (d.get('action'), [short(c)[:40] for c in d.get('calls') or []])")"
"$TEMPER" check run >/dev/null 2>&1; _w3b+="|check run=exit $?"
_w3b+="|suite=integrate $(_ledger64 build "sum(1 for x in rows if kind(x) == 'suite')"),runs $(_n64 suite),check $(_ledger64 check "next(('reused' if x.get('reused') else 'ran') for x in rows if kind(x) == 'suite') if any(kind(x) == 'suite' for x in rows) else 'no suite row'")"
assert_eq "w23 one owner: with no test command in the config and none detected, the plan's Integration line is the suite at Check too, which reuses integrate's run" \
  "next=the CLI runs Check|check run=exit 0|suite=integrate 1,runs 1,check reused" "$_w3b"

# --- w23 triage first, in every mode: a failing locked test at the Build gate gets the triage agent ---
_accfail64() { # _accfail64: a run at Build, integrated, whose Build gate failed on the locked acceptance test alone
  _tasks64 | m_setup; _progs64; _acc64; _passed64
  python3 -B -c "
import json
d = json.load(open('.temper/groups.json')); d['integration'] = {'verdict': 'PASS'}; json.dump(d, open('.temper/groups.json', 'w'))"
  gfail build "acceptance tests written before Build" "FAIL: test_ac01 expected the field stage"
}
_triage64() { _x64 "a = (d.get('agents') or [{}])[0]; p = a.get('prompt', ''); af = [short(c) for c in a.get('after') or []]
r = '%s:%s:%s:%s:%s' % (d.get('action'), a.get('type'), 'Triage at Build' if re.search(r'^Triage:.*fails at Build', p, re.M) else 'no triage at Build',
  'usage build' if any(c.startswith('usage add --stage build') for c in af) else 'usage %s' % af[:1],
  'triaged' if af and af[-1].startswith('acceptance triaged --reason') else 'not triaged')"; }
_accfail64
_w4="default=$(_triage64)"
_accfail64; _armed64
_w4+="|unattended=$(_triage64)"
assert_eq "w23 triage first, in every mode: with a failing locked test at the Build gate, next launches the triage agent at Build, also when the run goes on by itself" \
  "default=work:temper:temper-acceptance:Triage at Build:usage build:triaged|unattended=work:temper:temper-acceptance:Triage at Build:usage build:triaged" "$_w4"

# --- w23 the triage picks the step: code is one fix pass as the CLI's own action; test is the person's question ---
_triaged64() { # _triaged64 [verdict text]: the triage agent's work: its verdict (none when not given), then its after calls
  local after; after="$(_x64 "r = '\n'.join((d.get('agents') or [{}])[0].get('after') or [])")"
  [[ -z "${1:-}" ]] || "$TEMPER" acceptance triage --reason "$1" >/dev/null 2>&1
  _calls64 "$after"
}
_accfail64; _triaged64 "code: the route answers 200 where AC-01 says 403"
_b0="$(_spent64)"
_w5="code=$(_steps64):spent $(( $(_spent64) - _b0 ))"
gfail build "acceptance tests written before Build" "FAIL: test_ac01 expected the field stage"
_w5+="|after the fix pass=$(_x64 "r = '%s:%s' % (d.get('action'), d.get('stage'))")"
_accfail64; _triaged64 "test: the test wants the field state; the intent says stage"
_w5+="|test=$(_x64 "o = opt(d, 'correct-test') or {}
r = '%s:%s:%s:%s' % (d.get('action'), 'correct-test' if o else 'no correct-test', 'recommended' if rec(d) == 'correct-test' else 'recommended %s' % rec(d),
  'reopen' if [short(c) for c in o.get('calls') or []] == [\"acceptance reopen --reason '{reason}'\"] else 'calls %s' % o.get('calls'))")"
_accfail64; _triaged64
_w5+="|no verdict=$(_x64 "r = '%s:%s' % (d.get('action'), 'correct-test' if opt(d, 'correct-test') else 'no correct-test')")"
assert_eq "w23 the triage picks the step: code is one fix pass as the CLI's own action with one repeat spent, then the run asks; test is a question whose correct-test is the person's, with no agent; no verdict is the question" \
  "code=temper:temper-build:spent 1|after the fix pass=ask:build|test=ask:correct-test:recommended:reopen|no verdict=ask:correct-test" "$_w5"

# --- w23 setup at Build: a fault of the environment at integrate is the setup question, with no fix agent ---
_setup64() { _x64 "ids = [o.get('id') for o in opts(d)]
r = '%s:%s:%s:%s:%s' % (d.get('action'), 'SETUP' if 'SETUP' in text(d) else 'no SETUP', ','.join(i for i in ('check-again', 'it-is-the-code', 'save') if i in ids),
  'no agent' if not d.get('agents') else 'agents', 'repair first' if rec(d) in ('add-setup', 'check-again') else 'recommended %s' % rec(d))"; }
_run64; echo env > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_w6="first=$(_setup64)"
_opt64 check-again
_w6+="|again=$(_x64 "r = 'save' if rec(d) == 'save' else 'recommended %s (%s)' % (rec(d), d.get('action'))")"
_opt64 it-is-the-code
_w6+="|the code=$(_steps64)"
_run64; echo env > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1; _armed64
_w6+="|unattended=$(_x64 "c = [short(x) for x in d.get('calls') or []]
r = 'stop' if d.get('action') == 'auto' and any(x.startswith('park ') for x in c) and not d.get('agents') else '%s %s' % (d.get('action'), [a.get('type') for a in d.get('agents') or []] or c)")"
assert_eq "w23 setup at Build: a suite that exits 125 at integrate gives the setup question at Build with no fix agent; the same failure again recommends Save for later; it-is-the-code launches the fix pass; an unattended run stops" \
  "first=ask:SETUP:check-again,it-is-the-code,save:no agent:repair first|again=save|the code=temper:temper-build|unattended=stop" "$_w6"

# --- w23 a fix run: the Fix agent's after calls run the suite and the regression proof; red fails the Build gate ---
_fix64() { # _fix64 [broken]: a /temper:fix run at Fix whose agent wrote a regression test and a fix (with broken, a fix
           # that also breaks another test of the suite); the test command runs both tests
  setup; rm -rf .git src unit; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  _progs64
  mkdir -p src unit
  echo 'echo 1' > src/total64.sh; echo 'echo a' > src/other64.sh
  printf 'echo other >> "%s/log"\n[ "$(bash src/other64.sh)" = a ] || { echo "FAIL: test_other expected a"; exit 1; }\n' "$P64" > unit/test_other64.sh
  python3 -B - <<'PY'
p = ".claude/temper.config"
s = open(p).read()
s = s.replace("  coverage-threshold: 80\n", '  coverage-threshold: 80\n  commands:\n    test: "bash unit/test_total64.sh && bash unit/test_other64.sh"\n', 1)
open(p, "w").write(s)
PY
  git add -A >/dev/null 2>&1; git commit -q -m base
  rm -f .temper/groups.json .temper/view.json .temper/build-state.json
  "$TEMPER" state init bug --command fix --feature "the total is one short" >/dev/null 2>&1; _base_known
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  mkdir -p .temper/specs/bug
  printf '# RCA: the total is one short\n\n## Root cause\n\nsrc/total64.sh prints 1.\n\n## Fix\n\nPrint 2.\n' > .temper/specs/bug/rca.md
  gpass rca; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
  printf 'echo total >> "%s/log"\n[ "$(bash src/total64.sh)" = 2 ] || { echo "FAIL: test_total expected 2"; exit 1; }\n' "$P64" > unit/test_total64.sh
  "$TEMPER" evidence run --stage build --phase red --claim 'regression test: the total' -- bash unit/test_total64.sh >/dev/null 2>&1
  echo 'echo 2' > src/total64.sh
  [[ "${1:-}" == broken ]] && echo 'echo b' > src/other64.sh
  "$TEMPER" evidence run --stage build --phase green --claim 'regression test: the total' -- bash unit/test_total64.sh >/dev/null 2>&1
  : > "$P64/log"
}
_fixafter64() { _x64 "r = '\n'.join((d.get('agents') or [{}])[0].get('after') or [])"; }
_fix64
_after="$(_fixafter64)"
_w7="after=$(_x64 "a = [short(c) for c in (d.get('agents') or [{}])[0].get('after') or []]
i = next((k for k, c in enumerate(a) if c.startswith('check build-checks')), -1)
r = 'build-checks, then gate build' if 0 <= i < len(a) - 1 and a[-1] == 'gate build' else 'calls %s' % a")"
_calls64 "$_after"
_w7+="|ledger=$(_ledger64 build "','.join('%s %s %s' % (kind(x), x.get('exit_code'), x.get('executed_by')) for x in rows if kind(x) in ('suite', 'regression'))")"
_w7+="|build=$(python3 -B -c "import json; print((json.load(open('.temper/gates.json')).get('build') or {}).get('verdict'))" 2>/dev/null)"
_fix64 broken
_calls64 "$(_fixafter64)"
_w7+="|broken=$(python3 -B -c "
import json
e = json.load(open('.temper/gates.json')).get('build') or {}
r = next((x for x in e.get('requirements') or [] if x.get('name') == 'tests pass'), {})
print('%s,tests pass %s' % (e.get('verdict'), r.get('pass')))" 2>/dev/null)"
_w7+=":$(_x64 "r = 'a Review launch' if any(a.get('type') == 'temper:temper-review' for a in d.get('agents') or []) else 'no Review launch'")"
assert_eq "w23 a fix run: the Fix agent's after calls run check build-checks before its gate; the Build ledger holds the suite row and the regression proof the CLI ran; a red suite fails the Build gate before any Review agent" \
  "after=build-checks, then gate build|ledger=suite 0 cli,regression 0 cli|build=PASS|broken=FAIL,tests pass False:no Review launch" "$_w7"

# The regression proof counts only as the CLI ran it: a row an agent writes with evidence add is no proof, at the Build
# gate, at the Check gate and on the commit card.
_fix64
"$TEMPER" evidence add --stage build --claim 'regression proof' --exit 0 --cmd 'bash unit/test_total64.sh' >/dev/null 2>&1
_w7b="build=$(_gate64 build "row('regression proof').get('pass')")"
gpass build review; _at check
"$TEMPER" evidence add --stage check --claim 'regression proof' --exit 0 --cmd 'bash unit/test_total64.sh' >/dev/null 2>&1
_w7b+="|check=$(_gate64 check "row('regression proof').get('pass')")"
_w7b+="|card=$(python3 -B - "$REPO_ROOT/scripts" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import card
s = card.regression() or {}
shown = [c for c in s.get("rows") or [] if str(c.get("text", "")).startswith("proof:") and c.get("mark") is None]
print("a passed proof" if shown else "no passed proof")
PY
)"
assert_eq "w23 a fix run: a regression proof row an agent wrote with evidence add counts nowhere: the Build gate and the Check gate fail the row, and the commit card shows no passed proof" \
  "build=False|check=False|card=no passed proof" "$_w7b"

# --- w23 the record: each failure appends one record with every field of the format ---
_tasks64 "$P64/suite" | m_setup; _progs64; echo fail > "$P64/suite.mode"
python3 -B -c "
import json
d = json.load(open('.temper/groups.json')); d.setdefault('tasks', {})['1'] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))"
"$TEMPER" group gate G1 >/dev/null 2>&1
_w8="group=$(_rec64 "'%d:%s:%s' % (len(f), whole(f[-1]) if f else 'none', '%s,%s' % (f[-1].get('scope'), 'one of five' if f[-1].get('class') in CLASSES else f[-1].get('class')) if f else '')")"
"$TEMPER" state loop build plan --reason 'the plan cannot be built' >/dev/null 2>&1
_w8+="|after back=$(_rec64 "'kept' if any(x.get('scope') == 'group:G1' for x in f) else 'gone'")"
_run64; echo fail > "$P64/suite.mode"; _integ64
_w8+="|integrate=$(_rec64 "'%d:%s:%s' % (len(f), whole(f[-1]) if f else 'none', '%s,%s,%s' % (f[-1].get('scope'), f[-1].get('check'), 'one of five' if f[-1].get('class') in CLASSES else f[-1].get('class')) if f else '')")"
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' '**Test:** `true`' \
  '**Cases:**' '- a holds' '- [ ] done' '' '### Task 2: second task' '**File:** `src/b.sh`' '**Depends:** none' \
  '**Test:** `true`' '**Cases:**' '- b holds' '- [ ] done' | m_setup
"$TEMPER" task start 1 >/dev/null 2>&1
"$TEMPER" task blocked 1 --needs src/b.sh --reason 'its test needs the parser of task 2' >/dev/null 2>&1
_w8+="|blocked=$(_rec64 "'%d:%s:%s' % (len(f), whole(f[-1]) if f else 'none', '%s,%s' % (f[-1].get('scope'), 'one of five' if f[-1].get('class') in CLASSES else f[-1].get('class')) if f else '')")"
fresh; rm -rf .git; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
git config user.email t@example.com; git config user.name T; printf '/.temper/\n' >> .git/info/exclude
_progs64; echo fail > "$P64/suite.mode"; _cmds64 no-coverage
git add -A >/dev/null 2>&1; git commit -q -m base
rm -f .temper/evidence/baseline.json; TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start >/dev/null 2>&1
_w8+="|base=$(_rec64 "'%d:%s:%s' % (len(f), whole(f[-1]) if f else 'none', 'one of five' if f and f[-1].get('class') in CLASSES else (f[-1].get('class') if f else ''))")"
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w23 the record: a failed group gate, a failed integrate, a blocked task and a red base each append one record with every field; the class is one of five; integrate's scope is gate:build; the group's record outlives a step back to Plan" \
  "group=1:all fields:group:G1,one of five|after back=kept|integrate=1:all fields:gate:build,suite,one of five|blocked=1:all fields:task:1,one of five|base=1:all fields:one of five" "$_w8"

# --- w23 a class never changes a verdict: an environment record leaves its gate FAIL until a pass or a skip ---
_run64; echo env > "$P64/suite.mode"; _integ64
_w9="verdict=$(_gate64 build "e.get('verdict')"):$(_rec64 "','.join(sorted({str(x.get('class')) for x in f})) or 'no record'")"
_integ64
_w9+="|same key=$(_gate64 build "e.get('verdict')"):$(_rec64 "'open' if any(x.get('class') == 'environment' and x.get('resolved') is None for x in f) else 'resolved'")"
rm -f "$P64/suite.mode"; echo more >> README; git add README; git commit -q -m 'another tree'
_integ64
_w9+="|another key=$(_rec64 "'resolved' if f and all(x.get('resolved') for x in f if x.get('class') == 'environment') else 'open'")"
_run64; echo env > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
"$TEMPER" override build --reason 'the database is down on this machine' >/dev/null 2>&1
_w9+="|skip=$(_rec64 "'resolved with the reason' if f and all('the database is down on this machine' in json.dumps(x.get('resolved')) for x in f if x.get('class') == 'environment') else 'open'")"
assert_eq "w23 a class never changes a verdict: a record of class environment leaves the Build gate FAIL, also on the same key; a pass on another key or the person's skip with a reason resolves it" \
  "verdict=FAIL:environment|same key=FAIL:open|another key=resolved|skip=resolved with the reason" "$_w9"

# --- w23 the record is archived: state archive writes it into gate-ledger.json, and state clear leaves that file ---
_run64; echo fail > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_ids64="$(_rec64 "' '.join(sorted(str(x.get('id')) for x in f))")"
_archived64() { python3 -B - "$_ids64" <<'PY'
import json, sys
want = set(sys.argv[1].split())
try:
    d = json.load(open(".temper/specs/demo/gate-ledger.json"))
except (OSError, ValueError):
    print("no gate-ledger.json")
    sys.exit(0)
found = set()
def walk(x):
    if isinstance(x, dict):
        if "class" in x and "scope" in x and "id" in x:
            found.add(str(x["id"]))
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for v in x:
            walk(v)
walk(d)
print("all" if want and want <= found else "records %s, archived %s" % (sorted(want) or "none", sorted(found)))
PY
}
"$TEMPER" state archive >/dev/null 2>&1
_w10="archived=$(_archived64)"
"$TEMPER" state clear >/dev/null 2>&1
_w10+="|after clear=$(_archived64)"
assert_eq "w23 the record is archived: temper state archive writes the records into the spec folder's gate-ledger.json, and temper state clear leaves that file" \
  "archived=all|after clear=all" "$_w10"
# --- w23 a repaired environment: its record, open while no other key passed, is no fault of a later run ---
_stepq64() { _x64 "r = '%s:%s:%s' % (d.get('action'), 'SETUP' if 'SETUP' in text(d) else 'no SETUP', ','.join(a.get('type', '') for a in d.get('agents') or []) or 'no agent')"; }
_run64; echo env > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
rm -f "$P64/suite.mode"; _opt64 check-again
_w11="repaired=$(python3 -B -c "import json; print((json.load(open('.temper/gates.json')).get('build') or {}).get('verdict'))" 2>/dev/null)"
echo more >> README; git add README; git commit -q -m 'a code change'; echo fail > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_w11+="|a code failure=$(_stepq64):$(_x64 "r = 'it-is-the-code' if opt(d, 'it-is-the-code') else 'no it-is-the-code'")"
_run64; echo env > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
rm -f "$P64/suite.mode"; _opt64 check-again
"$TEMPER" state advance build_complete review >/dev/null 2>&1; gfail review findings 'a finding: the total is one short'
"$TEMPER" state loop review build --reason 'a finding: the total is one short' >/dev/null 2>&1
_w11+="|a step back from Review=$(_stepq64)"
echo fixed >> README; git add README; git commit -q -m 'the fix pass'; echo fail > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_w11b="after the step back=$(_rec64 "'%s %s' % (f[0].get('class'), 'open' if f[0].get('resolved') is None else 'resolved')"),last $(_rec64 "[x for x in f if x.get('check') == 'suite'][-1].get('class')")"
_w11b+="|a code failure=$(_stepq64):$(_x64 "r = 'it-is-the-code' if opt(d, 'it-is-the-code') else 'no it-is-the-code'")"
_run64; echo env > "$P64/acc"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_w11+="|acceptance=$(_rec64 "f[-1].get('class') if f else 'no record'"):$(_stepq64)"
assert_eq "w23 a repaired environment: after the person repairs it and the checks pass on the same key, a later failure of the code is no setup question, and a step back from Review launches the fix agent; a locked acceptance test that meets the environment gets the setup question, not the triage" \
  "repaired=PASS|a code failure=ask:no SETUP:no agent:no it-is-the-code|a step back from Review=work:no SETUP:temper:temper-build|acceptance=environment:ask:SETUP:no agent" "$_w11"
assert_eq "w23 a record stands only while its failure is the latest of its check: after the repair and a step back from Review, a failure of the code in the fix pass is no setup question, though the repaired record stays open" \
  "after the step back=environment open,last code|a code failure=ask:no SETUP:no agent:no it-is-the-code" "$_w11b"
_run64; echo bare > "$P64/acc"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_w11c="record=$(_rec64 "'%s/%s' % (f[-1].get('class'), f[-1].get('kind')) if f else 'no record'")|step=$(_stepq64)"
assert_eq "w23 a locked acceptance test that exits 125 with no SETUP marker is a record of class environment, and gets the setup question, not the triage" \
  "record=environment/setup-line|step=ask:SETUP:no agent" "$_w11c"

# --- w23 a pass resolves: a group gate, a task gate and a gate row that pass resolve the records of their own ---
_tasks64 "$P64/suite" | m_setup; _progs64; echo fail > "$P64/suite.mode"
python3 -B -c "
import json
d = json.load(open('.temper/groups.json')); d.setdefault('tasks', {})['1'] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))"
"$TEMPER" group gate G1 >/dev/null 2>&1
_open64() { _rec64 "','.join('%s %s' % (x.get('$1'), 'open' if x.get('resolved') is None else 'resolved') for x in f if $2) or 'no record'"; }
_w12="group=$(_open64 scope "x.get('scope') == 'group:G1'")"
rm -f "$P64/suite.mode"
( cd .claude/worktrees/temper-demo-G1 && echo more >> README && git add README && git commit -q -m 'the group mended' ) >/dev/null 2>&1
"$TEMPER" group gate G1 >/dev/null 2>&1
_w12+=",then $(python3 -B -c "import json; print((json.load(open('.temper/groups.json'))['groups']['G1'].get('gate') or {}).get('verdict'))"):$(_open64 scope "x.get('scope') == 'group:G1'")"
declare -F st_setup >/dev/null || source "$TESTS_DIR/case-helpers-5.sh"
st_setup; st_attempt m 5 >/dev/null
_w12+="|task=$(_open64 scope "x.get('scope') == 'task:1'")"
st_pass_ready; "$TEMPER" task gate 1 --model m >/dev/null 2>&1
_w12+=",then $(st_field 1 status):$(_open64 scope "x.get('scope') == 'task:1'")"
fresh
printf '%s\n' '**Status:** draft' '' '## Problem' 'The demo.' '' '### Success Criteria' '- [ ] AC-01 [required]: alpha works' \
  '  Why: a' '  Validate: manual - check it' > .temper/specs/demo/intent.md
"$TEMPER" gate intent >/dev/null 2>&1
_rows64="x.get('check') == 'row:rules checklist covered'"
_w12+="|row=$(_open64 check "$_rows64")"
printf '\n### Rules covered\n\n- Who: asked\n- When: not applicable (no time rule)\n- How much: not applicable\n- Exempt: not applicable (every run is reported)\n- States: assumed (none change)\n- Where it shows: assumed\n- Exceptions: asked (twice, gone)\n' >> .temper/specs/demo/intent.md
"$TEMPER" gate intent >/dev/null 2>&1
_w12+=",then $(_open64 check "$_rows64"),the rows that fail $(_rec64 "'open' if [x for x in f if x.get('check') != 'row:rules checklist covered'] and all(x.get('resolved') is None for x in f if x.get('check') != 'row:rules checklist covered') else 'resolved'")"
assert_eq "w23 a pass resolves: a group gate that passes on another key resolves the group's record, a task that passes the task's, a gate row that passes its own row's; the rows that still fail stay open" \
  "group=group:G1 open,then PASS:group:G1 resolved|task=task:1 open,then passed:task:1 resolved|row=row:rules checklist covered open,then row:rules checklist covered resolved,the rows that fail open" "$_w12"

# --- w23 the person's skip resolves: the skip of a red base resolves the base's record, a stage's skip does not ---
fresh; rm -rf .git; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
git config user.email t@example.com; git config user.name T; printf '/.temper/\n' >> .git/info/exclude
_progs64; echo fail > "$P64/suite.mode"; _cmds64 no-coverage
git add -A >/dev/null 2>&1; git commit -q -m base
rm -f .temper/evidence/baseline.json; TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start >/dev/null 2>&1
_w13="base=$(_rec64 "','.join('%s %s %s' % (x.get('scope'), x.get('stage'), 'open' if x.get('resolved') is None else 'resolved') for x in f) or 'no record'")"
"$TEMPER" override intent --reason 'the intent is fine as it is' >/dev/null 2>&1
_w13+="|intent skip=$(_rec64 "'open' if f and all(x.get('resolved') is None for x in f) else 'resolved'")"
"$TEMPER" override base-suite --reason 'the base fails the same on main; go on' >/dev/null 2>&1
_w13+="|base skip=$(_rec64 "'resolved with the reason' if f and all('the base fails the same on main' in json.dumps(x.get('resolved')) for x in f) else 'open'")"
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline clean >/dev/null 2>&1 || true
assert_eq "w23 the person's skip resolves: override base-suite resolves the record of the red base with its reason; the skip of the stage the record was written at does not" \
  "base=base intent open|intent skip=open|base skip=resolved with the reason" "$_w13"

# --- w23 the triage calls the test wrong: the acceptance record is class plan, kind test-wrong, by the triage ---
_run64; echo fail > "$P64/acc"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
_acc64r() { _rec64 "','.join('%s/%s/%s' % (x.get('class'), x.get('kind'), x.get('class_by')) for x in f if x.get('check') == 'acceptance') or 'no record'"; }
_w14="before=$(_acc64r):$(_stepq64)"
_triaged64 "test: the test wants the field state; the intent says stage"
_w14+="|test=$(_acc64r)"
assert_eq "w23 the triage calls the test wrong: the open acceptance record turns from code to class plan, kind test-wrong, class_by triage" \
  "before=code/test-failed/exit:work:no SETUP:temper:temper-acceptance|test=plan/test-wrong/triage" "$_w14"

rm -rf "$P64" src unit
