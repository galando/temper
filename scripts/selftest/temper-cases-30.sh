# Release 9.8.5 case file 30: sourced by test-temper.sh after temper-cases-29.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (U5): the person's note is labelled as the person's input ---
setup
assert_eq "9.8.5 U5: a note with --kind input prints [PERSON], not [HEURISTIC]" "1|0" \
  "$("$TEMPER" evidence add --stage build --phase note --kind input --claim 'use the SSO login' 2>&1 | grep -c '^OK: \[PERSON\] build:')|$(grep -c HEURISTIC .temper/evidence/build.json)"

# --- 9.8.5 (Q5): an Interfaces signature matches by shape: a short imported type name where the full one was planned ---
_lf() { python3 - "$REPO_ROOT/scripts" "$1" "$2" <<'PYF'
import sys
src = open(sys.argv[1] + '/task_ops.py').read()   # task_ops.py runs a mode on import: read the function out of it
ns = {}
exec('import re\n' + src[src.index('def _shape'):src.index('def red_why')], ns)
print(ns['literal_found'](sys.argv[2], sys.argv[3]))
PYF
}
assert_eq "9.8.5 Q5: a full name in the plan, a short imported one in the code (and the reverse); another type still fails" "True|True|False" \
  "$(_lf 'static MonitoringSummary.AgencyHealth classify(' 'static AgencyHealth classify(List<A> a) {')|$(_lf 'static AgencyHealth classify(' 'static MonitoringSummary.AgencyHealth  classify(x)')|$(_lf 'static Health classify(' 'static AgencyHealth classify(')"

# --- 9.8.5 (Q4): a RED run made on the final code is no proof that the test fails first ---
_q4plan() { printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`, `unit/a_test.sh`' '**Depends:** none' \
  '**Test:** `bash unit/a_test.sh`' '**Cases:**' '- a holds' '- [ ] done'; }
_q4plan | m_setup; "$TEMPER" task start 1 >/dev/null 2>&1
W=.claude/worktrees/temper-demo-T1; mkdir -p "$W/src" "$W/unit"
echo 'echo 3' > "$W/src/a.sh"                                     # the final code, written first
echo '[ "$(bash src/a.sh)" = 3 ] && [ -e .ok ]' > "$W/unit/a_test.sh"   # fails until .ok exists: a staged failing run
"$TEMPER" task test 1 --phase red >/dev/null 2>&1
touch "$W/.ok"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1; rm -f "$W/.ok"
OUT="$("$TEMPER" task gate 1 --model haiku 2>&1)"
assert_eq "9.8.5 Q4: the gate refuses a RED made on the final code, and says why" "True" \
  "$(grep -q 'the RED run was made on the final code (src/a.sh unchanged since)' <<<"$OUT" && echo True || echo False)"
_q4plan | m_setup; "$TEMPER" task start 1 >/dev/null 2>&1; mkdir -p "$W/src" "$W/unit"
echo '[ "$(bash src/a.sh 2>/dev/null)" = 3 ]' > "$W/unit/a_test.sh"
"$TEMPER" task test 1 --phase red >/dev/null 2>&1
echo 'echo 3' > "$W/src/a.sh"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_eq "9.8.5 Q4: a RED before the code is the proof, as before" "PASS" "$(G="$("$TEMPER" task gate 1 --model haiku 2>&1)"; grep -q '^PASS: Task 1' <<<"$G" && echo PASS || echo FAIL)"
# a stub before the RED: allowed by default (Python needs one), refused with build.red-before-code: true
_q4stub() { _q4plan | m_setup; printf 'build:\n  red-before-code: %s\n' "$1" >> .claude/temper.config; "$TEMPER" task start 1 >/dev/null 2>&1; mkdir -p "$W/src" "$W/unit"
  echo '[ "$(bash src/a.sh 2>/dev/null)" = 3 ]' > "$W/unit/a_test.sh"; echo 'echo 0' > "$W/src/a.sh"   # the stub
  "$TEMPER" task test 1 --phase red >/dev/null 2>&1; echo 'echo 3' > "$W/src/a.sh"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1; }
_q4stub false
assert_eq "9.8.5 Q4: a stub before the RED passes by default" "PASS" "$(G="$("$TEMPER" task gate 1 --model haiku 2>&1)"; grep -q '^PASS: Task 1' <<<"$G" && echo PASS || echo FAIL)"
_q4stub true
assert_eq "9.8.5 Q4: with build.red-before-code: true, a RED after a stub is refused, naming the file" "True" \
  "$(G="$("$TEMPER" task gate 1 --model haiku 2>&1)"; grep -q 'the RED run came after a change to src/a.sh' <<<"$G" && echo True || echo False)"
# a retried attempt is judged too: the code at its start is the baseline
_q4plan | m_setup; "$TEMPER" task start 1 >/dev/null 2>&1; mkdir -p "$W/src" "$W/unit"
echo 'exit 1' > "$W/unit/a_test.sh"; "$TEMPER" task test 1 --phase red >/dev/null 2>&1; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
"$TEMPER" task gate 1 --model haiku >/dev/null 2>&1   # attempt 1 fails (no green); the task is retried
"$TEMPER" task start 1 >/dev/null 2>&1; mkdir -p "$W/src" "$W/unit"
echo 'echo 3' > "$W/src/a.sh"; echo '[ "$(bash src/a.sh)" = 3 ] && [ -e .ok ]' > "$W/unit/a_test.sh"
"$TEMPER" task test 1 --phase red >/dev/null 2>&1; touch "$W/.ok"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1; rm -f "$W/.ok"
assert_eq "9.8.5 Q4: a retried attempt that writes the code before its RED is refused too" "True" \
  "$(G="$("$TEMPER" task gate 1 --model haiku 2>&1)"; grep -q 'the RED run was made on the final code' <<<"$G" && echo True || echo False)"

# --- 9.8.5 (U2): the orchestrator's note for this step's question, marked as Claude's, in the CLI's own question ---
fresh; gpass intent
STEP="$(python3 -c "import json; print(json.load(open('.temper/build-state.json')).get('step'))")"
"$TEMPER" state set ask_note "$STEP: the database was down during the last check" >/dev/null 2>&1
assert_eq "9.8.5 U2: the question of this step ends with the marked note, and its options are unchanged" "True|True" \
  "$(nx "q = d['ask']['question']; str(q['question'].endswith('Note from Claude (not from Temper): the database was down during the last check')) + '|' + str(q['options'][0]['label'].startswith('Continue to Plan'))")"
"$TEMPER" state set ask_note "$((STEP + 7)): an old note" >/dev/null 2>&1
assert_eq "9.8.5 U2: a note of another step is not shown" "False" "$(nx "'Note from Claude' in d['ask']['question']['question']")"
