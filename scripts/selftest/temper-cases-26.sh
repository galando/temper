# Release 9.8.5 case file 26: sourced by test-temper.sh after temper-cases-25.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (S4): the failure text is the build tool's summary, not the first line that says ERROR ---
_fl() { python3 - "$REPO_ROOT/scripts" "$1" "${2:-}" <<'PYF'
import sys
src = open(sys.argv[1] + '/task_ops.py').read()   # task_ops.py runs a mode on import: read fail_lines out of it
ns = {}
exec('import re\n' + src[src.index('FAIL_LINE ='):src.index('def red_why')], ns)
rc = int(sys.argv[3]) if sys.argv[3] else None
print(' | '.join(ns['fail_lines'](sys.argv[2].encode().decode('unicode_escape').encode(), rc=rc)))
PYF
}
OUT="$(_fl '20:01:44.264 [main] ERROR com.x.MonitoringSummaryService -- Failed to send email: SMTP down\n[INFO] Tests run: 328, Failures: 0, Errors: 0\n[WARNING] Rule violated for bundle demo: lines covered ratio is 0.04, but expected minimum is 0.94\n[ERROR] Failed to execute goal org.jacoco:jacoco-maven-plugin:0.8.16:check (coverage-check) on project demo: Coverage checks have not been met.\n')"
assert_eq "9.8.5 S4: Maven's failed goal comes first, then the JaCoCo rule, and a passing test's log line is left out" "True|True|False" \
  "$([[ "$OUT" == "[ERROR] Failed to execute goal"* ]] && echo True || echo False)|$(grep -q 'Rule violated for bundle' <<<"$OUT" && echo True || echo False)|$(grep -q 'SMTP down' <<<"$OUT" && echo True || echo False)"
assert_eq "9.8.5 S4: a time-out says so first; no matching line falls back to the last lines" "the command did not finish within its time limit (exit 124)|c | d | e" \
  "$(_fl 'a\nb\n' 124)|$(_fl 'a\nb\nc\nd\ne\n')"

# --- 9.8.5 (S8): a fix agent that changed nothing keeps the check failed and points at the plan or the environment ---
_g3() { # _g3 <group G1 fields>: a run at Build whose group G1 failed its check
  fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "$1" > .temper/groups.json
}
_g3 '"fails": 1, "fix_tries": 1, "fix_empty": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: make test", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}'
assert_eq "9.8.5 S8: after an empty fix, the command change is recommended and first (S6), and the question says the code is not the cause" \
  "Change the group's command (Recommended)|True|False" \
  "$(nx "q = d['ask']; o = q['question']['options']; '|'.join([o[0]['label'], str('the cause is not in the group' in q['question']['question']), str(any(x['label'] == 'Run the gate again with twice the time (Recommended)' for x in o))])")"
_g3 '"fails": 2, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: make test", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}'
assert_eq "9.8.5 S8 (WP20): a second time-out asks, and twice the time is no option any more" "ask|False|False" \
  "$(nx "o = d['ask']['question']['options'] + (d['ask'].get('more') or {}).get('question', {}).get('options', []); '|'.join([d['action'], str(any(x['label'] == 'Run the gate again with twice the time (Recommended)' for x in o)), str(any(x['label'] == 'Run the gate again with twice the time' for x in o))])")"
assert_eq "9.8.5: every question has four options at most; the rest go under More options" "True|True" \
  "$(nx "q = d['ask']; str(len(q['question']['options']) <= 4) + '|' + str(q['question']['options'][-1]['label'] == 'More options' if 'more' in q else True)")"
fresh; mkdir -p gfx; git -C gfx init -q; git -C gfx -c user.name=t -c user.email=t@e commit -q --allow-empty -m base
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "%s", "gate": {"verdict": "FAIL", "reason": "r"}, "fix": {"requested": "x"}, "fix_tries": 1}}, "tasks": {}}\n' "$PWD/gfx" > .temper/groups.json
python3 -E -s "$REPO_ROOT/scripts/group_fix.py" "$PWD/.temper/groups.json" now demo G1 --commit >/dev/null 2>&1
assert_eq "9.8.5 S8: group fix --commit with no change keeps the failed check and counts the empty fix" "FAIL|1" \
  "$(python3 -c "import json; g = json.load(open('.temper/groups.json'))['groups']['G1']; print((g.get('gate') or {}).get('verdict', '') + '|' + str(g.get('fix_empty')))")"
rm -rf gfx

# --- 9.8.5 (S7): no fix pass starts without a fault in its prompt ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "confirmed": "t", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "FAIL", "reason": "integration suite failed (exit 1): make it"}}\n' > .temper/groups.json
assert_eq "9.8.5 S7: a fix pass after a failed integrate carries the integrate verdict" "work|True" \
  "$(nx "d['action'] + '|' + str('What failed: integrate: integration suite failed (exit 1): make it' in d['agents'][0]['prompt'])")"
python3 - <<'PY'
import json
json.dump({"version": 1, "history": [], "active_loops": [{"id": "loop-1", "from_stage": "review", "to_stage": "build", "reason": "x",
           "iteration": 1, "max_iterations": 2, "started": "2026-01-01T00:00:00Z", "at": "2026-01-01T00:00:00Z",
           "findings": ["src/a.ts:3 a missing null check"]}]}, open('.temper/feedback-loops.json', 'w'))
PY
assert_eq "m1 the fix pass names the failure" "work|True|True" \
  "$(nx "p = d['agents'][0]['prompt']; d['action'] + '|' + str('src/a.ts:3 a missing null check' in p) + '|' + str('What failed: integrate: integration suite failed (exit 1): make it' in p)")"
rm -f .temper/feedback-loops.json
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "confirmed": "t", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
assert_eq "9.8.5 S7: with no fault named anywhere, the CLI checks Build again and launches no agent" "auto|True|0" \
  "$(nx "d['action'] + '|' + str(d['calls'][-1].endswith('gate build')) + '|' + str(len(d.get('agents') or []))")"

# --- 9.8.5 (Q6): a Check that hit the environment says SETUP and never recommends a loop back ---
fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage check --claim "tests: the suite (run by the CLI)" --cmd "bash scripts/temper-check.sh" --exit 4 >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim "setup fault: no Postgres answering on 127.0.0.1:5432" --cmd "bash scripts/temper-check.sh" --exit 1 >/dev/null 2>&1
gfail check "tests pass" "the latest run of a test command failed"
assert_eq "9.8.5 Q6: the Check question says SETUP; repairing the environment is first and recommended; no loop back is recommended" \
  "True|Repair the environment and run again (Recommended)|0" \
  "$(nx "q = d['ask']['question']; '|'.join([str('SETUP: the environment was not ready (no Postgres answering on 127.0.0.1:5432)' in q['question']), q['options'][0]['label'], str(sum(1 for o in q['options'] if o['label'].startswith('Loop back') and o['label'].endswith('(Recommended)')))])")"
# M10 of WP08: Check ran again after the repair (the redo the CLI keeps) and met the same fault: the same repair is not
# recommended again, Save for later is
python3 - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p)); d["redo"] = {"stage": "check", "reason": "SETUP: no Postgres answering on 127.0.0.1:5432", "ts": "2026-01-01T00:00:00Z"}
json.dump(d, open(p, "w"), indent=2)
PY
assert_eq "9.8.5 M10: SETUP: the same fault after a run again recommends Save for later" "Save for later (Recommended)|0" \
  "$(nx "o = d['ask']['question']['options'] + (d['ask'].get('more') or {}).get('question', {}).get('options', []); o[0]['label'] + '|' + str(sum(1 for x in o[1:] if x['label'].endswith('(Recommended)')))")"
assert_eq "9.8.5 Q6: check_run reads a project's SETUP marker, and the JVM's start text leaves a row" "no Postgres answering on 127.0.0.1:5432|ok" \
  "$(python3 -I -c "
import sys; sys.path.insert(0, sys.argv[1]); import check_run
print(check_run.setup_fault(b'11633 tests passed\ntemper-check: SETUP: no Postgres answering on 127.0.0.1:5432\n', 4, 'x') + '|' +
      check_run.row('x', 'c', 1, b'Picked up JAVA_TOOL_OPTIONS: -Djdk.http.auth.tunneling.disabledSchemes=\nWARNING: A terminally deprecated method in sun.misc.Unsafe has been called\nok')['output'])" "$REPO_ROOT/scripts")"

# --- 9.8.5: the Context answer "Include what is left out" is accepted (it was refused at 100 characters) ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
printf '## Context Map\n- use: src/ (3 files)\n- reviewed: pending\n\n## Plan\n' > .temper/specs/demo/plan.md
LONG="Include what is left out: packages 2 to 4 (decisions to tasks, finding levels, failure text, SETUP verdict, reuse); the RCA prompt"
assert_eq "9.8.5: a long Context answer is accepted; plan.md keeps a line that fits the map" "0|True" \
  "$("$TEMPER" plan review --answer "$LONG" >/dev/null 2>&1; echo $?)|$(python3 -c "import sys; print(all(len(l) <= 100 for l in open('.temper/specs/demo/plan.md').read().splitlines()))")"

# --- 9.8.5 (found by the A/B replay): a failure whose text differs only in a count is the same failure ---
assert_eq "9.8.5: same_failure ignores the numbers, not the words" "True|False" \
  "$(python3 -I -c "
import sys; sys.path.insert(0, sys.argv[1]); import flow
print(str(flow.same_failure('RED then GREEN: have red=0 green=1', 'RED then GREEN: have red=0 green=2')) + '|' + str(flow.same_failure('tests pass: unit failed', 'coverage: 40 < 80')))" "$REPO_ROOT/scripts")"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "confirmed": "t", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "RED then GREEN" "need >=1 failing test run (RED) and >=1 passing run (GREEN); have red=0 green=1"
"$TEMPER" state redo build --reason "RED then GREEN: need >=1 failing test run (RED) and >=1 passing run (GREEN); have red=0 green=1" >/dev/null 2>&1
gfail build "RED then GREEN" "need >=1 failing test run (RED) and >=1 passing run (GREEN); have red=0 green=2"
assert_eq "9.8.5: the same failure with a grown count recommends Save for later, not Run Build again (it looped 72 times)" "Save for later (Recommended)" \
  "$(nx "d['ask']['options'][0]['label']")"
