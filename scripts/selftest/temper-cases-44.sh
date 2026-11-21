# Case file 44 (WP07): the run unit rows of docs/plans/one-go/done.md that are cases, and rules 1 to 6. Sourced by
# test-temper.sh; its helpers (fresh, gpass, gfail, m_setup, nx, vw, _unattended) are used here. The first word of every
# assertion is the token of its row; a token still expected to fail is a line of scripts/selftest/expected-fail.txt.
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_repo44() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_nogit44() { (cd "$WORKDIR" && rm -rf .git src); }   # no commit to stand on: no base commit is read into a state
_x44() { # _x44 <python code over d, the JSON of temper next (or of the second argument), that sets r>: prints r
  python3 - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
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
def section(card, sid):
    return next((s for s in (card or {}).get("sections") or [] if s.get("id") == sid), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
_calls44() { # _calls44 <option id>: the calls of that option of the question next asks, one a line, the typed parts filled
  _x44 "o = opt(d, '$1'); r = '\n'.join(c.replace('{reason}', 'a reason').replace('{answer}', 'the person') for c in (o or {}).get('calls') or [])"
}
_run44() { # _run44 <option id>: runs the calls of that option as the session would, stopping at the first that fails
  local c rc out=""
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1; rc=$?
    [[ "$c" == *"state advance"* ]] && out+="adv=$rc "
    [[ $rc -eq 0 ]] || { out+="stopped=$rc"; break; }
  done < <(_calls44 "$1")
  echo "${out:-none}"
}
_auto44() { # runs the calls of next when next is an auto action
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1
  done < <(_x44 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'auto' else ''")
}
_stop44() { # _stop44 [ERE]: "stop" when next is a question or a recorded stop (the park call) and no call of the CLI's own
            # action matches the ERE; else what next does
  python3 - "${1:-}" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
bad = re.compile(sys.argv[1]) if sys.argv[1] else None
try:
    d = json.loads(sys.argv[2])
except ValueError:
    print("no next")
    sys.exit(0)
a = d.get("action")
calls = list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]
short = ",".join(re.sub(r"^\S*/temper ", "", c)[:60] for c in calls[:2]) or ",".join(str(x.get("type")) for x in d.get("agents") or [])
if a in ("auto", "work") and bad and any(bad.search(c) for c in calls):
    print("%s runs %s" % (a, short))
elif a == "ask" or (a == "auto" and calls and all(re.search(r"\spark\s", c) and "--end" not in c for c in calls)):
    print("stop")
else:
    print("%s %s" % (a, short))
PY
}
_row44() { # _row44 <stage> <row name>: pass of that row of the stage's verdict in gates.json (state too when set), or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else ("%s:%s" % (r.get("pass"), r.get("state")) if r.get("state") else str(r.get("pass"))))
PY
}
_approved44() { # an approved run at Build in a repository, from the approval's own calls (ask-every-stage, by id)
  fresh; _repo44; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _run44 ask-every-stage >/dev/null
}
_approved_run44() { # an unattended run at Build in a repository, started at the approval by its option approve-run
  fresh; _repo44; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _run44 approve-run >/dev/null
}
_armed44() { # _armed44 [ERE]: what _stop44 prints when the run goes on by itself, else "not unattended": a leg whose
             # state is no unattended run proves nothing of the rule
  if [[ "$("$TEMPER" state get run_mode 2>/dev/null)" == autonomous ]]; then _stop44 "${1:-}"
  else echo "not unattended"; fi
}
_g44() { printf '%s\n' "$1" > .temper/groups.json; }   # _g44 <groups.json text>
_GROUP44='{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}'

# --- D02b: the answer to the Context check is recorded at the approval only when the card shows every flagged line ---
_map44() { # a Context Map with one flagged line of 95 characters (the question text cuts at 90), not yet reviewed
  cat > .temper/specs/demo/plan.md <<'MAP'
# Plan

## Context Map
- use: intent.md AC-01..AC-02 - the accepted scope
- ignore: .temper/specs/old-login/ - a finished feature of another scope, kept for its history only
- reviewed: pending

## Approach
The demo.
MAP
}
fresh; _map44; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_d02_fold="$(_x44 "line = '.temper/specs/old-login/ - a finished feature of another scope, kept for its history only'
sec = section(d.get('card'), 'context')
whole = bool(sec) and any(line in x.get('text', '') for x in sec.get('rows') or []) and (sec.get('total') or 0) <= len(sec.get('rows') or [])
o = opt(d, 'approve-run') or opt(d, 'ask-every-stage') or {}
rec = any('plan review --answer' in c for c in o.get('calls') or [])
r = '%s:%s:%s' % (d.get('context_check') is None, rec, rec == whole)")"
fresh; _map44; printf 'plan:\n  context-check: always\n' >> .claude/temper.config
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_d02_always="$(_x44 "r = 'asked' if d.get('context_check') else 'not asked'")"
assert_eq "D02b the Context check is answered at the approval only when the card shows every flagged line whole; always still asks" \
  "fold=True:True:True|always=asked" "fold=$_d02_fold|always=$_d02_always"

# --- D05b: in an unattended run none of the eight is repaired by rule ---
_head44() { # the run as it stands on a reviewed HEAD: its tree in a commit on the run's own branch, Build integrated and
            # the Review snapshot of that commit, so a state of D05b is refused by its own condition, not for want of these
  git checkout -q -B feature/demo 2>/dev/null; git config user.email t@example.com; git config user.name T
  mkdir -p src; [[ -f src/demo.sh ]] || echo 'echo demo prints the demo line' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m build
  "$TEMPER" state set branch feature/demo >/dev/null 2>&1; sed -i '/block-on/d' .claude/temper.config   # a High finding blocks
  printf '{"version": 1, "slug": "demo", "groups": {}, "tasks": {}, "integration": {"verdict": "PASS", "merged": true}}\n' > .temper/groups.json
  python3 -I "$(dirname "$TEMPER")/state_ops.py" review-code save .temper/build-state.json >/dev/null 2>&1
}
_d05() { # _d05 <case>: the state of one of the eight (or plain, a High finding of the plan's file), on a reviewed HEAD,
         # then what next does and whether a repair window opened
  _nogit44
  case "$1" in
    plain) _unattended review
      "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
      gfail review "no blocking findings" "1 open high finding" ;;
    contested) _unattended review; mkdir -p src; echo 'echo demo prints the demo line' > src/demo.sh
      "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
      "$TEMPER" evidence contest --stage review --id 1 --cite src/demo.sh:1 --quote 'echo demo prints the demo line' \
        --reason 'the line prints' >/dev/null 2>&1
      gfail review "no blocking findings" "1 open high finding" ;;
    outside) _unattended review
      "$TEMPER" evidence add --stage review --claim 'lib/other.py:3 the fix needs a file outside the plan' --severity high --label PROVEN >/dev/null 2>&1
      gfail review "no blocking findings" "1 open high finding" ;;
    sensitive) _unattended review
      sed -i 's|`src/demo.sh`|`src/demo.sh`, `src/auth/login.sh`|' .temper/specs/demo/tasks.md
      "$TEMPER" evidence add --stage review --claim 'src/auth/login.sh:4 the lockout is never reset' --severity high --label PROVEN >/dev/null 2>&1
      gfail review "no blocking findings" "1 open high finding" ;;
    unfinished) _unattended review
      "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
      gfail review "review completed" "no review completed row" ;;
    environment) _unattended check
      ev_red check 'tests: the suite (run by the CLI)'
      "$TEMPER" evidence add --stage check --claim 'setup fault: the JDK is 21 and pom.xml needs 24' --exit 1 >/dev/null 2>&1
      gfail check "tests pass" "the latest run of a test command failed: the suite" ;;
    unmeasured) _unattended check; gfail check "tests pass" "no passing test-run evidence recorded" ;;
    person) _unattended check; sed -i '0,/Validate: scenario/s//Validate: manual/' .temper/specs/demo/intent.md
      gfail check "acceptance evidence" "AC-01 has no supported passing evidence row" ;;
    acceptance) _unattended check
      printf '{"verdict": "test", "why": "the locked test asserts the wrong text"}\n' > .temper/evidence/acceptance-triage.json
      gfail check "acceptance tests written before Build" "the locked acceptance tests fail: 1 of 2" ;;
  esac
  _head44
  printf '%s,%s' "$(_stop44 'repair start|state loop')" \
    "$(python3 -c "import json; print('window' if json.load(open('.temper/build-state.json')).get('repair') else 'no window')" 2>/dev/null)"
}
_d05_got=""; _d05_want=""
for _c in contested outside sensitive unfinished environment unmeasured person acceptance; do
  _d05_want+="$_c=stop,no window|"; _d05_got+="$_c=$(_d05 "$_c")|"
done
assert_eq "D05b in an unattended run none of the eight is repaired by rule: each is a question or a recorded stop, no repair window" \
  "$_d05_want" "$_d05_got"
assert_eq "D05b the eight stand on a reviewed HEAD: there a High finding of a file of the plan is repaired by rule" \
  "auto runs repair start --stage review" "$(_d05 plain | cut -d, -f1)"

# --- D15, D15b: a failed check is never run again unchanged; the person keeps one counted way to run it anyway ---
_suite44() { # _suite44 <exit>: a run at Check whose test command appends a line to .temper/count44 and exits with <exit>
  fresh; _repo44
  printf 'check:\n  commands:\n    test: "echo run >> .temper/count44; exit %s"\n' "$1" >> .claude/temper.config
  gpass intent plan build review; _at check
}
_count44() { if [[ -f .temper/count44 ]]; then wc -l < .temper/count44 | tr -d ' '; else echo 0; fi; }
_suite44 1
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" check run >/dev/null 2>&1; _d15_same="$(_count44)"
echo 'echo demo two' > src/demo.sh; "$TEMPER" check run >/dev/null 2>&1; _d15_edit="$(_count44)"
assert_eq "D15 a failed check is not run again on the same tree and command; an edit of a tracked file runs it again" \
  "same=1|edited=2" "same=$_d15_same|edited=$_d15_edit"
_lastrow44() { # _lastrow44 <python expression over x, the last tests row of Check's ledger>
  python3 -c "
import json, sys
try:
    rows = [x for x in json.load(open('.temper/evidence/check.json')) if str(x.get('claim', '')).startswith('tests')]
except (OSError, ValueError):
    rows = []
x = rows[-1] if rows else {}
print(eval(sys.argv[1]))" "$1"
}
_suite44 0
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" check run >/dev/null 2>&1; _d15b_kept="$(_count44)"
_d15b_reused="$(_lastrow44 "'%s,%s' % (bool(x.get('reused')), bool(x.get('tree')))")"
_d15b_b0="$("$TEMPER" budget 2>&1)"
"$TEMPER" check run --fresh >/dev/null 2>&1; _d15b_fresh="$(_count44)"
_d15b_forced="$(_lastrow44 "bool(x.get('forced'))")"
_d15b_b1="$("$TEMPER" budget 2>&1)"
assert_eq "D15b a kept pass is reused with its date and tree; check run --fresh runs anyway, is marked forced and spends a repeat" \
  "kept=1|reused=True,True|fresh=2|forced=True|spent=True" \
  "kept=$_d15b_kept|reused=$_d15b_reused|fresh=$_d15b_fresh|forced=$_d15b_forced|spent=$([[ -n "$_d15b_b1" && "$_d15b_b0" != "$_d15b_b1" ]] && echo True || echo False)"

# --- D16: in a default run no question follows a passed check from the approval to the commit ---
fresh; _repo44; sed -i '/^  enabled: false$/d' .claude/temper.config
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_run44 approve-run >/dev/null
_d16=""
for _s in build review check; do
  "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
  gpass "$_s"
  _d16+="$_s=$(_x44 "r = d.get('action')")|"
  _auto44
done
assert_eq "D16 a run approved with approve-run asks no question after a passed Build, Review or Check" \
  "build=auto|review=auto|check=auto|" "$_d16"

# --- D18a to D18d: run.default and the option that runs to the commit ---
_plan44() { # _plan44 [config lines]: the plan question of a run whose config holds the lines (autonomy.enabled taken out)
  fresh; sed -i '/^  enabled: false$/d' .claude/temper.config; [[ -z "${1:-}" ]] || printf '%s\n' "$1" >> .claude/temper.config
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
}
_first44() { _x44 "o = (opts(d) or [{}])[0]; r = '%s,%s' % (o.get('id'), bool(o.get('recommended')))"; }
_plan44
assert_eq "D18a with no run.default the approval's first option is approve-run, and it is recommended" "approve-run,True" "$(_first44)"
_plan44 $'run:\n  default: ask'; _d18b_ask="$(_first44),$(_x44 "r = opt(d, 'approve-run') is not None")"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1   # the fixture's autonomy.enabled: false
_d18b_off="$(_first44)"
assert_eq "D18b run.default ask, and autonomy.enabled false with no run.default, put ask-every-stage first and recommended" \
  "ask=ask-every-stage,True,True|enabled-false=ask-every-stage,True" "ask=$_d18b_ask|enabled-false=$_d18b_off"
_plan44 $'run:\n  default: never-unattended'
assert_eq "D18c run.default never-unattended offers no option that starts the unattended run" "none" \
  "$(_x44 "r = ','.join(o.get('id') for o in opts(d) if o.get('id') == 'approve-run' or any('run_mode autonomous' in c for c in o.get('calls') or [])) or 'none'")"
_plan44; riskH; _d18d_none="$(_x44 "r = opt(d, 'approve-run') is not None")"
_plan44; riskH; fresh_reviewed
"$TEMPER" evidence add --stage plan --phase fresh --claim '[readiness] Task 1: the plan never checks the input' --severity high \
  --label PROVEN >/dev/null 2>&1
_d18d_high="$(_x44 "r = opt(d, 'approve-run') is not None")"
_plan44; riskH; fresh_reviewed
for _l44 in readiness zoom-out comprehension tests; do   # risk H: reviewer B completes the round too (WP14)
  "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $_l44 B" \
    $([[ $_l44 == readiness ]] && echo "--value $(grep -c '^### Task' .temper/specs/demo/tasks.md)") >/dev/null 2>&1
done
_d18d_clean="$(_x44 "r = opt(d, 'approve-run') is not None")"
assert_eq "D18d at risk H approve-run needs a fresh round on the plan as it is with no open High finding" \
  "no-round=False|open-high=False|clean-round=True" "no-round=$_d18d_none|open-high=$_d18d_high|clean-round=$_d18d_clean"

# --- D19: an unattended run taken up again asks the question of its stage once, with every option ---
_nogit44; _unattended build; gpass build; "$TEMPER" state set run_mode interactive >/dev/null 2>&1
_d19_ids="$(_x44 "r = ','.join(sorted(str(o.get('id')) for o in opts(d)))")"
_unattended build; gpass build
"$TEMPER" go --taken-up >/dev/null 2>&1 || true
_d19_after="$(_x44 "r = '%s,%s' % (d.get('action'), (d.get('ask') or {}).get('id'))")"
_d19_got_ids="$(_x44 "r = ','.join(sorted(str(o.get('id')) for o in opts(d)))")"
assert_eq "D19 an unattended run taken up again records a stop and asks its stage's question with every option" \
  "stop=yes|asked=ask,build.pass|options=every" \
  "stop=$([[ -n "$("$TEMPER" state get parked 2>/dev/null)" ]] && echo yes || echo no)|asked=$_d19_after|options=$(python3 -c "import sys; a, b = (set(x.split(',')) for x in sys.argv[1:3]); print('every' if a <= b else 'missing ' + ','.join(sorted(a - b)))" "$_d19_ids" "$_d19_got_ids")"

# --- D22a, D22b: the approval card and the commit card, the same in the view, in next and as the CLI's text ---
_same44() { # "same" when next and the view hold one card object
  python3 - "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    n = json.loads(sys.argv[1])
    v = json.load(open(".temper/view.json"))
except (OSError, ValueError):
    n, v = {}, {}
print("same" if n.get("card") and n.get("card") == v.get("card") else "differs")
PY
}
fresh
sed -i 's|`src/demo.sh`|`src/demo.sh`, `src/auth/login.sh`|; s|^\*\*Validate:\*\* `true`|**Validate:** `sh -c "true \| cat"`|' .temper/specs/demo/tasks.md
# WP15: the fresh review of the plan is off, so the approval of the risk H plan is asked at once (at risk H the fresh
# review runs first, and the approval follows it)
printf 'plan:\n  fresh-review: off\n' >> .claude/temper.config
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" risk >/dev/null 2>&1
_d22a_text="$("$TEMPER" card 2>/dev/null)"
assert_eq "D22a the approval card is one object in next and the view, and its text holds the request, criteria, files, the sensitive path, risk H, commands and foot" \
  "approval|same|request|criteria|files|sensitive|risk H|commands|foot" \
  "$(_x44 "r = (d.get('card') or {}).get('kind')")|$(_same44)|$(python3 - "$_d22a_text" <<'PY'
import re, sys
t = sys.argv[1]
lines = t.splitlines()
out = ["request" if "the demo thing" in t else "no request",
       "criteria" if any("AC-01" in l and "demo criterion one" in l for l in lines) and any("AC-02" in l for l in lines) else "no criteria",
       "files" if "src/demo.sh" in t else "no files",
       "sensitive" if any("src/auth/login.sh" in l and re.search(r"sensitive", l, re.I) for l in lines) else "no sensitive line",
       "risk H" if re.search(r"risk H\b", t) else "no risk H",
       "commands" if 'sh -c "true | cat"' in t else "no commands",
       "foot" if "Nothing is pushed." in t else "no foot"]
print("|".join(out))
PY
)"
# WP15: the commit question of a run the person started at the approval, parked before the commit with one change
# uncommitted (a run that asks at every stage commits at its Check question, and at Commit the gate runs first)
_unattended commit; _ran_unattended; mkdir -p src; echo 'echo demo' > src/demo.sh; gpass commit
"$TEMPER" park --verdict SHIP-PENDING-COMMIT --reason 'every gate passed' >/dev/null 2>&1
_d22b_text="$("$TEMPER" card 2>/dev/null)"
_d22b_msg="$(_x44 "o = opt(d, 'commit') or {}; m = [re.search(r\"spec commit '([^']+)'\", c) for c in o.get('calls') or []]; r = next((x.group(1) for x in m if x), '')")"
assert_eq "D22b the commit card is one object in next and the view, and its text holds the criteria, the message the click uses and not pushed" \
  "commit|same|criteria|message|not pushed" \
  "$(_x44 "r = (d.get('card') or {}).get('kind')")|$(_same44)|$(python3 - "$_d22b_text" "$_d22b_msg" <<'PY'
import sys
t, msg = sys.argv[1], sys.argv[2]
print("|".join(["criteria" if "AC-01" in t else "no criteria", "message" if msg and msg in t else "no message",
                "not pushed" if "not pushed" in t else "no not pushed"]))
PY
)"

# --- D30b, D30c: rule 1, before the approval no branch and no commit ---
# the calls of the step: of the action, of every option of its question and before and after each launch
_d30b="cs = ' '.join(list(d.get('calls') or []) + [c for o in opts(d) for c in o.get('calls') or []]
  + [c for x in d.get('agents') or [] for c in (x.get('before') or []) + (x.get('after') or [])])
r = 'branch=%s|commit=%s' % ('yes' if 'spec branch' in cs else 'no', 'yes' if 'spec commit' in cs or 'git commit' in cs else 'no')"
assert_eq "check44: the reader of D30b sees a branch call before a launch and a commit call of a second option" \
  "branch=yes|commit=no branch=no|commit=yes" \
  "$(_x44 "$_d30b" '{"action": "work", "agents": [{"type": "temper:temper-plan", "before": ["temper spec branch demo"]}]}') $(
    _x44 "$_d30b" '{"action": "ask", "ask": {"options": [{"calls": []}, {"calls": ["temper spec commit x"]}]}}')"
fresh; _repo44; gpass intent
assert_eq "D30b the step that leaves Intent runs no branch call and no commit call" "branch=no|commit=no" "$(_x44 "$_d30b")"
fresh; _repo44; bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
echo 'echo early' > src/early.sh; git add src/early.sh >/dev/null 2>&1
assert_eq "D30c with the mod off a project file staged before the approval is not committed: the commit hook refuses it" \
  "refused|1" "$(git commit -q -m early >/dev/null 2>&1 && echo committed || echo refused)|$(git rev-list --count HEAD)"
git config --unset core.hooksPath 2>/dev/null

# --- D31a to D31f: rule 2, the approval is of what was shown ---
fresh; _repo44; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_d31a_calls="$(_calls44 ask-every-stage)"
sed -i 's/demo criterion one/demo criterion one, changed after the question/' .temper/specs/demo/intent.md
_d31a_adv=""
while IFS= read -r _c; do
  [[ -n "$_c" ]] || continue
  bash -c "$_c" >/dev/null 2>&1; _rc=$?
  # the calls that carry the digests shown compare them: the first (the run's mode, WP12) before anything is written
  [[ "$_c" == *"state advance plan_complete"* || "$_c" == *" --shown "* ]] && _d31a_adv="$_rc"
  [[ $_rc -eq 0 ]] || break
done <<<"$_d31a_calls"
assert_eq "D31a a criterion changed after the question was built: the approving advance is refused and the run stays at Plan" \
  "refused|plan" "$([[ -n "$_d31a_adv" && "$_d31a_adv" != 0 ]] && echo refused || echo "taken:$_d31a_adv")|$("$TEMPER" state get next_stage 2>/dev/null)"
_ROW44="intent unchanged since the approval"
_d31_gates() { local g o=""; for g in build check commit; do "$TEMPER" gate "$g" >/dev/null 2>&1; o+="$g=$(_row44 "$g" "$_ROW44")|"; done; echo "$o"; }
_approved44; sed -i 's/demo criterion one/demo criterion one, changed after the approval/' .temper/specs/demo/intent.md
_d31b_changed="$(_d31_gates)"
_approved44; "$TEMPER" intent accept >/dev/null 2>&1; "$TEMPER" intent complete >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1; _d31b_own="$(_row44 build "$_ROW44")"
assert_eq "D31b a criterion changed after the approval fails the Build, Check and commit gates; the CLI's own Status lines do not" \
  "build=False|check=False|commit=False|own=True" "${_d31b_changed}own=$_d31b_own"
_d31c=""
for _e in 'File:s|`src/demo.sh`|`src/demo.sh`, `src/extra.sh`|' 'Test:s|^\*\*Test:\*\* `true`|**Test:** `true; true`|' \
  'Validate:s|^\*\*Validate:\*\* `true`|**Validate:** `true; true`|'; do
  _approved44; sed -i "${_e#*:}" .temper/specs/demo/tasks.md
  "$TEMPER" gate build >/dev/null 2>&1; _d31c+="${_e%%:*}=$(_row44 build "$_ROW44")|"
done
_approved44; sed -i 's|^\*\*Test:\*\* `true`|**Test:** `true; true`|' .temper/specs/demo/tasks.md
_d31c+="check=$("$TEMPER" gate check >/dev/null 2>&1; _row44 check "$_ROW44")|commit=$("$TEMPER" gate commit >/dev/null 2>&1; _row44 commit "$_ROW44")"
assert_eq "D31c a changed File, Test or Validate line of tasks.md fails the gates too" \
  "File=False|Test=False|Validate=False|check=False|commit=False" "$_d31c"
_approved44
sed -i 's/demo criterion one/demo criterion one, changed after the approval/' .temper/specs/demo/intent.md
sed -i 's|^\*\*Test:\*\* `true`|**Test:** `true; true`|' .temper/specs/demo/tasks.md
_d31d_amend="$("$TEMPER" plan amend task 1 --add-file src/demo.sh >/dev/null 2>&1 && echo taken || echo refused)"
"$TEMPER" repair commit >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1; _d31d_repair="$(_row44 build "$_ROW44")"
_at review; "$TEMPER" state loop review build --reason 'rule: a finding' >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1; _d31d_loop="$(_row44 build "$_ROW44")"
"$TEMPER" integrate >/dev/null 2>&1 || true
"$TEMPER" gate build >/dev/null 2>&1; _d31d_integ="$(_row44 build "$_ROW44")"
_d31d_set="$("$TEMPER" state set intent_hash x >/dev/null 2>&1 && echo taken || echo refused),$("$TEMPER" state set plan_hash x >/dev/null 2>&1 && echo taken || echo refused)"
assert_eq "D31d no call a rule makes approves an edit: plan amend refuses, repair commit, state loop and integrate leave the row failing" \
  "amend=refused|repair=False|loop=False|integrate=False|set=refused,refused" \
  "amend=$_d31d_amend|repair=$_d31d_repair|loop=$_d31d_loop|integrate=$_d31d_integ|set=$_d31d_set"
_digests44() { _x44 "o = opt(d, 'approve-run') or opt(d, 'ask-every-stage') or {}; r = ' '.join(re.findall(r'--shown \S+', ' '.join(o.get('calls') or []))) or 'none'"; }
_d31e=""
_e44_task='- [x] done task\n\n### Task 2: more\n**File:** `src/demo.sh`\n**Test:** `true`'
_e44_said='- How long does the demo wait? -> two seconds (the person, 2026-01-01)'
_e44_said+='\n\n### Assumptions\n- The demo runs on one machine (because no rule was given)'
# every section of the card built from intent.md or tasks.md is shown: the demo intent gets an assumption and an answer
# of the person, as the Intent agent and scripts/answer_ops.py write them; launches counts the tasks of tasks.md
for _e in 'criteria:intent.md:s/demo criterion one/demo criterion one and more/' \
  'out_of_scope:intent.md:s/Out of scope: production behavior/Out of scope: production and staging/' \
  'assumptions:intent.md:s/runs on one machine/runs on two machines/' \
  'answers:intent.md:s/-> two seconds (the person/-> three seconds (the person/' \
  'files:tasks.md:s|`src/demo.sh`|`src/demo2.sh`|' \
  'commands:tasks.md:s|^\*\*Validate:\*\* `true`|**Validate:** `true; true`|' \
  "launches:tasks.md:s|^- \\[x\\] done task\$|$_e44_task|"; do
  fresh; sed -i "s/^### Decisions\$/### Decisions\n$_e44_said/" .temper/specs/demo/intent.md
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  _s="${_e%%:*}"; _f="${_e#*:}"; _f="${_f%%:*}"
  _shown="$(_x44 "r = 'shown' if section(d.get('card'), '$_s') else 'no section'")"
  _before="$(_digests44)"; sed -i "${_e#*:*:}" ".temper/specs/demo/$_f"; _after="$(_digests44)"
  _d31e+="$_s=$_shown,$([[ "$_before" != none && "$_before" != "$_after" ]] && echo changed || echo "$_after")|"
done
assert_eq "D31e an edit of the source line of a row of the approval card changes the digest the approving call carries" \
  "criteria=shown,changed|out_of_scope=shown,changed|assumptions=shown,changed|answers=shown,changed|$(
  )files=shown,changed|commands=shown,changed|launches=shown,changed|" "$_d31e"
fresh; sed -i 's/^\*\*Status:\*\* accepted/**Status:** draft/' .temper/specs/demo/intent.md
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gfail plan "tasks agree with decisions" "a task names no decision"
_d31f_skip="$(_calls44 override)"
_run44 override >/dev/null
_d31f_q="$(_x44 "r = (d.get('ask') or {}).get('id')")"
_run44 "$(_x44 "r = (opts(d) or [{}])[0].get('id')")" >/dev/null
assert_eq "D31f a skip of the plan gate never accepts a draft intent: intent.accept is asked, then the plan question offers no approve-run" \
  "skip-accepts=no|asked=intent.accept|approve-run=absent" \
  "skip-accepts=$([[ "$_d31f_skip" == *"intent accept"* ]] && echo yes || echo no)|asked=$_d31f_q|approve-run=$(_x44 "r = 'present' if opt(d, 'approve-run') else 'absent'")"

# --- D32a, D32b, D32d, D32e: rule 3, only an option the person picked starts an unattended run ---
_views44() { # every fixture view, as JSON lines: {"name": ..., "view": ...}
  python3 - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" "$REPO_ROOT/scripts/selftest/view-fixtures-2.ts" <<'PY'
import json, re, sys
for f in sys.argv[1:]:
    for line in open(f, encoding="utf-8"):
        m = re.match(r'^\s*"([^"]+)": (\{.*\}),?\s*$', line)
        if m:
            print(json.dumps({"name": m.group(1), "view": json.loads(m.group(2))}))
PY
}
assert_eq "D32a no action of the CLI's own in any fixture view sets the unattended mode" "ok" \
  "$(_views44 | python3 -c "
import json, sys
n, bad = 0, []
for line in sys.stdin:
    v = json.loads(line); x = v['view'].get('next') or {}
    if x.get('action') not in ('auto', 'work'):
        continue
    n += 1
    calls = list(x.get('calls') or []) + [c for a in x.get('agents') or [] for c in (a.get('before') or []) + (a.get('after') or [])]
    bad += [v['name'] for c in calls if 'run_mode autonomous' in c or 'unattended_from' in c]
print('ok' if n >= 5 and not bad else 'views %d, setting it: %s' % (n, ','.join(bad)))")"
_nogit44; _unattended build; "$TEMPER" state loop build plan --reason x >/dev/null 2>&1; _d32b_plan="$("$TEMPER" state get run_mode 2>/dev/null)"
_unattended build; "$TEMPER" state set next_stage intent >/dev/null 2>&1; _d32b_intent="$("$TEMPER" state get run_mode 2>/dev/null)"
assert_eq "D32b after a step back to Plan or Intent the run asks at every stage" "plan=interactive|intent=interactive" \
  "plan=$_d32b_plan|intent=$_d32b_intent"
_unattended check; gfail check "tests pass" "the latest run of a test command failed: unit"
"$TEMPER" override check --reason 'the flaky suite is known' >/dev/null 2>&1; _d32d_skip="$("$TEMPER" state get run_mode 2>/dev/null)"
_unattended review
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence accept --stage review --id 1 --reason 'known and tracked' >/dev/null 2>&1; _d32d_accept="$("$TEMPER" state get run_mode 2>/dev/null)"
assert_eq "D32d with the mod off a skip and an accepted finding end the unattended run" "skip=interactive|accept=interactive" \
  "skip=$_d32d_skip|accept=$_d32d_accept"
_arm44() { # the session types the call that starts the unattended run: was it taken, and the mode after
  printf '%s,%s' "$("$TEMPER" state set run_mode autonomous >/dev/null 2>&1 && echo taken || echo refused)" "$("$TEMPER" state get run_mode 2>/dev/null)"
}
fresh; gpass intent plan build; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_d32e="build=$(_arm44)|"
"$TEMPER" state set run_mode interactive >/dev/null 2>&1; gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
_d32e+="review=$(_arm44)|"
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gfail plan "tasks agree with decisions" "x"
"$TEMPER" override plan --reason 'skip it' >/dev/null 2>&1; _d32e+="plan-skipped=$(_arm44)|"
_plan44 $'run:\n  default: never-unattended'; _d32e+="never=$(_arm44)|"
_d32e+="unattended_from=$("$TEMPER" state set unattended_from build >/dev/null 2>&1 && echo taken || echo refused)|"
fresh; python3 -c "
import json
p = '.temper/build-state.json'; d = json.load(open(p)); d['run_mode'] = 'autonomous'; d.pop('unattended_from', None)
json.dump(d, open(p, 'w'), indent=2)"
_d32e+="saved=$("$TEMPER" state get run_mode 2>/dev/null)"
assert_eq "D32e the session's own call cannot start the unattended run, and a saved autonomous mode with no start reads as interactive" \
  "build=refused,interactive|review=refused,interactive|plan-skipped=refused,interactive|never=refused,interactive|unattended_from=refused|saved=interactive" \
  "$_d32e"

# --- D33a, D33b, D33f: rule 4, an unattended run never passes a stop by rule ---
_FORBID44='state loop \S+ (plan|intent)|plan patch|override|evidence accept|doctor .*--write|git push|gh pr|spec commit .* -- |git commit'
_back44() { # a failed group check of an unattended run whose way on is a step back to Plan (its one fix was spent)
  _unattended build
  _g44 "$(printf "$_GROUP44" '"fails": 2, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}')"
}
_foreign44() { # _foreign44 [kept]: Build's merge found a commit the CLI did not make on group G1's branch
  _unattended build
  _g44 '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "branch": "temper/demo/G1", "confirmed": true, "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "FAIL", "foreign": {"G1": ["abc1234def5678"]}}}'
  [[ -z "${1:-}" ]] || printf '[{"stage": "foreign-commit:G1:abc1234def5678", "reason": "kept", "by": "person"}]\n' > .temper/overrides.json
}
_finding_again44() { # an unattended Review whose blocking finding is still open after its one loop back
  _unattended review
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
  "$TEMPER" state loop review build --reason 'rule: repair 1 open finding' >/dev/null 2>&1
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
  gfail review "no blocking findings" "1 open high finding"
}
_drift44() { # a pending scope drift of a fix pass, then what next does. Where the CLI has no `drift ask` yet, the drift
             # question is the page's (the view's drift entry), and the state is the failed Build the fix pass answers
  _unattended build
  if ! "$TEMPER" drift ask --path src/outside.sh --why 'the fix needs it' --change 'one line' >/dev/null 2>&1; then
    gfail build "integration" "the merged groups fail: unit"
    printf '%s' "$(vw "'' if d.get('drift', {}).get('id') == 'scope.drift' else 'no drift question '")"
  fi
  _stop44 "$_FORBID44|phase feedback --claim .?drift"
}
_walk44() { # _walk44 <stop id>: the state of that stop in an unattended run, then what next does there
  _nogit44
  case "$1" in
    design.tasks-changed) _unattended design; gpass design
      printf '\n### Task 2: more\n**File:** `src/more.sh`\n**Depends:** none\n**Test:** `true`\n**Cases:**\n- more\n- [ ] done\n' >> .temper/specs/demo/tasks.md
      _stop44 "$_FORBID44" ;;
    design.concerns) _unattended design
      printf '# Design\n\n## Areas of Concern\n- The token store may race under load\n' > .temper/specs/demo/design.md
      gpass design; _stop44 "$_FORBID44" ;;
    gate.failed|person.step-back) _unattended build; gfail build "RED then GREEN" "have red=0 green=0"; _stop44 "$_FORBID44|next_stage" ;;
    task.manual|person.task-confirm) _unattended build
      sed -i 's|^\*\*Test:\*\* `true`|**Test:** manual|; s|^- \[x\] done task|- [ ] done task|' .temper/specs/demo/tasks.md
      _g44 '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1"}}, "tasks": {"1": {"status": "running", "group": "G1", "awaiting": "confirm"}}}'
      _stop44 "$_FORBID44|task (confirm|accept)" ;;
    build.foreign|person.accept-foreign) _foreign44; _stop44 "$_FORBID44|accept-foreign" ;;
    build.remerge) _foreign44 kept; _stop44 "$_FORBID44|integrate" ;;
    group.parked) _unattended build
      _g44 '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "branch": "temper/demo/G1", "parked_reason": "Task 1 is out of attempts"}}, "tasks": {"1": {"status": "failed", "group": "G1"}}}'
      _stop44 "$_FORBID44" ;;
    group.fail-typed) _unattended build
      _g44 "$(printf "$_GROUP44" '"fails": 1, "fix_tries": 1, "fix_empty": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: make test", "ran": true, "timeout_s": 600, "fail_lines": ["x"]}')"
      _stop44 "$_FORBID44" ;;
    group.fail-back|person.loop) _back44; _stop44 "$_FORBID44|state (init|clear|archive)" ;;
    task.env) _unattended build; sed -i 's|^- \[x\] done task|- [ ] done task|' .temper/specs/demo/tasks.md
      _g44 '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1"}}, "tasks": {"1": {"status": "running", "group": "G1", "env_fault": {"reason": "the JDK is 21 and pom.xml needs 24"}}}}'
      _stop44 "$_FORBID44" ;;
    build.ungrouped) _unattended build
      printf '# Tasks: demo\n\n### Task 1: one\n**File:** `src/demo.sh`\n**Depends:** none\n**Test:** `true`\n**Cases:**\n- a\n- [ ] done\n' > .temper/specs/demo/tasks.md
      _stop44 "$_FORBID44" ;;
    scope.drift) _drift44 ;;
    review.unfinished) _unattended review; gfail review "review completed" "no review completed row"; _stop44 "$_FORBID44" ;;
    check.setup) _unattended check
      ev_red check 'tests: the suite (run by the CLI)'
      "$TEMPER" evidence add --stage check --claim 'setup fault: the JDK is 21 and pom.xml needs 24' --exit 1 >/dev/null 2>&1
      gfail check "tests pass" "the latest run of a test command failed: the suite"; _stop44 "$_FORBID44|doctor" ;;
    check.person-criterion) _unattended check; sed -i '0,/Validate: scenario/s//Validate: manual/' .temper/specs/demo/intent.md
      gfail check "acceptance evidence" "AC-01 has no supported passing evidence row"; _stop44 "$_FORBID44|state loop" ;;
    budget.spent|person.budget-grant) _unattended check   # WP10: the third repeat for one failure is no call the run makes
      for _i44 in 1 2; do gfail check "tests pass" "unit failed"; "$TEMPER" state redo check --reason x >/dev/null 2>&1; done
      gfail check "tests pass" "unit failed"; _stop44 "$_FORBID44|state (redo|loop) check|budget grant" ;;
    commit.always|person.adhoc-open) _unattended commit; gpass commit; _stop44 "$_FORBID44|adhoc open" ;;
    commit.fail) _unattended commit; gfail commit "files changed outside the plan" "src/outside.sh is in no task"
      _stop44 "$_FORBID44|evidence add" ;;
    plan.after-back|person.arm) _unattended build; "$TEMPER" state loop build plan --reason 'the plan cannot be built' >/dev/null 2>&1
      gpass plan; _stop44 "$_FORBID44|run_mode autonomous|state advance plan_complete" ;;
    person.override) _unattended check
      gfail check "tests pass" "no passing test-run evidence recorded"; _stop44 "$_FORBID44" ;;
    person.plan-review) _unattended plan
      printf '# Plan\n\n## Context Map\n- use: intent.md AC-01..AC-02 - the scope\n- gap: no rate limit policy found in code or docs\n- reviewed: pending\n' \
        > .temper/specs/demo/plan.md
      gpass plan; _stop44 "$_FORBID44|plan review" ;;
    person.acceptance-reopen) _unattended check
      gfail check "acceptance tests written before Build" "the locked acceptance tests fail: 1 of 2"; _stop44 "$_FORBID44|acceptance reopen" ;;
    person.branch) _unattended plan; _repo44; git checkout -q -b feature/demo; echo 'echo old' > src/old.sh; git add src/old.sh
      git commit -q -m 'an earlier run'; git checkout -q master; gpass plan; _stop44 "$_FORBID44|state set branch|spec branch" ;;
    person.evidence-accept) _finding_again44; _stop44 "$_FORBID44|evidence clear" ;;
    person.leave-intent-plan) _unattended plan; gpass plan; _stop44 "$_FORBID44|state advance (intent|plan)_complete" ;;
    plan.sensitive-path) _unattended build   # WP11 stop 20: the plan declares a file under a sensitive path
      sed -i 's|^\*\*File:\*\* `src/demo.sh`$|**File:** `src/demo.sh`, `src/auth/login.sh`|' .temper/specs/demo/tasks.md
      _g44 "$(printf "$_GROUP44" '"fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}')"
      _stop44 "$_FORBID44|group (fix|reopen)" ;;
    approval.changed) _approved_run44; _at check   # WP12: the row failed
      sed -i 's/demo criterion one/demo criterion one, changed after the approval/' .temper/specs/demo/intent.md
      gfail check "intent unchanged since the approval" "intent.md changed since the approval"
      _armed44 "$_FORBID44|state loop" ;;
    run.taken-up) _unattended build; gpass build   # WP11 stop 22: the run taken up again asks its stage once
      "$TEMPER" go --taken-up >/dev/null 2>&1; _stop44 "$_FORBID44|state advance" ;;
    base.red|person.baseline) _unattended build   # WP20: a red base nobody answered; WP21: its skip is the person's
      printf '{"result": "red", "kind": "red-base", "why": "make test exited 1", "exit_code": 1, "fail_lines": ["FAIL: test_a"], "env": []}\n' \
        > .temper/evidence/baseline.json
      _stop44 "$_FORBID44|baseline (accept-red|skip)" ;;
    plan.command) _unattended build   # WP21: a command the plan wrote fails on the base, the result after the approval
      printf '{"result": "green", "seconds": 1, "plan": {"true": {"result": "fail", "exit": 1, "seconds": 1, "class": "command", "kind": "fails-on-base", "why": "exit 1", "fail_lines": ["FAIL: test_a"], "tail": ""}}}\n' \
        > .temper/evidence/baseline.json
      _stop44 "$_FORBID44|baseline (skip|timeout)|state (loop|redo) \S+ plan" ;;
    repair.contested|repair.outside-plan|repair.sensitive|repair.unfinished|repair.environment|repair.unmeasured|\
    repair.person-criterion|repair.acceptance-test)   # WP24: the never by rule list, each state as D05b builds it
      _d05 "$(sed 's/^repair\.//; s/^outside-plan$/outside/; s/^person-criterion$/person/; s/^acceptance-test$/acceptance/' <<<"$1")" \
        | cut -d, -f1 ;;
    repair.tests-removed|repair.worse) _unattended review   # WP24: what a repair asks (repair.stop) is a stop, never passed
      "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
      gfail review "no blocking findings" "1 open high finding"
      python3 -c "
import json, sys
p = '.temper/build-state.json'; d = json.load(open(p))
d['repair_stop'] = {'kind': 'tests' if sys.argv[1] == 'repair.tests-removed' else 'worse', 'why': 'repair 1 at Review: ' + sys.argv[1],
                    'n': 1, 'stage': 'review', 'lines': ['src/demo_test.sh: b=2']}
json.dump(d, open(p, 'w'), indent=2)" "$1"
      _stop44 "$_FORBID44|repair (start|commit|revert)" ;;
    config.tidy) _unattended build   # WP29: an unattended run on a config of 9.8.4: no rule tidies it, the CLI refuses
      python3 -I -c 'import json, sys; sys.stdout.write(json.load(open(sys.argv[1]))["7c7a1c1"]["template"].replace("@PLUGIN@", sys.argv[2]))' \
        "$TESTS_DIR/saved-old.json" "$REPO_ROOT" > .claude/temper.config
      local cfg44 out44 rc44; cfg44="$(cat .claude/temper.config)"
      out44="$(_stop44 "$_FORBID44|config tidy")"
      "$TEMPER" config tidy --apply >/dev/null 2>&1; rc44=$?
      if [[ "$out44" != *" runs "* && $rc44 -eq 1 && "$(cat .claude/temper.config)" == "$cfg44" && ! -e .claude/temper.config.before-9.8.5 ]]
      then echo stop; else echo "$out44; config tidy --apply exit $rc44 by the session"; fi ;;
    *) echo "no state is built for this stop" ;;
  esac
}
_d33a_got=""; _d33a_want=""
for _id in $(python3 -c 'import json, sys; print(" ".join(s["id"] for s in json.load(open(sys.argv[1]))["stops"]))' "$REPO_ROOT/scripts/stops.json"); do
  _d33a_want+="$_id=stop|"; _d33a_got+="$_id=$(_walk44 "$_id")|"
done
assert_eq "D33a every stop of scripts/stops.json, built in an unattended run, is a question or a recorded stop" "$_d33a_want" "$_d33a_got"
assert_eq "D33b no auto action of a fixture view runs a call an unattended run may never make" "ok" \
  "$(_views44 | python3 -c "
import json, re, sys
bad = re.compile(sys.argv[1])
n, hits = 0, []
for line in sys.stdin:
    v = json.loads(line); x = v['view'].get('next') or {}
    if x.get('action') != 'auto':
        continue
    n += 1
    hits += ['%s: %s' % (v['name'], c[-60:]) for c in x.get('calls') or [] if bad.search(c)]
print('ok' if n >= 1 and not hits else 'auto views %d; %s' % (n, '; '.join(hits)))" "$_FORBID44")"
_d33f() { # _d33f <temptation>: its state in an unattended run, then what next does
  _nogit44
  case "$1" in
    group-back) _back44 ;;
    base-validate) _unattended build
      printf '{"result": "green", "seconds": 1, "plan": {"true": {"result": "fail", "exit": 1, "seconds": 1, "class": "command", "kind": "fails-on-base", "why": "exit 1", "fail_lines": ["FAIL: test_a"], "tail": ""}}}\n' \
        > .temper/evidence/baseline.json ;;
    criterion) _approved_run44
      sed -i 's/demo criterion one/demo criterion one, changed after the approval/' .temper/specs/demo/intent.md
      "$TEMPER" gate build >/dev/null 2>&1
      _armed44 "$_FORBID44"; return ;;
    blocked) _unattended build; sed -i 's|^- \[x\] done task|- [ ] done task|' .temper/specs/demo/tasks.md
      _g44 '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "branch": "temper/demo/G1", "parked_reason": "Task 1 is blocked: its test needs src/nobody.sh"}}, "tasks": {"1": {"status": "failed", "group": "G1", "blocked": {"needs": "src/nobody.sh", "owners": [], "reason": "the test needs it", "ts": "2026-01-01T00:00:00Z"}}}}' ;;
    budget) _unattended check
      # WP21: each step back is from a failed check, so it spends the budget (one from a passed gate spends nothing)
      for _i in 1 2; do
        gfail check "tests pass" "the latest run of a test command failed: unit"
        "$TEMPER" state loop check build --reason 'rule: tests fail' >/dev/null 2>&1; gpass build review
        "$TEMPER" state advance build_complete review >/dev/null 2>&1; "$TEMPER" state advance review_complete check >/dev/null 2>&1
      done
      gfail check "tests pass" "the latest run of a test command failed: unit" ;;
    finding) _finding_again44 ;;
    drift) _drift44; return ;;
    red-base) _unattended build
      printf '<project><properties><maven.compiler.release>24</maven.compiler.release></properties></project>\n' > pom.xml
      printf '{"result": "red", "kind": "tool-version", "why": "pom.xml needs JDK 24; the shell has 21", "fail_lines": [], "env": [{"kind": "tool-version", "file": "pom.xml", "need": "24", "have": "21"}]}\n' \
        > .temper/evidence/baseline.json ;;
    passed-check) _unattended check; gpass check; _auto44; [[ "$("$TEMPER" state get next_stage 2>/dev/null)" == commit ]] && gpass commit ;;
  esac
  _stop44 "$_FORBID44"
  rm -f pom.xml
}
_d33f_got=""; _d33f_want=""
for _t in group-back base-validate criterion blocked budget finding drift red-base passed-check; do
  _d33f_want+="$_t=stop|"; _d33f_got+="$_t=$(_d33f "$_t")|"
done
assert_eq "D33f each temptation built here leaves an unattended run at a question or a recorded stop" "$_d33f_want" "$_d33f_got"

# --- D34a to D34d: rule 5, every verdict is computed by the CLI from runs it made and names its tree ---
_tests_row44() { # the row of Check's verdict that says the tests pass
  _row44 check "$(python3 -c "
import json
e = json.load(open('.temper/gates.json')).get('check') or {}
print(next((x['name'] for x in e.get('requirements') or [] if x.get('name', '').startswith('tests')), 'tests pass'))" 2>/dev/null)"
}
fresh; sed -i '/^evidence:$/d; /claimed-runs:/d' .claude/temper.config; gpass intent plan build review; _at check
"$TEMPER" evidence add --stage check --claim 'tests: unit' --exit 0 >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_d34a_default="$(_tests_row44)"
fresh; sed -i '/^evidence:$/d; /claimed-runs:/d' .claude/temper.config   # WP30: the key written here, so the half stays a
printf 'evidence:\n  claimed-runs: count\n' >> .claude/temper.config        # case of it when the selftest's config drops it
gpass intent plan build review; _at check
"$TEMPER" evidence add --stage check --claim 'tests: unit' --exit 0 >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
assert_eq "D34a a test run recorded with evidence add passes no row, and evidence.claimed-runs: count changes nothing" \
  "default=False|count=False" "default=$_d34a_default|count=$(_tests_row44)"
_tree44() { python3 -c "import json; print(json.load(open('.temper/gates.json')).get('$1', {}).get('tree'))" 2>/dev/null; }
fresh; _repo44; gpass intent plan build review; _at check
"$TEMPER" gate build >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_d34b_all="$(python3 -c "
import json
g = json.load(open('.temper/gates.json'))
print(all(isinstance(g.get(k), dict) and g[k].get('tree') for k in ('build', 'check')))")"
_d34b_t1="$(_tree44 check)"
echo 'echo demo changed' > src/demo.sh; "$TEMPER" gate check >/dev/null 2>&1; _d34b_t2="$(_tree44 check)"
assert_eq "D34b every verdict names the tree it judged, and an edit of a tracked file changes the tree of the next verdict" \
  "trees=True|changed=True" "trees=$_d34b_all|changed=$([[ "$_d34b_t1" != None && "$_d34b_t1" != "$_d34b_t2" ]] && echo True || echo False)"
fresh; _repo44; gpass intent plan build review; _at check; "$TEMPER" gate check >/dev/null 2>&1
python3 -c "
import json
p = '.temper/gates.json'; g = json.load(open(p)); g['check']['verdict'] = 'PASS'
for x in g['check'].get('requirements') or []:
    x['pass'] = True
json.dump(g, open(p, 'w'))"
_d34c_tree="$(_tree44 check)"
"$TEMPER" state advance check_complete commit >/dev/null 2>&1
echo 'echo demo after check' > src/demo.sh; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "D34c a file changed after Check passed fails the commit gate with a row that names both trees" "FAIL|both trees" \
  "$(python3 - "$_d34c_tree" <<'PY'
import json, re, sys
t = sys.argv[1] if sys.argv[1] != "None" else ""
e = json.load(open(".temper/gates.json")).get("commit") or {}
rows = [x for x in e.get("requirements") or [] if x.get("pass") is False]
both = any(t and t[:7] in str(x.get("detail")) and len(set(re.findall(r"\b[0-9a-f]{7,64}\b", str(x.get("detail"))))) >= 2 for x in rows)
print("%s|%s" % (e.get("verdict"), "both trees" if both else "no row names both trees"))
PY
)"
_review44() { # _review44 <files read...>: the row review completed for a change of three files whose completion row names them
  fresh; _repo44; "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
  echo a > src/a.sh; echo b > src/b.sh; echo c > src/c.sh; git add src; git commit -q -m change
  gpass intent plan build; _at review
  local f args=()
  for f in "$@"; do args+=(--read "$f"); done
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC "${args[@]}" >/dev/null 2>&1
  "$TEMPER" gate review >/dev/null 2>&1
  _row44 review "review completed"
}
assert_eq "D34d a Review whose completion row names fewer files than the change holds fails the row review completed" \
  "short=False|whole=True" "short=$(_review44 src/a.sh)|whole=$(_review44 src/a.sh src/b.sh src/c.sh)"

# --- D35a to D35e: rule 6, a failure's class picks the next step, never a verdict ---
_classes44() { python3 -c "
import json
try:
    f = json.load(open('.temper/evidence/failures.json'))
except (OSError, ValueError):
    f = []
print(','.join(sorted({x.get('class') for x in f if isinstance(x, dict) and x.get('class')})) or 'none')"; }
_suite44 125
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_d35a="class=$(_classes44)|verdict=$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['check']['verdict'])")"
"$TEMPER" state loop check plan --reason 'the plan cannot be built' >/dev/null 2>&1
assert_eq "D35a a failure of class environment leaves its gate FAIL, and its record outlives a step back to Plan" \
  "class=environment|verdict=FAIL|after-back=environment" "$_d35a|after-back=$(_classes44)"
fresh; _repo44; printf '[package]\nname = "demo"\nversion = "0.1.0"\n' > Cargo.toml   # no coverage tool for the stack
mkdir -p .temper/bin44; printf '#!/bin/sh\nexit 0\n' > .temper/bin44/cargo; chmod +x .temper/bin44/cargo
gpass intent plan build review; _at check
PATH="$WORKDIR/.temper/bin44:$PATH" "$TEMPER" check run >/dev/null 2>&1; PATH="$WORKDIR/.temper/bin44:$PATH" "$TEMPER" gate check >/dev/null 2>&1
_covrow44() { python3 -c "
import json
e = json.load(open('.temper/gates.json')).get('check') or {}
r = next((x for x in e.get('requirements') or [] if x.get('name', '').startswith('coverage')), {})
print('%s:%s' % (r.get('pass'), r.get('state')) if r.get('state') else r.get('pass'))"; }
assert_eq "D35b a missing coverage tool is not measured in the gate, the view and the commit card" \
  "gate=None:not measured|view=not measured|card=not measured" \
  "gate=$(_covrow44)|view=$(vw "next((x.get('state') for x in d.get('checks') or [] if str(x.get('name', '')).startswith('coverage')), None)")|card=$(_x44 "s = section(d.get('card'), 'coverage'); r = 'not measured' if s and any('not measured' in x.get('text', '') for x in s.get('rows') or []) else 'no coverage row'")"
rm -f Cargo.toml
_mut44() { # _mut44 <with|without>: Check's verdict and its failed rows, then next's action and calls, with or without a
           # planted bug score of 4 of 10 in .temper/evidence/mutation.json (of this tree) and of 40 in Check's ledger
  fresh; gpass intent plan build review; _at check
  [[ "$1" == with ]] && "$TEMPER" evidence add --stage check --claim 'mutation score' --value 40 >/dev/null 2>&1
  [[ "$1" == with ]] && python3 -B -c "
import os, sys
sys.path.insert(0, sys.argv[1])
import check_run, run_env
check_run.planted_write(os.getcwd(), run_env.tree_key(os.getcwd(), root=os.getcwd()), 'measured', ran=10, caught=4)
None if check_run.planted(os.getcwd()) else print('the score is not of this tree')" "$REPO_ROOT/scripts"
  "$TEMPER" gate check >/dev/null 2>&1
  python3 -c "
import json
e = json.load(open('.temper/gates.json')).get('check') or {}
print('%s:%s' % (e.get('verdict'), ','.join(x['name'] for x in e.get('requirements') or [] if x.get('pass') is False)))"
  nx "d['action'] + '|' + ' '.join(d.get('calls') or [])"
}
_d35c_with="$(_mut44 with)"; _d35c_without="$(_mut44 without)"
assert_eq "D35c the planted bug score fails nothing and moves nothing" "mutation rows=0|same=True" \
  "mutation rows=$(grep -o 'mutation' <<<"$_d35c_with" | wc -l | tr -d ' ')|same=$([[ "$_d35c_with" == "$_d35c_without" ]] && echo True || echo False)"
_cov44() { # _cov44 <coverage command>: Check with a passing suite and that coverage command; prints the coverage row
  fresh; printf 'check:\n  commands:\n    test: "true"\n    coverage: %s\n' "$1" >> .claude/temper.config
  gpass intent plan build review; _at check
  "$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
  _covrow44
}
assert_eq "D35d a missing coverage tool is told by exit 127, never by the words of its output" "text=True|exit127=None:not measured" \
  "text=$(_cov44 "\"echo 'coverage: command not found'; echo 'TOTAL 10 1 90%'\"")|exit127=$(_cov44 '"exit 127"')"
_red44() { # _red44 <test command>: a red base the person passed with go-on-anyway, then a Check whose suite is that command
  fresh; _repo44; printf 'check:\n  commands:\n    test: "%s"\n' "$1" >> .claude/temper.config
  printf '{"result": "red", "kind": "red-base", "why": "1 test fails on the base", "fail_lines": ["FAIL: test_a"], "seconds": 1}\n' \
    > .temper/evidence/baseline.json
  "$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
  gpass intent plan build review; _at check
  "$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1; _row44 check "tests pass"
}
assert_eq "D35e a red base passed with go-on-anyway is a recorded skip: its old failing lines are skipped, a new one fails the row" \
  "old=None:skipped|new=False" "old=$(_red44 'echo FAIL: test_a; exit 1')|new=$(_red44 'echo FAIL: test_a; echo FAIL: test_b; exit 1')"
