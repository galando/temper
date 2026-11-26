# Case file 58 (WP17): /temper:fix asks twice, its checks run beside Review, and TRIVIAL is a recorded verdict.
# A clean bug run asks the root cause question, which is the approval (rca.approve: Approve and fix starts the run to
# the commit, bound to rca.md as it was shown), and the commit question (commit.confirm, with no pull request). A passed
# Fix, Review and Check move on as the CLI's own action, and Review starts Check's run (check ahead), as in a feature
# run.
# A trivial request is the verdict `temper intent trivial --why TEXT`, which the flow closes with
# `intent trivial --close`; the record .temper/trivial.json holds a commit with no run to one production file and 10
# lines until HEAD moves or a run starts. Sourced by test-temper.sh; its helpers (setup, gpass) are used here, and the
# builders below are this file's own. A digest is always computed by scripts/approval.py, never held as text. A call
# the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.
#
# The order of the approving calls: since the phase 4a review the first call of every approving option is the run's
# mode bound to what was shown (`state set run_mode <mode> --shown <file>=<digest>`, scripts/approval.py), so a stale
# approval writes nothing and makes no branch. Approve and fix therefore carries the three calls of the spec in this
# order: the bound mode `state set run_mode autonomous --shown rca.md=<H>`, `spec branch --if-protected`, and
# `state advance rca_complete fix --shown rca.md=<H>`.

# --- the helpers of this file ---
_BUG58="the totals drop a cent on export"
_x58() { # _x58 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More questions, opt(d, i) the one with that id, short(c) a call without
         # the path of the CLI, bare(c) a short call without its --shown arguments, sec(d, i) the card's section i
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    out, q = [], d.get("ask") or {}
    while isinstance(q, dict) and q:
        out += list(q.get("options") or [])
        q = q.get("more")
    return out
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
def bare(c):
    return re.sub(r" --shown \S+", "", short(c))
def sec(d, i):
    return next((s for s in ((d.get("card") or {}).get("sections") or []) if s.get("id") == i), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
_repo58() { # a git repository under the run on main: two source files, a test file and the suite in one commit, the
            # run's files left out
  rm -rf .git src unit suite.sh; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src/auth unit
  printf 'def total_of(lines):\n    return sum(round(x, 2) for x in lines)\n' > src/auth/totals.py
  printf 'echo a1\necho a2\necho a3\n' > src/a.sh; printf 'echo b1\necho b2\necho b3\n' > src/b.sh
  printf 'import unittest\n' > unit/test_a.py; printf 'echo ok\n' > suite.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_rca58() { # rca.md as the root cause agent writes it (agents/rca.md): AT under a sensitive path, a LOW confidence
  mkdir -p .temper/specs/bug
  cat > .temper/specs/bug/rca.md <<'RCA'
# RCA: The totals drop a cent

CAUSE: total_of rounds each line before the sum, so each line loses its half cent
AT: src/auth/totals.py:2
CONFIDENCE: LOW
SINCE: unknown
CHAIN: export -> total_of -> round
FIX: sum the exact amounts and round once at the end
TEST: three lines of 0.005 total 0.02

## Root cause

`total_of` rounds each line before the sum.

## Blast radius

- src/a.sh

## Read first

- src/auth/totals.py
RCA
}
_fix58() { # _fix58 [config lines]: a fix run at its root cause question in a repository on main: autonomy.enabled taken
           # out of the fixture's config (run.default to-commit), a test command the CLI finds, the run started as
           # commands/fix.md starts it (the bug as typed), and rca.md as the root cause agent writes it
  setup; sed -i '/^  enabled: false$/d' .claude/temper.config
  sed -i 's/^  coverage-threshold: 80$/  coverage-threshold: 80\n  commands:\n    test: bash suite.sh/' .claude/temper.config
  [[ -z "${1:-}" ]] || printf '%s\n' "$1" >> .claude/temper.config
  rm -f .temper/groups.json .temper/view.json .temper/build-state.json
  _repo58
  "$TEMPER" state init bug --command fix --feature "$_BUG58" >/dev/null 2>&1; _base_known
  _rca58
}
# _dg58 <file>: its digest, or nothing
_dg58() { python3 -B "$REPO_ROOT/scripts/approval.py" digest "$1" 2>/dev/null; }
# _calls58 <option id>: the calls of that option of the question next asks, one a line
_calls58() { _x58 "o = opt(d, '$1'); r = '\n'.join((o or {}).get('calls') or [])"; }
_bare58() { sed -E 's#^[^ ]*/temper ##; s# --shown [^ ]+##g' <<<"$1"; }   # a call without the CLI's path and --shown
_run58() { # _run58 <option id>: runs the calls of that option of the question next asks, as the session would, the
           # typed parts filled, stopping at the first that fails; prints ran, none, or the first call that failed
  local c out="none"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{reason\}/a reason}"
    bash -c "$c" >/dev/null 2>&1 || { echo "stopped at: $(_bare58 "$c")"; return; }
    out="ran"
  done < <(_calls58 "$1")
  echo "$out"
}
_auto58() { # runs the calls of next when next is an auto action; prints them, bare, or "not auto: <action> <id>"
  local c out="" a
  a="$(_x58 "r = '%s %s' % (d.get('action'), (d.get('ask') or {}).get('id', ''))")"
  [[ "$a" == "auto "* ]] || { echo "not auto: $a"; return; }
  while IFS= read -r c; do
    [[ -n "$c" ]] && { bash -c "$c" >/dev/null 2>&1; out+="${out:+;}$(_bare58 "$c")"; }
  done < <(_x58 "r = '\n'.join(d.get('calls') or [])")
  echo "$out"
}
_moves58() { # _moves58 <stage> <next stage>: auto when next is the CLI's own advance of the stage; after its calls ran,
             # where the run is
  local how
  how="$(_x58 "c = [bare(x) for x in d.get('calls') or []]
r = '%s,%s' % (d.get('action') if d.get('action') != 'ask' else 'ask ' + str((d.get('ask') or {}).get('id')),
    'advance' if any(x.startswith('state advance $1_complete $2') for x in c) else 'calls: ' + '; '.join(c)[:120])")"
  [[ "$how" == auto,* ]] && _auto58 >/dev/null
  echo "$how,at=$("$TEMPER" state get next_stage 2>/dev/null)"
}
_approved58() { _fix58 "${1:-}"; _run58 approve-run >/dev/null; }   # a fix run the person approved with Approve and fix
_atcommit58() { # an approved fix run whose Fix, Review and Check passed, at its commit question (the park call ran)
  _approved58; gpass build; _auto58 >/dev/null; gpass review; _auto58 >/dev/null; gpass check; _auto58 >/dev/null
  gpass commit; _auto58 >/dev/null
}

# --- question one: the root cause question is the approval ---
_fix58
_h58="$(_dg58 .temper/specs/bug/rca.md)"
assert_eq "fix: the root cause question is the approval" \
  "rca.approve|RCA: the root cause and the proposed fix are on the card. Approve the fix?|first=approve-run|arm|at most 4|ask-every-stage,save|calls=state set run_mode autonomous;spec branch --if-protected;state advance rca_complete fix|shown=first,last" \
  "$(_x58 "a = d.get('ask') or {}; top = a.get('options') or [{}]; o = opt(d, 'approve-run') or {}; c = o.get('calls') or []
ids = [x.get('id') for x in opts(d)]
w = ' --shown rca.md=$_h58'
r = '%s|%s|first=%s|%s|%s|%s|calls=%s|shown=%s' % (a.get('id'), (a.get('question') or {}).get('question'),
    top[0].get('id'), o.get('move'), 'at most 4' if len(top) <= 4 else 'more than 4',
    ','.join(i for i in ('ask-every-stage', 'save') if i in ids), ';'.join(bare(x) for x in c),
    'first,last' if '$_h58' and c and c[0].endswith(w) and c[-1].endswith(w) else 'missing')")"
assert_eq "fix: the root cause question is the approval: its card is of kind approval with the sections of step 2" \
  "approval|request,cause,fix,test,files,commands,risk|request=bug as typed|commands=bash suite.sh|foot=fix/bug,Nothing is pushed." \
  "$(_x58 "k = d.get('card') or {}; rows = lambda i: [str(x.get('text')) for x in (sec(d, i) or {}).get('rows') or []]
foot = [str(x) for x in k.get('foot') or []]
r = '%s|%s|request=%s|commands=%s|foot=%s,%s' % (k.get('kind'), ','.join(str(s.get('id')) for s in k.get('sections') or []),
    'bug as typed' if any('$_BUG58' in x for x in rows('request')) else rows('request'),
    'bash suite.sh' if 'bash suite.sh' in rows('commands') else rows('commands'),
    'fix/bug' if any('fix/bug' in x for x in foot) else 'no branch', foot[-1] if foot else '')")"
# run.default orders the first options as WP11 does at the plan question
_ord58() { _x58 "r = ','.join(str(o.get('id')) for o in (d.get('ask') or {}).get('options') or []
    if o.get('id') in ('approve-run', 'ask-every-stage'))"; }
_fix58 "run:
  default: ask"
_o58="ask=$(_ord58)"
_fix58 "run:
  default: never-unattended"
_o58+="|never=$(_ord58)"
assert_eq "fix: run.default ask puts ask-every-stage first, and never-unattended offers no approve-run" \
  "ask=ask-every-stage,approve-run|never=ask-every-stage" "$_o58"

# --- the approval is of what was shown: rca.md edited after next printed the question ---
_fix58
_s58_calls="$(_calls58 approve-run)"
_s58_adv="$(tail -n 1 <<<"$_s58_calls")"
printf '\nFIX: also round the tax line\n' >> .temper/specs/bug/rca.md
_s58_head="$(git rev-parse HEAD)"
while IFS= read -r _c; do
  [[ -n "$_c" ]] || continue
  bash -c "$_c" >/dev/null 2>&1 || break
done <<<"$_s58_calls"
assert_eq "fix: the approval is of what was shown" \
  "advance=1|at=rca|mode=not autonomous|on=main|head=same" \
  "advance=$([[ "$_s58_adv" == *"--shown rca.md="* ]] && { bash -c "$_s58_adv" >/dev/null 2>&1; echo $?; } || echo "no digest")|at=$(
    "$TEMPER" state get next_stage 2>/dev/null)|mode=$([[ "$("$TEMPER" state get run_mode 2>/dev/null)" == autonomous ]] \
    && echo autonomous || echo "not autonomous")|on=$(git branch --show-current)|head=$(
    [[ "$(git rev-parse HEAD)" == "$_s58_head" ]] && echo same || echo moved)"

# --- no branch and no commit before the approval ---
setup; sed -i '/^  enabled: false$/d' .claude/temper.config; rm -f .temper/build-state.json .temper/view.json; _repo58
_b58="$(git branch --show-current),$(git rev-parse HEAD),$(git branch --list | wc -l | tr -d ' ')"
"$TEMPER" state init bug --command fix --feature "$_BUG58" >/dev/null 2>&1; _base_known; _rca58
"$TEMPER" usage add --stage rca --model opus --ms 1 >/dev/null 2>&1 || true
"$TEMPER" next --json >/dev/null 2>&1; "$TEMPER" go >/dev/null 2>&1 || true
assert_eq "fix: no branch and no commit before the approval" "same|feature=$_BUG58" \
  "$([[ "$(git branch --show-current),$(git rev-parse HEAD),$(git branch --list | wc -l | tr -d ' ')" == "$_b58" ]] \
    && echo same || echo "moved")|feature=$("$TEMPER" state get feature 2>/dev/null)"

# --- rule 1 with the mod off (R3-4, RULES-3): the commit hook holds the branch a fix run stands on before its approval ---
# a line of a file rca.md names, staged at the root cause question: on the branch the run started from the commit hook
# refuses it. After the approval's calls the run is on its own branch and the same commit lands there; and the branch
# it started from is no longer the run's, so a commit there is not gated (the hook gates the run's branch only)
_c58() { # _c58: the staged file committed as the fix, through the hook: committed or refused, then the branch
  echo "$(git commit -q -m 'fix(bug): the fix' >/dev/null 2>&1 && echo committed || echo refused)|$(git branch --show-current)"; }
_fix58; bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo 'echo a4' >> src/a.sh; git add src/a.sh >/dev/null 2>&1
assert_eq "fix: with the mod off a project file staged before the approval is not committed: the commit hook refuses it" \
  "refused|main|1" "$(_c58)|$(git rev-list --count HEAD)"
_fix58; bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1; _run58 approve-run >/dev/null
echo 'echo a4' >> src/a.sh; git add src/a.sh >/dev/null 2>&1; gpass build review check commit
assert_eq "fix: the same commit after the approval's calls goes through the gate on the run's branch and lands" \
  "committed|fix/bug|2" "$(_c58)|$(git rev-list --count HEAD)"
git checkout -q main; echo 'echo a4' >> src/a.sh; git add src/a.sh >/dev/null 2>&1
assert_eq "fix: after the approval the branch the run started on is not the run's: a commit there is not gated" \
  "committed|main|2" "$(_c58)|$(git rev-list --count HEAD)"
git config --unset core.hooksPath 2>/dev/null

# --- in between: a passed Fix, Review and Check move on by rule; next stops at the commit question ---
_approved58; gpass build
_m58="fix=$(_moves58 fix review)"; gpass review
_m58+="|review=$(_moves58 review check)"; gpass check
_m58+="|check=$(_moves58 check commit)"; gpass commit; _auto58 >/dev/null
_m58+="|$(_x58 "a = d.get('ask') or {}; k = d.get('card') or {}
m = '\n'.join(str(x.get('text')) for x in (sec(d, 'message') or {}).get('rows') or [])
r = '%s,card=%s,message=%s' % (a.get('id'), k.get('kind'),
    'fix_message' if 'fix(bug): the totals drop a cent' in m and 'Root cause: \`total_of\` rounds each line before the sum.' in m
    else repr(m[:120]))")"
assert_eq "fix: a passed Fix, Review and Check move on by rule" \
  "fix=auto,advance,at=review|review=auto,advance,at=check|check=auto,advance,at=commit|commit.confirm,card=commit,message=fix_message" \
  "$_m58"

# --- the checks start beside Review in a fix run, as in a feature run of the same project (the control) ---
_ahead58() { _x58 "a = (d.get('agents') or [{}])[0]
r = '%s|%s' % (a.get('type'), 'check ahead' if any(short(x) == 'check ahead' for x in a.get('before') or []) else a.get('before'))"; }
_fix58; "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known; gpass intent plan build
for _a58 in intent_complete:plan plan_complete:build build_complete:review; do
  "$TEMPER" state advance "${_a58%%:*}" "${_a58##*:}" >/dev/null 2>&1
done
_rv58="feature=$(_ahead58)"
_fix58; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1; gpass build
"$TEMPER" state advance fix_complete review >/dev/null 2>&1
assert_eq "fix: Review starts Check's run" "feature=temper:temper-review|check ahead|fix=temper:temper-review|check ahead" \
  "$_rv58|fix=$(_ahead58)"

# --- the run asks at every stage when the person picked that: the four questions of today ---
_fix58
_q58="$(_x58 "r = (d.get('ask') or {}).get('id')")"
_e58="$(_run58 ask-every-stage)"
for _st58 in fix:build review:review check:check; do
  gpass "${_st58#*:}"
  _q58+=",$(_x58 "r = (d.get('ask') or {}).get('id')")"
  [[ "${_st58%%:*}" == check ]] && break
  _run58 "$(_x58 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), None)")" >/dev/null
done
assert_eq "fix: the run asks at every stage when the person picked that" \
  "ran|rca.approve,fix.pass,review.pass,check.pass|mode=interactive" "$_e58|$_q58|mode=$("$TEMPER" state get run_mode 2>/dev/null)"

# --- question two: the commit, with no pull request ---
_atcommit58
assert_eq "fix: no pull request option at the commit" \
  "commit.confirm|commit,back,run-anyway,save|rec=commit|back=state loop check fix" \
  "$(_x58 "a = d.get('ask') or {}; b = (opt(d, 'back') or {}).get('calls') or ['']
r = '%s|%s|rec=%s|back=%s' % (a.get('id'), ','.join(str(o.get('id')) for o in opts(d) if o.get('kind') != 'more'),
    ','.join(str(o.get('id')) for o in opts(d) if o.get('recommended')), short(b[0]).split(' --reason')[0])")"

# --- the commit card of a fix run: the regression test as the CLI ran it, and the fix's own files in its plan ---
_fixed58() { # an approved fix run at its commit question: the regression test, the fix at AT, a line of the Blast
             # radius file and one of a file rca.md does not name; RED and GREEN of the test run by the CLI, each
             # followed by an agent's claim of the same, and Check's regression proof row
  _approved58
  printf 'import unittest\nclass T(unittest.TestCase):\n    def test_cent(self): pass\n' > unit/test_totals.py
  printf 'def total_of(lines):\n    return round(sum(lines), 2)\n' > src/auth/totals.py
  echo 'echo a4' >> src/a.sh; echo 'echo b4' >> src/b.sh
  "$TEMPER" state set regression_test unit/test_totals.py >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim "regression test" --phase red -- sh -c 'exit 3' >/dev/null 2>&1
  "$TEMPER" evidence add --stage build --claim "regression test" --phase red --exit 1 >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim "regression test" --phase green -- true >/dev/null 2>&1
  "$TEMPER" evidence add --stage build --claim "regression test" --phase green --exit 0 >/dev/null 2>&1
  python3 -B - <<'PY2'
import json
p = ".temper/evidence/check.json"
try:
    rows = json.load(open(p))
except (OSError, ValueError):
    rows = []
rows.append({"claim": "regression proof", "cmd": "bash suite.sh", "exit_code": 0, "phase": "check",
             "executed_by": "cli", "output": "the new or changed tests (unit/test_totals.py) fail on the code before "
             "the fix and pass with it"})
json.dump(rows, open(p, "w"))
PY2
  gpass build; _auto58 >/dev/null; gpass review; _auto58 >/dev/null; gpass check; _auto58 >/dev/null
  gpass commit; _auto58 >/dev/null
}
_fixed58
assert_eq "fix: the commit card starts with the regression test as the CLI ran it" \
  "commit.confirm|first=regression|RED: sh -c 'exit 3': failed (exit 3)|GREEN: true: passed|proof=fails before, passes" \
  "$(_x58 "k = d.get('card') or {}; ids = [s.get('id') for s in k.get('sections') or []]
t = [str(x.get('text')) for x in (sec(d, 'regression') or {}).get('rows') or []]
r = '%s|first=%s|%s|proof=%s' % ((d.get('ask') or {}).get('id'), ids[0] if ids else 'none',
    '|'.join(x for x in t if not x.startswith('proof: ')) or 'no RED or GREEN row',
    'fails before, passes' if any(x.startswith('proof: ') and 'fail on the code before the fix' in x for x in t)
    else 'no proof row')")"
assert_eq "fix: the commit card marks outside the fix only a file rca.md does not name" \
  "4 changed, 1 outside the plan|outside=src/b.sh" \
  "$(_x58 "s = sec(d, 'files') or {}
r = '%s|outside=%s' % (s.get('note'), ','.join(str(x.get('text')).replace(' (outside the plan)', '')
    for x in s.get('rows') or [] if '(outside the plan)' in str(x.get('text'))))")"

# --- TRIVIAL: the verdict, the close, the bound ---
_triv58() { # a /temper:temper run at Intent, step 0, with no spec file, in a repository on main
  setup; rm -f .temper/specs/demo/*.md .temper/groups.json .temper/view.json .temper/build-state.json
  _repo58
  "$TEMPER" state init demo --feature "fix the typo in the help text" >/dev/null 2>&1; _base_known; rm -f .temper/runs.jsonl
}
_tr58() { # what the run state holds under trivial: its keys, and whether head is HEAD
  python3 -B - "$(git rev-parse HEAD)" <<'PY'
import json, sys
try:
    t = (json.load(open(".temper/build-state.json")) or {}).get("trivial")
except (OSError, ValueError):
    t = None
if not isinstance(t, dict):
    print("no record")
else:
    print("why=%s|head=%s|at=%s|dirty_before=%s" % (t.get("why"), "HEAD" if t.get("head") == sys.argv[1] else t.get("head"),
          "set" if t.get("at") else "unset", "list" if isinstance(t.get("dirty_before"), list) else "none"))
PY
}
_refused58() { # _refused58 <args of temper intent trivial>: refused when it exits non zero and the state holds no
               # trivial
  "$TEMPER" intent trivial "$@" >/dev/null 2>&1 && { echo taken; return; }
  [[ "$(_tr58)" == "no record" ]] && echo refused || echo "exit 1 but recorded"
}
_closed58() { # a trivial request the flow closed: the verdict, the Intent gate, then the action next gives, run
  _triv58; "$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
  "$TEMPER" gate intent >/dev/null 2>&1; _auto58 >/dev/null
}
_add58() { # _add58 <file> <n>: appends n lines to the file
  local i; for ((i = 1; i <= $2; i++)); do echo "echo line $i" >> "$1"; done
}
_gc58() { # _gc58: the commit gate on what is staged: its exit in _gc58_rc, its output (one line) in _gc58_out
  _gc58_out="$("$TEMPER" gate commit 2>&1)"; _gc58_rc=$?; _gc58_out="${_gc58_out//$'\n'/ }"
}

_triv58
_tv58_out="$("$TEMPER" intent trivial --why "a typo in the help text" 2>&1)"; _tv58_rc=$?
_tv58="rc=$_tv58_rc|lines=$(grep -c . <<<"$_tv58_out")|$(_tr58)"
_triv58; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_tv58+="|plan=$(_refused58 --why x)"
_triv58; printf '# Intent: x\n' > .temper/specs/demo/intent.md; _tv58+="|intent.md=$(_refused58 --why x)"
_triv58; printf '# Tasks: x\n' > .temper/specs/demo/tasks.md; _tv58+="|tasks.md=$(_refused58 --why x)"
_triv58; "$TEMPER" state init demo --command fix >/dev/null 2>&1; _base_known; _tv58+="|fix=$(_refused58 --why x)"
assert_eq "trivial: the verdict is recorded" \
  "rc=0|lines=1|why=a typo in the help text|head=HEAD|at=set|dirty_before=list|plan=refused|intent.md=refused|tasks.md=refused|fix=refused" \
  "$_tv58"

_triv58; "$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
"$TEMPER" gate intent >/dev/null 2>&1
_cl58="next=$(_auto58)|run=$([[ -f .temper/build-state.json ]] && echo active || echo none)"
_cl58+="|$(python3 -B - "$(git rev-parse HEAD)" <<'PY'
import json, sys
try:
    t = json.load(open(".temper/trivial.json"))
except (OSError, ValueError):
    t = None
if not isinstance(t, dict):
    print("record=none")
else:
    ok = [k for k in ("request", "why", "head", "at", "dirty_before") if t.get(k) is not None]
    print("record=%s,request=%s,head=%s,bound=%s" % (",".join(ok), t.get("request"),
          "HEAD" if t.get("head") == sys.argv[1] else t.get("head"), t.get("bound")))
PY
)"
_cl58+="|runs=$(python3 -B -c '
import json
try:
    lines = [json.loads(l) for l in open(".temper/runs.jsonl") if l.strip()]
except (OSError, ValueError):
    lines = []
print("%d %s" % (len(lines), ",".join(str(x.get("kind") or x.get("ended")) for x in lines)))')"
_cl58+="|$(_x58 "s = str(d.get('say') or '')
r = 'say=%s,%s,%s,%s' % (d.get('action'), 'one line' if s and '\n' not in s.strip() else 'lines', 'reason' if 'a typo in the help text' in s else 'no reason',
    '10 lines' if '10 lines' in s else 'no bound')")"
assert_eq "trivial: the flow closes the run" \
  "next=intent trivial --close|run=none|record=request,why,head,at,dirty_before,request=fix the typo in the help text,head=HEAD,bound={'files': 1, 'lines': 10}|runs=1 trivial|say=none,one line,reason,10 lines" \
  "$_cl58"

_closed58; _add58 src/a.sh 10; git add src/a.sh
_gc58; _bd58="ten=$_gc58_rc"; _bd58+=",$([[ "$_gc58_out" == *"trivial exit"* && "$_gc58_out" == *src/a.sh* ]] && echo named || echo "not named")"
git reset -q --hard; _add58 src/a.sh 11; git add src/a.sh; _gc58; _bd58+="|eleven=$_gc58_rc"
git reset -q --hard; _add58 src/a.sh 1; _add58 src/b.sh 1; git add src/a.sh src/b.sh; _gc58; _bd58+="|two=$_gc58_rc"
_bd58+=",$([[ "$_gc58_out" == *"/temper:temper"* ]] && echo "/temper:temper" || echo "no way on")"
git reset -q --hard; _add58 src/a.sh 10; _add58 unit/test_a.py 20; git add src/a.sh unit/test_a.py
_gc58; _bd58+="|test beside=$_gc58_rc"; git reset -q --hard
assert_eq "trivial: the commit hook holds the bound" \
  "ten=0,named|eleven=1|two=1,/temper:temper|test beside=0" "$_bd58"

_closed58; _sp58="record=$([[ -f .temper/trivial.json ]] && echo written || echo none)"
_add58 src/a.sh 1; git add src/a.sh; git commit -q -m "the trivial change" >/dev/null 2>&1
_add58 src/a.sh 20; _add58 src/b.sh 20; git add src/a.sh src/b.sh; _gc58; _sp58+="|after commit=$_gc58_rc"; git reset -q --hard
_closed58; "$TEMPER" state init other --feature "another request" >/dev/null 2>&1; _base_known; "$TEMPER" state clear >/dev/null 2>&1
_add58 src/a.sh 20; _add58 src/b.sh 20; git add src/a.sh src/b.sh; _gc58; _sp58+="|after state init=$_gc58_rc"; git reset -q --hard
assert_eq "trivial: the record is spent" "record=written|after commit=0|after state init=0" "$_sp58"

_triv58; _add58 src/b.sh 30
"$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
"$TEMPER" gate intent >/dev/null 2>&1; _auto58 >/dev/null
_db58="dirty_before=$(python3 -B -c '
import json
try:
    t = json.load(open(".temper/trivial.json"))
except (OSError, ValueError):
    t = {}
print("src/b.sh" if "src/b.sh" in (t.get("dirty_before") or []) else "not listed")')"
_add58 src/a.sh 1; git add src/a.sh src/b.sh; _gc58; _db58+="|before=$_gc58_rc"; git reset -q --hard
_closed58; _add58 src/a.sh 1; _add58 src/b.sh 30; git add src/a.sh src/b.sh; _gc58; _db58+="|after=$_gc58_rc"; git reset -q --hard
assert_eq "trivial: work that was there before is not counted" "dirty_before=src/b.sh|before=0|after=1" "$_db58"
# --- the verdict is the CLI's: state set trivial, or a path below it, is refused (phase 4b review) ---
_triv58; printf '# Intent: x\n' > .temper/specs/demo/intent.md
_o58="$("$TEMPER" state set trivial.why x 2>&1)"; _ss58="trivial.why=$?,$(grep -o '^FAIL' <<<"$_o58" | head -n 1)"
"$TEMPER" gate intent >/dev/null 2>&1
_ss58+="|$(_tr58)"
_ss58+="|$(_x58 "r = 'close' if any('intent trivial --close' in str(c) for c in d.get('calls') or []) else 'no close'")"
_o58="$("$TEMPER" state set trivial x 2>&1)"; _ss58+="|trivial=$?,$(grep -o '^FAIL' <<<"$_o58" | head -n 1)"
assert_eq "trivial: state set trivial, or a path below it, is refused, so no window opens and nothing closes the run" \
  "trivial.why=1,FAIL|no record|no close|trivial=1,FAIL" "$_ss58"

# --- a staged binary file is over the bound, whatever its size (phase 4b review) ---
_closed58; python3 -B -c 'open("src/one.bin", "wb").write(bytes(range(256)))'; git add src/one.bin; _gc58
_bn58="binary=$_gc58_rc"
_bn58+=",$([[ "$_gc58_out" == *src/one.bin* && "$_gc58_out" == *binary* ]] && echo named || echo "not named")"
git reset -q --hard; rm -f src/one.bin
assert_eq "trivial: a staged binary production file fails the bound, and the row names it as binary" \
  "binary=1,named" "$_bn58"

# --- a staged rename: dirty_before holds its two paths, never a path cut from the old one (phase 4b review) ---
_triv58; printf 'echo x\n' > xx_suite.sh; git add xx_suite.sh; git commit -q -m xx; git mv xx_suite.sh renamed.sh
"$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
"$TEMPER" gate intent >/dev/null 2>&1; _auto58 >/dev/null
_rn58="$(python3 -B -c '
import json
try:
    b = json.load(open(".temper/trivial.json")).get("dirty_before") or []
except (OSError, ValueError):
    b = []
print(",".join(sorted(x for x in b if not x.startswith("."))))')"
_add58 src/a.sh 1; git add src/a.sh; _gc58; _rn58+="|one line=$_gc58_rc"
git reset -q src/a.sh; git checkout -q -- src/a.sh
_add58 suite.sh 30; git add suite.sh; _gc58; _rn58+="|suite.sh=$_gc58_rc"; git reset -q --hard
assert_eq "trivial: a rename staged before the verdict is its two paths, and the file its old name ends in is counted" \
  "renamed.sh,xx_suite.sh|one line=0|suite.sh=1" "$_rn58"
# R3-1, BLACKBOX-7: an rca.md with no CAUSE, no FIX or not written is nothing to approve. One question and one question
# site (the cap of question_sites): its two shapes are told apart in rca_approval (flow_work.py).
_q58="a = d.get('ask') or {}; r = '%s:%s:%s' % (d.get('action'), a.get('id'), ','.join(x.get('id') for x in opts(d)))"
_shape58() { rm -f .temper/view.json; _x58 "$_q58"; }   # the question next asks, read anew
fresh; _fix58; _s58="whole=$(_shape58)"
sed -i '/^FIX: /d' .temper/specs/bug/rca.md; _s58+="|no-fix=$(_shape58)"
_t58="$(_x58 "a = d.get('ask') or {}; r = (a.get('question') or {}).get('question')")"
sed -i '/^CAUSE: /d' .temper/specs/bug/rca.md; _s58+="|no-cause=$(_shape58)"
rm -f .temper/specs/bug/rca.md; _s58+="|none=$(_shape58)"
assert_eq "fix: an rca.md with a CAUSE and a FIX is the approval; with no FIX line, no CAUSE line or none written the same question offers the root cause agent again, or Save" \
  "whole=ask:rca.approve:approve-run,ask-every-stage,save|no-fix=ask:rca.approve:redo,save|no-cause=ask:rca.approve:redo,save|none=ask:rca.approve:redo,save" "$_s58"
assert_eq "fix: with nothing to approve the question says what rca.md lacks and offers the root cause agent again with a note" \
  "RCA: rca.md gives no FIX line, so there is nothing to approve yet. Run the root cause agent again with your note, or save the run?" "$_t58"
setup
