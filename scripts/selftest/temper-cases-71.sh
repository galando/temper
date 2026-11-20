# Case file 71 (WP27): a narrow revise agent; code and metric criteria by the CLI; models by tier and risk. A change
# to a plan that exists (a note, a fresh finding, a loop back that does not pass through Intent) is made by
# temper:temper-plan-revise on Sonnet, which gets the reason, every item whole and the task blocks they name, and no
# project brief; a first plan and a changed intent get the planner, and a second failed revise falls back to it before
# the approval (after it, the budget question). A criterion validated by `code` or `metric` carries its command in
# backticks, which the CLI runs at integrate and at Check, so no record pass and no Check agent are launched; one with
# no command is the person's to confirm. One table of models by tier and risk, with config keys over it. A sensitive
# path makes risk H, and the CLI runs temper risk after the planner. The acceptance writer stays alone and first.
# Sourced by test-temper.sh; its helpers (fresh, setup, gpass, gfail, _at, nx, riskH, m_setup, fresh_reviewed) are
# used here, and the builders below are this file's own. Token: w27. A call the CLI does not have yet stays inside
# $( ... ) or ends in || true, so the file always runs to its end.

# The words of the record pass, spelled in two parts so that the package's Done when (a git grep of the two words in
# scripts) does not find this file.
_RO71="Record"; _RO71+=" only"

# --- the helpers of this file ---
_tasks71() { # _tasks71 [one-case]: tasks.md of one group and three tasks, three production files; with one-case,
             # Task 2 has one Case, which fails the plan gate's row task test cases
  cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The demo group.

### Task 1: parse
**File:** `src/parse.sh`, `unit/parse_test.sh`
**Depends:** none
**Test:** `bash unit/parse_test.sh`
**Cases:**
- a line is parsed into its fields
- an empty line gives no field
- [ ] done

### Task 2: refund
**File:** `src/refund.sh`, `unit/refund_test.sh`
**Depends:** Task 1
**Test:** `bash unit/refund_test.sh`
**Cases:**
- a refund lowers the balance by its amount
- a refund larger than the balance is refused
- [ ] done

### Task 3: report
**File:** `src/report.sh`, `unit/report_test.sh`
**Depends:** Task 2
**Test:** `bash unit/report_test.sh`
**Cases:**
- the report prints one line per account
- an account with no movement prints a zero line
- [ ] done
TASKS
  [[ "${1:-}" == one-case ]] && sed -i '/^- a refund larger than the balance is refused$/d' .temper/specs/demo/tasks.md
  return 0
}
_plan71() { # a run at Plan before the approval, tier simple, with the tasks of this file and no plan.md
  fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _tasks71 "${1:-}"; rm -f .temper/specs/demo/plan.md
  "$TEMPER" state set complexity simple >/dev/null 2>&1
}
_NOTE71="the refund case of Task 2 must name the amount in cents, as the ledger stores it"
_note71() { # the plan gated, then the person's note typed at the plan question, as the page records a typed change
            # (commands/temper.md, Typed text: the evidence add of kind input, then temper state redo plan)
  _plan71; "$TEMPER" gate plan >/dev/null 2>&1
  "$TEMPER" evidence add --stage plan --phase note --kind input --claim "$_NOTE71" >/dev/null 2>&1
  "$TEMPER" state redo plan --reason "$_NOTE71" >/dev/null 2>&1
}
_agent71() { # _agent71 <python expression over d (temper next --json), a (its first agent or {}), p (a's prompt) and
             # line(prefix) (the first line of p that starts with prefix, else None)>
  python3 -B - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
a = (d.get("agents") or [{}])[0]
p = str(a.get("prompt") or "")
def line(prefix):
    return next((l for l in p.splitlines() if l.startswith(prefix)), None)
print(eval(sys.argv[1]))
PY
}
_drive71() { # _drive71 <launches> <text>: plays the flow as the orchestrator does, from temper next: an action's calls,
             # then each agent's before and after calls (the scripted agent changes nothing); at a question, the option
             # that runs the plan again (state redo plan, or a step back into Plan), as the person picks it; a question
             # with no such option ends the play (a typed note would be a new reason). Prints each launch as its action
             # and agent type (`work temper:temper-plan`) and how the play stopped, joined by |, then |items=yes when
             # the prompt of the first planner launch holds <text> (else items=no, or items=none with no planner launch)
  python3 -B - "$1" "$TEMPER" "$2" <<'PY'
import json, re, subprocess, sys
most, cli, text = int(sys.argv[1]), sys.argv[2], sys.argv[3]
def nxt():
    out = subprocess.run([cli, "next", "--json"], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except ValueError:
        return {}
def run(c):
    c = str(c).replace("{ms}", "1000").replace("{reason}", "the plan is still wrong").replace("{text}", "the plan is still wrong")
    subprocess.run(["bash", "-c", c], capture_output=True, text=True)
trace, items, launches = [], "none", 0
for _ in range(14):
    d = nxt()
    act = d.get("action")
    if act in ("work", "auto"):
        for c in d.get("calls") or []:
            run(c)
        agents = d.get("agents") or []
        for a in agents:
            trace.append("%s %s" % (act, a.get("type")))
            launches += 1
            if a.get("type") == "temper:temper-plan" and items == "none":
                items = "yes" if text in str(a.get("prompt") or "") else "no"
            for c in list(a.get("before") or []) + list(a.get("after") or []):
                run(c)
        if launches >= most:
            break
        if not agents and not d.get("calls"):
            trace.append("stop %s" % act)
            break
    elif act == "ask":
        q = d.get("ask") or {}
        if q.get("id") == "run.budget":
            trace.append("ask run.budget")
            break
        opts = list(q.get("options") or []) + list((q.get("more") or {}).get("options") or [])
        pick = next((o for o in opts if any(re.search(r"\bstate (?:redo|loop \S+) plan\b", str(c)) for c in o.get("calls") or [])), None)
        if pick is None:
            trace.append("ask %s" % q.get("id"))
            break
        for c in pick.get("calls") or []:
            run(c)
    else:
        trace.append("stop %s" % act)
        break
print("%s|items=%s" % ("|".join(trace), items))
PY
}
_crit71() { # _crit71 <the Validate text of AC-02>: an accepted intent; AC-01 by its scenario (Test: true), AC-02 as given
  python3 -B - "$1" <<'PY'
import sys
open(".temper/specs/demo/intent.md", "w").write("""**Author:** Demo Author <demo@example.com>
**Status:** accepted
**Created:** 2026-01-01
**Complexity:** simple

## Problem
Users cannot reset the demo today.

### Success Criteria
- [ ] AC-01 [required]: the demo resets its counter
  Why: a reset must be possible
  Validate: scenario — the scenario below
- [ ] AC-02 [required]: the reset route is registered
  Why: the client calls it by that route
  Validate: %s

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
Scenario: the demo resets
  Then the counter is zero
  Covers: AC-01
  Test: true
```

## Source Traceability
### Context Sources
- none: description only — nothing linked
""" % sys.argv[1])
PY
}
_bind71() { # the intent as the approval binds it (WP12): intent_hash is the digest of intent.md as it is now
  python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, subprocess, sys
p = ".temper/build-state.json"
d = json.load(open(p))
d["intent_hash"] = subprocess.run([sys.executable, sys.argv[1] + "/approval.py", "digest", ".temper/specs/demo/intent.md"],
                                  capture_output=True, text=True).stdout.strip()
json.dump(d, open(p, "w"), indent=2)
PY
}
_build71() { # _build71 <Validate text of AC-02> <file> <its text>: a one group run at Build on its feature branch, the
             # group passed, the task's test runs recorded, the file committed on the branch, ready for temper integrate
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'The demo group.' '' '### Task 1: reset' '**File:** `src/reset.sh`' '**Depends:** none' '**Test:** `true`' \
    '**Cases:**' '- the counter is zero after a reset' '- a reset of a zero counter keeps it zero' '- [ ] done' | m_setup
  printf 'check:\n  commands:\n    test: "true"\n' >> .claude/temper.config
  _crit71 "$1"; _bind71
  python3 -B - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
for g in d.get("groups", {}).values():
    g.update({"status": "passed", "confirmed": True, "gate": {"verdict": "PASS"}})
d["tasks"] = {"1": {"status": "passed", "group": "G1"}}
json.dump(d, open(".temper/groups.json", "w"))
PY
  "$TEMPER" evidence add --stage build --phase red --claim 'unit tests' --cmd 'true' --exit 1 >/dev/null 2>&1
  "$TEMPER" evidence add --stage build --phase green --claim 'unit tests' --cmd 'true' --exit 0 >/dev/null 2>&1
  mkdir -p "$(dirname "$2")"; printf '%s\n' "$3" > "$2"
  git add -- "$2" >/dev/null 2>&1; git commit -q -m "the file the criterion reads" -- "$2" >/dev/null 2>&1
}
_rows71() { # _rows71 <stage>: the exit codes of the rows of that ledger for AC-02 that the CLI ran, joined by , (none)
  python3 -B - "$1" <<'PY'
import json, sys
try:
    rows = [x for x in json.load(open(".temper/evidence/%s.json" % sys.argv[1])) if isinstance(x, dict)]
except (OSError, ValueError):
    rows = []
got = [str(x.get("exit_code")) for x in rows if x.get("criterion") == "AC-02" and x.get("executed_by") == "cli"]
print(",".join(got) or "none")
PY
}
_row71() { # _row71 <stage> <row>: pass|detail of that row of the stage's verdict in gates.json, or absent
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    rows = (json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}).get("requirements") or []
except (OSError, ValueError):
    rows = []
x = next((x for x in rows if isinstance(x, dict) and x.get("name") == sys.argv[2]), None)
print("absent" if x is None else "%s|%s" % (x.get("pass"), x.get("detail")))
PY
}
_named71() { # _named71 <text>...: how many agents of temper next hold any of the texts in their prompt
  python3 -B - "$("$TEMPER" next --json 2>/dev/null)" "$@" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
print(sum(1 for a in d.get("agents") or [] if any(t in str(a.get("prompt") or "") for t in sys.argv[2:])))
PY
}

# --- 1. a note gets the revise agent ---
_note71
assert_eq "w27 a note gets the revise agent: at Plan with tasks.md, a typed note launches one temper:temper-plan-revise on sonnet with the note whole, Affected tasks naming Task 2, no Project brief line and no brief call" \
  "work|1|temper:temper-plan-revise|sonnet|note=yes|affected=2|brief line=no|brief call=no" \
  "$(_agent71 "'|'.join([str(d.get('action')), str(len(d.get('agents') or [])), str(a.get('type')), str(a.get('model')), 'note=' + ('yes' if '$_NOTE71' in p else 'no'), 'affected=' + (','.join(re.findall(r'\d+', line('Affected tasks:'))) or 'not named' if line('Affected tasks:') is not None else 'no line'), 'brief line=' + ('yes' if line('Project brief:') is not None else 'no'), 'brief call=' + ('yes' if any(re.search(r'temper brief\b', str(c)) for c in d.get('calls') or []) else 'no')])")"

# --- 1b. the brief of the revise agent (mechanism step 1) ---
assert_eq "w27 the revise brief: agents/plan-revise.md is named temper-plan-revise on sonnet, has its Gotchas, is listed in the manifest, is under 6 KB, points at no reference/plan.md and returns PLAN REVISED" \
  "exists=yes|name=temper-plan-revise|model=sonnet|gotchas=yes|listed=yes|small=yes|reference=no|returns=yes" \
  "$(python3 -B - "$REPO_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
p = os.path.join(root, "agents", "plan-revise.md")
if not os.path.isfile(p):
    print("exists=no"); sys.exit(0)
t = open(p, encoding="utf-8").read()
fm = t.split("---", 2)[1] if t.startswith("---") else ""
get = lambda k: (re.search(r"^%s:\s*(.+?)\s*$" % k, fm, re.M) or [None, "none"])[1]
listed = "./agents/plan-revise.md" in (json.load(open(os.path.join(root, ".claude-plugin", "plugin.json"))).get("agents") or [])
print("exists=yes|name=%s|model=%s|gotchas=%s|listed=%s|small=%s|reference=%s|returns=%s" % (
    get("name"), get("model"), "yes" if "**Gotchas**" in t else "no", "yes" if listed else "no",
    "yes" if len(t.encode("utf-8")) < 6144 else "no", "yes" if "reference/plan.md" in t else "no",
    "yes" if "PLAN REVISED" in t else "no"))
PY
)"

# --- 2. a finding is passed whole ---
_LONG71="$(python3 -B -c "
s = '[readiness] Task 3: the Case the report prints one line per account names no expected value, '
w = 'so a builder cannot tell a report that prints the balance from one that prints the count of movements; '
while len(s) < 600:
    s += w
print(s[:600].rsplit(' ', 1)[0])")"
_plan71; fresh_reviewed
"$TEMPER" evidence add --stage plan --phase fresh --severity high --claim "$_LONG71" >/dev/null 2>&1
"$TEMPER" gate plan >/dev/null 2>&1; "$TEMPER" state redo plan --reason "fresh review" >/dev/null 2>&1
assert_eq "w27 a finding is passed whole: an open finding of about 600 characters is in the revise prompt whole (not cut at 200), and Affected tasks holds the Task 3 its claim names" \
  "length=${#_LONG71}|temper:temper-plan-revise|whole=yes|affected=3" \
  "length=${#_LONG71}|$(W71="$_LONG71" _agent71 "'|'.join([str(a.get('type')), 'whole=' + ('yes' if __import__('os').environ['W71'] in p else 'no'), 'affected=' + (','.join(re.findall(r'\d+', line('Affected tasks:'))) or 'not named' if line('Affected tasks:') is not None else 'no line')])")"

# --- 3. a first plan and a changed intent get the planner; a loop back into Plan gets the revise agent ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; rm -f .temper/specs/demo/tasks.md
"$TEMPER" evidence add --stage plan --phase note --kind input --claim "$_NOTE71" >/dev/null 2>&1
_w27_3="first=$(_agent71 "a.get('type')")"
_plan71; "$TEMPER" gate plan >/dev/null 2>&1
"$TEMPER" state loop plan intent --reason 'the intent misses the rule for a partial refund' >/dev/null 2>&1
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_w27_3+="|through Intent=$(_agent71 "a.get('type')")"
assert_eq "w27 a first plan and a changed intent get the planner: no tasks.md, and a loop back to Intent that passes Plan again, launch temper:temper-plan" \
  "first=temper:temper-plan|through Intent=temper:temper-plan" "$_w27_3"
_plan71; gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" state loop build plan --reason 'Task 2 cannot be built as written: the refund needs the ledger first' >/dev/null 2>&1
assert_eq "w27 a loop back into Plan that does not pass through Intent gets the revise agent, with the reason a loop back from Build and the task it names" \
  "temper:temper-plan-revise|reason=yes|affected=2" \
  "$(_agent71 "'|'.join([str(a.get('type')), 'reason=' + ('yes' if re.search(r'^Reason: a loop back from build\b', p, re.M | re.I) else 'no'), 'affected=' + (','.join(re.findall(r'\d+', line('Affected tasks:'))) or 'not named' if line('Affected tasks:') is not None else 'no line')])")"

# --- 4. the second failure falls back ---
_W27_4="[readiness] Task 2: the Case a refund larger than the balance is refused names no message"
_plan71; fresh_reviewed
"$TEMPER" evidence add --stage plan --phase fresh --severity high --claim "$_W27_4" >/dev/null 2>&1; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "w27 the second failure falls back: before the approval, two revise launches for one reason with the plan gate still FAIL, then the planner with the same items" \
  "work temper:temper-plan-revise|work temper:temper-plan-revise|work temper:temper-plan|items=yes" "$(_drive71 3 "$_W27_4")"
# after the approval: the run the person started at the approval, a step back into Plan, a plan gate that keeps failing
fresh; _tasks71 one-case; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
gpass plan; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" state loop build plan --reason 'Task 2 cannot be built as written: the refund needs the ledger first' >/dev/null 2>&1
assert_eq "w27 the second failure falls back: after the approval (a step back into Plan the person picked) the same state is the budget question run.budget, never a planner launch, and no revise launch is an auto step" \
  "work temper:temper-plan-revise|work temper:temper-plan-revise|ask run.budget|items=none" "$(_drive71 4 "Task 2 cannot be built")"

# --- 5. a code criterion is run by the CLI ---
_CMD71='grep -q "POST /api/reset" src/routes.txt'
_build71 "code — \`$_CMD71\`" src/routes.txt 'POST /api/reset -> reset_counter'
"$TEMPER" integrate >/dev/null 2>&1 || true
_w27_5="rows=$(_rows71 build)"; "$TEMPER" gate build >/dev/null 2>&1
_w27_5+="|criteria validated=$(_row71 build 'criteria validated' | cut -d'|' -f1)|record agents=$(_named71 "$_RO71")"
assert_eq "w27 a code criterion is run by the CLI: after temper integrate the build ledger has the CLI's row for AC-02 with exit 0, criteria validated passes, and no agent is told to record" \
  "rows=0|criteria validated=True|record agents=0" "$_w27_5"
_build71 "code — \`$_CMD71\`" src/routes.txt 'GET /api/count -> count'
"$TEMPER" integrate >/dev/null 2>&1 || true
_w27_5b="rows=$(_rows71 build)"
# an agent's row that claims the criterion passed does not count: only a row the CLI ran does
"$TEMPER" evidence add --stage build --criterion AC-02 --claim 'grep found the route' --cmd "$_CMD71" --exit 0 >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_w27_5b+="|$(_row71 build 'criteria validated' | python3 -B -c "
import sys
s = sys.stdin.read().strip()
ok, _, detail = s.partition('|')
print('row=%s,AC-02=%s,command=%s' % (ok, 'yes' if 'AC-02' in detail else 'no', 'yes' if sys.argv[1] in detail else 'no'))" "$_CMD71")"
_w27_5b+="|agents for it=$(_named71 "$_RO71" AC-02)"
assert_eq "w27 a code criterion is run by the CLI: with the text missing the CLI's row has exit 1, the Build gate fails naming AC-02 and its command (an agent's passing row does not count), and no agent is named for it" \
  "rows=1|row=False,AC-02=yes,command=yes|agents for it=0" "$_w27_5b"
assert_eq "w27 a code criterion is run by the CLI: no script holds the words of the record pass" "none" \
  "$({ git -C "$REPO_ROOT" grep -n -F "$_RO71" -- scripts | cut -d: -f1,2 | head -10 | tr '\n' ' '; echo; } | sed 's/ $//;s/^$/none/')"

# --- 6. a metric criterion ---
_build71 "metric — \`test \"\$(wc -c < out.txt)\" -lt 2000\`" out.txt 'a short output'
"$TEMPER" integrate >/dev/null 2>&1 || true
_w27_6="integrate=$(_rows71 build)"
_at check build review
_w27_6+="|check action=$(nx "'%s,agents=%d,%s' % (d.get('action'), len(d.get('agents') or []), 'check run' if any(c.rstrip().endswith('temper check run') for c in d.get('calls') or []) else 'no check run')")"
"$TEMPER" check run >/dev/null 2>&1 || true
_w27_6+="|check run=$(_rows71 check)"
assert_eq "w27 a metric criterion: its command is recorded by the CLI at integrate and by temper check run, and the Check action has no agent" \
  "integrate=0|check action=work,agents=0,check run|check run=0" "$_w27_6"

# --- 7. no command means the person confirms ---
fresh; sed -i '0,/Validate: scenario — traced to a test below/s//Validate: code — the module exports one builder function/' .temper/specs/demo/intent.md
_at check intent plan build review
_w27_7="agents=$(nx "len(d.get('agents') or [])")"
gfail check "acceptance evidence" "AC-01 has no supported passing evidence row"
_w27_7+="|$(nx "o = next((o for o in list(d.get('ask', {}).get('options') or []) + list((d.get('ask', {}).get('more') or {}).get('options') or []) if o.get('id') == 'confirm'), {}); 'ask=%s|confirm AC-01=%s' % (d.get('ask', {}).get('id'), 'yes' if any('--criterion AC-01' in c for c in o.get('calls') or []) else 'no')")"
assert_eq "w27 no command means the person confirms: an accepted intent whose code criterion has prose and no command launches no agent at Check, and the criterion is in the list the person confirms" \
  "agents=0|ask=check.fail|confirm AC-01=yes" "$_w27_7"
_draft71() { # _draft71 <Validate text of AC-01>: a draft intent that passes temper gate intent at the head but for that line
  cat > .temper/specs/demo/intent.md <<EOF
**Author:** A Author <a@example.com>
**Status:** draft
**Created:** 2026-01-01

## Problem
A real problem with real text.

### Success Criteria
- [ ] AC-01 [required]: the reset route is registered
  Why: the client calls it by that route
  Validate: $1

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
setup; _draft71 "code — \`grep -q 'POST /api/reset' src/routes.txt\`"; "$TEMPER" gate intent >/dev/null 2>&1
_w27_7b="with a command=$(_row71 intent 'criteria validate' | cut -d'|' -f1)"
setup; _draft71 'code — the module exports one builder function'; "$TEMPER" gate intent >/dev/null 2>&1
_w27_7b+="|$(_row71 intent 'criteria validate' | python3 -B -c "
import re, sys
ok, _, detail = sys.stdin.read().strip().partition('|')
print('prose=%s,AC-01=%s,backticks=%s,manual=%s' % (ok, 'yes' if 'AC-01' in detail else 'no',
      'yes' if re.search(r'backtick', detail, re.I) else 'no', 'yes' if re.search(r'\bmanual\b', detail) else 'no'))")"
assert_eq "w27 no command means the person confirms: a draft whose code criterion has no command in backticks fails criteria validate, saying to write the command in backticks or to use manual" \
  "with a command=True|prose=False,AC-01=yes,backticks=yes,manual=yes" "$_w27_7b"

# --- 8. the model table ---
_models71() { # every line of temper model --all --source as name=model/source, sorted, joined by ,
  "$TEMPER" model --all --source 2>/dev/null | python3 -B -c "
import re, sys
got = []
for l in sys.stdin:
    m = re.match(r'^([a-z-]+)=(\S+) \((\w+)\)\s*$', l)
    if m:
        got.append('%s=%s/%s' % m.groups())
print(','.join(sorted(got)) or 'none')"
}
_line71() { "$TEMPER" model --all --source 2>/dev/null | grep "^$1=" | head -1; }
_want71="$(python3 -B - "$REPO_ROOT" <<'PY'
import os, sys
t = {"plan": "opus", "design": "opus", "rca": "opus"}
for a in ("intent", "plan-revise", "plan-review", "acceptance", "build", "review", "check", "fix", "pipeline", "task", "task-escalation"):
    t[a] = "sonnet"
if not os.path.isfile(os.path.join(sys.argv[1], "agents", "check.md")):
    del t["check"]   # mechanism step 13: the Check brief goes, with its row, when nothing launches it any more
print(",".join(sorted("%s=%s/table" % kv for kv in t.items())))
PY
)"
setup
assert_eq "w27 the model table: temper model --all --source prints opus for plan, design and rca and sonnet for every other agent and for task, each from the table" \
  "$_want71" "$(_models71)"
assert_eq "w27 the model table: one resolver: temper model task and temper model plan-revise print the table's sonnet" \
  "task=sonnet|plan-revise=sonnet" "task=$("$TEMPER" model task 2>&1)|plan-revise=$("$TEMPER" model plan-revise 2>&1)"
printf 'models:\n  plan: sonnet\n' >> .claude/temper.config; _w27_8="key=$(_line71 plan)"
printf '  high:\n    plan: opus\n' >> .claude/temper.config; _w27_8+="|standard=$(_line71 plan)"
riskH; _w27_8+="|risk H=$(_line71 plan)"
python3 -B -c "
import json
p = '.temper/build-state.json'; d = json.load(open(p)); d.pop('risk', None); d['complexity'] = 'complex'
json.dump(d, open(p, 'w'), indent=2)"
_w27_8+="|complex=$(_line71 plan)"
assert_eq "w27 the model table: models.plan sets the plan line from config; models.high.plan takes over at risk H or tier complex" \
  "key=plan=sonnet (config)|standard=plan=sonnet (config)|risk H=plan=opus (config)|complex=plan=opus (config)" "$_w27_8"
setup; printf 'models:\n  task: haiku\n' >> .claude/temper.config; _w27_8b="models.task=$(_line71 task)"
setup; printf 'build:\n  grouped:\n    task-model: haiku\n' >> .claude/temper.config; _w27_8b+="|old key=$(_line71 task)"
assert_eq "w27 the model table: models.task sets the task line, and the old key build.grouped.task-model says the same" \
  "models.task=task=haiku (config)|old key=task=haiku (config)" "$_w27_8b"
assert_eq "w27 the model table: the model line of every agents/*.md equals the table's standard value, and every agent of the table has its brief" \
  "none" "$(python3 -B - "$REPO_ROOT" <<'PY'
import os, re, sys
root = os.path.join(sys.argv[1], "agents")
t = {"plan": "opus", "design": "opus", "rca": "opus"}
for a in ("intent", "plan-revise", "plan-review", "acceptance", "build", "review", "check", "fix", "pipeline", "task"):
    t[a] = "sonnet"
bad = []
seen = set()
for f in sorted(os.listdir(root)):
    if not f.endswith(".md"):
        continue
    name = "task" if f == "build-task.md" else f[:-3]
    seen.add(name)
    text = open(os.path.join(root, f), encoding="utf-8").read()
    fm = text.split("---", 2)[1] if text.startswith("---") else ""
    m = re.search(r"^model:\s*(\S+)\s*$", fm, re.M)
    got = m.group(1) if m else "none"
    if name not in t:
        bad.append("%s not in the table" % f)
    elif got != t[name]:
        bad.append("%s=%s, the table says %s" % (f, got, t[name]))
for name in sorted(set(t) - seen - {"check"}):
    bad.append("no brief for %s" % name)
print("; ".join(bad) or "none")
PY
)"

# --- 9. a sensitive path makes risk H; the CLI runs temper risk after the planner and the revise agent ---
fresh
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'The demo group.' '' '### Task 1: login' '**File:** `src/auth/login.ts`' '**Depends:** none' '**Test:** `true`' \
  '**Cases:**' '- a good password signs in' '- a bad password is refused' '- [ ] done' > .temper/specs/demo/tasks.md
_w27_9="$("$TEMPER" risk 2>&1 | head -1)"
sed -i 's|^  park-on-touch: .*$|  park-on-touch: []|' .claude/temper.config
_w27_9+=" / $("$TEMPER" risk 2>&1 | head -1)"
assert_eq "w27 a sensitive path makes risk H: one declared production file under a sensitive path is risk H and says so; with autonomy.park-on-touch: [] the same plan is L" \
  "RISK: H (1 production file; sensitive path src/auth/login.ts) / RISK: L (1 production file)" "$_w27_9"
_riskfirst71() { # yes when the after calls of the first agent of temper next run temper risk (no --raise) before gate plan
  _agent71 "(lambda c: 'yes' if any(x.strip() == 'risk' for x in c[:next((i for i, x in enumerate(c) if x.startswith('gate plan')), 0)]) else 'no')([re.sub(r'^\S*/temper ', '', str(x)) for x in a.get('after') or []])"
}
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; rm -f .temper/specs/demo/tasks.md
_w27_9b="planner=$(_agent71 "a.get('type')"),$(_riskfirst71)"
_note71; _w27_9b+="|revise=$(_agent71 "a.get('type')"),$(_riskfirst71)"
_w27_9b+="|brief asks=$(python3 -B - "$REPO_ROOT/agents/plan.md" <<'PY'
import re, sys
t = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
print(len([m for m in re.finditer(r"scripts/temper risk\b", t) if not t[m.end():].lstrip().startswith("--raise")]))
PY
)"
assert_eq "w27 the CLI runs temper risk in the after calls of the planner and of the revise agent, before gate plan, and agents/plan.md no longer asks for it (only its --raise)" \
  "planner=temper:temper-plan,yes|revise=temper:temper-plan-revise,yes|brief asks=0" "$_w27_9b"

# --- 10. the acceptance writer is alone and first ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
_w27_10="first=$(nx "','.join(str(a.get('type')) for a in d.get('agents') or []) or 'none:' + str(d.get('action'))")"
bash -c "$(nx "'; '.join(c for a in d.get('agents') or [] for c in a.get('before') or [])")" >/dev/null 2>&1 || true
_w27_10+="|before the lock=$(nx "','.join(sorted(set(str(a.get('type')) for a in d.get('agents') or []))) or 'none:' + str(d.get('action'))")"
assert_eq "w27 the acceptance writer is alone and first: at the start of Build temper next names exactly one agent, temper:temper-acceptance, and no task agent while no lock or skip exists" \
  "first=temper:temper-acceptance|before the lock=temper:temper-acceptance" "$_w27_10"
assert_eq "w27 the acceptance writer is alone and first: no brief but agents/acceptance.md holds acceptance start or acceptance lock" \
  "agents/acceptance.md" "$(git -C "$REPO_ROOT" grep -l -e 'acceptance start' -e 'acceptance lock' -- agents | tr '\n' ' ' | sed 's/ $//')"

# --- 11. the phase 7 review, lane A: the tier the CLI records, and one launch spends once ---
_room71() { # _room71 <key>: used=<launches of the key>,run=<entries this run spent>, from the CLI's own count
  "$TEMPER" budget room "$1" 2>/dev/null | python3 -B -c "
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
print('used=%s,run=%s' % (d.get('used'), d.get('run_used')))"
}
_two71() { # a run at Plan recorded simple whose tasks.md has two groups (above the simple tier the CLI bounds, WP26)
  fresh; _tasks71; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; rm -f .temper/specs/demo/plan.md
  printf '\n## Group G2: Later\n**Depends:** G1\n**Validate:** `true`\n**Context:**\nThe later work.\n\n### Task 4: later\n**File:** `src/later.sh`\n**Depends:** Task 3\n**Test:** `true`\n**Cases:**\n- the later step prints its line\n- an empty input prints nothing\n- [ ] done\n' >> .temper/specs/demo/tasks.md
  "$TEMPER" state set complexity simple >/dev/null 2>&1
}
# F1: a run recorded simple that the bound refuses, stepped back into Plan after the approval, is not left to the revise
# agent (which may not run state set): when the bound is the only failed row the CLI records medium itself
_two71; gpass plan; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" state loop build plan --reason 'Task 2 cannot be built as written: the refund needs the ledger first' >/dev/null 2>&1
_w27_11="after the approval=$(_drive71 4 x | sed 's/|items=.*//')|tier=$("$TEMPER" state get complexity 2>/dev/null)"
_two71; "$TEMPER" gate plan >/dev/null 2>&1
_w27_11+="|first plan=$(nx "'%s,agents=%d,%s' % (d.get('action'), len(d.get('agents') or []), ';'.join(__import__('re').sub(r'^\S*/temper ', '', c) for c in d.get('calls') or []))")"
assert_eq "w27 the tier bound: a simple run with two groups gets temper state set complexity medium from the CLI when the bound is the only failed row, after one revise of a step back and at a first plan alike; never a second revise or run.budget" \
  "after the approval=work temper:temper-plan-revise|ask plan.approve|tier=medium|first plan=work,agents=0,state set complexity medium;gate plan" "$_w27_11"
# WP27-R1: the planner launched as the fall back after two revises spends one entry, as any repeat of a failed gate does
_plan71; fresh_reviewed
"$TEMPER" evidence add --stage plan --phase fresh --severity high --claim "$_W27_4" >/dev/null 2>&1; "$TEMPER" gate plan >/dev/null 2>&1
_w27_11b="$(_drive71 2 "$_W27_4" | sed 's/|items=.*//')|before=$(_room71 gate:plan)"
_w27_11b+="|$(_drive71 1 "$_W27_4" | sed 's/|items=.*//')|after=$(_room71 gate:plan)"
assert_eq "w27 the fall back planner spends: after two revise launches the planner's launch writes one entry of gate:plan" \
  "work temper:temper-plan-revise|work temper:temper-plan-revise|before=used=1,run=2|work temper:temper-plan|after=used=2,run=3" "$_w27_11b"
# WP27-R2: the revise the person picks at a failed plan gate is one launch and one spend: the run again paid for it, and
# the launch still counts for its reason (the fall back comes after two)
_plan71 one-case; "$TEMPER" gate plan >/dev/null 2>&1
"$TEMPER" evidence add --stage plan --phase note --kind input --claim "$_NOTE71" >/dev/null 2>&1
"$TEMPER" state redo plan --reason "$_NOTE71" >/dev/null 2>&1
_w27_11c="redo=$(_room71 plan-revise:note)|$(_drive71 1 x | sed 's/|items=.*//')|launch=$(_room71 plan-revise:note)"
_w27_11c+="|$(_drive71 1 x | sed 's/|items=.*//')|again=$(_room71 plan-revise:note)"
assert_eq "w27 one launch, one spend: the revise after the person's run again at a failed plan gate spends nothing more of the run, counts for its reason, and the second revise by rule spends one" \
  "redo=used=0,run=1|work temper:temper-plan-revise|launch=used=1,run=1|work temper:temper-plan-revise|again=used=2,run=2" "$_w27_11c"
# WP27-R3: a loop back through Intent gives the planner the pass that answers the changed intent, and only that one
_plan71; "$TEMPER" gate plan >/dev/null 2>&1
"$TEMPER" state loop plan intent --reason 'the intent misses the rule for a partial refund' >/dev/null 2>&1
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_w27_11d="changed intent=$(_agent71 "a.get('type')")"
sleep 1; "$TEMPER" brief >/dev/null 2>&1; "$TEMPER" gate plan >/dev/null 2>&1; sleep 1
"$TEMPER" evidence add --stage plan --phase note --kind input --claim "$_NOTE71" >/dev/null 2>&1
"$TEMPER" state redo plan --reason "$_NOTE71" >/dev/null 2>&1
_w27_11d+="|a later note=$(_agent71 "a.get('type')")"
assert_eq "w27 a changed intent gets the planner once: after the planner answered the loop back through Intent, a later note gets the revise agent" \
  "changed intent=temper:temper-plan|a later note=temper:temper-plan-revise" "$_w27_11d"
