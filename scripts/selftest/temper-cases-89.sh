# Case file 89 (round 2 of the adversarial review, reviewer 1): the fixes of rules 1, 2, 3, 4 and 11 and of the upgrade,
# broken again. Each check fails on the code under review and names the rule it holds. Sourced by test-temper.sh; its
# helpers (setup, fresh, gpass, _base_known) are used here. Every assertion name starts with "round 2 reviewer 1:".
# A call that may fail stays inside $( ... ) or ends in || true, so the file always runs to its end.

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

