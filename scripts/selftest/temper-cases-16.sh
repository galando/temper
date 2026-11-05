# 9.8.0, round 5 of the benchmark: the session relays, the CLI does the steps it did by hand (docs/evidence/bench-2026-11.md).
# Sourced by test-temper.sh after temper-cases-15.sh (helpers: nx, vw, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

_i16() { # an intent at Intent with two Blocking questions, one of Design, and Decisions to fill
  fresh
  cat > .temper/specs/demo/intent.md <<'MD'
# Intent: Demo

**Author:** the person
**Status:** draft

## Intent (IDD)

### Problem

The demo prints nothing yet.

### Success Criteria

- [ ] AC-01 [required]: it prints the output (source: request) Why: the person reads it. Validate: scenario

### Open Questions

- Blocking: Who may run the demo? choices: Admins only | Everyone (house rule) | Nobody
- Blocking: Design: How is the cache cleared on a price change? choices: On write | Every minute
- Deferred: A later thing; consequence: none; why work can proceed: it is later; needed by: Build.

### Decisions

- (none yet)
MD
  cat > .temper/specs/demo/design.md <<'MD'
# Design

## Areas of Concern

### The cache can serve stale prices after a price change

Two ways to clear it.

### Logs hold customer names

Mask them.
MD
}

# --- 1. temper intent answer: the person's answer goes into Decisions, by the CLI ---
_i16
assert_eq "9.8.0: intent answer moves a Blocking question into Decisions as the template's row" "0|1|0|0" \
  "$("$TEMPER" intent answer 'Who may run the demo?' 'Admins only' >/dev/null 2>&1; echo $?)|$(grep -c '^- Who may run the demo? -> Admins only (the person, ' .temper/specs/demo/intent.md)|$(grep -c 'Blocking: Who may run' .temper/specs/demo/intent.md)|$(grep -c '(none yet)' .temper/specs/demo/intent.md)"
assert_eq "9.8.0: a Design: question's answer also resolves the concern it names in design.md, and only that one" "1|1|0" \
  "$("$TEMPER" intent answer 'Design: How is the cache cleared on a price change?' 'On write' 2>&1 | grep -c 'resolved in design.md')|$(grep -c '^resolved: On write$' .temper/specs/demo/design.md)|$(sed -n '/Logs hold/,$p' .temper/specs/demo/design.md | grep -c resolved)"
assert_exit "9.8.0: an answer to no open Blocking question changes nothing and fails" 1 "$TEMPER" intent answer 'Who may run the demo?' 'Everyone'
_i16
assert_eq "9.8.0: one call takes every answer of a dialog, the CLI's path written once" "0|2" \
  "$("$TEMPER" intent answer 'Who may run the demo?' 'Admins only' 'Design: How is the cache cleared on a price change?' 'On write' >/dev/null 2>&1; echo $?)|$(grep -c ' -> ' .temper/specs/demo/intent.md)"
assert_exit "9.8.0: an answer without its question is a usage error" 1 "$TEMPER" intent answer 'Only a question'

# --- 2. temper go: Blocking questions ready to ask, a slim question, brief gate calls after an agent ---
_i16
"$TEMPER" gate intent >/dev/null 2>&1
GO="$("$TEMPER" go 2>/dev/null)"
assert_eq "9.8.0: go hands each Blocking question as the session asks it, with the call that records its answer" \
  "ask|Question 1|Who may run the demo?|Everyone (house rule)|Recommended|Carry forward|intent answer 'Who may run the demo?' '{answer}'|intent carry 'Who may run the demo?'" \
  "$(_ev "b = d['blocking'][0]; q = b['question']; '|'.join([d['action'], q['header'], q['question'], q['options'][0]['label'], q['options'][0]['description'], q['options'][-1]['label'], b['answer'].split('temper ', 1)[1], b['carry'].split('temper ', 1)[1]])" "$GO")"
assert_eq "9.8.0: go's question keeps the question as asked, and per option only what the answer runs" "yes|no|no|yes" \
  "$(_ev "a = d['ask']; '|'.join(['yes' if a['question']['options'] else 'no', 'yes' if any('description' in o for o in a['options']) else 'no', 'yes' if any('move' in o for o in a['options']) else 'no', 'yes' if all('label' in o for o in a['options']) else 'no'])" "$GO")"
assert_eq "9.8.0: the view holds the same Blocking questions for the mod" "2|Who may run the demo?" \
  "$(vw "str(len(d['blocking_asks'])) + '|' + d['blocking_asks'][0]['question']['question']")"
assert_eq "9.8.0: a skill option names its skill in the view (the mod lets its questions through)" "grill-me" \
  "$(vw "next(o['skill'] for o in d['ask']['options'] if o.get('skill'))")"
fresh
GO="$("$TEMPER" go 2>/dev/null)"
assert_eq "9.8.0: the agent's gate call after it prints the failed rows only, and the view names the agent to launch" "gate intent --brief|gate intent --brief|temper:temper-intent" \
  "$(_ev "a = d['agents'][0]; a['after'][-1].split('temper ', 1)[1] + '|' + a['gate'].split('temper ', 1)[1]" "$GO")|$(vw "d['next']['agents'][0]['type']")"
_i16
assert_eq "9.8.0: gate --brief prints the verdict and the failed rows, no passed row" "1|0|1" \
  "$("$TEMPER" gate intent --brief 2>&1 | grep -c '^temper gate intent -> FAIL')|$("$TEMPER" gate intent --brief 2>&1 | grep -c '^  \[v\]')|$("$TEMPER" gate intent 2>&1 | grep -c '^  \[v\]' | awk '{print ($1 > 0)}')"

# --- 3. temper spec branch | commit | deviations: the git steps and the Deviations, by the CLI ---
fresh
git config user.email t@t; git config user.name t
echo base > README.demo; git add README.demo; git commit -qm base --no-verify >/dev/null 2>&1; git checkout -q -B main
assert_eq "9.8.0: spec branch switches to the run's branch, creating it" "0|feature/demo" \
  "$("$TEMPER" spec branch >/dev/null 2>&1; echo $?)|$(git branch --show-current)"
assert_eq "9.8.0: spec branch on the run's branch already changes nothing" "0|feature/demo" \
  "$("$TEMPER" spec branch >/dev/null 2>&1; echo $?)|$(git branch --show-current)"
printf '# Intent\n' > .temper/specs/demo/intent.md
assert_eq "9.8.0: spec commit stages the spec folder and commits it with the message" "0|docs(intent): accept demo|.temper/specs/demo/intent.md" \
  "$("$TEMPER" spec commit 'docs(intent): accept demo' >/dev/null 2>&1; echo $?)|$(git log -1 --format=%s)|$(git show --name-only --format= HEAD | grep -c 'intent.md' | sed 's|1|.temper/specs/demo/intent.md|')"
assert_eq "9.8.0: with nothing changed, spec commit makes no empty commit" "0|1" \
  "$("$TEMPER" spec commit 'docs: again' >/dev/null 2>&1; echo $?)|$(git log --format=%s | grep -c '^docs(intent): accept demo$')"
mkdir -p src; echo x > src/a.sh
assert_eq "9.8.0: spec commit -- FILE commits the files named (the record commit), and skips one that is not there" "0|1|0" \
  "$("$TEMPER" spec commit 'feat(demo): the demo' -- src/a.sh .temper/lessons.md >/dev/null 2>&1; echo $?)|$(git show --name-only --format= HEAD | grep -c '^src/a.sh$')|$(git status --porcelain src | wc -l | tr -d ' ')"
printf '# Plan\n\n## Tasks\nx\n' > .temper/specs/demo/plan.md
printf '{"deviations": {"unplanned_files": ["src/b.sh"], "skipped_tasks": [], "approach_changes": ["a queue, not a cron"]}}\n' > .temper/specs/demo/build-context.json
"$TEMPER" spec deviations >/dev/null 2>&1; "$TEMPER" spec deviations >/dev/null 2>&1
assert_eq "9.8.0: spec deviations writes plan.md's Deviations from build-context.json, once however often it runs" "1|1|1" \
  "$(grep -c '^## Deviations$' .temper/specs/demo/plan.md)|$(grep -c '^- Files outside the plan: src/b.sh$' .temper/specs/demo/plan.md)|$(grep -c '^- Approach changes: a queue, not a cron$' .temper/specs/demo/plan.md)"
rm -rf .git src README.demo; git init -q . 2>/dev/null

# --- 4. The plan keeps every route the request names (a run's Plan once built the request's refund route as another path) ---
_r16() { # a run whose request names routes, with a plan
  setup; rm -f .temper/groups.json .temper/view.json
  "$TEMPER" state init demo --feature "Add refunds. POST /invoices/{id}/refunds takes a payment_id. GET /invoices/{id} shows them." >/dev/null 2>&1
  printf '# Plan\n\n## Architecture\n%s\n' "$1" > .temper/specs/demo/plan.md
}
_rr() { python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" plan-rows .temper/specs/demo "$(pwd -P)" auto | python3 -c "import json,sys; r=[json.loads(l) for l in sys.stdin if 'request routes' in l][0]; print(('PASS' if r['pass'] else 'FAIL') + '|' + r['detail'])"; }
_r16 "- new route POST /invoices/{invoice_id}/refunds; GET /invoices/{id} adds them"
assert_eq "9.8.0: a plan that keeps each route of the request, a parameter renamed, passes" "PASS" "$(_rr | cut -d'|' -f1)"
_r16 "- new route POST /payments/{payment_id}/refunds; GET /invoices/{id} adds them"
assert_eq "9.8.0: a plan that moves a route of the request fails, naming the route and what it has instead" "FAIL|1|1" \
  "$(_rr | cut -d'|' -f1)|$(_rr | grep -c 'the request names POST /invoices/{}/refunds, the plan does not')|$(_rr | grep -c 'it names POST /payments/{}/refunds')"
setup; rm -f .temper/groups.json .temper/view.json; "$TEMPER" state init demo --feature "Make the export faster" >/dev/null 2>&1; printf '# Plan\n' > .temper/specs/demo/plan.md
assert_eq "9.8.0: a request that names no route passes" "PASS|the request names no route" "$(_rr)"
