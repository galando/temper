# Case file 51 (WP10): one budget in the CLI. Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, nx, _pl,
# _unattended) are used here. Every repeat that follows a failed check spends one entry of `.temper/budget.json`, 2 for
# one failure and 6 for one run; a call past a limit is refused (exit 1, a line `BLOCKED: ...`) and writes nothing; the
# flow never offers such a call: at the limit it asks `run.budget`, and only the person grants more.
# A case that checks that a call spends nothing also checks that a call of the same kind that should spend does, so it
# cannot pass while nothing is counted. `python3 scripts/budget.py room <key>` prints the room of a key as one JSON
# object, `{"used", "limit", "run_used", "run_limit", "ok"}`, with `ok` true when one more repeat of it fits both
# limits.

# --- the helpers of this file ---
_b51used() { # _b51used [key [kind]]: how many entries of the budget record have that key and kind (all, with none)
  python3 - "${1:-}" "${2:-}" <<'PY'
import json, sys
try:
    u = json.load(open(".temper/budget.json")).get("used") or []
except (OSError, ValueError, AttributeError):
    u = []
print(sum(1 for x in u if isinstance(x, dict) and (not sys.argv[1] or x.get("key") == sys.argv[1])
          and (not sys.argv[2] or x.get("kind") == sys.argv[2])))
PY
}
_b51spend() { # _b51spend <key> <kind> <temper args>...: runs the call; prints how many entries of that key and kind it
              # added, then how many it added in all
  local k="$1" kind="$2" a b
  shift 2
  a="$(_b51used "$k" "$kind")"; b="$(_b51used)"
  "$TEMPER" "$@" >/dev/null 2>&1
  echo "$(( $(_b51used "$k" "$kind") - a )):$(( $(_b51used) - b ))"
}
_b51sum() { # the record and every file of the run state a refused call leaves byte equal
  cat .temper/budget.json .temper/build-state.json .temper/gates.json .temper/groups.json .temper/feedback-loops.json \
    .temper/overrides.json 2>/dev/null | cksum
}
_b51fail() { gfail "$1" "tests pass" "the latest run of a test command failed: unit"; }
_b51check() { # a run at Check, every stage before it passed
  fresh; gpass intent plan build review
  local s
  for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do
    "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1
  done
}
_b51build() { # a run at Build, Intent and Plan passed
  fresh; gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1
}
_b51g() { # _b51g <group G1 fields> <task 1 fields>: groups.json in the shape of _polg of temper-cases-28.sh
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"worktree": "w", "branch": "temper/demo/G1", %s}}, ' "$1" \
    > .temper/groups.json
  printf '"tasks": {"1": {"group": "G1", %s}}}\n' "$2" >> .temper/groups.json
}
_B51GFAIL='"status": "running", "fails": 1, "gate": {"verdict": "FAIL", '
_B51GFAIL+='"reason": "group G1 Validate failed (exit 1): true", "ran": true, "fail_lines": ["FAIL: test_a"]}'
_b51failat() { # _b51failat <review or check>: from a run at Build, pass the stages up to that one, go there and fail
               # its check
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  if [[ "$1" == check ]]; then gpass review; "$TEMPER" state advance review_complete check >/dev/null 2>&1; fi
  _b51fail "$1"
}
_b51full() { # a budget record of this run that already holds the limit of the run: six repeats, two for each of three
             # keys no case below fails (the record as docs/plans/one-go/wp/phase-4a-flow-core.md, WP10, step 1,
             # fixes it)
  python3 - <<'PY'
import json
rid = json.load(open(".temper/build-state.json")).get("run_id")
used = [{"key": k, "kind": kind, "stage": s, "why": "an earlier repeat", "ts": "2026-11-16T10:00:00Z"}
        for k, kind, s in (("gate:plan", "run again", "plan"), ("gate:build", "run again", "build"),
                           ("acceptance", "test corrected", "check")) for _ in (1, 2)]
json.dump({"v": 1, "run": rid, "used": used, "grants": []}, open(".temper/budget.json", "w"))
PY
}
_b51next() { # _b51next <python code over d, the JSON of temper next, that sets r>: prints r. The code has
             # ask(), every_option(q), calls_of(d) and refused(calls): the calls of a list the budget would refuse now,
             # each call mapped to its key by the table SPENDS and that key run through `budget.py room`
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" "$REPO_ROOT" <<'PY'
import json, os, shlex, subprocess, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def load(p, default):
    try:
        v = json.load(open(p))
        return v if isinstance(v, type(default)) else default
    except (OSError, ValueError):
        return default
gates, overrides = load(".temper/gates.json", {}), load(".temper/overrides.json", [])
groups = load(".temper/groups.json", {})
def ask():
    return d.get("ask") or {}
def every_option(q):
    out = list(q.get("options") or [])
    for k in ("more", "accept", "change"):
        if isinstance(q.get(k), dict):
            out += every_option(q[k])
    return out
def calls_of(d):
    agents = d.get("agents") or []
    return list(d.get("calls") or []) + [c for a in agents for c in (a.get("before") or []) + (a.get("after") or [])]
def failed(stage):
    g = gates.get(stage) or {}
    return g.get("verdict") == "FAIL" and not any(isinstance(o, dict) and o.get("stage") == stage for o in overrides)
def group(gid):
    return (groups.get("groups") or {}).get(gid) or {}
def key_of(call):
    try:
        w = shlex.split(call)
    except ValueError:
        return None
    i = next((n for n, x in enumerate(w) if x == "temper" or x.endswith("/temper")), None)
    if i is None:
        return None
    w = w[i + 1:]
    a, b, c, e = (w + ["", "", "", ""])[:4]
    if a == "state" and b in ("loop", "redo"):
        return "gate:" + c if failed(c) else None
    if a == "state" and b == "set" and c == "pipeline_round":
        return "pipeline"
    if a == "group" and b == "fix":
        return None if "--commit" in w else "group:" + c
    if a == "group" and b == "reopen":
        g = group(c)
        return "group:" + c if (g.get("gate") or {}).get("verdict") == "FAIL" or g.get("status") == "parked" else None
    if a == "group" and b == "gate":
        return "group:" + c if "--timeout-s" in w and (group(c).get("gate") or {}).get("verdict") == "FAIL" else None
    if a == "plan" and b == "patch":
        return "task:" + e if c == "task" else "gate:build" if c == "integration" else "group:" + c
    if a == "task" and b == "retry":
        return "task:" + c
    if a == "task" and b == "test":
        green = "--phase" in w and w[w.index("--phase") + 1:w.index("--phase") + 2] == ["green"]
        return "task:" + c if green and ((groups.get("tasks") or {}).get(c) or {}).get("env_fault") else None
    if a == "acceptance" and b == "reopen":
        return "acceptance"
    return None
def refused(calls):
    out = []
    for call in calls:
        k = key_of(call)
        if k is None:
            continue
        p = subprocess.run([sys.executable, os.path.join(sys.argv[3], "scripts", "budget.py"), "room", k],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        try:
            room = json.loads(p.stdout)
        except ValueError:
            room = None
        if not isinstance(room, dict) or room.get("ok") is not True:
            why = "no room" if isinstance(room, dict) else "no answer"
            out.append("%s (%s: %s)" % (call.split("/scripts/")[-1], k, why))
    return out
r = None
exec(sys.argv[1])
print(r)
PY
}
_b51stop() { # one value for a state: "ok" when next is no auto or work action holding a call the budget refuses now
  _b51next "c = refused(calls_of(d)) if d.get('action') in ('auto', 'work') else []
r = ('no next' if not d.get('action') else 'ok' if not c else '%s holds %s' % (d['action'], '; '.join(c)))"
}

# --- each kind of repeat spends one: one assertion for each row of SPENDS ---
_b51check; _b51fail check
assert_eq "budget: each kind of repeat spends one: state loop from a failed gate, gate:<from>, step back" "1:1" \
  "$(_b51spend gate:check 'step back' state loop check build --reason 'a real problem')"
_b51check; _b51fail check
assert_eq "budget: each kind of repeat spends one: state redo of a failed gate, gate:<stage>, run again" "1:1" \
  "$(_b51spend gate:check 'run again' state redo check --reason 'the suite again')"
_b51build; _b51g "$_B51GFAIL" '"status": "passed"'
assert_eq "budget: each kind of repeat spends one: group fix, group:<G>, group fix" "1:1" \
  "$(_b51spend group:G1 'group fix' group fix G1)"
_b51build; _b51g "$_B51GFAIL" '"status": "passed"'
_b51x="failed=$(_b51spend group:G1 'tasks again' group reopen G1 --task 1)"
_b51build; _b51g '"status": "parked", "parked_reason": "Task 1 failed three attempts"' '"status": "failed"'
assert_eq "budget: each kind of repeat spends one: group reopen of a failed or parked group, group:<G>, tasks again" \
  "failed=1:1|parked=1:1" "$_b51x|parked=$(_b51spend group:G1 'tasks again' group reopen G1 --task 1)"
_b51build
_b51x='"status": "running", "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: true", '
_b51g "$_b51x"'"ran": true, "timeout_s": 600}' '"status": "passed"'
assert_eq "budget: each kind of repeat spends one: group gate with more time at a failed check, group:<G>, more time" \
  "1:1" "$(_b51spend group:G1 'more time' group gate G1 --timeout-s 1200)"
_b51build; _b51g '"status": "running"' '"status": "passed"'
_b51x="group=$(_b51spend group:G1 'plan patch' plan patch G1 --cmd 'test -d .')"
_b51x+="|task=$(_b51spend task:1 'plan patch' plan patch task 1 --cmd 'test -d src || true')"
assert_eq "budget: each kind of repeat spends one: plan patch, group:<G>, task:<N> or gate:build, plan patch" \
  "group=1:1|task=1:1|integration=1:1" \
  "$_b51x|integration=$(_b51spend gate:build 'plan patch' plan patch integration --cmd 'test -f README || true')"
_b51build; _b51g '"status": "running"' '"status": "covered", "covered": {"cmd": "true", "tail": "1 passed"}'
assert_eq "budget: each kind of repeat spends one: task retry, task:<N>, task again" "1:1" \
  "$(_b51spend task:1 'task again' task retry 1)"
_b51build; _b51g '"status": "running"' '"status": "running", "attempt": 1'
_b51nofault="$(_b51spend task:1 'check again' task test 1 --phase green)"
_b51build
_b51x='"env_fault": {"reason": "connection refused", "ts": "2026-11-16T10:00:00Z", "again": false}'
_b51g '"status": "running"' '"status": "running", "attempt": 1, '"$_b51x"
_b51x="no fault=$_b51nofault"
assert_eq "budget: each kind of repeat spends one: task test green on an environment fault, task:<N>, check again" \
  "no fault=0:0|fault=1:1" "$_b51x|fault=$(_b51spend task:1 'check again' task test 1 --phase green)"
_b51check; _b51fail check
assert_eq "budget: each kind of repeat spends one: acceptance reopen, acceptance, test corrected" "1:1" \
  "$(_b51spend acceptance 'test corrected' acceptance reopen --reason 'the locked test asserts the wrong status')"
_pl
assert_eq "budget: each kind of repeat spends one: state set pipeline_round, pipeline, CI fix" "1:1" \
  "$(_b51spend pipeline 'CI fix' state set pipeline_round 2)"

# --- the third repeat for one failure is refused, and writes nothing ---
_b51check
for _b51i in 1 2; do _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1; done
_b51fail check
_b51before="$(_b51sum)"; _b51out="$("$TEMPER" state redo check --reason 'a third time' 2>&1)"; _b51rc=$?
_b51line="$(head -1 <<<"$_b51out")"
assert_eq "budget: the third repeat for one failure is refused" \
  "1|BLOCKED: gate:check was repeated 2 times (limit 2)|unchanged|2|FAIL" \
  "$_b51rc|${_b51line%%;*}|$([[ "$(_b51sum)" == "$_b51before" ]] && echo unchanged || echo written)|$(
    _b51used gate:check)|$(python3 -c "import json
print((json.load(open('.temper/gates.json')).get('check') or {}).get('verdict'))" 2>&1)"

# --- the seventh repeat of a run is refused: three keys, two each, then a fourth key ---
_b51seven() { # groups.json of the run: G1 and G2 failed their checks, Task 1 of G1 is covered
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"worktree": "w", "branch": "temper/demo/G1", %s}, ' \
    "$_B51GFAIL" > .temper/groups.json
  printf '"G2": {"worktree": "w2", "branch": "temper/demo/G2", "status": "running", "gate": {"verdict": "FAIL", ' \
    >> .temper/groups.json
  printf '"reason": "group G2 Validate timed out after 600s: true", "ran": true, "timeout_s": 600}}}, ' \
    >> .temper/groups.json
  printf '"tasks": {"1": {"group": "G1", "status": "covered", "covered": {"cmd": "true", "tail": "1 passed"}}}}\n' \
    >> .temper/groups.json
}
_b51check
for _b51i in 1 2; do
  _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1
  _b51seven; "$TEMPER" group fix G1 >/dev/null 2>&1
  _b51seven; "$TEMPER" task retry 1 >/dev/null 2>&1
done
_b51seven
_b51six="$(_b51used gate:check):$(_b51used group:G1):$(_b51used task:1):$(_b51used)"
_b51before="$(_b51sum)"; _b51out="$("$TEMPER" group gate G2 --timeout-s 1200 2>&1)"; _b51rc=$?
assert_eq "budget: the seventh repeat of a run is refused" "2:2:2:6|1:BLOCKED|no marker|unchanged|6" \
  "$_b51six|$_b51rc:$(head -1 <<<"$_b51out" | cut -d: -f1)|$(
    grep -q '^VERDICT:' <<<"$_b51out" && echo marker || echo 'no marker')|$(
    [[ "$(_b51sum)" == "$_b51before" ]] && echo unchanged || echo written)|$(_b51used)"

# --- a change at a passed gate spends nothing; the same call at a failed gate spends one ---
_b51build; gpass build
_b51x="redo of a passed Build=$(_b51spend gate:build 'run again' state redo build --reason 'once more')"
_b51build; _b51g '"status": "passed", "gate": {"verdict": "PASS", "ran": true}' '"status": "passed"'
_b51x+="|reopen of a passed group=$(_b51spend group:G1 'tasks again' group reopen G1 --task 1)"
_b51build; _b51failat review; gpass review
_b51x+="|step back from a passed Review=$(_b51spend gate:review 'step back' state loop review build --reason x)"
_b51check; _b51fail check; "$TEMPER" override check --reason 'a known flaky test' >/dev/null 2>&1
_b51x+="|redo of a skipped Check=$(_b51spend gate:check 'run again' state redo check --reason 'once more')"
_b51build; _b51fail build
_b51want="redo of a passed Build=0:0|reopen of a passed group=0:0|step back from a passed Review=0:0"
_b51want+="|redo of a skipped Check=0:0|redo of a failed Build=1:1"
assert_eq "budget: a change at a passed gate spends nothing" "$_b51want" \
  "$_b51x|redo of a failed Build=$(_b51spend gate:build 'run again' state redo build --reason 'the fix')"

# --- no argument and no variable exempts a call ---
_b51check
_b51fail check; TEMPER_BUDGET=off "$TEMPER" state redo check --reason 'the variable says off' >/dev/null 2>&1
_b51x="variable=$(_b51used gate:check)"
_b51fail check; "$TEMPER" state redo check --reason 'the flag says so' --no-budget --person >/dev/null 2>&1
_b51x+="|flags=$(_b51used gate:check)"
_b51fail check
_b51out="$(TEMPER_BUDGET=99 "$TEMPER" state redo check --reason 'the variable says more' 2>&1)"; _b51rc=$?
_b51x+="|variable at the limit=$_b51rc:$(head -1 <<<"$_b51out" | cut -d: -f1):$(_b51used gate:check)"
_b51out="$("$TEMPER" state redo check --no-budget --reason 'the flag says so' --person 2>&1)"; _b51rc=$?
assert_eq "budget: no argument and no variable exempts a call" \
  "variable=1|flags=2|variable at the limit=1:BLOCKED:2|flags at the limit=1:BLOCKED:2" \
  "$_b51x|flags at the limit=$_b51rc:$(head -1 <<<"$_b51out" | cut -d: -f1):$(_b51used gate:check)"

# --- at the limit next asks run.budget, and offers no call the CLI would refuse ---
_b51q='a = ask(); o = every_option(a); q = a.get("question") or {}
g = next((x for x in o if x.get("id") == "grant-more"), {})
f = (a.get("options") or [{}])[0]
r = "|".join([str(a.get("id")), str(a.get("kind")), str(q.get("header")),
    "first=%s:%s" % (f.get("id"), f.get("recommended")),
    "recommended=%s" % ",".join(str(x.get("id")) for x in o if x.get("recommended")),
    "grant=%s:%s:%s" % (g.get("label"), g.get("move"),
                        any(" budget grant --key %s --reason " % KEY in c for c in g.get("calls") or [])),
    "count=%s" % ("was repeated 2 times (limit 2)" in str(q.get("question"))),
    "ends=%s" % str(q.get("question")).endswith("Save the run for later, or allow two more?"),
    "refused=%s" % ("; ".join(refused([c for x in o for c in x.get("calls") or []])) or "none")])'
_b51want="run.budget|gate|Temper gate|first=save:True|recommended=save|grant=Allow two more:grant:True|count=True"
_b51want+="|ends=True|refused=none"
_b51check
for _b51i in 1 2; do _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1; done
_b51fail check
assert_eq "budget: at the limit next asks run.budget: a failed Check run again twice" "$_b51want" \
  "$(_b51next "KEY = 'gate:check'
$_b51q")"
_b51build
for _b51i in 1 2; do _b51g "$_B51GFAIL" '"status": "passed"'; "$TEMPER" group fix G1 >/dev/null 2>&1; done
_b51g "$_B51GFAIL"', "fix_tries": 2' '"status": "passed"'
assert_eq "budget: at the limit next asks run.budget: a failed group check fixed twice" "$_b51want" \
  "$(_b51next "KEY = 'group:G1'
$_b51q")"

# --- with a record at the limit of the run, no auto or work action holds a call the budget refuses ---
_unattended build; _b51g "$_B51GFAIL" '"status": "passed"'; _b51full
_b51x="failed group check=$(_b51stop)"
_unattended review
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:3 the input reaches a shell unquoted' --severity critical \
  --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC >/dev/null 2>&1
"$TEMPER" gate review >/dev/null 2>&1; _b51full
_b51x+="|blocking finding at Review=$(_b51stop)"
_unattended check; _b51fail check; _b51full
assert_eq "budget: no auto or work action holds a refused call" \
  "failed group check=ok|blocking finding at Review=ok|failed Check=ok" "$_b51x|failed Check=$(_b51stop)"

# --- a grant adds two for the key and for the run, with its reason ---
_b51check
for _b51i in 1 2; do _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1; done
_b51fail check
"$TEMPER" budget grant --key gate:check >/dev/null 2>&1; _b51x="no reason=$?"
"$TEMPER" budget grant --key gate:check --reason 'The next try is different' >/dev/null 2>&1; _b51x+="|grant=$?"
_b51x+="|room=$(python3 "$REPO_ROOT/scripts/budget.py" room gate:check 2>/dev/null | python3 -c "import json, sys
d = json.load(sys.stdin)
print('%s/%s of %s/%s' % (d['used'], d['limit'], d['run_used'], d['run_limit']))" 2>/dev/null || echo none)"
_b51x+="|grants=$(python3 -c "import json
g = json.load(open('.temper/budget.json'))['grants']
print(','.join('%s:%s:%s' % (x['key'], x['n'], x['reason']) for x in g))" 2>/dev/null || echo none)"
_b51x+="|next=$(_b51next "r = '%s:%s' % (ask().get('id'), any(x.get('id') == 'back' for x in every_option(ask())))")"
"$TEMPER" state redo check --reason 'a third time, granted' >/dev/null 2>&1; _b51rc=$?
assert_eq "budget: a grant adds two for the key and for the run, with its reason" \
  "no reason=1|grant=0|room=2/4 of 2/8|grants=gate:check:2:The next try is different|next=check.fail:True|third=0:3" \
  "$_b51x|third=$_b51rc:$(_b51used gate:check)"

# --- the record survives a step back to Plan; state clear and state init remove it ---
_b51build; _b51g "$_B51GFAIL" '"status": "passed"'
"$TEMPER" group fix G1 >/dev/null 2>&1
"$TEMPER" state loop build plan --reason 'the plan splits the work wrong' >/dev/null 2>&1
_b51x="stage=$("$TEMPER" state get next_stage 2>/dev/null)"
_b51x+="|groups.json=$([[ -f .temper/groups.json ]] && echo kept || echo gone)"
assert_eq "budget: the record survives a step back to Plan" "stage=plan|groups.json=gone|group:G1=1" \
  "$_b51x|group:G1=$(_b51used group:G1 'group fix')"
_b51check; _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1
_b51x="before clear=$(_b51used)"
"$TEMPER" state clear >/dev/null 2>&1
_b51x+="|after clear=$([[ -e .temper/budget.json ]] && echo kept || echo gone)"
_b51check; _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1
_b51x+="|before init=$(_b51used)"
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
assert_eq "budget: state clear and state init remove it" \
  "before clear=1|after clear=gone|before init=1|after init=gone" \
  "$_b51x|after init=$([[ -e .temper/budget.json ]] && echo kept || echo gone)"

# --- the old loop keys are read by nothing: they change no count and no refusal, and no script names them ---
_b51old() { # the run's config holds every old loop key, set high, and the step back turned off
  python3 - <<'PY'
import re
p = ".claude/temper.config"
t = open(p).read()
t = re.sub(r"(?m)^loops:\n(?:  .*\n)*", "", t)
t = re.sub(r"(?m)^  budget:\n(?:    .*\n)*", "", t)
budget = "  budget:\n    max-total-loops: 99\n    max-stages: 99\n"
if re.search(r"(?m)^autonomy:$", t):
    t = re.sub(r"(?m)^autonomy:\n", "autonomy:\n" + budget, t, count=1)
else:
    t += "autonomy:\n" + budget
open(p, "w").write(t + "loops:\n  max-per-type: 9\nfix:\n  max-loops: 9\nfeedback:\n  enabled: false\n")
PY
}
_b51check; _b51old; _b51fail check
_b51x="config=$("$TEMPER" config get loops.max-per-type):$("$TEMPER" config get autonomy.budget.max-total-loops):$(
  "$TEMPER" config get feedback.enabled)"
_b51x+="|back offered=$(_b51next "r = any(x.get('id') == 'back' and any(' state loop check build ' in c
        for c in x.get('calls') or []) for x in every_option(ask()))")"
"$TEMPER" state loop check build --reason 'one' >/dev/null 2>&1; _b51failat check
"$TEMPER" state loop check build --reason 'two' >/dev/null 2>&1; _b51failat check
_b51out="$("$TEMPER" state loop check build --reason 'three' 2>&1)"; _b51rc=$?
_b51x+="|third from Check=$_b51rc:$(head -1 <<<"$_b51out" | cut -d: -f1):$(_b51used gate:check 'step back')"
_b51build; _b51old
for _b51i in 1 2; do _b51failat review; "$TEMPER" state loop review build --reason "$_b51i" >/dev/null 2>&1; done
_b51failat review
_b51out="$("$TEMPER" state loop review build --reason 'three' 2>&1)"; _b51rc=$?
_b51x+="|third from Review=$_b51rc:$(head -1 <<<"$_b51out" | cut -d: -f1):$(_b51used gate:review 'step back')"
_b51x+="|readers=$(grep -rlE 'max-per-type|max-loops|max-total-loops|max-stages|feedback\.enabled' \
  "$REPO_ROOT/scripts" --exclude-dir=selftest --exclude-dir=__pycache__ 2>/dev/null | sed "s|^$REPO_ROOT/||" \
  | LC_ALL=C sort | paste -sd, -)"
assert_eq "budget: the old keys are read by nothing" \
  "config=9:99:false|back offered=True|third from Check=1:BLOCKED:2|third from Review=1:BLOCKED:2|readers=" "$_b51x"

# --- an unattended run at the limit stops: the park call, and then run.budget ---
_unattended check
for _b51i in 1 2; do _b51fail check; "$TEMPER" state redo check --reason 'the suite again' >/dev/null 2>&1; done
_b51fail check
_b51x="$(_b51next "c = d.get('calls') or []
p = 'park' if c and ' park --verdict ' in c[0] else 'no park'
r = '%s:%s:%s' % (d.get('action'), p, '; '.join(refused(calls_of(d))) or 'none')")"
[[ "$_b51x" == auto:park:* ]] && bash -c "$(nx "d['calls'][0]")" >/dev/null 2>&1
assert_eq "budget: an unattended run at the limit stops" "auto:park:none|ask:run.budget" \
  "$_b51x|$(_b51next "r = '%s:%s' % (d.get('action'), ask().get('id'))")"
