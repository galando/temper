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
# A repository of its own: an earlier case file may leave files (src/) and git settings (a hooks path) in the folder.
fresh; rm -rf .git src; git init -q . 2>/dev/null
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

# --- 3b. The Intent agent's prompt carries the request as typed, one period after it ---
fresh; "$TEMPER" state init demo --feature "Add refunds. A refund needs a reason." >/dev/null 2>&1
assert_eq "9.8.0: a request that ends a sentence gets no second period in the Intent prompt" "1|0" \
  "$(nx "d['agents'][0]['prompt']" | grep -c '^Feature: Add refunds. A refund needs a reason.$')|$(nx "d['agents'][0]['prompt']" | grep -c '\.\.$')"
fresh; "$TEMPER" state init demo --feature "Add refunds" >/dev/null 2>&1
assert_eq "9.8.0: a request with no end gets its period" "1" "$(nx "d['agents'][0]['prompt']" | grep -c '^Feature: Add refunds\.$')"

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
printf '# Intent\n\n### Decisions\n\n- Where do refunds live? -> POST /payments/{id}/refunds (the person, 2026-11-05)\n' > .temper/specs/demo/intent.md
assert_eq "9.8.0: a route the person changed in the intent's Decisions passes" "PASS" "$(_rr | cut -d'|' -f1)"
printf '# Intent\n\n### Open Questions\n\n- Deferred: POST /payments/{id}/refunds maybe; consequence: none\n\n### Decisions\n\n- (none yet)\n' > .temper/specs/demo/intent.md
assert_eq "9.8.0: a route named in the intent outside its Decisions does not excuse a moved route" "FAIL" "$(_rr | cut -d'|' -f1)"
setup; rm -f .temper/groups.json .temper/view.json; "$TEMPER" state init demo --feature "Make the export faster" >/dev/null 2>&1; printf '# Plan\n' > .temper/specs/demo/plan.md
assert_eq "9.8.0: a request that names no route passes" "PASS|the request names no route" "$(_rr)"

# --- 5. The CLI draws the Plan, Design and RCA panels from the files those stages wrote (9.8.0, round 5) ---
_p16() { # a run at Plan with intent.md, plan.md and tasks.md written, one file of the plan already in the project
  fresh; mkdir -p src; echo x > src/old.py
  cat > .temper/specs/demo/intent.md <<'MD'
# Intent: Demo

### Problem

The demo prints nothing yet. It should.

### Success Criteria

- [ ] AC-01 [required]: it prints (source: request) Why: read. Validate: scenario
- [ ] AC-02 [required]: it exits 0 (source: request) Why: scripts. Validate: scenario

## Scenarios (BDD)

#### Happy Path

Scenario: it prints the output
  Covers: AC-01

#### Error Paths

Scenario: a bad flag exits 2
  Covers: AC-02
MD
  cat > .temper/specs/demo/plan.md <<'MD'
# Plan: Demo printer

## Cross-Repo Search

- not available: local grep used.

## Approach Decisions

### Decision 1: print from main, not from a hook

## Diagram

```mermaid
flowchart LR
  A --> B
```

```text
+------+     +------+
| main | --> | out  |
+------+     +------+
```
MD
  printf '# Tasks: demo\n\n## Group G1: Core\n**Depends:** none\n**Validate:** `true`\n**Context:**\nc\n\n### Task 1: print\n**Files:**\n- `src/old.py`\n- `src/new.py`\n**Depends:** none\n**Test:** `true`\n**Cases:**\n- prints\n- [ ] done\n' > .temper/specs/demo/tasks.md
  "$TEMPER" state set complexity medium >/dev/null 2>&1
}
_p16
PANEL="$("$TEMPER" panel plan 2>&1)"
assert_eq "9.8.0: the Plan panel counts the criteria, the scenarios and the files from the spec files" "1|1|1|1|1" \
  "$(tr -s ' |\n' ' ' <<<"$PANEL" | grep -c 'INTENT: The demo prints nothing yet. -> 2 criteria (2 scenarios cover them)')|$(grep -c '^| ARCHITECTURE: create 1 files, modify 1 files' <<<"$PANEL")|$(grep -c '^| COMPLEXITY: medium   SEARCH: local' <<<"$PANEL")|$(grep -c '^| \[Error Paths\] a bad flag exits 2, Covers: AC-02' <<<"$PANEL")|$(grep -c '^| print from main, not from a hook' <<<"$PANEL")"
assert_eq "9.8.0: the Plan panel is one closed box of 76 columns, then the text diagram and never the mermaid" "1|1|0" \
  "$(awk '/^\+-+\+$/ && length($0) == 76 { last = NR } { a[NR] = $0 } END { for (i = 1; i <= last; i++) if (length(a[i]) != 76) bad = 1; print (last && !bad) ? 1 : 0 }' <<<"$PANEL")|$(grep -c '^| main | --> | out  |$' <<<"$PANEL")|$(grep -c 'flowchart' <<<"$PANEL")"
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1 || python3 - <<'PY'
import json; p='.temper/build-state.json'; d=json.load(open(p)); d['next_stage']='plan'; json.dump(d, open(p,'w'))
PY
assert_eq "9.8.0: the Plan agent's after calls draw its panel, before the gate call (the gate stays last)" "panel plan|gate plan" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['agents'][0]['after'][-2:])")"
printf '# Design: Demo\n\n## Areas of Concern\n\n### Two writes, no transaction\n\nresolved: accepted as written\n\n### Logs hold names\n\nMask them.\n\n## Decision Log\n\n| Decision | Options Considered | Chosen | Rationale |\n|---|---|---|---|\n| Store | table / file | table | queries |\n' > .temper/specs/demo/design.md
PANEL="$("$TEMPER" panel design 2>&1)"
assert_eq "9.8.0: the Design panel lists each concern with its state, and the Decision Log rows" "1|1|1|1" \
  "$(grep -c 'CONCERNS OPEN: 1' <<<"$PANEL")|$(grep -c '^| Two writes, no transaction (resolved: accepted as written)' <<<"$PANEL")|$(grep -c '^| Logs hold names (open)' <<<"$PANEL")|$(grep -c '^| Store: table, because queries' <<<"$PANEL")"
cat > .temper/specs/demo/rca.md <<'MD'
# RCA: Totals drop a cent

CAUSE: round() runs per line, not on the sum
AT: ledger/totals.py:41   CONFIDENCE: HIGH
SINCE: unknown
FIX: round once, on the sum.
TEST: three lines of 0.333 total 1.00

## Root cause

round() runs on each line, so three thirds lose a cent.

## Blast radius

- ledger/export.py: sums rounded lines too
MD
PANEL="$("$TEMPER" panel rca .temper/specs/demo/rca.md 2>&1)"
assert_eq "9.8.0: the RCA panel comes from rca.md's fields, with its blast radius" "1|1|1|0" \
  "$(grep -c '^| RCA: Totals drop a cent' <<<"$PANEL")|$(grep -c '^| CAUSE: round() runs per line, not on the sum' <<<"$PANEL")|$(grep -c '^+--- BLAST RADIUS (1) ---+' <<<"$PANEL")|$(grep -c 'READ FIRST' <<<"$PANEL")"
printf '+----+\n| RCA |\n+----+\n' > .temper/specs/demo/rca.md
assert_eq "9.8.0: an rca.md saved as a box by an earlier version prints as it is; no file is a note, not a failure" "| RCA ||0" \
  "$("$TEMPER" panel rca .temper/specs/demo/rca.md | sed -n 2p)|$("$TEMPER" panel rca .temper/specs/demo/none.md >/dev/null 2>&1; echo $?)"
assert_exit "9.8.0: temper panel with no stage is a usage error" 1 "$TEMPER" panel
rm -rf src

# --- 6. The project brief: the CLI maps the code the request reaches, with no model (9.8.0, round 5) ---
fresh; mkdir -p src unit
printf 'def refund(invoice, amount_cents):\n    return amount_cents\n' > src/payments.py
printf 'def total(lines):\n    return sum(lines)\n' > src/totals.py
printf 'from src import payments\n\ndef test_refund():\n    assert payments.refund(None, 1) == 1\n' > unit/test_payments.py
printf '# House rules\n\n1. Money is integer cents.\n' > CONVENTIONS.md
"$TEMPER" state init demo --feature 'Add partial refunds: `refund` takes `amount_cents`. POST /invoices/{id}/refunds.' >/dev/null 2>&1
OUT="$("$TEMPER" brief 2>&1)"; B="$(cat .temper/brief.md 2>/dev/null)"
assert_eq "9.8.0: temper brief ranks the file the request's names reach, lists its test and copies the conventions" "1|1|0|1|1" \
  "$(grep -c '^| `src/payments.py` |' <<<"$B")|$(grep -c '^- `unit/test_payments.py`: mentions `src/payments.py`' <<<"$B")|$(grep -c '^| `src/totals.py` |' <<<"$B")|$(grep -c '^1. Money is integer cents.$' <<<"$B")|$(grep -c '^OK: .temper/brief.md' <<<"$OUT")"
assert_eq "9.8.0: temper brief with no request still maps the project and never fails" "0|1" \
  "$(rm -f .temper/brief.md; python3 -E -s "$REPO_ROOT/scripts/brief.py" "$(pwd -P)" .temper/brief.md --text '' >/dev/null 2>&1; echo $?)|$(grep -c '^- `src/totals.py`' .temper/brief.md)"
mkdir -p bin; printf '#!/usr/bin/env bash\ncmd_status() { echo ok; }\n' > bin/tool
"$TEMPER" brief --text 'Add a flag to `cmd_status` in bin/tool' >/dev/null 2>&1
assert_eq "9.8.0: a file with no extension that the request names (a script) is read and ranks first" '| `bin/tool` |' \
  "$(sed -n '/^| File/,/^$/p' .temper/brief.md | sed -n 3p | cut -d'|' -f1-2)|"
rm -rf bin
python3 - <<'PY'
import json; p='.temper/build-state.json'; d=json.load(open(p)); d['next_stage']='plan'; json.dump(d, open(p,'w'))
PY
assert_eq "9.8.0: the Plan action's own call makes the brief, and the Plan prompt names it" "brief|1" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['calls'])")|$(nx "d['agents'][0]['prompt']" | grep -c '^Project brief: .temper/brief.md')"
rm -rf src unit CONVENTIONS.md

# --- 7. Three defects of a measured Build (round 5): a scenario owed by a task before its test file exists, a park question
#        that recommended the same rerun again, and acceptance tests locked with a command that cannot run ---
fresh
cat > .temper/specs/demo/intent.md <<'MD'
# Intent: Demo

## Scenarios (BDD)

Scenario: an admin refunds a paid invoice
  Covers: AC-01
  Test: python3 -m unittest unit/test_refunds_api.py -k test_partial
MD
printf '# Tasks: demo\n\n## Group G1: Core\n**Depends:** none\n**Validate:** `true`\n**Context:**\nc\n\n### Task 1: the refund module\n**File:** `ledger/refunds.py`, `unit/test_refunds.py`\n**Depends:** none\n**Test:** `python3 -m unittest unit/test_refunds.py`\n**Cases:**\n- x\n**Traced to:** Scenario: "an admin refunds a paid invoice"\n- [ ] done\n\n### Task 2: the route\n**File:** `ledger/api.py`, `unit/test_refunds_api.py`\n**Depends:** Task 1\n**Test:** `python3 -m unittest unit/test_refunds_api.py`\n**Cases:**\n- y\n- [ ] done\n' > .temper/specs/demo/tasks.md
assert_eq "9.8.0: a scenario traced to a task is owed by the later task that writes the test file it runs" "0|1" \
  "$(python3 -E -s "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 1 | wc -l | tr -d ' ')|$(python3 -E -s "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 2 | grep -c '^an admin refunds a paid invoice')"
f9_tasks | m_setup
python3 - <<'PY'
import json; p='.temper/groups.json'; d=json.load(open(p))
d['groups']['G1'].update(status='parked', parked_reason='Task 1 failed 3 attempts')
d.setdefault('tasks', {})['1'] = {'group': 'G1', 'status': 'failed', 'attempt': 3}
json.dump(d, open(p, 'w'))
PY
assert_eq "9.8.0: the park question recommends running the task again the first time" "Run the task again (Recommended)" "$(nx "d['ask']['question']['options'][0]['label']")"
python3 - <<'PY'
import json; p='.temper/groups.json'; d=json.load(open(p))
d['tasks']['1']['reopened'] = [{'ts': '2026-11-05T13:21:37Z', 'feedback': None}]
json.dump(d, open(p, 'w'))
PY
assert_eq "9.8.0: a group parked again after a rerun recommends Loop back to Plan, and still offers the rerun" "Loop back to Plan (Recommended)|1|1" \
  "$(nx "d['ask']['question']['options'][0]['label']")|$(nx "d['ask']['question']['question']" | grep -c 'parked again after a rerun')|$(labels | grep -c 'Run the task again')"
_at_lock() { fresh; mkdir -p .temper/specs/demo/acceptance; printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ac01(self):\n        self.assertEqual(1, 2)\n' > .temper/specs/demo/acceptance/test_ac.py; }
_at_lock
assert_eq "9.8.0: acceptance lock refuses a command that cannot run here, and names why" "1|1" \
  "$("$TEMPER" acceptance lock --cmd "nosuchrunner-x .temper/specs/demo/acceptance" >/dev/null 2>&1; echo $?)|$("$TEMPER" acceptance lock --cmd "nosuchrunner-x ." 2>&1 | grep -c 'cannot run here (command not found)')"
mkdir -p empty_tests
assert_exit "9.8.0: acceptance lock refuses a command that collects no test" 1 "$TEMPER" acceptance lock --cmd "python3 -m unittest discover -s empty_tests"
assert_exit "9.8.0: acceptance lock takes tests that fail, as they do before the feature is built" 0 "$TEMPER" acceptance lock --cmd "python3 -m unittest discover -s .temper/specs/demo/acceptance -t .temper/specs/demo/acceptance"
rm -rf empty_tests

# --- 8. Intent asks Who, When and How much first, and never skips one because the request is silent (round 5) ---
_rc16() { # a draft intent whose rules checklist is $1 (lines)
  fresh; printf '# Intent: Demo\n\n**Status:** draft\n\n### Rules covered\n\n%b\n' "$1" > .temper/specs/demo/intent.md
}
_rcr() { python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" intent-rules .temper/specs/demo/intent.md | python3 -c "import json,sys; r=json.load(sys.stdin); print(('PASS' if r['pass'] else 'FAIL') + '|' + r['detail'])"; }
_rc16 '- Who: asked\n- When: not applicable (no time window in the request)\n- How much: asked\n- Exempt: asked\n- States: asked\n- Where it shows: assumed\n- Exceptions: asked'
assert_eq "9.8.0: When not applicable because the request is silent fails, and says to ask it" "FAIL|1" "$(_rcr | cut -d'|' -f1)|$(_rcr | grep -c 'that is the reason to ask')"
_rc16 '- Who: asked\n- When: assumed (see Assumptions: no time limit)\n- How much: asked\n- Exempt: asked\n- States: asked\n- Where it shows: asked (the export)\n- Exceptions: asked'
assert_eq "9.8.0: When assumed while a later item was asked fails: the first three come first" "FAIL|1" "$(_rcr | cut -d'|' -f1)|$(_rcr | grep -c 'When assumed while States, Where it shows, Exceptions asked')"
_rc16 '- Who: asked\n- When: not applicable (a CLI flag has no time rule)\n- How much: not applicable (no amounts)\n- Exempt: not applicable (every stage is reported)\n- States: not applicable\n- Where it shows: asked (the CI log)\n- Exceptions: assumed (see Assumptions)'
assert_eq "9.8.0: not applicable with a reason of the feature itself passes, and so does a later item assumed" "PASS" "$(_rcr | cut -d'|' -f1)"
_rc16 '- Who: asked\n- When: asked\n- How much: assumed (house rule: CONVENTIONS.md caps every amount)\n- Exempt: asked\n- States: assumed\n- Where it shows: assumed\n- Exceptions: assumed'
assert_eq "9.8.0: a first four item assumed while no later item was asked passes (the six questions went to the first four)" "PASS" "$(_rcr | cut -d'|' -f1)"
_rc16 '- Who: asked\n- When: asked\n- How much: asked\n- Exempt: assumed (none)\n- States: asked\n- Where it shows: assumed\n- Exceptions: asked (twice, fees on fees)'
assert_eq "9.8.0: Exempt assumed while narrower exceptions were asked fails: what never gets the action is asked with the first" "FAIL|1" \
  "$(_rcr | cut -d'|' -f1)|$(_rcr | grep -c 'Exempt assumed while States, Exceptions asked')"
_rc16 '- Who: asked\n- When: asked\n- How much: asked\n- States: asked\n- Where it shows: assumed\n- Exceptions: asked'
assert_eq "9.8.0: a draft with no Exempt line fails the row, naming it" "FAIL|1" "$(_rcr | cut -d'|' -f1)|$(_rcr | grep -c 'line for: Exempt$')"

# --- 9. A command that would wait for input until the Bash timeout is refused (block-stdin-wait.sh) ---
_sw() { # _sw <cwd> <command>: the guard's exit code for this Bash call
  python3 -I -c 'import json,sys; print(json.dumps({"tool_name": "Bash", "cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "$1" "$2" \
    | bash "$REPO_ROOT/scripts/guards/block-stdin-wait.sh" >/dev/null 2>&1; echo $?
}
fresh; mkdir -p deep/er
_SW_HANG=$'cat > /tmp/x 2>/dev/null; python3 - <<\'EOF\'\nprint(1)\nEOF'
assert_eq "9.8.0: a bare cat in a command with a heredoc is refused, from the project and from a folder below it" "2|2" \
  "$(_sw "$WORKDIR" "$_SW_HANG")|$(_sw "$WORKDIR/deep/er" "$_SW_HANG")"
assert_eq "9.8.0: cat with its own heredoc, of a file, after a pipe or from a file passes; so does a bare cat with no heredoc" "0|0|0|0|0" \
  "$(_sw "$WORKDIR" $'cat > f.py <<\'EOF\'\ncat x\nEOF\npython3 f.py')|$(_sw "$WORKDIR" $'cat a > b; python3 - <<EOF\nEOF')|$(_sw "$WORKDIR" $'echo hi | cat > b; python3 - <<EOF\nEOF')|$(_sw "$WORKDIR" $'cat < a > b; python3 - <<EOF\nEOF')|$(_sw "$WORKDIR" 'cat > /tmp/x')"
assert_eq "9.8.0: a bare cat inside a heredoc body, in quotes, or outside a Temper project passes" "0|0|0" \
  "$(_sw "$WORKDIR" $'python3 - <<\'EOF\'\ncat > x\nEOF')|$(_sw "$WORKDIR" $'echo \'cat > x\'; python3 - <<EOF\nEOF')|$(_sw / "$_SW_HANG")"
assert_eq "9.8.0: the refusal says why and what to do instead" "1" \
  "$(python3 -I -c 'import json,sys; print(json.dumps({"cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "$WORKDIR" "$_SW_HANG" \
     | bash "$REPO_ROOT/scripts/guards/block-stdin-wait.sh" 2>&1 >/dev/null | grep -c 'Write the file with its own heredoc')"
rm -rf deep

# --- 10. The CLI draws each Build task's panel from what it recorded; the agent draws none ---
f9_tasks | m_setup
mkdir -p src unit; echo a > src/a.sh; echo t > unit/a_test.sh; git add src/a.sh unit/a_test.sh; git commit -qm "task 1" >/dev/null 2>&1
python3 - "$(git rev-parse HEAD)" <<'PY'
import json, sys
p = '.temper/groups.json'; d = json.load(open(p))
d.setdefault('tasks', {})['1'] = {'status': 'passed', 'commit': sys.argv[1], 'attempts': [{'n': 1, 'outcome': 'PASS', 'reason': ''}]}
d['tasks']['2'] = {'status': 'failed', 'attempts': [{'n': 1, 'outcome': 'FAIL', 'reason': 'no green run for this task and attempt'}]}
json.dump(d, open(p, 'w'))
rows = [{'task': 1, 'attempt': 1, 'phase': 'red', 'exit_code': 1, 'executed_by': 'cli'},
        {'task': 1, 'attempt': 1, 'phase': 'green', 'exit_code': 0, 'executed_by': 'cli'},
        {'task': 2, 'attempt': 1, 'phase': 'red', 'exit_code': 1, 'executed_by': 'cli'}]
json.dump(rows, open('.temper/evidence/build.json', 'w'))
PY
_PT="$("$TEMPER" panel task 1 2)"
assert_eq "9.8.0: a passed task's panel: its title, the attempt, both runs, the verdict, and the files of its commit" "1|1|1" \
  "$(grep -c '^| TASK 1: first ' <<<"$_PT")|$(grep -c 'Attempt: 1   Test: red exit 1, green exit 0   Gate: PASS' <<<"$_PT")|$(grep -A1 -- '--- CHANGED (2)' <<<"$_PT" | grep -c 'src/a.sh')"
assert_eq "9.8.0: a failed task's panel names why its gate failed, and its declared files" "1|1|1" \
  "$(grep -c 'Test: red exit 1, green exit none   Gate: FAIL' <<<"$_PT")|$(grep -A1 -- '--- WHY IT FAILED (1)' <<<"$_PT" | grep -c 'no green run')|$(grep -c -- '--- DECLARED (2)' <<<"$_PT")"
assert_eq "9.8.0: every row of the task panels is 76 columns" "0" "$(awk 'length($0) != 76' <<<"$_PT" | wc -l | tr -d ' ')"
assert_eq "9.8.0: a task tasks.md does not have prints a line, and the panel never fails" "0|1" \
  "$("$TEMPER" panel task 9 >/dev/null 2>&1; echo $?)|$("$TEMPER" panel task 9 2>&1 | grep -c 'no Task 9')"
assert_eq "9.8.0: the Build task brief draws no box and returns one line a task" "0|1|1" \
  "$(grep -c '^+---' "$REPO_ROOT/agents/build-task.md")|$(grep -c 'TASK {N}: done' "$REPO_ROOT/agents/build-task.md")|$(grep -c 'TASK {N}: stopped:' "$REPO_ROOT/agents/build-task.md")"

# --- 11. A stage waiting only for the person's answers is no failure in the view (the mod draws it current, not red) ---
fresh; printf '# Intent: Demo\n\n**Status:** draft\n\n## Problem\nThe demo.\n\n## Open Questions\n- Blocking: Who may run it? choices: Admins | Anyone\n' > .temper/specs/demo/intent.md
"$TEMPER" gate intent >/dev/null 2>&1
assert_eq "9.8.0: the view marks an open Blocking question's row as waiting for the person, and only that row" "yes|no" \
  "$(vw "rows = next(s for s in d['stages'] if s['id'] == 'intent')['failed']; ('yes' if any(r['name'] == 'blocking question open' and r.get('waits') for r in rows) else 'no') + '|' + ('yes' if any(r.get('waits') and r['name'] != 'blocking question open' for r in rows) else 'no')")"
