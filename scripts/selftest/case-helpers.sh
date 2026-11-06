# Helpers the case files share (sourced by test-temper.sh before them, so any case file runs alone with TEMPER_CASES_ONLY).
# They use assert_eq, setup, $TEMPER and the counters of test-temper.sh.

_ev() { # _ev <code> <json text>: runs the code over d (the JSON); the last "; " part is printed
  python3 - "$1" "$2" <<'PY' 2>&1
import json, sys
code, text = sys.argv[1], sys.argv[2]
d = json.loads(text)
*stmts, last = code.split('; ')
env = {'d': d}
for st in stmts:
    exec(st, env)
print(eval(last, env))
PY
}
nx() { _ev "$1" "$("$TEMPER" next --json 2>/dev/null)"; }   # one value of `temper next --json`
vw() { _ev "$1" "$(cat .temper/view.json 2>/dev/null)"; }      # one value of .temper/view.json
labels() { nx "'|'.join(o['label'] for o in d['ask']['question']['options'])"; }
second_group() { # second_group: append a second group to the run's tasks.md (9.8.0: one group goes on by itself, so the group
                #                question is asked only in a plan with two or more)
  printf '\n## Group G2: Later\n**Depends:** G1\n**Validate:** `true`\n**Context:**\nThe later work.\n\n### Task 9: later\n**File:** `src/z9.sh`\n**Depends:** none\n**Test:** `true`\n**Cases:**\n- z holds\n- [ ] done\n' >> .temper/specs/demo/tasks.md
}

riskH() { # riskH: the run's plan is rated risk H, as `temper risk` writes it (9.8.0: a medium plan runs Design only at risk H)
  python3 -c "
import json
p = '.temper/build-state.json'
d = json.load(open(p)); d['risk'] = 'H'
json.dump(d, open(p, 'w'), indent=2)"
}

gpass() { # gpass <stage>...: record a PASS verdict for each stage, as a gate run would
  python3 - "$@" <<'PY'
import json, sys
p = '.temper/gates.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
for s in sys.argv[1:]:
    d[s] = {'verdict': 'PASS', 'requirements': [{'name': 'all', 'pass': True, 'detail': 'ok'}]}
json.dump(d, open(p, 'w'))
PY
}
gfail() { # gfail <stage> <row name> <detail>: record a FAIL verdict with one failed row
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
p = '.temper/gates.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
d[sys.argv[1]] = {'verdict': 'FAIL', 'requirements': [{'name': sys.argv[2], 'pass': False, 'detail': sys.argv[3]}]}
json.dump(d, open(p, 'w'))
PY
}
fresh_reviewed() { # 9.7.6: a finished fresh review of the demo plan: the person's request, the CLI's launch mark, then the reviewer's
                  # rows (three lenses, the readiness row with the task count, and a paraphrase of two real sentences)
  local l n; n="$(grep -c '^### Task' .temper/specs/demo/tasks.md)"
  "$TEMPER" plan fresh request >/dev/null 2>&1; "$TEMPER" plan fresh start >/dev/null 2>&1
  for l in readiness zoom-out comprehension; do
    "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $l A" \
      $([[ $l == readiness ]] && echo "--value $n") >/dev/null 2>&1
  done
  "$TEMPER" evidence add --stage plan --phase fresh \
    --claim "paraphrase: the demo runs twice and prints its output | a demo is one shell step run by the suite" >/dev/null 2>&1
}
fresh() { # a new run of the demo spec at Intent, with the run state written by the CLI
  setup
  rm -f .temper/groups.json .temper/view.json
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
}

m_setup() { # m_setup <tasks.md text on stdin>: a fresh repository on the run's feature branch with the plan approved, one group started
  local text; text="$(cat)"
  setup
  rm -rf .git README; git init -q . 2>/dev/null
  git config user.email t@example.com; git config user.name T
  echo base > README; git add README; git commit -q -m base
  git checkout -q -B feature/demo
  printf '%s\n' "$text" > .temper/specs/demo/tasks.md
  printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" group start G1 >/dev/null 2>&1
}

m_field() { python3 -c "import json,sys; print(json.load(open('.temper/groups.json'))['tasks'][sys.argv[1]].get(sys.argv[2],''))" "$1" "$2"; }

f9_tasks() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
**Traced to:** Scenario: "alpha"
- [ ] done

### Task 2: second
**File:** `src/b.sh`, `unit/b_test.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b holds
**Traced to:** Scenario: "alpha", "beta"
- [ ] done
TASKS
}

f9_intent() { # f9_intent <alpha command> <beta command>
  cat > .temper/specs/demo/intent.md <<INT
**Status:** accepted

## Problem
The demo.

### Success Criteria
- [ ] AC-01 [required]: alpha works
  Why: a
  Validate: scenario — alpha
- [ ] AC-02 [required]: beta works
  Why: b
  Validate: scenario — beta

## Scenarios (BDD)
\`\`\`gherkin
Scenario: alpha
  Given a
  When b
  Then c
  Covers: AC-01
  Test: $1
\`\`\`
\`\`\`gherkin
Scenario: beta
  Given a
  When b
  Then c
  Covers: AC-02
  Test: $2
\`\`\`
INT
}

_three_groups() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: One
**Depends:** none
**Validate:** `true`
**Context:**
x

### Task 1: a
**File:** `src/a.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a
- [ ] done

## Group G2: Two
**Depends:** none
**Validate:** `true`
**Context:**
x

### Task 2: b
**File:** `src/b.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- b
- [ ] done

## Group G3: Three
**Depends:** none
**Validate:** `true`
**Context:**
x

### Task 3: c
**File:** `src/c.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- c
- [ ] done
TASKS
}

_change_tasks() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
x

### Task 1: parse
**File:** `src/p.sh`, `src/shared.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a
- [x] done

### Task 2: print
**File:** `src/o.sh`, `src/shared.sh`
**Depends:** Task 1
**Test:** `true`
**Cases:**
- b
- [x] done

### Task 3: help
**File:** `src/h.sh`
**Depends:** Task 2
**Test:** `true`
**Cases:**
- c
- [x] done

### Task 4: version
**File:** `src/v.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- d
- [x] done
TASKS
}

_pl() { # _pl: a run at the Pipeline stage after a Commit that opened a pull request
  fresh; gpass intent plan build review check commit; "$TEMPER" state set pr one >/dev/null 2>&1; _at pipeline
}
_plctx() { printf '%s\n' "$1" > .temper/specs/demo/pipeline-context.json; }
