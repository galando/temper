# Release 9.8.5 case file 28: sourced by test-temper.sh after temper-cases-27.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (U1): autonomy.policy: decide, approved once by arming the run, decides Review and Check by fixed rules ---
_pol() { # _pol <stage>: an armed run under the policy, at <stage> with the stages before it passed
  fresh; printf 'autonomy:\n  policy: decide\n' >> .claude/temper.config
  gpass intent plan build
  for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
  [[ "$1" == check ]] && { gpass review; "$TEMPER" state advance review_complete check >/dev/null 2>&1; }
  "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
}
_pol review
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
assert_eq "9.8.5 policy: an open Medium finding loops back to Build by itself, with the finding as the reason" "auto|True|True" \
  "$(nx "c = d['calls'][0]; d['action'] + '|' + str(' state loop review build --reason ' in c) + '|' + str('a missing null check' in c)")"
_pol review; "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1; gpass review
assert_eq "9.8.5 policy: a clean Review goes on to Check by itself" "auto|True" "$(nx "d['action'] + '|' + str(d['calls'][0].endswith('state advance review_complete check'))")"
_pol check; gfail check "tests pass" "the latest run of a test command failed: unit"
assert_eq "9.8.5 policy: a failed Check loops back to Build while the budget lasts" "auto|True" "$(nx "d['action'] + '|' + str(' state loop check build ' in d['calls'][0])")"
_pol check; gfail check "coverage >= threshold" "recorded coverage 'none' vs threshold 80% (install coverage.py)"
assert_eq "9.8.5 policy: a missing measurement parks for the person" "auto|True" "$(nx "d['action'] + '|' + str(' park --verdict PARKED-NEEDS-DECISION ' in d['calls'][0])")"
_pol check; gpass check
assert_eq "9.8.5 policy: a passed Check goes on to the commit, which still parks for the person" "True" \
  "$(nx "d['calls'][0].endswith('state advance check_complete commit')")"
assert_eq "9.8.5 policy: no policy move ever overrides or accepts" "0" "$(grep -cE "c\(\"(override|evidence accept)" <(sed -n '/def policy_move/,/def setup_offer/p' "$REPO_ROOT/scripts/flow.py"))"
fresh; gpass intent plan build
for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1; gpass review
assert_eq "9.8.5 policy: without autonomy.policy, an armed run still asks at Review, as before" "ask" "$(nx "d['action']")"
