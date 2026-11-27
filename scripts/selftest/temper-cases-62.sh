# Case file 62 (WP21): a command the plan wrote runs once on the base, and the old per command check goes. The plan gate
# runs no project command. A group's Validate and the Integration line run once on the current code, started by the CLI
# after the planner returned (`temper baseline plan`, an after call of the Plan agent placed before `gate plan`), in the
# baseline worktree of WP20, each under Build's own limit, judged by its exit code alone: exit 0 is `pass`, exit 124
# `timeout`, exit 125 and a program that does not resolve are class `environment`, any other exit is `fail` (class
# `command`) or, on a red base, `fails like the base`. Each result is kept in `plan` of .temper/evidence/baseline.json
# under the command's text. A `fail` or a `timeout` is the question `plan.command`; no environment agent is left.
# At a task gate only the three sure signs give ENV. Sourced by test-temper.sh; its helpers (fresh, gpass, nx, m_setup,
# m_field) are used here, and the builders below are this file's own. Token: w21. Every call of `baseline` runs in the
# foreground (TEMPER_BASELINE_FOREGROUND=1). A call the CLI does not have yet stays inside $( ... ) or ends in || true,
# so the file always runs to its end. The names of the removed agent type and flag are built from two parts, so that
# the grep of the package's "Done when" finds none of them here.

# --- the helpers of this file ---
_x62() { # _x62 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More question, opt(d, i) the one with that id, short(c) a call without the
         # path of the CLI, calls(d) every call of its options, text(d) the question's text
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
def calls(d):
    return [short(c) for o in opts(d) for c in o.get("calls") or []]
def text(d):
    return str(((d.get("ask") or {}).get("question") or {}).get("question", ""))
r = None
exec(sys.argv[1])
print(r)
PY
}
_b62() { # _b62 <python expression>: over d, the JSON of .temper/evidence/baseline.json ({} when absent), with res(c) the
         # result of the plan's command c in its `plan` ({} when none) and num(v) true for a number
  python3 -B - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(".temper/evidence/baseline.json"))
except (OSError, ValueError):
    d = {}
d = d if isinstance(d, dict) else {}
num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
def res(c):
    p = d.get("plan") if isinstance(d.get("plan"), dict) else {}
    v = p.get(c)
    return v if isinstance(v, dict) else {}
print(eval(sys.argv[1]))
PY
}
_repo62() { # the case folder as a git repository on main with one commit of every file but the run's own
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A >/dev/null 2>&1; git commit -q -m base
}
_progs62() { # the programs of this file in $P62 (inside .git, so no file of the tree): each appends its first word
             # to $P62/log when it starts. ok exits 0; no fails with one fail line; conn prints a connection error
             # and exits with its second word; rc exits with its second word; mark fails until $P62/repaired exists
  P62="$WORKDIR/.git/p62"; mkdir -p "$P62"; : > "$P62/log"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\nexit 0\n' "$P62" > "$P62/ok"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\necho "FAIL: test_x expected 2, got 3"\nexit 1\n' "$P62" > "$P62/no"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\necho "java.net.ConnectException: Connection refused"\nexit "${2:-0}"\n' "$P62" > "$P62/conn"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\nexit "$2"\n' "$P62" > "$P62/rc"
  printf '#!/bin/sh\necho "$1" >> "%s/log"\ntest -e "%s/repaired" || { echo "FAIL: test_m the service was not ready"; exit 1; }\n' \
    "$P62" "$P62" > "$P62/mark"
  chmod +x "$P62"/ok "$P62"/no "$P62"/conn "$P62"/rc "$P62"/mark
}
_n62() { # _n62 <word>: how many runs the log holds of that first word
  if [[ -f "$P62/log" ]]; then grep -cx -- "$1" "$P62/log" | tr -d ' '; else echo 0; fi
}
_known62() { # the baseline on record as not run (what the selftest helper _base_known of WP20 writes)
  mkdir -p .temper/evidence
  printf '{"result": "unknown", "why": "not run in the selftest"}\n' > .temper/evidence/baseline.json
}
_tasks62() { # _tasks62 <Integration> <Task 1 Test> <Validate>...: the demo plan with one group a Validate, each with one task;
             # Task i writes src/t62_<i>.sh, a file that is not on the base
  python3 -B - "$@" > .temper/specs/demo/tasks.md <<'PY'
import sys
integ, test1, vals = sys.argv[1], sys.argv[2], sys.argv[3:]
out = ["# Tasks: demo", "", "**Integration:** `%s`" % integ]
for i, v in enumerate(vals, 1):
    out += ["", "## Group G%d: Part %d" % (i, i), "**Depends:** %s" % ("none" if i == 1 else "G%d" % (i - 1)),
            "**Validate:** `%s`" % v, "**Context:**", "Part %d of the demo." % i, "",
            "### Task %d: part %d" % (i, i), "**File:** `src/t62_%d.sh`" % i,
            "**Depends:** %s" % ("none" if i == 1 else "Task %d" % (i - 1)),
            "**Test:** `%s`" % (test1 if i == 1 else "true"), "**Cases:**", "- part %d holds" % i,
            "- a bad input to part %d is refused" % i, "- [ ] done"]
print("\n".join(out))
PY
}
_scen62() { # _scen62 <first Test> <second Test>: the Test lines of the demo intent's two scenarios
  python3 -B - "$1" "$2" <<'PY'
import sys
p = ".temper/specs/demo/intent.md"
t = open(p).read()
t = t.replace("  Test: true", "  Test: %s" % sys.argv[1], 1).replace("  Test: true", "  Test: %s" % sys.argv[2], 1)
open(p, "w").write(t)
PY
}
_at62() { # _at62: the run at Plan with the plan gate passed, as the planner leaves it after its last call
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
}
_bp62() { TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline plan "$@" >/dev/null 2>&1; }
_start62() { TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start "$@" >/dev/null 2>&1; }
_cmd62() { printf 'check:\n  commands:\n    test: "%s"\n' "$1" >> .claude/temper.config; }
_runopt62() { # _runopt62 <option id>: runs the calls of that option of the question next asks, as the person's answer
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{reason\}/the check needs the staging data}"; c="${c//\{answer\}/true}"
    TEMPER_BASELINE_FOREGROUND=1 bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x62 "o = opt(d, '$1') or {}
r = '\n'.join(o.get('calls') or [])")
}
_old62="pre"; _old62+="flight"   # the name of the plan gate's old row, built from two parts

# --- w21 the plan gate runs nothing: every command of the plan counts its runs; gate plan leaves the log empty ---
fresh; _repo62; _progs62; _known62
_tasks62 "$P62/ok I" "$P62/ok T" "$P62/ok V" "$P62/ok W"; _scen62 "$P62/ok S" "$P62/ok S"
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; rm -f .temper/gates.json; gpass intent
_after62="$(_x62 "a = next((x for x in d.get('agents') or [] if x.get('type') == 'temper:temper-plan'), {})
r = '|'.join(short(c).split(' --')[0] for c in a.get('after') or [])")"
: > "$P62/log"
_gate62="$("$TEMPER" gate plan 2>&1)"
assert_eq "w21 the plan gate runs nothing: temper gate plan runs no command of the plan and has no row of the old check" \
  "ran=0|rows=none|printed=none" \
  "ran=$(grep -c . "$P62/log" | tr -d ' ')|rows=$(OLD="$_old62" python3 -B -c "
import json, os
try:
    g = json.load(open('.temper/gates.json')).get('plan') or {}
except (OSError, ValueError):
    g = {}
print(','.join(str(x.get('name')) for x in g.get('requirements') or [] if os.environ['OLD'] in str(x.get('name')).lower()) or 'none')
")|printed=$(grep -ci -- "$_old62" <<<"$_gate62" | sed 's/^0$/none/')"
assert_eq "w21 the plan gate runs nothing: the planner's after calls run baseline plan, then gate plan, which stays last" \
  "baseline plan before gate plan|gate plan last" \
  "$(python3 -B -c "
import sys
c = sys.argv[1].split('|')
b = c.index('baseline plan') if 'baseline plan' in c else -1
g = c.index('gate plan') if 'gate plan' in c else -1
print('%s|%s' % ('baseline plan before gate plan' if 0 <= b < g else 'after calls: %s' % sys.argv[1],
                 'gate plan last' if c and c[-1] == 'gate plan' else 'last: %s' % (c[-1] if c else 'none')))" "$_after62")"

# --- w21 which commands run: a group Validate and an Integration line once each; no task Test, no scenario Test, no
#     command equal to the owner's test text, no Validate that names a file a task creates ---
fresh; _repo62; _progs62; _cmd62 "$P62/ok O"; git add -A >/dev/null 2>&1; git commit -q -m config
_tasks62 "$P62/ok I" "$P62/ok T" "$P62/ok V" "$P62/ok O" "$P62/ok N src/t62_3.sh"; _scen62 "$P62/ok S" "$P62/ok S"
rm -f .temper/evidence/baseline.json; _start62
_owner62="$(_n62 O)"; : > "$P62/log"
_bp62
assert_eq "w21 which commands run: after baseline plan a group Validate and the Integration line ran once each; no task Test, scenario Test, command equal to the owner's test text or Validate that names a file a task creates" \
  "owner on the base=1|V=1|I=1|T=0|S=0|O=0|N=0" \
  "owner on the base=$_owner62|V=$(_n62 V)|I=$(_n62 I)|T=$(_n62 T)|S=$(_n62 S)|O=$(_n62 O)|N=$(_n62 N)"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# with no command of the plan to run on the base (each is left out), the programs of every command are still checked
fresh; _repo62; _progs62; _known62
_tasks62 "sh src/t62_1.sh" "nosuchprog21 --run" "sh src/t62_1.sh"; _scen62 "$P62/ok S" "$P62/ok S"
_at62; _bp62
assert_eq "w21 which commands run: with every command left out, a task Test whose program is missing is still an environment fault shown in base.red" \
  "ran=0|red|program-missing:nosuchprog21|asked=base.red" \
  "ran=$(grep -c . "$P62/log" | tr -d ' ')|$(_b62 "'%s|%s' % (d.get('result'), ','.join('%s:%s' % (x.get('kind'), x.get('need')) for x in d.get('env') or []) or 'no fault')")|asked=$(_x62 "r = (d.get('ask') or {}).get('id')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# --- w21 where and how long: the baseline worktree; Build's limit; a time out is no environment fault ---
fresh; _repo62; _progs62; _known62
_tasks62 "$P62/ok I" "$P62/ok T" "pwd -P > $P62/where" "sleep 3"; _scen62 "$P62/ok S" "$P62/ok S"
_at62; TEMPER_TASK_TEST_TIMEOUT_S=1 _bp62
assert_eq "w21 where and how long: the command runs in the baseline worktree, and a Validate past TEMPER_TASK_TEST_TIMEOUT_S=1 is a time out, never the class environment" \
  "where=the baseline worktree|result=timeout|class not environment" \
  "where=$([[ "$(cat "$P62/where" 2>/dev/null)" == "$WORKDIR/.claude/worktrees/temper-baseline" ]] && echo 'the baseline worktree' || echo "'$(cat "$P62/where" 2>/dev/null)'")|$(
  _b62 "'result=%s|%s' % (res('sleep 3').get('result'), 'class not environment' if res('sleep 3') and res('sleep 3').get('class') != 'environment' else 'class %s' % res('sleep 3').get('class'))")"
assert_eq "w21 where and how long: the question plan.command offers more time first, another command and a skip with a reason, and no setup block and no agent" \
  "plan.command|first=more-time|change=yes|skip=yes|setup=no|agents=0" \
  "$(_x62 "a = d.get('ask') or {}
r = '%s|first=%s|change=%s|skip=%s|setup=%s|agents=%d' % (a.get('id'), (opts(d) or [{}])[0].get('id'),
    'yes' if any(c.startswith('plan patch') for c in calls(d)) or any(o.get('kind') == 'type' for o in opts(d)) else 'no',
    'yes' if any(c.startswith('baseline skip') and '{reason}' in c for c in calls(d)) else 'no',
    'yes' if opt(d, 'add-setup') or any(c.startswith('doctor') and '--write' in c for c in calls(d)) else 'no',
    len(d.get('agents') or []))")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# a passed command's seconds feed its limit: three times them, as for the suite
fresh; mkdir -p .temper/evidence
printf '{"result": "green", "cmd": "make test", "seconds": 1, "plan": {"make lint": {"result": "pass", "seconds": 500}, "make slow": {"result": "fail", "seconds": 500}}}\n' > .temper/evidence/baseline.json
_lim62() { python3 -B "$REPO_ROOT/scripts/baseline.py" "$PWD" "" "" limit "$1" 600 2>&1; }
assert_eq "w21 where and how long: the seconds a plan command took when it passed on the base set its limit at the group gate, three times them" \
  "pass=1500|fail=600|other=600" "pass=$(_lim62 'make lint')|fail=$(_lim62 'make slow')|other=$(_lim62 'make other')"
# two calls of baseline plan at once share the one worktree: the later one waits, and a command that passes on the base
# is never recorded as failed because the other call made the worktree again or removed it
fresh; _repo62; _progs62; _known62
_tasks62 "$P62/ok I" "$P62/ok T" "sleep 1; exit 1" "sleep 4; test -f src/demo.sh"; _scen62 "$P62/ok S" "$P62/ok S"
_at62
env -u TEMPER_BASELINE_FOREGROUND "$TEMPER" baseline plan >/dev/null 2>&1
for _i62 in 1 2 3 4 5 6 7 8 9 10; do [[ "$(_b62 "res('sleep 1; exit 1').get('result')")" == fail ]] && break; sleep 0.5; done
env -u TEMPER_BASELINE_FOREGROUND "$TEMPER" baseline plan --cmd 'sleep 1; exit 1' >/dev/null 2>&1
for _i62 in $(seq 1 80); do
  [[ "$(_b62 "any(isinstance(e, dict) and e.get('result') == 'running' for e in (d.get('plan') or {}).values())")" == False ]] && break
  sleep 0.5
done
assert_eq "w21 where and how long: a second baseline plan while the first runs waits for it; the command that passes on the base is pass, the failing one fail, and the worktree is gone after both" \
  "G1=fail|G2=pass|worktree=gone" \
  "G1=$(_b62 "res('sleep 1; exit 1').get('result')")|G2=$(_b62 "res('sleep 4; test -f src/demo.sh').get('result')")|worktree=$([[ -d .claude/worktrees/temper-baseline ]] && echo there || echo gone)"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
# the wait of the later call lasts as long as the older call's commands may run, not only the baseline's own limit
# (TEMPER_BASELINE_TIMEOUT_S, here 1 s against a Validate that runs 4 s under its limit of 600 s)
fresh; _repo62; _progs62; _known62
_tasks62 "$P62/ok I" "$P62/ok T" "sleep 1; exit 1" "sleep 4; test -f src/demo.sh"; _scen62 "$P62/ok S" "$P62/ok S"
_at62
env -u TEMPER_BASELINE_FOREGROUND "$TEMPER" baseline plan >/dev/null 2>&1
for _i62 in 1 2 3 4 5 6 7 8 9 10; do [[ "$(_b62 "res('sleep 1; exit 1').get('result')")" == fail ]] && break; sleep 0.5; done
env -u TEMPER_BASELINE_FOREGROUND TEMPER_BASELINE_TIMEOUT_S=1 "$TEMPER" baseline plan --cmd 'sleep 1; exit 1' >/dev/null 2>&1
for _i62 in $(seq 1 80); do
  [[ "$(_b62 "any(isinstance(e, dict) and e.get('result') == 'running' for e in (d.get('plan') or {}).values())")" == False ]] && break
  sleep 0.5
done
assert_eq "w21 where and how long: the later baseline plan waits as long as the older call's commands may run, past the baseline's own limit, so the command that passes on the base is pass" \
  "G1=fail|G2=pass|worktree=gone" \
  "G1=$(_b62 "res('sleep 1; exit 1').get('result')")|G2=$(_b62 "res('sleep 4; test -f src/demo.sh').get('result')")|worktree=$([[ -d .claude/worktrees/temper-baseline ]] && echo there || echo gone)"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# --- w21 binary rule: the exit code alone decides; a connection error in the output changes nothing ---
fresh; _repo62; _progs62; _cmd62 "$P62/ok O"; git add -A >/dev/null 2>&1; git commit -q -m config
_tasks62 "$P62/ok I" "$P62/ok T" "$P62/ok A" "$P62/no B" "$P62/conn C 0" "$P62/conn D 1" "$P62/rc E 125" "$P62/conn F 125" \
  "nosuchprog62 --all"
rm -f .temper/evidence/baseline.json; _start62; _base62="$(_b62 "d.get('result')")"; _bp62
assert_eq "w21 binary rule: exit 0 is pass with its seconds; exit 1 on a green base is fail, class command; exit 125 and a first word that does not resolve are class environment; a connection error in the output changes none of these" \
  "base=green|A=pass:seconds|B=fail:command|C=pass|D=fail:command|E=environment|F=environment|G=environment" \
  "base=$_base62|$(_b62 "'|'.join([
  'A=%s:%s' % (res('$P62/ok A').get('result'), 'seconds' if num(res('$P62/ok A').get('seconds')) else 'no seconds'),
  'B=%s:%s' % (res('$P62/no B').get('result'), res('$P62/no B').get('class')),
  'C=%s' % res('$P62/conn C 0').get('result'),
  'D=%s:%s' % (res('$P62/conn D 1').get('result'), res('$P62/conn D 1').get('class')),
  'E=%s' % res('$P62/rc E 125').get('class'), 'F=%s' % res('$P62/conn F 125').get('class'),
  'G=%s' % res('nosuchprog62 --all').get('class')])")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true
fresh; _repo62; _progs62; _cmd62 "$P62/no O"; git add -A >/dev/null 2>&1; git commit -q -m config
_tasks62 "$P62/ok I" "$P62/ok T" "$P62/no B"; _scen62 "$P62/ok S" "$P62/ok S"
rm -f .temper/evidence/baseline.json; _start62; _bp62; _at62
_red62="base=$(_b62 "d.get('result')")|B=$(_b62 "res('$P62/no B').get('result')")|asked=$(_x62 "r = (d.get('ask') or {}).get('id')")"
"$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
assert_eq "w21 binary rule: exit 1 on a red base fails like the base and raises no second question: the red base is asked, then the approval" \
  "base=red|B=fails like the base|asked=base.red|then=plan.approve" "$_red62|then=$(_x62 "r = (d.get('ask') or {}).get('id')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# a failed Validate at its gate matches the base only when its fail lines are all there: a list cut at its eight lines
# may hide a new failure, so it is no match
fresh; mkdir -p .temper/evidence
python3 -B - <<'PY'
import json
lines = ["FAILED t62/test_a.py::test_parse_%d - assert 2 == 3" % i for i in range(1, 9)]
json.dump({"result": "red", "kind": "red-base", "answer": "go-on-anyway", "cmd": "make test", "fail_lines": [],
           "plan": {"make it": {"result": "fails like the base", "fail_lines": lines}}}, open(".temper/evidence/baseline.json", "w"))
PY
_like62() { python3 -B "$REPO_ROOT/scripts/baseline.py" "$PWD" "" "" like-base "make it" "$1" >/dev/null 2>&1 && echo match || echo 'no match'; }
assert_eq "w21 binary rule: at the gate, two of the base's fail lines match the base; eight lines, the cap of the list, are no match" \
  "two=match|eight=no match" \
  "two=$(_like62 '["FAILED t62/test_a.py::test_parse_1 - assert 2 == 3", "FAILED t62/test_a.py::test_parse_2 - assert 2 == 3"]')|eight=$(_like62 "$(python3 -c 'import json; print(json.dumps(["FAILED t62/test_a.py::test_parse_%d - assert 2 == 3" % i for i in range(1, 9)]))')")"

# --- w21 a failed result is not final: after the repair, Run it again runs the command again and it passes ---
fresh; _repo62; _progs62; _known62
_tasks62 "$P62/ok I" "$P62/ok T" "$P62/mark M"; _scen62 "$P62/ok S" "$P62/ok S"
_at62; _bp62
_f62="first=$(_b62 "res('$P62/mark M').get('result')")|asked=$(_x62 "r = '%s:%s' % ((d.get('ask') or {}).get('id'), 'check-again' if opt(d, 'check-again') else 'no check-again')")"
gfail plan "maven group verify" "the group's verify is filtered"
assert_eq "w21 a failed result is not final: at a failed plan gate the gate's own question comes first, not plan.command" \
  "plan.fail" "$(_x62 "r = (d.get('ask') or {}).get('id')")"
gpass plan
touch "$P62/repaired"; _runopt62 check-again
assert_eq "w21 a failed result is not final: after the repair, the option check-again runs the command again and the result is pass" \
  "first=fail|asked=plan.command:check-again|runs=2|then=pass|asked=plan.approve" \
  "$_f62|runs=$(_n62 M)|then=$(_b62 "res('$P62/mark M').get('result')")|asked=$(_x62 "r = (d.get('ask') or {}).get('id')")"
"$TEMPER" baseline clean >/dev/null 2>&1 || true

# --- w21 no environment agent: the label, the agent type, its brief and the flag of doctor are gone ---
fresh; _at62
_key62="env"; _key62+="_agent"; _type62="temper:temper-"; _type62+="env"; _flag62="--cand"; _flag62+="idate"
"$TEMPER" state set "$_key62" requested >/dev/null 2>&1 || true
"$TEMPER" doctor "$_flag62" x >/dev/null 2>&1; _doc62=$?
assert_eq "w21 no environment agent: no question holds Let an agent find the setup, next launches no agent of that type, its brief is gone and doctor takes no such flag" \
  "label=0|launched=0|brief=gone|manifest=0|doctor=2" \
  "label=$(_flow_text | grep -c 'Let an agent find the setup')|launched=$(TYPE="$_type62" _x62 "import os
r = sum(1 for a in d.get('agents') or [] if a.get('type') == os.environ['TYPE'])")|brief=$(
  [[ -e "$REPO_ROOT/agents/env.md" ]] && echo there || echo gone)|manifest=$(grep -c '"./agents/env.md"' "$REPO_ROOT/.claude-plugin/plugin.json")|doctor=$_doc62"

# --- w21 task gate, sure signs only: a connection error with no declared service spends the attempt ---
_task62() { # _task62 [service]: a task whose GREEN prints a connection error and exits 1, after a RED that failed on an
            # assertion; with service, the config declares a service on a closed port
  printf '# Tasks: demo\n\n**Integration:** `true`\n\n## Group G1: Core\n**Depends:** none\n**Validate:** `true`\n**Context:**\nThe demo group.\n\n### Task 1: first task\n**File:** `src/a.sh`\n**Depends:** none\n**Test:** `faketest62`\n**Cases:**\n- a holds\n- [ ] done\n' | m_setup
  [[ -z "${1:-}" ]] || printf 'setup:\n  services:\n    db62: 127.0.0.1:1\n' >> .claude/temper.config
  mkdir -p "$WORKDIR/.git/bin62"
  printf '#!/usr/bin/env bash\nif [[ "$(cat "$(dirname "$0")/mode")" == red ]]; then echo "AssertionError: expected 3, got 2"; else echo "java.net.ConnectException: Connection refused"; fi\nexit 1\n' \
    > "$WORKDIR/.git/bin62/faketest62"
  chmod +x "$WORKDIR/.git/bin62/faketest62"
  PATH="$WORKDIR/.git/bin62:$PATH" "$TEMPER" task start 1 >/dev/null 2>&1
  echo red > "$WORKDIR/.git/bin62/mode"; PATH="$WORKDIR/.git/bin62:$PATH" "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  mkdir -p .claude/worktrees/temper-demo-T1/src; echo built > .claude/worktrees/temper-demo-T1/src/a.sh
  echo conn > "$WORKDIR/.git/bin62/mode"; PATH="$WORKDIR/.git/bin62:$PATH" "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  PATH="$WORKDIR/.git/bin62:$PATH" "$TEMPER" task gate 1 --model haiku 2>&1
}
_tries62() { m_field 1 attempts | python3 -B -c "import sys, ast; print(len(ast.literal_eval(sys.stdin.read().strip() or '[]')))"; }
OUT="$(_task62)"
_s62="no service=$(grep -q '^ENV:' <<<"$OUT" && echo ENV || { grep -q '^FAIL:' <<<"$OUT" && echo FAIL || echo other; }):attempts=$(_tries62)"
OUT="$(_task62 service)"
_s62+="|service down=$(grep -q '^ENV:' <<<"$OUT" && echo ENV || echo not ENV):attempts=$(_tries62):$(
  _x62 "r = '%s,%s' % ((d.get('ask') or {}).get('id'), 'it-is-the-code' if opt(d, 'it-is-the-code') else 'no it-is-the-code')")"
assert_eq "w21 task gate, sure signs only: a GREEN that prints Connection refused and exits 1 with no declared service is FAIL and spends the attempt; with a declared service that does not answer it is ENV, and it-is-the-code is offered" \
  "no service=FAIL:attempts=1|service down=ENV:attempts=0:task.env,it-is-the-code" "$_s62"
rm -rf "$WORKDIR/.git/bin62"

# the phase 5 gate: an operator inside quotes splits no step, so a quoted `;` names no program (failing-scenario's base)
_s62="$(cd "$WORKDIR" && python3 -I - "$REPO_ROOT/scripts" <<'PYEOF'
import os, sys, tempfile
sys.path.insert(0, sys.argv[1])
import run_env, doctor
cmd = 'python3 -c "import sys; sys.exit(3)"'
d = tempfile.mkdtemp()
faults, _, _ = doctor.needs(d, {}, [cmd, "pytest -q 2>&1 | tee out.txt", "A=1 sh -c 'x || y' && echo 'a|b'"])
print("%s|%s|%s|%s" % (",".join(sorted(run_env.programs(cmd))),
                       ",".join(sorted(run_env.programs("pytest -q 2>&1 | tee out.txt"))),
                       ",".join(sorted(run_env.programs("A=1 sh -c 'x || y' && echo 'a|b'"))),
                       ",".join(sorted(f["need"] for f in faults if f.get("kind") == "program-missing" and f["need"] != "pytest")) or "none"))
PYEOF
)"
assert_eq "w21 which programs a command starts: an operator inside quotes splits no step, so a quoted ; or | names no program" \
  "python3|pytest,tee|echo,sh|none" "$_s62"
