# Case file 55 (WP14): Design runs only when asked; design concerns are questions in front of the approval. A run of
# /temper:temper has the Design stage when design.md exists, when the run is at Design or has a Design verdict, or when
# the state key want_design is true (the option run-design of the approval sets it); tier, risk, phases.design and an
# Intent that asked decide nothing. The row `tasks agree with decisions` is a row of the plan gate: an answer that is
# the first choice of its Blocking line passes it with a note, another answer fails it until tasks.md changes. The
# first such failure is the CLI's own `state redo plan`; the second asks, with Revise the plan recommended. At risk H
# the fresh review of the plan applies with no request, and the option that starts the unattended run needs a round on
# the plan as it is with no open High finding. Sourced by test-temper.sh; its helpers (fresh, gpass, nx, riskH, m_setup,
# f9_tasks, fresh_reviewed) are used here, and the builders below are this file's own.

# --- the helpers of this file ---
_x55() { # _x55 <python code over d, the JSON of temper next>: prints r. opts(d) is every option of the question with
         # its depth (0 for the first dialog, 1 for its More question, and on), as (option, depth) pairs
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    out, q, depth = [], d.get("ask") or {}, 0
    while isinstance(q, dict) and q:
        out += [(o, depth) for o in q.get("options") or []]
        q, depth = q.get("more"), depth + 1
    return out
def opt(d, i):
    return next((o for o, _ in opts(d) if o.get("id") == i), None)
def targets(d, but=()):
    """The stages the options of the question advance the plan to, but for the options named."""
    return ",".join(sorted({m.group(1) for o, _ in opts(d) if o.get("id") not in but for c in o.get("calls") or []
                            for m in [re.search(r"state advance plan_complete (\w+)", c)] if m})) or "none"
r = None
exec(sys.argv[1])
print(r)
PY
}
_plan55() { # _plan55 [config lines]: a fresh run at Plan, the plan's check passed; the lines go into the config
  fresh; [[ -z "${1:-}" ]] || printf '%s\n' "$1" >> .claude/temper.config
  gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gpass plan
}
_set55() { # _set55 <key> <JSON value>: writes one key of the run state, as an earlier version or a stage left it
  python3 - "$1" "$2" <<'PY'
import json, sys
p = ".temper/build-state.json"
d = json.load(open(p))
d[sys.argv[1]] = json.loads(sys.argv[2])
json.dump(d, open(p, "w"), indent=2)
PY
}
_ask55() { # _ask55 <Blocking line>: one open Blocking question under ### Open Questions of the run's intent.md
  python3 - "$1" <<'PY'
import sys
p = ".temper/specs/demo/intent.md"
s = open(p).read()
open(p, "w").write(s.replace("### Open Questions\n", "### Open Questions\n\n- Blocking: %s\n" % sys.argv[1], 1))
PY
}
_row55() { # _row55 <stage> <row name> <field>: that field of the row of the stage's verdict in gates.json, or absent
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
try:
    g = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    g = {}
r = next((x for x in g.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else r.get(sys.argv[3]))
PY
}
_verdict55() { # _verdict55 <stage>: the verdict of the stage in gates.json
  python3 -c "import json, sys
print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict'))" "$1" 2>/dev/null
}
_sched55() { # a run at Plan, with one open Blocking question of a product call and no prefix
  fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _ask55 'Which schedule does a job use? choices: its own | 24 hours'
}
_b55() { # after fresh_reviewed: the second reviewer of risk H (instance B) completes its lenses in the same round
  local l n; n="$(grep -c '^### Task' .temper/specs/demo/tasks.md)"
  for l in readiness zoom-out comprehension tests; do
    "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $l B" \
      $([[ $l == readiness ]] && echo "--value $n") >/dev/null 2>&1
  done
}
_stage55() { _x55 "r = (d.get('run') or {}).get('stage')"; }   # the stage the run is at, as next reports it
_calls55() { # _calls55 <python expression over d>: runs each call it names (one a line) as the session would; prints
             # ran, or the first call that failed
  local c out="none"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || { echo "stopped at: ${c##*/scripts/temper }"; return; }
    out="ran"
  done < <(_x55 "r = '\n'.join($1)")
  echo "$out"
}

# --- Run.has_design: no tier, no risk, no phases.design and no Intent that asked add the stage ---
# (plan.fresh-review off at risk H: the plan question is asked, not the launch of the fresh reviewers)
_tg55=""
_plan55 $'plan:\n  fresh-review: off'; "$TEMPER" state set complexity complex >/dev/null 2>&1; riskH
_set55 intent_asked true; _tg55+="complex,H,asked=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55 $'plan:\n  fresh-review: off'; "$TEMPER" state set complexity medium >/dev/null 2>&1; riskH
_tg55+="medium,H=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55; "$TEMPER" state set complexity complex >/dev/null 2>&1; _set55 intent_asked true
_tg55+="complex,asked=$(_x55 "r = targets(d, ('run-design',))")"
assert_eq "design: no tier and no risk adds the stage" \
  "complex,H,asked=build|medium,H=build|complex,asked=build" "$_tg55"

_plan55 $'phases:\n  design: true\nplan:\n  fresh-review: off'
"$TEMPER" state set complexity complex >/dev/null 2>&1; riskH; _set55 intent_asked true
assert_eq "design: phases.design true adds nothing" "build" "$(_x55 "r = targets(d, ('run-design',))")"

_hd55=""
_plan55; _hd55+="none=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55; : > .temper/specs/demo/design.md; _hd55+="design.md=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55; gpass design; _hd55+="a Design verdict=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55; "$TEMPER" state set want_design true >/dev/null 2>&1
_hd55+="asked=$(_x55 "r = targets(d, ('run-design',))")|"
_plan55; gpass plan; _set55 next_stage '"design"'   # a run saved at Design by 9.8.4 or by the base, no design.md yet
_hd55+="at Design=$(_stage55),$(_x55 "r = d.get('action')")"
assert_eq "design: an existing design.md, a run at Design and the person's ask each add it" \
  "none=build|design.md=design|a Design verdict=design|asked=design|at Design=design,work" "$_hd55"

# --- the approval offers run-design ---
_plan55
_rd55="$(_x55 "o = opt(d, 'run-design')
c = (o or {}).get('calls') or []
r = 'none' if o is None else '%s|%s|first=%s|last=%s' % (o.get('label'), o.get('move'),
    'want_design' if c and c[0].endswith('state set want_design true') else c[:1],
    'design' if c and c[-1].endswith('state advance plan_complete design') else c[-1:])")"
_rd55+="|$(_calls55 "(opt(d, 'run-design') or {}).get('calls') or []")"
assert_eq "design: the approval offers run-design, and its calls end in state advance plan_complete design" \
  "Run Design first|approve|first=want_design|last=design|ran|stage=design|want_design=true" \
  "$_rd55|stage=$(_stage55)|want_design=$("$TEMPER" state get want_design 2>/dev/null)"

# The More list grows by one, and a list of more than four makes a second level (M2 of pull request 115): every option
# of the passed plan question is reachable in at most two dialogs, run-design among them, in each of its variants.
_reach55() { _x55 "o = opts(d)
deep = [x.get('id') for x, k in o if k > 1 or (k == 1 and x.get('kind') == 'more')]
r = 'not asked' if (d.get('ask') or {}).get('id') != 'plan.approve' else 'deeper: %s' % ','.join(deep) if deep else \
    'ok' if any(x.get('id') == 'run-design' for x, _ in o) else 'no run-design'"; }
_rc55=""
_plan55; _rc55+="offer=$(_reach55)|"
_plan55 $'plan:\n  fresh-review: off'; _rc55+="plain=$(_reach55)|"
_plan55; fresh_reviewed
"$TEMPER" evidence add --stage plan --phase fresh --claim '[readiness] Task 1: the case names no expected value' \
  --severity medium --label PROVEN >/dev/null 2>&1
gpass plan; _rc55+="revise=$(_reach55)"
assert_eq "design: every option of the plan question is reachable in at most two dialogs, run-design among them" \
  "offer=ok|plain=ok|revise=ok" "$_rc55"

# --- the answers reach the plan: the row tasks agree with decisions is the plan gate's ---
_sched55; "$TEMPER" intent answer 'Which schedule does a job use?' 'Its own.' >/dev/null 2>&1   # the first choice
"$TEMPER" gate plan >/dev/null 2>&1
_fc55="$(_row55 plan 'tasks agree with decisions' detail)"
python3 -c "import re, sys
t = sys.argv[1]
sys.exit(0 if re.search(r'first choice', t, re.I) and re.search(r'\b(1|one)\b', t, re.I) else 1)" "$_fc55" \
  && _fc55='counts 1 first choice'
_fc55_store="$(python3 -c "
import json
d = json.load(open('.temper/decisions.json'))
print(','.join(str(e.get('first')) for e in d if e.get('spec') == 'demo' and 'schedule' in str(e.get('question'))))
" 2>/dev/null)"
assert_eq "design: an answer that is the first choice passes the row with a note" \
  "row=True|counts 1 first choice|store first=True|plan=PASS" \
  "row=$(_row55 plan 'tasks agree with decisions' pass)|$_fc55|store first=$_fc55_store|plan=$(_verdict55 plan)"

_other55() { # the run of _sched55, answered with the second choice, its plan gate run
  _sched55; "$TEMPER" intent answer 'Which schedule does a job use?' '24 hours' >/dev/null 2>&1
  "$TEMPER" gate plan >/dev/null 2>&1
}
_other55
_an55="plan=$(_verdict55 plan)|row=$(_row55 plan 'tasks agree with decisions' pass)"
_an55_d="$(_row55 plan 'tasks agree with decisions' detail)"
if [[ "$_an55_d" == *'Revise the plan'* ]]; then _an55+="|names Revise the plan"; else _an55+="|detail: $_an55_d"; fi
"$TEMPER" gate plan >/dev/null 2>&1; _an55+="|again=$(_verdict55 plan)"
printf -- '- the job keeps its own schedule of 24 hours\n' >> .temper/specs/demo/tasks.md
"$TEMPER" gate plan >/dev/null 2>&1
_an55+="|tasks.md changed=$(_verdict55 plan),row=$(_row55 plan 'tasks agree with decisions' pass)"
assert_eq "design: another answer fails the plan gate until tasks.md changes" \
  "plan=FAIL|row=False|names Revise the plan|again=FAIL|tasks.md changed=PASS,row=True" "$_an55"

_other55
_rv55="first=$(_x55 "c = d.get('calls') or []
r = '%s,%d call,%s,agents=%d' % (d.get('action'), len(c), 'redo plan for the answer' if c and re.search(
    r'state redo plan --reason .*24 hours', c[0]) else c[:1], len(d.get('agents') or []))")"
_rv55+=",$(_calls55 "d.get('calls') or []")"
"$TEMPER" gate plan >/dev/null 2>&1   # the Plan agent ran again and left tasks.md as it was
_rv55+="|second=$(_x55 "a = d.get('ask') or {}
rec = next((o for o, k in opts(d) if o.get('recommended')), {})
skip = next((o for o, k in opts(d) if o.get('move') == 'override'), {})
r = '%s,%s,%s,redo=%s,skip reason=%s' % (d.get('action'), a.get('id'), rec.get('label'),
    any('state redo plan' in c for c in rec.get('calls') or []),
    ((skip.get('reason_question') or {}).get('options') or [{}])[0].get('label'))")"
_rv55_want="first=work,1 call,redo plan for the answer,agents=0,ran"
_rv55_want+="|second=ask,plan.fail,Revise the plan (Recommended),redo=True,skip reason=The tasks already agree"
assert_eq "design: the first revision is the CLI's own step, the second failure asks" "$_rv55_want" "$_rv55"

# --- an answer given after tasks.md exists reaches the Build prompt, whatever its prefix ---
m_setup < <(f9_tasks)
python3 - <<'PY'
p = ".temper/specs/demo/intent.md"
s = open(p).read()
# a Design row written before the plan (no answer the CLI kept), and an open product call with no prefix
s = s.replace("### Decisions\n",
              "### Decisions\n\n- Design: Which port does it use? -> 8080 (the person, 2026-01-01)\n", 1)
s = s.replace("### Open Questions\n",
              "### Open Questions\n\n- Blocking: Which schedule does a job use? choices: its own | 24 hours\n", 1)
open(p, "w").write(s)
PY
"$TEMPER" intent answer 'Which schedule does a job use?' '24 hours' >/dev/null 2>&1
_bp55="$(_x55 "p = '\n'.join(str(a.get('prompt')) for a in d.get('agents') or []
              if a.get('type') == 'temper:temper-build-task')
r = 'no task prompt' if not p else '%s|%s' % (
    'the answer' if re.search(r'Which schedule does a job use\?.*24 hours', p, re.S) else 'no answer',
    'the row with the prefix' if 'Which port' in p else 'no row with the prefix')")"
assert_eq "design: an answer given after tasks.md exists reaches the Build prompt whatever its prefix" \
  "the answer|no row with the prefix" "$_bp55"

# --- advance_ok: plan_complete is refused while a Blocking question is open ---
_sched55; gpass plan
_adv55() { # state advance plan_complete build: moved or refused, then the stage the run is at
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1 && echo "moved,$(_stage55)" || echo "refused,$(_stage55)"
}
_bq55="open=$(_adv55)"
"$TEMPER" intent answer 'Which schedule does a job use?' 'its own' >/dev/null 2>&1; _bq55+="|answered=$(_adv55)"
assert_eq "design: plan_complete is refused while a Blocking question is open" \
  "open=refused,plan|answered=moved,build" "$_bq55"

# --- risk H: the fresh review applies with no request, and the unattended run needs its round ---
_fh55=""
_plan55; riskH
_fh55+="H=$(_x55 "r = '%s,%s' % (d.get('action'),
    ','.join(sorted({str(a.get('type')) for a in d.get('agents') or []})) or 'no agent')")"
"$TEMPER" gate plan >/dev/null 2>&1; _fh55+=",gate=$(_verdict55 plan)"
_plan55
_fh55+="|M=$(_x55 "r = '%s,%s' % (d.get('action'), 'offers fresh-review' if opt(d, 'fresh-review') else 'no offer')")"
"$TEMPER" gate plan >/dev/null 2>&1; _fh55+=",gate=$(_verdict55 plan)"
assert_eq "design: at risk H the fresh review applies with no request" \
  "H=work,temper:temper-plan-review,gate=FAIL|M=ask,offers fresh-review,gate=PASS" "$_fh55"

_run55() { _x55 "r = '%s,%s' % ((d.get('ask') or {}).get('id'), 'offers approve-run' if opt(d, 'approve-run') else
    'no approve-run')"; }   # the question next asks, and whether it offers the option that starts the unattended run
_ar55=""
_plan55 $'plan:\n  fresh-review: off'; riskH; _ar55+="H no round=$(_run55)"
_plan55 $'plan:\n  fresh-review: off'; _ar55+="|M no round=$(_run55)"
_plan55; riskH; fresh_reviewed; _b55; gpass plan; _ar55+="|H clean round=$(_run55)"
_ar55+="|may_run_alone=$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import flow
print(callable(getattr(flow.Builder, 'may_run_alone', None)))" "$REPO_ROOT/scripts" 2>/dev/null)"
_ar55_want="H no round=plan.approve,no approve-run|M no round=plan.approve,offers approve-run"
_ar55_want+="|H clean round=plan.approve,offers approve-run|may_run_alone=True"
assert_eq "design: at risk H a plan with no fresh round offers no approve-run" "$_ar55_want" "$_ar55"

# --- the hold moved: the Design gate has no decisions row ---
_sched55; printf '# Design\n\n## Areas of Concern\n\nNone flagged: one module.\n' > .temper/specs/demo/design.md
"$TEMPER" intent answer 'Which schedule does a job use?' '24 hours' >/dev/null 2>&1
"$TEMPER" gate plan >/dev/null 2>&1; _dg55="plan row=$(_row55 plan 'tasks agree with decisions' pass)"
gpass plan; "$TEMPER" state advance plan_complete design >/dev/null 2>&1; "$TEMPER" gate design >/dev/null 2>&1
assert_eq "design: the Design gate has no decisions row" \
  "plan row=False|at=design|design row=absent|design=PASS" \
  "$_dg55|at=$(_stage55)|design row=$(_row55 design 'tasks agree with decisions' pass)|design=$(_verdict55 design)"

# --- the floor: only the entry design launches the Design agent (the scenario design starts it by run-design) ---
assert_eq "design: no floor entry but design launches temper:temper-design" "design=1,1,1|others=none" \
  "$(python3 - "$REPO_ROOT/scripts/e2e/floor.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["scenarios"]
launches = lambda x: ((x or {}).get("now") or {}).get("launches") or {}
n = lambda x: launches(x).get("temper:temper-design", 0)
others = sorted(k for k, e in d.items() if k != "design" and any(n(x) for x in e.values()))
print("design=%s|others=%s" % (",".join(str(n(x)) for x in (d.get("design") or {}).values()),
                               ",".join(others) or "none"))
PY
)"
