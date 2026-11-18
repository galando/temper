# Case file 52 (WP11): the approval runs to the commit by default. The first option of plan.approve, approve-run,
# approves the plan and lets the run go on to the commit: a passed check moves on as the CLI's own `auto` action, a
# failed check gets at most one counted repair by rule, and every other case is a recorded stop (the park call, then the
# stage's own question) that keeps run_mode. run.default (to-commit, ask, never-unattended) chooses the first option;
# the CLI starts the unattended run only at the approval (state key unattended_from), and a skip, an accepted finding
# and a step back to Plan end it. What a rule decided is in .temper/rule-log.json and in the view's rule_log. Sourced by
# test-temper.sh; its helpers (fresh, gpass, gfail, vw, second_group, review_done, _unattended) are used here, and the
# builders below are this file's own. A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the
# file always runs to its end.

# --- the helpers of this file ---
_x52() { # _x52 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More question, opt(d, i) the one with that id, short(c) a call without the
         # path of the CLI
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
r = None
exec(sys.argv[1])
print(r)
PY
}
_repo52() { # a git repository under the run: one source file and the config in one commit, the run's files left out
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper'; git commit -q -m base
}
_nogit52() { (cd "$WORKDIR" && rm -rf .git src); }   # no commit to stand on: no base commit is read into a state
_plan52() { # _plan52 [config lines]: a fresh run at the approval (the plan's check passed), autonomy.enabled taken out
            # of the fixture's config and the lines added
  fresh; sed -i '/^  enabled: false$/d' .claude/temper.config
  [[ -z "${1:-}" ]] || printf '%s\n' "$1" >> .claude/temper.config
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
}
_run52() { # _run52 <option id>: runs the calls of that option of the question next asks, as the session would, the
           # typed parts filled; prints ran, or the first call that failed
  local c out="none"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || { echo "stopped at: ${c##*/scripts/temper }"; return; }
    out="ran"
  done < <(_x52 "o = opt(d, '$1') or {}
r = '\n'.join(c.replace('{reason}', 'a reason').replace('{answer}', 'the person') for c in o.get('calls') or [])")
  echo "$out"
}
_rec52() { _x52 "r = next((o.get('id') for o in opts(d) if o.get('recommended')), None)"; }   # the recommended id
_approved52() { # a default run: the person took the recommended option of the approval, in a repository; at Build now
  _plan52; _repo52; _run52 "$(_rec52)" >/dev/null
}
_auto52() { # runs the calls of next when next is an auto action; prints them, short, or "not auto: <action>"
  local c out="" a
  a="$(_x52 "r = d.get('action')")"
  [[ "$a" == auto ]] || { echo "not auto: $a"; return; }
  while IFS= read -r c; do
    [[ -n "$c" ]] && { bash -c "$c" >/dev/null 2>&1; out+="${out:+;}${c##*/scripts/temper }"; }
  done < <(_x52 "r = '\n'.join(d.get('calls') or [])")
  echo "$out"
}
_stop52() { # "stop" when next is a question or a recorded stop (an auto action whose every call is the park call); else
            # the action and its first call
  _x52 "a = d.get('action'); c = [short(x) for x in d.get('calls') or []]
r = 'stop' if a == 'ask' or (a == 'auto' and c and all(re.match(r'park --verdict ', x) for x in c)) else \
    '%s %s' % (a, c[0][:70] if c else ','.join(str(x.get('type')) for x in d.get('agents') or []))"
}
_moves52() { # _moves52 <stage> <next stage>: auto when next is the CLI's own advance of the stage and sets no run_mode;
             # after its calls ran, where the run is and its run_mode
  local how
  how="$(_x52 "c = [short(x) for x in d.get('calls') or []]
r = '%s,%s' % (d.get('action'), 'advance' if any(x.startswith('state advance $1_complete $2') for x in c)
    and not any('run_mode' in x for x in c) else 'calls: ' + '; '.join(c)[:160])")"
  [[ "$how" == auto,* ]] && _auto52 >/dev/null
  echo "$how,at=$("$TEMPER" state get next_stage 2>/dev/null),mode=$("$TEMPER" state get run_mode 2>/dev/null)"
}
_g52() { printf '%s\n' "$1" > .temper/groups.json; }   # _g52 <groups.json text>
_auth52() { # the run's plan declares a file under a sensitive path (autonomy.park-on-touch of the fixture: **/auth/**)
  sed -i 's|^\*\*File:\*\* `src/demo.sh`$|**File:** `src/demo.sh`, `src/auth/login.sh`|' .temper/specs/demo/tasks.md
}
_rowpass52() { # _rowpass52 <stage> <row name>...: pass of the first named row the stage's verdict holds, or absent
  python3 -B - "$@" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
rows = [x for x in e.get("requirements") or [] if x.get("name") in sys.argv[2:]]
print(rows[0].get("pass") if rows else "absent")
PY
}
_kinds52() { # _kinds52 <file>: the kinds of the entries of a rule log, in order, and whether each has stage, what, ts
  python3 -B - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("no rule log"); sys.exit(0)
if isinstance(d, dict):
    d = d.get("rule_log")
if not isinstance(d, list):
    print("no list"); sys.exit(0)
whole = all(isinstance(e, dict) and all(e.get(k) for k in ("kind", "stage", "what", "ts")) for e in d)
print("%s|whole=%s" % (",".join(str(e.get("kind")) for e in d if isinstance(e, dict)), whole))
PY
}

# --- the approval: run.default chooses its first option (to-commit by default) ---
_first52() { # the approval: its id; id, recommended, move and first call of its first two options; the ids of the rest
  _x52 "a = d.get('ask') or {}
top = a.get('options') or []
more = (a.get('more') or {}).get('options') or []
two = ['%s,%s,%s,%s' % (o.get('id'), bool(o.get('recommended')), o.get('move'),
                        short((o.get('calls') or [''])[0]).split(' --shown ')[0])
       for o in top[:2]]
r = '%s|%s|rest=%s|more=%s' % (a.get('id'), '|'.join(two), ','.join(str(o.get('id')) for o in top[2:]),
                               ','.join(str(o.get('id')) for o in more))"
}
_plan52
_ap52_want="plan.approve|approve-run,True,arm,state set run_mode autonomous"
_ap52_want+="|ask-every-stage,False,approve,state set run_mode interactive"
_ap52_want+="|rest=fresh-review,more|more=html-review,run-design,back,save"   # WP13: the step back to Intent
assert_eq "run: the default approval" "$_ap52_want" "$(_first52)"

_ask52() { # the first two options of the approval: id, label and first call
  _x52 "top = (d.get('ask') or {}).get('options') or []
r = '|'.join('%s,%s,%s' % (o.get('id'), o.get('label'), short((o.get('calls') or [''])[0]).split(' --shown ')[0])
             for o in top[:2])"
}
_ask52_want="ask-every-stage,Ask me at every stage (Recommended),state set run_mode interactive"
_ask52_want+="|approve-run,Approve and build,state set run_mode autonomous"
_plan52 $'run:\n  default: ask'
assert_eq "run: run.default ask puts ask-every-stage first and recommended" "$_ask52_want" "$(_ask52)"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1   # the fixture's enabled: false
assert_eq "run: autonomy.enabled false with no run.default means ask" "$_ask52_want" "$(_ask52)"

_plan52 $'run:\n  default: never-unattended'
_nv52="$(_x52 "top = (d.get('ask') or {}).get('options') or []
arm = [str(o.get('id')) for o in opts(d) if o.get('id') == 'approve-run' or o.get('move') == 'arm'
       or any('run_mode autonomous' in c for c in o.get('calls') or [])]
r = 'first=%s,%s|arm=%s' % (top[0].get('id') if top else None, bool(top and top[0].get('recommended')),
                           ','.join(arm) or 'none')")"
_nv52+="|call=$("$TEMPER" state set run_mode autonomous >/dev/null 2>&1 && echo taken || echo refused)"
_nv52+=",mode=$("$TEMPER" state get run_mode 2>/dev/null)"
assert_eq "run: never-unattended offers no approve-run, and the CLI refuses the call" \
  "first=ask-every-stage,True|arm=none|call=refused,mode=interactive" "$_nv52"

# --- the call that starts the unattended run is taken only at the approval, and the start is recorded ---
_arm52() { # the session types the call that starts the unattended run: taken or refused, and the mode after
  printf '%s,%s' "$("$TEMPER" state set run_mode autonomous >/dev/null 2>&1 && echo taken || echo refused)" \
    "$("$TEMPER" state get run_mode 2>/dev/null)"
}
fresh; gpass intent plan build; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1; _aw52="build=$(_arm52)"
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gfail plan "preflight" "x"
"$TEMPER" override plan --reason 'skip it' >/dev/null 2>&1; _aw52+="|plan skipped=$(_arm52)"
_plan52; _aw52+="|approval=$(_arm52),from=$("$TEMPER" state get unattended_from 2>/dev/null)"
assert_eq "run: the CLI refuses to start the unattended run away from the approval" \
  "build=refused,interactive|plan skipped=refused,interactive|approval=taken,autonomous,from=plan" "$_aw52"

_plan52
_hw52="first=$(_x52 "o = opt(d, 'approve-run') or {}; r = short((o.get('calls') or [''])[0]).split(' --shown ')[0]")"
bash -c "$(_x52 "o = opt(d, 'approve-run') or {}; r = (o.get('calls') or ['true'])[0]")" >/dev/null 2>&1
_hw52+="|next=$(_x52 "r = '%s,%s,run.armed=%s' % (d.get('action'), (d.get('ask') or {}).get('id'),
                                             (d.get('run') or {}).get('armed'))")"
_hw52+="|guard.armed=$(vw "(d.get('guard') or {}).get('armed')")"
assert_eq "run: a run whose approving calls stopped half way is not armed" \
  "first=state set run_mode autonomous|next=ask,plan.approve,run.armed=False|guard.armed=False" "$_hw52"

# After approve-run stopped half way the person picks Run Design first: Design asks its own question, the last one
# before Build, and the run asks at every stage (rule 3: only the option the person picked starts the unattended run)
_plan52; _repo52
bash -c "$(_x52 "o = opt(d, 'approve-run') or {}; r = (o.get('calls') or ['true'])[0]")" >/dev/null 2>&1
_hd52="$(_run52 run-design)"; gpass design
_hd52+="|mode=$("$TEMPER" state get run_mode 2>/dev/null)|next=$(_x52 "r = '%s,%s,run.armed=%s' % (
    d.get('action'), (d.get('ask') or {}).get('id'), (d.get('run') or {}).get('armed'))")"
assert_eq "run: Run Design first after a half way approve-run asks the Design question, and the run asks at every stage" \
  "ran|mode=interactive|next=ask,design.pass,run.armed=False" "$_hd52"

# --- a passed check moves on as the CLI's own action, in the run of the recommended option ---
_approved52; gpass build
assert_eq "run: a passed Build moves on as auto" "auto,advance,at=review,mode=autonomous" "$(_moves52 build review)"
_approved52; gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1; review_done; gpass review
assert_eq "run: a passed Review moves on as auto" "auto,advance,at=check,mode=autonomous" "$(_moves52 review check)"
_approved52; gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1; review_done; gpass review
"$TEMPER" state advance review_complete check >/dev/null 2>&1; gpass check
assert_eq "run: a passed Check moves on as auto" "auto,advance,at=commit,mode=autonomous" "$(_moves52 check commit)"

# groups.json with group G1 in a status (and its gate), its one task passed
_GROUPS52='{"version": 1, "slug": "demo", "groups": {"G1": {"status": "%s", "worktree": "w",'
_GROUPS52+=' "branch": "temper/demo/G1"%s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}'
_G1FAIL52=', "fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test",'
_G1FAIL52+=' "ran": true, "fail_lines": ["FAIL: test_a"]}'
_plan52; second_group; _repo52; _run52 "$(_rec52)" >/dev/null
_g52 "$(printf "$_GROUPS52" passed ', "gate": {"verdict": "PASS"}')"
assert_eq "run: a passed group moves on" "auto,group continue G1" \
  "$(_x52 "r = '%s,%s' % (d.get('action'), ';'.join(short(c) for c in d.get('calls') or []))")"

# --- a failed check gets one repair by rule at most; the closed list of stops ---
_finding52() { # _finding52 <severity> [claim]: an open finding of Review, as the reviewer records it
  "$TEMPER" evidence add --stage review --claim "${2:-src/demo.sh:1 the demo prints nothing on error}" --severity "$1" \
    --label PROVEN >/dev/null 2>&1
}
_nogit52; _unattended review; _finding52 critical; gfail review "no blocking findings" "1 open critical finding"
_bf52="first=$(_x52 "c = [short(x) for x in d.get('calls') or []]
rule = len(c) == 1 and re.match(r\"state loop review build --reason 'rule: \", c[0])
r = '%s,%s' % (d.get('action'), 'loop by rule' if rule else '; '.join(c)[:160])")"
_auto52 >/dev/null
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
_finding52 critical; gfail review "no blocking findings" "1 open critical finding"
_bf52+="|second=$(_stop52)"
assert_eq "run: a blocking finding gets one loop back by rule, the second stops" "first=auto,loop by rule|second=stop" \
  "$_bf52"

_nogit52; _unattended review; _finding52 high; review_done; gpass review   # the fixture's review.block-on is [critical]
_bb52="review=$(_x52 "c = [short(x) for x in d.get('calls') or []]
loop = not c or any(x.startswith('state loop') for x in c)
r = '%s,%s' % (d.get('action'), '; '.join(c)[:160] if loop else 'no loop')")"
_auto52 >/dev/null; gpass check; _auto52 >/dev/null; gpass commit; _auto52 >/dev/null
_bb52+="|commit=$(_x52 "a = d.get('ask') or {}; t = str((a.get('question') or {}).get('question'))
r = '%s,%s' % (a.get('id'), 'names 1 high' if re.search(r'\b1 high\b', t) else t[:160])")"
assert_eq "run: a finding below review.block-on starts no loop and is named at the commit question" \
  "review=auto,no loop|commit=commit.confirm,names 1 high" "$_bb52"

_nogit52; _unattended check
gfail check "mutation score >= threshold" "40% of planted bugs caught < 60%: no test notices these changes"
assert_eq "run: a failed Check whose only failed row is the mutation row stops" "stop" "$(_stop52)"

_nogit52; _unattended build; _auth52; _g52 "$(printf "$_GROUPS52" running "$_G1FAIL52")"
_sp52="group=$(_stop52)"
_nogit52; _unattended review; _auth52; _finding52 critical 'src/auth/login.sh:4 the lockout is never reset'
gfail review "no blocking findings" "1 open critical finding"
_sp52+="|finding=$(_stop52)"
assert_eq "run: no repair by rule when the plan declares a sensitive path" "group=stop|finding=stop" "$_sp52"

fresh; _auth52; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_rk52_out="$("$TEMPER" risk 2>&1)"
_rk52="risk=$("$TEMPER" state get risk 2>/dev/null)|$([[ "$_rk52_out" == *'sensitive path src/auth/login.sh'* ]] \
  && echo 'names the path' || echo "says: ${_rk52_out:0:160}")"
assert_eq "run: a declared sensitive path makes risk H" "risk=H|names the path" "$_rk52"

# --- a stop is the park call and then the stage's own question; it keeps run_mode, and the answer ends it ---
_nogit52; _unattended review; gfail review "review completed" "no review completed row"
"$TEMPER" park --verdict PARKED-NEEDS-DECISION --reason 'Review: no review completed row' >/dev/null 2>&1
_sk52="mode=$("$TEMPER" state get run_mode 2>/dev/null)|$(_x52 "a = d.get('ask') or {}
t = str((a.get('question') or {}).get('question'))
called = [o for o in opts(d) if (o.get('calls') or []) and not o.get('stop')]
bad = [str(o.get('id')) for o in called if short(o['calls'][-1]) != 'park --end --answer %s' % o.get('id')]
fh = [short(c) for c in (opt(d, 'ask-every-stage') or {}).get('calls') or []]
r = '%s,%s|goes on=%s|ends=%s|from here=%s' % (d.get('action'), a.get('id'),
    'After your answer the run goes on by itself.' in t, 'too few' if len(called) < 2 else ','.join(bad) or 'all',
    'yes' if fh == ['state set run_mode interactive', 'park --end --answer ask-every-stage'] else fh)")"
assert_eq "run: a stop keeps run_mode" "mode=autonomous|ask,review.fail|goes on=True|ends=all|from here=yes" "$_sk52"

_nogit52; _unattended build; second_group; _g52 "$(printf "$_GROUPS52" running "$_G1FAIL52")"
"$TEMPER" park --verdict PARKED-NEEDS-DECISION --reason 'Build: group G1 failed its check' >/dev/null 2>&1
_last52() { # the last call of the recommended option, short
  _x52 "o = next((o for o in opts(d) if o.get('recommended')), {}); c = [short(x) for x in o.get('calls') or []]
r = c[-1] if c else ''"
}
_aa52_end="$(_last52)"
[[ "$_aa52_end" == 'park --end --answer '* ]] || _aa52_end="park --end --answer $(_rec52)"
# the person's answer: its other calls repaired the group (the group's check passes now), its last call ends the stop
"$TEMPER" $_aa52_end >/dev/null 2>&1 || true
_g52 "$(printf "$_GROUPS52" passed ', "gate": {"verdict": "PASS"}')"
assert_eq "run: after the answer the same stage goes on as auto" "auto,group continue G1|parked=" \
  "$(_x52 "r = '%s,%s' % (d.get('action'), ';'.join(short(c) for c in d.get('calls') or []))")|parked=$(
    "$TEMPER" state get parked 2>/dev/null)"

_nogit52; _unattended check; gfail check "tests pass" "the latest run of a test command failed: unit"
"$TEMPER" override check --reason 'the flaky suite is known' >/dev/null 2>&1
_end52="skip=$("$TEMPER" state get run_mode 2>/dev/null)"
_nogit52; _unattended review; _finding52 critical
"$TEMPER" evidence accept --stage review --id 1 --reason 'known and tracked' >/dev/null 2>&1
_end52+="|accept=$("$TEMPER" state get run_mode 2>/dev/null)"
_nogit52; _unattended build; "$TEMPER" state loop build plan --reason 'the plan cannot be built' >/dev/null 2>&1
_end52+="|back=$("$TEMPER" state get run_mode 2>/dev/null)"
assert_eq "run: a skip, an accepted finding and a step back to Plan end it" \
  "skip=interactive|accept=interactive|back=interactive" "$_end52"

_nogit52; _unattended build; sed -i 's|^- \[x\] done task|- [ ] done task|' .temper/specs/demo/tasks.md
_g52 '{"version": 1, "slug": "demo",
 "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1"}},
 "tasks": {"1": {"status": "running", "group": "G1", "env_fault": {"reason": "the JDK is 21 and pom.xml needs 24"}}}}'
assert_eq "run: a task that failed on the environment is a recorded stop" "auto,park first" \
  "$(_x52 "c = [short(x) for x in d.get('calls') or []]
r = '%s,%s' % (d.get('action'), 'park first' if c and c[0].startswith('park --verdict') else '; '.join(c)[:120])")"

# --- the commit question of an unattended run: commit, a pull request, a loop back to Build ---
_atcommit52() { # an unattended run of a plan of two groups at the commit question: every gate passed, the park call ran
  _nogit52; _unattended commit; second_group; gpass commit; _auto52 >/dev/null
}
_atcommit52
_cq52_want="commit.confirm|top=commit,commit-pr,back,more|rec=commit|back=state loop check build"
_cq52_want+="|more=commit-stacked-prs,small-change,save"
assert_eq "run: the commit question of an unattended run" "$_cq52_want" \
  "$(_x52 "a = d.get('ask') or {}; top = a.get('options') or []; more = (a.get('more') or {}).get('options') or []
b = (opt(d, 'back') or {}).get('calls') or ['']
r = '%s|top=%s|rec=%s|back=%s|more=%s' % (a.get('id'), ','.join(str(o.get('id')) for o in top),
    ','.join(str(o.get('id')) for o in opts(d) if o.get('recommended')), short(b[0]).split(' --reason')[0],
    ','.join(str(o.get('id')) for o in more))")"

_prsteps52() { # takes commit-pr: its calls and its steps that are CLI calls, then the CLI's own work up to the record
               # steps; prints whether they hold the pull request steps
  local c i
  c="$(_x52 "o = opt(d, 'commit-pr')
cli = [x for x in ((o or {}).get('calls') or []) + ((o or {}).get('steps') or []) if re.match(r'^\S*/temper ', x)]
r = 'none' if o is None else '\n'.join(cli)")"
  [[ "$c" == none ]] && { echo "no commit-pr option"; return; }
  while IFS= read -r i; do [[ -n "$i" ]] && bash -c "$i" >/dev/null 2>&1; done <<<"$c"
  for i in 1 2 3 4; do
    case "$(_x52 "r = ('steps' if d.get('steps') else 'calls' if d.get('action') in ('auto', 'work') and d.get('calls')
    and not d.get('agents') else d.get('action'))")" in
      steps) _x52 "s = d.get('steps') or []
r = 'capture=%s,one pr=%s' % (any('section Capture' in x for x in s), any('section One PR' in x for x in s))"; return ;;
      calls) _x52 "r = '\n'.join(d.get('calls') or [])" | while IFS= read -r c; do bash -c "$c" >/dev/null 2>&1; done ;;
      *) echo "no record steps"; return ;;
    esac
  done
  echo "no record steps"
}
_atcommit52
assert_eq "run: the record steps open the pull request after that option" "capture=True,one pr=True" "$(_prsteps52)"

_nogit52; _unattended commit; _repo52; "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
mkdir -p src/auth; echo 'echo token' > src/auth/token.sh
"$TEMPER" evidence add --stage build --phase feedback --claim 'drift src/auth/token.sh: Allow once' >/dev/null 2>&1
"$TEMPER" gate commit >/dev/null 2>&1
_ex52="before=$(_rowpass52 commit 'park-on-touch paths' 'sensitive paths')"
_auto52 >/dev/null
_ex52+="|$(_x52 "o = opt(d, 'confirm') or {}
r = '%s|check-again=%s|confirm=%s,%s' % ((d.get('ask') or {}).get('id'), opt(d, 'check-again') is not None,
    o.get('label'), ';'.join(short(c) for c in o.get('calls') or []))")"
_ex52+="|$(_run52 confirm)|after=$(_rowpass52 commit 'park-on-touch paths' 'sensitive paths')"
_ex52_want="before=False|commit.fail|check-again=True|confirm=Confirm the change to src/auth/token.sh,"
_ex52_want+="override sensitive-path:src/auth/token.sh --reason '{reason}';gate commit|ran|after=True"
assert_eq "run: a changed sensitive file outside the plan has an exit" "$_ex52_want" "$_ex52"

# --- a run taken up again asks the question of its stage once, then goes on by itself ---
_nogit52; _unattended build; gpass build
_tu52_go="$("$TEMPER" go --taken-up 2>/dev/null)"; [[ -n "$_tu52_go" ]] || _tu52_go='{}'
_tu52="go=$(_x52 "park = any('park --verdict PARKED-NEEDS-DECISION' in str(c) for c in d.get('ran') or [])
r = '%s,%s,%s' % (d.get('action'), (d.get('ask') or {}).get('id'), 'parked' if park else 'no park')" "$_tu52_go")"
_tu52+="|$(_run52 "$(_rec52)")"
_tu52+="|then=$(_x52 "r = '%s,%s' % (d.get('action'), (d.get('ask') or {}).get('id') or d.get('stage'))")"
review_done; gpass review
_tu52+="|review=$(_x52 "c = [short(x) for x in d.get('calls') or []]
on = any(x.startswith('state advance review_complete check') for x in c)
r = '%s,%s' % (d.get('action'), 'advance' if on else c[:1])")"
assert_eq "run: a run taken up again asks its stage once" \
  "go=ask,build.pass,parked|ran|then=work,review|review=auto,advance" "$_tu52"

# --- a run saved armed by 9.8.4 or by the base was approved for Build alone: it asks at every stage ---
SAVED52="$TESTS_DIR/saved-old.json"
_restore52() { # _restore52 <commit> <state>: the project as that Temper left it at that state (_restore46 of case 46)
  cd "$WORKDIR" || return 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name t
  printf 'x\n' > README.md; git add README.md; git commit -q -m init
  local b
  b="$(python3 -I - "$SAVED52" "$1" "$2" "$WORKDIR" "$REPO_ROOT" "$(git rev-parse HEAD)" <<'PY'
import json, os, sys
saved, commit, state, work, plugin, head = sys.argv[1:7]
d = json.load(open(saved))[commit]["states"][state]
for rel, text in d["files"].items():
    p = os.path.join(work, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text.replace("@PROJECT@", work).replace("@PLUGIN@", plugin).replace("@HEAD@", head))
print(d.get("branch") or "master")
PY
)"
  git checkout -q -B "${b:-master}" 2>/dev/null
}
_old52=""
for _c52 in 7c7a1c1 10e965a; do
  _restore52 "$_c52" armed-build; gpass build
  _old52+="${_old52:+|}$([[ $_c52 == 7c7a1c1 ]] && echo 9.8.4 || echo base)"
  _old52+="=$("$TEMPER" state get run_mode 2>/dev/null)"
  _old52+=",$(_x52 "r = '%s %s' % (d.get('action'), (d.get('ask') or {}).get('id'))")"
  "$TEMPER" state advance build_complete review >/dev/null 2>&1; review_done; gpass review
  _old52+=",$(_x52 "r = '%s %s' % (d.get('action'), (d.get('ask') or {}).get('id'))")"
done
assert_eq "run: a run saved armed by an earlier version asks at every stage" \
  "9.8.4=interactive,ask build.pass,ask review.pass|base=interactive,ask build.pass,ask review.pass" "$_old52"

# --- the rule log: what a rule decided, in .temper/rule-log.json and in the view ---
_nogit52; _unattended build; rm -f .temper/rule-log.json   # what the helper's own approval and advances wrote goes
gpass build; _auto52 >/dev/null                                                                 # an advance
_finding52 critical; gfail review "no blocking findings" "1 open critical finding"; _auto52 >/dev/null     # a repair
gfail build "RED then GREEN" "have red=0 green=0"; _auto52 >/dev/null                            # a stop
_rl52_end="$(_last52)"
[[ "$_rl52_end" == 'park --end --answer '* ]] || _rl52_end="park --end --answer $(_rec52)"
"$TEMPER" $_rl52_end >/dev/null 2>&1 || true                                                    # the answer
assert_eq "run: the rule log holds each advance, repair, stop and answer" "advance,repair,stop,answer|whole=True" \
  "$(_kinds52 .temper/rule-log.json)"
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "run: view.json carries rule_log" "advance,repair,stop,answer|whole=True|version=1" \
  "$(_kinds52 .temper/view.json)|version=$(vw "d.get('version')")"
