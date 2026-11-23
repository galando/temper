# Case file 92 (the audit's NEW-RULES-1, NEW-RULES-2 and NEW-FLOW-4): the locked claims and the view's markers count
# only rows the CLI ran or the person confirmed, and spec_path is the CLI's. The probes this replaces (case 990) were
# removed before the final verify; these are the assertions they were written to become. Sourced by test-temper.sh;
# its helpers (setup, fresh, gpass, m_setup, _at) are used here.
_tasks92() {
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done'
}
_built92() { # the group passed and its task with it, as a gate run would record
  python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d["groups"]["G1"].update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
}
_verd92() { python3 -c "
import json,sys
try: print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict','none'))
except Exception: print('none')" "$1"; }
_row92() { python3 -c "
import json,sys
try: e=json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}
except Exception: e={}
r=next((x for x in e.get('requirements') or [] if x.get('name')==sys.argv[2]),None)
print('absent' if r is None else str(r.get('pass')))" "$1" "$2"; }

# --- NEW-RULES-1: one `evidence run` of true under a locked claim passes no gate row -------------------------------
# The acceptance row counts only rows whose cmd is the lock's command; a fix run's regression proof and tests the
# same. A run of `true` under the claim's words is a row of another command: it changes nothing.
_tasks92 | m_setup
"$TEMPER" acceptance start >/dev/null 2>&1
mkdir -p .temper/specs/demo/acceptance; printf 'exit 1\n' > .temper/specs/demo/acceptance/accept_test.sh
"$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1
_built92; "$TEMPER" integrate >/dev/null 2>&1 || true; "$TEMPER" gate build >/dev/null 2>&1
_b="verdict=$(_verd92 build) acc=$(_row92 build 'acceptance tests written before Build')"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build)' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "92 NEW-RULES-1: a run of true under the acceptance claim passes no row" \
  "verdict=FAIL acc=False|verdict=FAIL acc=False" "$_b|verdict=$(_verd92 build) acc=$(_row92 build 'acceptance tests written before Build')"

_tasks92 | m_setup
"$TEMPER" acceptance skip --reason 'the writer locked no test' >/dev/null 2>&1
_built92; "$TEMPER" integrate >/dev/null 2>&1 || true; "$TEMPER" gate build >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build): skipped' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "92 NEW-RULES-1: the skipped form of the claim passes no row either" \
  "not passed|FAIL" \
  "$(python3 -c "
import json
e = json.load(open('.temper/gates.json')).get('build') or {}
r = next((x for x in e.get('requirements') or [] if x.get('name') == 'acceptance tests written before Build'), None)
print('passed' if r is not None and r.get('pass') is True else 'not passed')")|$(_verd92 build)"

# A fix run: the regression proof and the Integration suite count only the suite owner's commands.
_tasks92 | m_setup
"$TEMPER" state init demo --command fix >/dev/null 2>&1
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
sed -i 's/^\*\*Integration:\*\* `true`/**Integration:** `bash unit\/fail.sh`/' .temper/specs/demo/tasks.md
mkdir -p unit; printf 'exit 1\n' > unit/fail.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude' 2>/dev/null; git commit -qm suite 2>/dev/null
"$TEMPER" check build-checks >/dev/null 2>&1 || true; "$TEMPER" gate build >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim 'regression proof' -- true >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim 'Integration suite' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "92 NEW-RULES-1: in a fix run a run of true passes neither the proof row nor the suite row" \
  "False|False|FAIL" \
  "$(_row92 build 'regression proof')|$(_row92 build 'tests pass')|$(_verd92 build)"

# --- NEW-RULES-2: spec_path is the CLI's, set only as the repair of a lost value ------------------------------------
fresh
_sp_own=".temper/specs/demo"
_sp_rc_take=0; "$TEMPER" state set spec_path "$_sp_own" >/dev/null 2>&1 || _sp_rc_take=$?
_sp_take="$("$TEMPER" state get spec_path 2>/dev/null)"
"$TEMPER" state set spec_path .temper/specs/copy >/dev/null 2>&1; _sp_rc_copy=$?
"$TEMPER" state set spec demo2 >/dev/null 2>&1; _sp_rc_spec=$?
assert_eq "92 NEW-RULES-2: the repair of the lost value is taken; a copy and a hand-set slug are refused" \
  "0|.temper/specs/demo|refused|refused" \
  "$_sp_rc_take|$_sp_take|$([[ $_sp_rc_copy -ne 0 ]] && echo refused || echo "taken:$("$TEMPER" state get spec_path 2>/dev/null)")|$([[ $_sp_rc_spec -ne 0 ]] && echo refused || echo "taken:$("$TEMPER" state get spec 2>/dev/null)")"

# --- NEW-FLOW-4: the view's compile, lint and security markers draw only from a counted row -------------------------
fresh; gpass intent plan build review; _at check
"$TEMPER" evidence add --stage check --claim 'compile: clean, the types check' --exit 0 >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim 'security: no secrets in the diff' --exit 0 >/dev/null 2>&1
_mk92() { python3 -c "
import json
try: m = json.load(open('.temper/view.json')).get('check_markers') or []
except Exception: m = []
x = next((x for x in m if x.get('name') == '$1'), None)
print('%s:%s' % (x.get('state'), str(x.get('detail'))[:40]) if x else 'absent')" 2>/dev/null; }
"$TEMPER" next --json >/dev/null 2>&1
_agent_rows="compile=$(_mk92 compile)|security=$(_mk92 security)"
"$TEMPER" evidence run --stage check --claim 'compile: clean, the types check' -- true >/dev/null 2>&1
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "92 NEW-FLOW-4: an agent's compile and security rows draw no marker; a CLI run draws its marker" \
  "compile=none:|security=none:|compile=pass:compile: clean, the types check" \
  "$_agent_rows|compile=$(_mk92 compile)"
