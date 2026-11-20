# Case file 70 (WP26): Plan writes what something reads; tasks.md only at the simple tier. At the simple tier a plan is
# tasks.md and the scenarios, and the plan gate passes with no plan.md; above it a short plan.md (a Context Map and a
# Blast Radius) and no tier needs one. The rows criteria -> scenarios, cross-repo search recorded, blast radius
# documented and target users action chain are gone; a plan.md with no Context Map passes its row; the row tier recorded
# bounds the simple tier (one group, at most 3 production files, risk below H). A scenario is owed by the task that
# writes the file its Test: command runs, with or without a Traced to: line; the deviations of a run are a file of their
# own. Owner's addition of 2026-11-19: Intent looks a fact up and never asks it.
# Sourced by test-temper.sh; its helpers (fresh, setup, gpass, riskH, m_setup, f9_tasks, f9_intent, nx,
# fresh_reviewed) are used here, and the builders below are this file's own. Token: w26.

# --- the helpers of this file ---
_intent70() { # an accepted intent in the shape Plan writes from WP26: each scenario one gherkin block of four lines
  cat > .temper/specs/demo/intent.md <<'INT'
**Author:** Demo Author <demo@example.com>
**Status:** accepted
**Created:** 2026-01-01
**Complexity:** simple
**States:** none

## Problem
Users cannot do the demo thing today.

### Success Criteria
- [ ] AC-01 [required]: the demo prints its output
  Why: keeps the demo flow honest
  Validate: scenario — the scenario below
- [ ] AC-02 [required]: a bad input is refused
  Why: a bad input must never pass
  Validate: scenario — the scenario below

### Constraints
- keep the demo self-contained (proposed)

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior
- Must keep working: the existing suite

### Open Questions

### Decisions

## Scenarios (BDD)
```gherkin
Scenario: the demo prints
  Then the output is printed
  Covers: AC-01
  Test: bash unit/a_test.sh
```
```gherkin
Scenario: a bad input is refused
  Then the demo exits 2 and prints nothing
  Covers: AC-02
  Test: bash unit/b_test.sh
```

## Source Traceability
### Context Sources
- none: description only — nothing linked
INT
}
_tasks70() { # tasks.md of one group and two production files, with no Traced to: line
  cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The demo group.

### Task 1: print
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `bash unit/a_test.sh`
**Cases:**
- the demo prints its output
- an empty input prints nothing and exits 0
- [ ] done

### Task 2: refuse
**File:** `src/b.sh`, `unit/b_test.sh`
**Depends:** Task 1
**Test:** `bash unit/b_test.sh`
**Cases:**
- a bad input is refused with exit 2
- a good input is let through
- [ ] done
TASKS
}
_group70() { # appends a second group to tasks.md, one task of two cases
  printf '\n## Group G2: Later\n**Depends:** G1\n**Validate:** `true`\n**Context:**\nThe later work.\n\n### Task 3: later\n**File:** `src/z.sh`, `unit/z_test.sh`\n**Depends:** none\n**Test:** `bash unit/z_test.sh`\n**Cases:**\n- z prints its line\n- an empty z exits 0\n- [ ] done\n' >> .temper/specs/demo/tasks.md
}
_plan70() { # _plan70 <tier>: a run at Plan, at that tier, with the intent and tasks.md of this file and no plan.md
  fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _intent70; _tasks70; rm -f .temper/specs/demo/plan.md
  "$TEMPER" state set complexity "${1:-simple}" >/dev/null 2>&1
}
_rows70() { # _rows70 <stage>: the plan gate's verdict and the names of its rows, as verdict|n rows|name,name,...
  python3 -I -c "
import json, sys
g = json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}
rows = g.get('requirements') or []
print('%s|%d|%s' % (g.get('verdict'), len(rows), ','.join(str(x.get('name')) for x in rows)))" "$1" 2>/dev/null || echo "none|0|"
}
_row70() { # _row70 <stage> <row>: pass and detail of that row of the stage's verdict, as pass|detail, or absent
  python3 -I -c "
import json, sys
rows = (json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('requirements') or []
x = next((x for x in rows if x.get('name') == sys.argv[2]), None)
print('absent' if x is None else '%s|%s' % (x.get('pass'), x.get('detail')))" "$1" "$2" 2>/dev/null || echo absent
}
_cut70() { # the names of the cut rows the plan gate still writes, or none
  python3 -I -c "
import json
rows = (json.load(open('.temper/gates.json')).get('plan') or {}).get('requirements') or []
cut = [x['name'] for x in rows if x.get('name') in ('cross-repo search recorded', 'blast radius documented', 'criteria -> scenarios')]
print(','.join(cut) or 'none')" 2>/dev/null || echo none
}
_draft70() { # a draft intent that passes temper gate intent at the head (no Reviewer, no Business Outcome, no Target Users)
  cat > .temper/specs/demo/intent.md <<'EOF'
**Author:** A Author <a@example.com>
**Status:** draft
**Created:** 2026-01-01

## Problem
A real problem with real text.

### Success Criteria
- [ ] AC-01 [required]: criterion one
  Why: serves the real outcome
  Validate: scenario — traced later

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior

### Rules covered
- Who: not applicable
- When: not applicable
- How much: not applicable
- Exempt: not applicable
- States: not applicable
- Where it shows: not applicable
- Exceptions: not applicable

### Open Questions

### Decisions

## Source Traceability
### Context Sources
- none: description only — nothing linked
EOF
}

# --- 1. the simple tier is tasks.md only ---
_plan70 simple; "$TEMPER" gate plan >/dev/null 2>&1
_w26_1="verdict=$(_rows70 plan | cut -d'|' -f1)|cut rows=$(_cut70)|ask=$(nx "(d.get('ask') or {}).get('id')")"
assert_eq "w26 simple tier is tasks.md only: no plan.md, the plan gate passes with no cut row, and next asks the approval" \
  "verdict=PASS|cut rows=none|ask=plan.approve" "$_w26_1"

# --- 2. no tier needs plan.md ---
_plan70 medium; _group70; fresh_reviewed; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "w26 no tier needs plan.md: tier medium with two groups and no plan.md passes the plan gate" \
  "verdict=PASS|plan.md=absent|failed=none" \
  "verdict=$(_rows70 plan | cut -d'|' -f1)|plan.md=$([[ -f .temper/specs/demo/plan.md ]] && echo present || echo absent)|failed=$(python3 -I -c "
import json
rows = (json.load(open('.temper/gates.json')).get('plan') or {}).get('requirements') or []
print(','.join(x['name'] for x in rows if x.get('pass') is False) or 'none')" 2>/dev/null)"

# --- 3. an untraced scenario is owed by the task that writes its test file ---
m_setup <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: the module
**File:** `src/a.py`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- [ ] done

### Task 2: its test
**File:** `src/b.py`, `unit/test_a.py`
**Depends:** none
**Test:** `true`
**Cases:**
- b holds
- [ ] done
TASKS
cat > .temper/specs/demo/intent.md <<'INT'
**Status:** accepted

## Problem
The demo.

### Success Criteria
- [ ] AC-01 [required]: a works
  Why: a
  Validate: scenario — a holds

## Scenarios (BDD)
```gherkin
Scenario: a holds
  Then a holds
  Covers: AC-01
  Test: python3 -m unittest unit.test_a
```
INT
"$TEMPER" task start 1 >/dev/null 2>&1; "$TEMPER" task start 2 >/dev/null 2>&1
_w26_show() { # _w26_show <n>: the lines of task show n under SCENARIO TESTS, up to the next heading, joined by ;
  "$TEMPER" task show "$1" 2>/dev/null | awk '/^--- SCENARIO TESTS/{f=1; next} /^--- /{f=0} f' | paste -sd';' -
}
assert_eq "w26 an untraced scenario is owed by the task that writes its test file: task show 2 lists it under SCENARIO TESTS, task show 1 does not" \
  "task 2=a holds: python3 -m unittest unit.test_a|task 1=" "task 2=$(_w26_show 2)|task 1=$(_w26_show 1)"

# --- 4. an old plan still reads: the fixture plan of case-helpers.sh (f9_tasks), with its Traced to: lines ---
f9_tasks | m_setup
f9_intent "bash unit/a_test.sh" "true"   # alpha runs a file Task 1 writes; Task 2 is traced to both scenarios
assert_eq "w26 an old plan still reads: the Traced to: lines of f9_tasks give the owner they give at the head (Task 2 owes alpha and beta)" \
  "task 2=alpha|beta|task 1=" \
  "task 2=$(python3 -E -s "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 2 | cut -f1 | paste -sd'|' -)|task 1=$(python3 -E -s "$REPO_ROOT/scripts/scenario_ops.py" owed .temper/specs/demo/intent.md .temper/specs/demo/tasks.md 1 | cut -f1 | paste -sd'|' -)"

# --- 5. deviations are a file of their own ---
_w26_dev() { # _w26_dev: runs temper spec deviations twice; prints exit|deviations.md rows|plan.md and tasks.md unchanged
  local before after rc
  before="$(cat .temper/specs/demo/plan.md .temper/specs/demo/tasks.md 2>/dev/null | cksum)"
  "$TEMPER" spec deviations >/dev/null 2>&1; "$TEMPER" spec deviations >/dev/null 2>&1; rc=$?
  after="$(cat .temper/specs/demo/plan.md .temper/specs/demo/tasks.md 2>/dev/null | cksum)"
  printf '%s|files=%s,%s|same=%s' "$rc" \
    "$(grep -c '^- Files outside the plan: src/b.sh$' .temper/specs/demo/deviations.md 2>/dev/null || echo 0)" \
    "$(grep -c '^- Approach changes: a queue, not a cron$' .temper/specs/demo/deviations.md 2>/dev/null || echo 0)" \
    "$([[ "$before" == "$after" ]] && echo yes || echo no)"
}
_w26_devctx() { printf '{"deviations": {"unplanned_files": ["src/b.sh"], "skipped_tasks": [], "approach_changes": ["a queue, not a cron"]}}\n' > .temper/specs/demo/build-context.json; }
fresh; printf '# Plan\n\n## Context Map\n- gap: none\n- reviewed: human\n\n## Blast Radius\n\nnone\n' > .temper/specs/demo/plan.md
_w26_devctx; _w26_5="with plan.md=$(_w26_dev)"
fresh; rm -f .temper/specs/demo/plan.md; _w26_devctx; _w26_5+=" / no plan.md=$(_w26_dev)|plan.md=$([[ -f .temper/specs/demo/plan.md ]] && echo written || echo absent)"
assert_eq "w26 deviations are a file of their own: spec deviations exits 0 with and without plan.md, writes deviations.md once, and leaves plan.md and tasks.md byte equal" \
  "with plan.md=0|files=1,1|same=yes / no plan.md=0|files=1,1|same=yes|plan.md=absent" "$_w26_5"

# --- 6. the intent row target users action chain is gone ---
setup; _draft70
python3 - <<'EOF'
p = '.temper/specs/demo/intent.md'
s = open(p).read().replace('### Open Questions', '### Target Users\n- developer benefits\n\n### Open Questions')
open(p, 'w').write(s)
EOF
"$TEMPER" gate intent >/dev/null 2>&1
assert_eq "w26 the intent row is gone: a draft with a Target Users bullet that has no arrow gets no row target users action chain" \
  "absent" "$(_row70 intent 'target users action chain' | cut -d'|' -f1)"

# --- 7. the context row passes with no map ---
_plan70 simple; printf '# Plan\n\n## Blast Radius\n\nnone outside the declared files\n' > .temper/specs/demo/plan.md
"$TEMPER" gate plan >/dev/null 2>&1
assert_eq "w26 the context row passes with no map: a plan.md with no Context Map gives context map reviewed with pass true" \
  "True|no map: nothing flagged" "$(_row70 plan 'context map reviewed')"

# --- 8. the tier is bounded by the CLI ---
_w26_tier() { # _w26_tier <label>: the row tier recorded after a plan gate, as label=pass,bound named,call named
  "$TEMPER" gate plan >/dev/null 2>&1
  python3 -I - "$1" <<'PY'
import json, re, sys
rows = (json.load(open('.temper/gates.json')).get('plan') or {}).get('requirements') or []
x = next((x for x in rows if x.get('name') == 'tier recorded'), None)
label = sys.argv[1]
if x is None:
    print('%s=absent' % label); sys.exit(0)
d = str(x.get('detail'))
bound = {'two groups': r'\bgroups?\b', 'four files': r'production files?', 'risk H': r'\brisk\b.*\bH\b'}.get(label)
named = 'bound' if bound and re.search(bound, d, re.I) else 'no bound'
call = 'call' if 'temper state set complexity medium' in d else 'no call'
print('%s=%s' % (label, x.get('pass')) if x.get('pass') else '%s=%s,%s,%s' % (label, x.get('pass'), named, call))
PY
}
_plan70 simple; _group70; _w26_8="$(_w26_tier 'two groups')"
_plan70 simple; sed -i 's|^\*\*File:\*\* `src/a.sh`, `unit/a_test.sh`|**File:** `src/a.sh`, `src/c.sh`, `src/d.sh`, `unit/a_test.sh`|' .temper/specs/demo/tasks.md
_w26_8+="|$(_w26_tier 'four files')"
_plan70 simple; sed -i 's|^\*\*File:\*\* `src/a.sh`, `unit/a_test.sh`|**File:** `src/a.sh`, `src/c.sh`, `unit/a_test.sh`|' .temper/specs/demo/tasks.md
_w26_8+="|$(_w26_tier 'three files')"
_plan70 simple; riskH; _w26_8+="|$(_w26_tier 'risk H')"
assert_eq "w26 the tier is bounded: tier simple with two groups, four production files or risk H fails tier recorded, naming the bound and temper state set complexity medium; three files pass" \
  "two groups=False,bound,call|four files=False,bound,call|three files=True|risk H=False,bound,call" "$_w26_8"

# --- 9. the templates pass their own gate ---
setup
awk '/^<!-- grouped-example:begin/{f=1;next} /^<!-- grouped-example:end/{f=0} f' "$REPO_ROOT/templates/tasks.md" > .temper/specs/demo/tasks.md
assert_eq "w26 the templates pass their own gate: the example of templates/tasks.md passes temper gate plan and holds no Traced to" \
  "exit=0|traced=0" \
  "exit=$("$TEMPER" gate plan >/dev/null 2>&1; echo $?)|traced=$(grep -c 'Traced to' .temper/specs/demo/tasks.md)"

# --- 10. no page asks for a cut part ---
assert_eq "w26 no page asks for a cut part: agents, reference and templates name none of the cut sections, and templates/plan.md holds no mermaid" \
  "none|mermaid=0" \
  "$(git -C "$REPO_ROOT" grep -n -F -e 'Cross-Repo Search' -e 'Files to Create' -e 'Files to Modify' -e 'Patterns to Follow' \
      -e 'Risk Level:' -e 'Scenario Coverage Checklist' -e 'Target Users' -e 'Business Outcome' -e 'Traced to' \
      -e 'Given/When/Then' -e 'Approach Decisions' -e '## Diagram' -- agents reference templates | cut -d: -f1,2 | head -20 \
      | tr '\n' ' ' | sed 's/ $//;s/^$/none/')|mermaid=$(grep -c mermaid "$REPO_ROOT/templates/plan.md" 2>/dev/null)"

# --- 14. Intent looks a fact up and never asks it (the owner's addition of 2026-11-19) ---
assert_eq "w26 intent looks a fact up: agents/intent.md holds the paragraph A fact is looked up, never asked, after The request decides first, naming one search a question and the Decisions row" \
  "paragraph=1|after=yes|one search=yes|row=yes" \
  "$(python3 -I - "$REPO_ROOT/agents/intent.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
mark = '**A fact is looked up, never asked.**'
starts = [m.start() for m in re.finditer(r'(?m)^' + re.escape(mark), text)]
if not starts:
    print('paragraph=0|after=no|one search=no|row=no'); sys.exit(0)
at = starts[0]
para = text[at:].split('\n\n', 1)[0]
first = text.find('The request decides first')
after = 'yes' if 0 <= first < at else 'no'
one = 'yes' if re.search(r'\bone search\b', para, re.I) else 'no'
row = 'yes' if 'Decisions' in para and '-> as the project holds it (' in para else 'no'
print('paragraph=%d|after=%s|one search=%s|row=%s' % (len(starts), after, one, row))
PY
)"

# --- 15. a looked up fact passes the intent gate ---
setup; _draft70
python3 - <<'EOF'
p = '.temper/specs/demo/intent.md'
s = open(p).read().replace('### Decisions\n', '### Decisions\n- GET /invoices/{id} returns the status refunded for a refunded invoice -> as the project holds it (src/api/invoices.py:42)\n')
open(p, 'w').write(s)
EOF
assert_eq "w26 a looked up fact passes the intent gate: a draft whose Decisions holds the row of a fact looked up, and no question for it, passes" \
  "exit=0|row=1|questions=0" \
  "exit=$("$TEMPER" gate intent >/dev/null 2>&1; echo $?)|row=$(grep -c -- '-> as the project holds it (src/api/invoices.py:42)$' .temper/specs/demo/intent.md)|questions=$(awk '/^### Open Questions/{f=1; next} /^#/{f=0} f && /^- /' .temper/specs/demo/intent.md | wc -l | tr -d ' ')"
