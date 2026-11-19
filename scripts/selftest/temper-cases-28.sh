# Release 9.8.5 case file 28: sourced by test-temper.sh after temper-cases-27.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (U1), WP11: the run to the commit, started at the approval, decides Review and Check by the closed list ---
_pol() { # _pol <stage>: a run the person started at the approval (approve-run), at <stage> with the stages before it passed
  _unattended "$1"
}
_pol review
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
assert_eq "9.8.5 policy: an open Medium finding goes on to Check by itself" "auto|True" \
  "$(nx "d['action'] + '|' + str(d['calls'][0].endswith('state advance review_complete check'))")"
_pol review
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a token leaks into the log' --severity high --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
assert_eq "WP11 rule: an open High finding under block-on critical goes on to Check by itself (the rule reads review.block-on)" "auto|True" \
  "$(nx "d['action'] + '|' + str(d['calls'][0].endswith('state advance review_complete check'))")"
_pol review
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a token leaks into the log' --severity critical --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gfail review "no blocking findings" "1 open critical finding"
assert_eq "WP11 rule: an open finding at a level of review.block-on loops back once, with the finding as the reason" "auto|1|True" \
  "$(nx "c = d['calls']; d['action'] + '|' + str(sum(' state loop review build --reason ' in x for x in c)) + '|' + str('a token leaks into the log' in c[0])")"
_pol review; "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1; gpass review
assert_eq "9.8.5 policy: a clean Review goes on to Check by itself" "auto|True" "$(nx "d['action'] + '|' + str(d['calls'][0].endswith('state advance review_complete check'))")"
_pol check; gfail check "tests pass" "the latest run of a test command failed: unit"
assert_eq "9.8.5 policy: a failed Check loops back to Build while the budget lasts" "auto|True" "$(nx "d['action'] + '|' + str(' state loop check build ' in d['calls'][0])")"
_pol check; gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "9.8.5 policy: a missing measurement parks for the person" "auto|True" "$(nx "d['action'] + '|' + str(' park --verdict PARKED-NEEDS-DECISION ' in d['calls'][0])")"
_pol check; gpass check
assert_eq "9.8.5 policy: a passed Check goes on to the commit, which still parks for the person" "True" \
  "$(nx "d['calls'][0].endswith('state advance check_complete commit')")"
assert_eq "WP11 rule: no move of the rule ever overrides or accepts" "0|yes" \
  "$(grep -cE "c\(\"(override|evidence accept)" <(sed -n '/def stop(self/,/def setup_offer/p' "$REPO_ROOT/scripts/flow_work.py"))|$(grep -q 'def rule_move' "$REPO_ROOT/scripts/flow_work.py" && echo yes || echo no)"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set run_mode interactive >/dev/null 2>&1   # the first call of ask-every-stage, the person's other option
gpass build; for s in plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1; gpass review
assert_eq "WP11: a run approved with Ask me at every stage asks at Review" "ask|review.pass" "$(nx "d['action'] + '|' + d['ask']['id']")"

# --- 9.8.5 (U1): under the policy a failed group check takes the recommended option, unless a person is needed ---
_polg() { # _polg <group G1 fields>: a run the person started at the approval, at Build, group G1's check failed
  _unattended build
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "$1" > .temper/groups.json
}
_polg '"fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.5 policy: a failed group check whose tasks all passed sends the fix agent by itself" "auto|True" \
  "$(nx "d['action'] + '|' + str(d['calls'][0].endswith('group fix G1'))")"
_polg '"fails": 1, "fix_tries": 1, "fix_empty": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: make test", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}'
assert_eq "9.8.5 policy: when the recommendation needs a typed command, the run parks for the person" "auto|True" \
  "$(nx "d['action'] + '|' + str(' park --verdict PARKED-NEEDS-DECISION ' in d['calls'][0])")"

# --- 9.8.5 (WP08, M3 to M6): the policy launches the group fix, never steps back to Plan, and parks for the person ---
_polg '"fails": 1, "fix": {"requested": "x"}, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.5 policy: after group fix G1 the fix agent is launched" "work|temper:temper-build" \
  "$(nx "d['action'] + '|' + ','.join(str(a.get('type')) for a in d.get('agents') or [])")"
_polg '"fails": 1, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.5 policy: a recommended step back to Plan parks" "auto|True|False" \
  "$(nx "c = d.get('calls') or []; d['action'] + '|' + str(any(' park --verdict PARKED-NEEDS-DECISION ' in x for x in c)) + '|' + str(any('state loop build plan' in x for x in c))")"
_polg '"fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
"$TEMPER" state loop build plan --reason x >/dev/null 2>&1
_m5_loop="$("$TEMPER" state get next_stage 2>/dev/null):$("$TEMPER" state get run_mode 2>/dev/null)"
_polg '"fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
"$TEMPER" state set next_stage plan >/dev/null 2>&1
assert_eq "9.8.5 policy: after a step back to Plan an armed run is interactive" "loop=plan:interactive|set=plan:interactive" \
  "loop=$_m5_loop|set=$("$TEMPER" state get next_stage 2>/dev/null):$("$TEMPER" state get run_mode 2>/dev/null)"
_pol check; sed -i '/AC-02 \[required\]/,/Validate:/s/Validate: scenario.*/Validate: manual — the person opens the demo and looks/' .temper/specs/demo/intent.md
gfail check "acceptance evidence" "AC-02 has no supported passing evidence row"
_m6_move="$(nx "c = d.get('calls') or []; d['action'] + '|' + str(any(' park --verdict PARKED-NEEDS-DECISION ' in x for x in c)) + '|' + str(any('state loop check build' in x for x in c))")"
[[ "$_m6_move" == auto\|True\|* ]] && bash -c "$(nx "d['calls'][0]")" >/dev/null 2>&1
assert_eq "9.8.5 policy: a criterion only the person can confirm parks, and then the question offers Confirmed first" \
  "auto|True|False|ask|Confirmed (Recommended)" \
  "$_m6_move|$(nx "d['action'] + '|' + (d.get('ask') or {}).get('question', {}).get('options', [{}])[0].get('label', 'none')")"
