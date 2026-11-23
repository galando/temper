# TEMPORARY probe file for the audit findings (deleted before commit).
_tasks990() {
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done'
}
_built990() {
  python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d["groups"]["G1"].update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
}
_row990() { python3 -c "
import json,sys
try: e=json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}
except Exception: e={}
r=next((x for x in e.get('requirements') or [] if x.get('name')==sys.argv[2]),None)
print('absent' if r is None else str(r.get('pass')))" "$1" "$2"; }
_verd990() { python3 -c "
import json,sys
try: print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict','none'))
except Exception: print('none')" "$1"; }
_led990() { python3 - "$1" <<'PY'
import json,sys
try: e=json.load(open('.temper/evidence/%s.json' % sys.argv[1]))
except Exception: e=[]
print(';'.join('%s|cmd=%s|exit=%s|by=%s|state=%s' % (x.get('claim'),x.get('cmd'),x.get('exit_code'),x.get('executed_by'),x.get('state')) for x in e))
PY
}
_fails990() { python3 -c "
import json,sys
try: e=json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}
except Exception: e={}
print(','.join(str(x.get('name')) for x in e.get('requirements') or [] if x.get('pass') is False))" "$1"; }

# A: Build gate, acceptance row, then evidence run -- true under the claim
_tasks990 | m_setup
"$TEMPER" acceptance start >/dev/null 2>&1
mkdir -p .temper/specs/demo/acceptance; printf 'exit 1\n' > .temper/specs/demo/acceptance/accept_test.sh
"$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/accept_test.sh' >/dev/null 2>&1
_built990
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
_a_before="verdict=$(_verd990 build) acc=$(_row990 build 'acceptance tests written before Build')"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build)' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE A before: $_a_before fails=$(_fails990 build)"
echo "PROBE A after : verdict=$(_verd990 build) acc=$(_row990 build 'acceptance tests written before Build') fails=$(_fails990 build)"

# A2: the ': skipped' acceptance form
_tasks990 | m_setup
"$TEMPER" acceptance skip --reason 'the writer locked no test' >/dev/null 2>&1
_built990
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE A2 before: verdict=$(_verd990 build) acc=$(_row990 build 'acceptance tests written before Build')"
"$TEMPER" evidence run --stage build --claim 'acceptance (written before Build): skipped' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE A2 after : verdict=$(_verd990 build) acc=$(_row990 build 'acceptance tests written before Build')"

# B: fix run, regression proof
_tasks990 | m_setup
rm -rf .temper/specs/demo/tasks.md
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' '**Context:**' \
  'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
  '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done' > .temper/specs/demo/tasks.md
"$TEMPER" state init demo --command fix >/dev/null 2>&1
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" check build-checks >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE B before: verdict=$(_verd990 build) reg=$(_row990 build 'regression proof') fails=$(_fails990 build)"; echo "  ledger: $(_led990 build)"; echo "  files: $(ls .temper/evidence 2>&1)"
"$TEMPER" evidence run --stage build --claim 'regression proof' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE B after : verdict=$(_verd990 build) reg=$(_row990 build 'regression proof') fails=$(_fails990 build)"

# C: fix run, Integration suite
_tasks990 | m_setup
"$TEMPER" state init demo --command fix >/dev/null 2>&1
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
sed -i 's/^\*\*Integration:\*\* `true`/**Integration:** `bash unit\/fail.sh`/' .temper/specs/demo/tasks.md
mkdir -p unit; printf 'exit 1\n' > unit/fail.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude' 2>/dev/null; git commit -qm suite 2>/dev/null
_ckrc=$("$TEMPER" check build-checks >/dev/null 2>&1; echo $?)
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE C before: verdict=$(_verd990 build) tests=$(_row990 build 'tests pass') fails=$(_fails990 build) ckrc=$_ckrc"; echo "  ledger: $(_led990 build)"; echo "  files: $(ls .temper/evidence 2>&1)"
"$TEMPER" evidence run --stage build --claim 'Integration suite' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
echo "PROBE C after : verdict=$(_verd990 build) tests=$(_row990 build 'tests pass') fails=$(_fails990 build)"
