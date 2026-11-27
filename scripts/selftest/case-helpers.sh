# Helpers the case files share (sourced by test-temper.sh before them, so any case file runs alone with TEMPER_CASES_ONLY).
# They use assert_eq, setup, $TEMPER and the counters of test-temper.sh.
# The flow: scripts/flow.py, the facade, and the modules it imports (WP03). A case that reads the text of the flow reads it
# through _flow_text, or names the files by FLOW_FILES (paths from the repository root), so a moved method is still read.
FLOW_FILES="scripts/flow.py scripts/flow_base.py scripts/flow_run.py scripts/flow_ask.py scripts/flow_work.py
scripts/flow_build.py scripts/flow_commit.py scripts/flow_view.py scripts/flow_repair.py scripts/flow_revise.py"
_unattended() { # _unattended <stage>: a fresh unattended run at <stage> (intent, plan, design, build, review, check or
                # commit), each stage before it passed. WP11: the run is started at the approval, as the person's option
                # approve-run starts it (state set run_mode autonomous at Plan, its check passed), then advanced (WP07).
  fresh
  [[ "$1" == design ]] && : > .temper/specs/demo/design.md
  local s prev=intent
  for s in plan design build review check commit; do
    [[ "$s" == design && "$1" != design ]] && continue
    [[ "$prev" == "$1" ]] && break
    gpass "$prev"
    [[ "$prev" == plan ]] && "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
    "$TEMPER" state advance "${prev}_complete" "$s" >/dev/null 2>&1
    prev="$s"
  done
}
_ran_unattended() { # the run state as a run the person started at the approval leaves it (WP11): run_mode autonomous,
                    # unattended_from plan, ran_unattended; for a case of a later point of such a run (the commit gate)
  python3 -B - <<'PY'
import json
p = ".temper/build-state.json"
try:
    d = json.load(open(p))
except (OSError, ValueError):
    d = {}
d.update(run_mode="autonomous", unattended_from="plan", ran_unattended=True)
json.dump(d, open(p, "w"), indent=2)
PY
}
_flow_text() { # the text of flow.py and of its modules, one after another
  local m
  for m in $FLOW_FILES; do cat "$REPO_ROOT/$m"; done
}

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
  for l in readiness zoom-out comprehension tests; do
    "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $l A" \
      $([[ $l == readiness ]] && echo "--value $n") >/dev/null 2>&1
  done
  "$TEMPER" evidence add --stage plan --phase fresh \
    --claim "paraphrase: the demo runs twice and prints its output | a demo is one shell step run by the suite" >/dev/null 2>&1
}
_base_known() { # WP20: the baseline on record as not run, so no case of the base meets the new first step (baseline
                # start)
  mkdir -p .temper/evidence
  printf '{"result": "unknown", "why": "not run in the selftest"}\n' > .temper/evidence/baseline.json
}
ev_red() { # ev_red <stage> <claim>: a failing test run the CLI made and recorded (WP30: a run an agent only claimed with
           # `temper evidence add --exit N` counts at no gate, so a case that needs a RED row records a real one)
  "$TEMPER" evidence run --stage "$1" --phase red --claim "$2" -- false >/dev/null 2>&1
}
ev_green() { # ev_green <stage> <claim>: a passing test run the CLI made and recorded (WP30)
  "$TEMPER" evidence run --stage "$1" --phase green --claim "$2" -- true >/dev/null 2>&1
}
ev_scen() { # ev_scen <stage> <scenario>: a passing run of a scenario's test the CLI made and recorded (rule 5: a trace
            # an agent wrote with `temper evidence add --scenario` counts at no gate)
  "$TEMPER" evidence run --stage "$1" --scenario "$2" --claim "scenario: $2" -- true >/dev/null 2>&1
}
fresh() { # a new run of the demo spec at Intent, with the run state written by the CLI
  setup
  rm -f .temper/groups.json .temper/view.json
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
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

f9_tasks() { # a plan in the shape of 9.8.4 and the base, with its Traced to: lines; WP26: Plan writes that line no more,
           # and a plan that has it still reads (case 70, w26 an old plan still reads)
  cat <<'TASKS'
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

# WP18: Review's completion row names the files read, and `evidence resolve` takes only a commit the CLI made after the
# reviewed HEAD. A case that records Review's completion in a project with changed files calls review_done; a case that
# needs a resolved finding resolves it with the id cli_commit prints.
review_done() { # review_done [evidence add flags...]: Review's completion row (exit 0), with one --read for each file
                # `temper review files` prints, so it names every changed file; a project with none passes as
                # `read 0 of 0 changed files`. When the command fails, the row names no file.
  local f out args=()
  if out="$("$TEMPER" review files 2>/dev/null)"; then
    while IFS= read -r f; do [[ -n "$f" ]] && args+=(--read "$f"); done <<<"$out"
  fi
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC \
    ${args[@]+"${args[@]}"} "$@" >/dev/null 2>&1
}
cli_commit() { # cli_commit [file name]: a commit the CLI recorded as its own after the reviewed HEAD, the only kind
               # `evidence resolve` takes: one file under the run's spec folder (at Review the commit hook lets that
               # through, and the row `no code changed at Review` does not count it), committed on the branch checked
               # out, its full id appended to cli_commits of .temper/groups.json. Prints the full id.
  local spec f sha
  spec="$("$TEMPER" state get spec_path 2>/dev/null)"; spec="${spec:-.temper/specs/demo}"
  f="$spec/${1:-repair-note.md}"
  mkdir -p "$spec"; echo "a repair after $(git rev-parse --short HEAD 2>/dev/null)" >> "$f"
  git add -f -- "$f" && git commit -q -m 'a commit of the CLI' -- "$f" || return 1
  sha="$(git rev-parse HEAD)"
  python3 - "$sha" <<'PY'
import json, sys
p = ".temper/groups.json"
try:
    d = json.load(open(p))
except (OSError, ValueError):
    d = {}
if not isinstance(d, dict):
    d = {}
d.setdefault("cli_commits", []).append(sys.argv[1])
json.dump(d, open(p, "w"))
PY
  # WP24: and as a repair the CLI closed after its recheck completed (the run state's repairs), the fifth condition of
  # evidence resolve (scripts/repair_ops.py recheck_after); its close resolved the ids a case resolves by hand (1 to 99)
  python3 - "$sha" "$(git rev-parse 'HEAD^{tree}')" <<'PY'
import json, os, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
p = ".temper/build-state.json"
d = json.load(open(p)) if os.path.exists(p) else {}
reps = d.setdefault("repairs", [])
reps.append({"n": len(reps) + 1, "stage": "review", "step": d.get("step"), "commit": sys.argv[1], "base_tree": sys.argv[2],
             "tree": sys.argv[2], "committed": ts, "reruns": "passed", "complete": True, "outcome": "resolved",
             "resolved": list(range(1, 100))})
json.dump(d, open(p, "w"), indent=2)
PY
  echo "$sha"
}
review_repo() { # review_repo <folder>: a project of its own in <folder> of the case folder, a git repository with one
                # commit, its run at Review by the CLI's own calls (so review_snapshot names that commit), for a case that
                # resolves a finding with the id cli_commit prints. The case folder's own repository is left as it was;
                # the case ends with `cd "$WORKDIR"; rm -rf "$WORKDIR/<folder>"`.
  local s
  setup; rm -rf "${WORKDIR:?}/$1"; mkdir -p "$WORKDIR/$1"; cp -R .claude .temper "$WORKDIR/$1/"; cd "$WORKDIR/$1" || return 1
  git init -q .; git config user.email t@example.com; git config user.name T; git commit -q --allow-empty -m base
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
  gpass intent plan build
  for s in intent_complete:plan plan_complete:build build_complete:review; do
    "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1
  done
}
