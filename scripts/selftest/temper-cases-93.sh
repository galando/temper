# Case file 93 (the 9.8.5 audit's rule-log gap): a step a rule takes through `state redo` or `group continue` is in
# .temper/rule-log.json. The audit named the gap in one sentence with no detail; the probes this case was written from
# took both calls in a run that asks at every stage and in one that goes on by itself, read the log after each, and
# found every by-rule step already written (the repair of `state redo`, the advance of `group continue`, the advance
# past a passed stage; after either call the run's next step is the session's work — the agent, the merge and the
# Build check — not a rule's). These assertions hold that: each expected entry by name, so a path that stops writing
# one fails here. Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, nx, second_group, _unattended,
# _ran_unattended) are used here.
_log93() { # the rule log as kind:stage:what, one row after another
  python3 -B -c "
import json
try:
    rows = json.load(open('.temper/rule-log.json'))
except Exception:
    rows = []
print('|'.join('%s:%s:%s' % (r.get('kind'), r.get('stage'), r.get('what')) for r in rows))"
}

# --- state redo: the stage runs again, and the rule log holds it in every mode -------------------------------------
_at93() { # a run at Build (interactive), its Build verdict FAIL, as a fix pass starts
  fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  gfail build "red then green" "no RED evidence for Task 1"
}
_at93
"$TEMPER" state redo build --reason "no RED evidence for Task 1" >/dev/null 2>&1
assert_eq "rule log 93: the person's redo of a failed Build is written as the rule's repair, a run that asks too" \
  "repair:build:build runs again: no RED evidence for Task 1" "$(_log93)"
assert_eq "rule log 93: after the redo the log holds no other rule's step (the Build agent's work is not one)" \
  "1" "$(python3 -B -c "import json; print(len(json.load(open('.temper/rule-log.json'))))")"
_at93; _ran_unattended
"$TEMPER" state redo build --reason "no RED evidence for Task 1" >/dev/null 2>&1
assert_eq "rule log 93: the same redo in a run that goes on by itself writes the same repair" \
  "repair:build:build runs again: no RED evidence for Task 1" "$(_log93)"

# --- group continue: the passed group's move on is written, in every mode; what follows is not a rule's step --------
_at93b() { fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1; }
_groups93() { # _groups93 [confirmed]: a one-group plan whose group passed its gate (a check run again already done)
  rm -f .temper/groups.json
  "$TEMPER" acceptance skip --reason "the rule-log case" >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}%s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "${1:-}" > .temper/groups.json
}
_at93b; _groups93
"$TEMPER" group continue G1 >/dev/null 2>&1
assert_eq "rule log 93: the Continue at the group question is written as the rule's advance, a run that asks too" \
  "covered:build:acceptance tests skipped: the rule-log case|advance:build:group G1 passed: it continues" "$(_log93)"
assert_eq "rule log 93: after the Continue no rule's step is missing: what next runs is the session's merge and check" \
  "integrate|gate build" "$(nx "'|'.join(c.rsplit('temper ', 1)[-1] for c in d.get('calls') or [])")"
_at93b; second_group; _groups93 ', "confirmed": true'
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": true}, "G2": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "9": {"status": "passed", "group": "G2"}}}\n' > .temper/groups.json
_ran_unattended   # the run goes on by itself at Build, so the Continue is the rule's own move (the flow's auto action)
"$TEMPER" group continue G2 >/dev/null 2>&1
assert_eq "rule log 93: a run that goes on by itself continues a passed group and the log holds the advance after the check" \
  "covered:build:acceptance tests skipped: the rule-log case|advance:build:group G2 passed: it continues" "$(_log93)"
gpass build
"$TEMPER" state advance build_complete review >/dev/null 2>&1
assert_eq "rule log 93: the advance past the passed Build that follows is written too, with its stage" \
  "covered:build:acceptance tests skipped: the rule-log case|advance:build:group G2 passed: it continues|advance:build:build passed: on to review" \
  "$(_log93)"
