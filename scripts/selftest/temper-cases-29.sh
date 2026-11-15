# Release 9.8.5 case file 29: sourced by test-temper.sh after temper-cases-28.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (S6): a plan patch changes one command line, keeps the passed tasks, and spends no loop ---
_pp() { # _pp: a run at Build with group G1 started (the plan approved, its hash recorded)
  f9_tasks | m_setup
}
_pp
assert_eq "9.8.5 patch: plan_patch's digest is the CLI's own _plan_digest" "$(python3 -c "import json; print(json.load(open('.temper/build-state.json')).get('plan_hash') or json.load(open('.temper/groups.json')).get('plan_hash'))")" \
  "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import plan_patch, tasks_md; print(plan_patch.digest(tasks_md.parse('.temper/specs/demo/tasks.md')))" "$REPO_ROOT/scripts")"
loops_before="$(cat .temper/feedback-loops.json 2>/dev/null | cksum)"
OUT="$("$TEMPER" plan patch G1 --cmd 'bash run-g1.sh' 2>&1)"; rc=$?
assert_eq "9.8.5 patch: the group's Validate line changes, the plan hash follows, the group check is cleared, a person's row is kept" "0|1|True|True" \
  "$rc|$(grep -c '^\*\*Validate:\*\* `bash run-g1.sh`' .temper/specs/demo/tasks.md)|$(python3 -I -c "
import json, sys; sys.path.insert(0, sys.argv[1]); import plan_patch, tasks_md
print(json.load(open('.temper/build-state.json'))['plan_hash'] == plan_patch.digest(tasks_md.parse('.temper/specs/demo/tasks.md')))" "$REPO_ROOT/scripts")|$(grep -q 'plan patch by the person: G1 Validate' .temper/evidence/plan.json && echo True || echo False)"
assert_eq "9.8.5 patch: no loop is spent" "$loops_before" "$(cat .temper/feedback-loops.json 2>/dev/null | cksum)"
assert_eq "9.8.5 patch: Build reads the patched plan as the approved one" "0" \
  "$("$TEMPER" group gate G1 --timeout-s 30 2>&1 | grep -c 'the approved plan changed')"
sed -i '0,/^\*\*File:\*\* `src\/a.sh`/s//**File:** `src\/other.sh`/' .temper/specs/demo/tasks.md
assert_exit "9.8.5 patch: a tasks.md that differs in more than the line is refused" 1 "$TEMPER" plan patch G1 --cmd 'true'
assert_exit "9.8.5 patch: a command with a backquote is refused" 1 "$TEMPER" plan patch integration --cmd 'echo `x`'

# --- the group question offers the patch first when the cause is the command ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", "fails": 1, "fix_tries": 1, "fix_empty": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: bash slow.sh", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "9.8.5 patch: after an empty fix, Change the group's command is first and recommended, and asks for the command" \
  "Change the group's command (Recommended)|plan patch G1 --cmd '{answer}'|group gate G1|Group command" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['label']] + [c.split('temper ', 1)[1] for c in o['calls']] + [o['answer_question']['header']])")"
