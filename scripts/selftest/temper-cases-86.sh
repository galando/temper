# Case file 86 (review 6 of the adversarial review of 9.8.5): rule 11, every rule again with the mod off. Each check
# drives the real CLI, the classic hooks and the native commit hook in a throwaway project, with no mod loaded, and makes
# the violating act a session could make there. Sourced by test-temper.sh; its helpers (setup, fresh, gpass, _unattended,
# _base_known) are used here. Every assertion name starts with "review 6:".
# A call the CLI does not have stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_repo86() { # a git repository under the run, on master: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_hold86() { # _hold86 <tool> <path>: what the classic hook hold_before_approval.py answers for a write of <path>: deny or allow
  local out
  out="$(printf '{"tool_name": "%s", "tool_input": {"file_path": "%s"}, "cwd": "%s"}' "$1" "$2" "$PWD" \
    | python3 -I "$REPO_ROOT/scripts/guards/hold_before_approval.py" 2>/dev/null)"
  if grep -c '"deny"' >/dev/null <<<"$out"; then echo deny; else echo allow; fi
}
_row86() { # _row86 <stage> <row name>: the detail of that row of the stage's verdict in gates.json, or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    g = json.load(open(".temper/gates.json"))
except (OSError, ValueError):
    g = {}
rows = [r for r in (g.get(sys.argv[1]) or {}).get("requirements") or [] if r.get("name") == sys.argv[2]]
print("%s:%s" % (rows[0].get("pass"), rows[0].get("detail")) if rows else "absent")
PY
}

# --- review 6: base_sha, the commit the run's diff is read against, is a CLI call the mod alone holds to its form ---
# The mod refuses `state set base_sha` but as a commit id (or $(git rev-parse HEAD)) at Plan or Build (rules.ts KEY_DENY);
# the CLI takes any word at any stage before plan_complete records one, and plan_complete keeps it. A session with the mod
# off types `temper state set base_sha HEAD` at Intent: from then on every diff the gates read is against the moving
# HEAD, so a commit the hook lets through mid Build (a checkpoint with a green test run) drops out of Review's file list
# and out of the commit gate's scope row. docs/trust.md names no such limit.
fresh; _repo86
"$TEMPER" state set base_sha HEAD >/dev/null 2>&1; _r6_set=$?
assert_eq "review 6: base_sha a symbolic name typed at Intent with the mod off is refused (only a commit id, recorded by plan_complete)" \
  "refused" "$([[ $_r6_set -ne 0 ]] && echo refused || echo "taken:$("$TEMPER" state get base_sha 2>/dev/null)")"
gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
git checkout -q -B feature/demo 2>/dev/null
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo 'echo outside' > src/outside.sh; git add src/outside.sh
"$TEMPER" evidence run --stage build --phase green --claim "test passes" -- true >/dev/null 2>&1
git commit -q -m 'a checkpoint the hook lets through' >/dev/null 2>&1
git config --unset core.hooksPath 2>/dev/null
_r6_review="$("$TEMPER" review files 2>/dev/null | paste -sd, -)"
gpass build review check; _at commit
"$TEMPER" gate commit >/dev/null 2>&1
assert_eq "review 6: base_sha an out of plan file committed mid Build is still a changed file: Review must read it and the scope row fails" \
  "review=src/outside.sh|blast=False" "review=$_r6_review|blast=$(_row86 commit "blast radius" | cut -d: -f1)"

# The same steps with no base_sha call: the run's own base (plan_complete) sees the file, so the check above is sound.
fresh; _repo86; gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
git checkout -q -B feature/demo 2>/dev/null
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo 'echo outside' > src/outside.sh; git add src/outside.sh
"$TEMPER" evidence run --stage build --phase green --claim "test passes" -- true >/dev/null 2>&1
git commit -q -m 'a checkpoint the hook lets through' >/dev/null 2>&1
git config --unset core.hooksPath 2>/dev/null
_r6_review="$("$TEMPER" review files 2>/dev/null | paste -sd, -)"
gpass build review check; _at commit
"$TEMPER" gate commit >/dev/null 2>&1
assert_eq "review 6: base_sha control: with the base plan_complete records, the same checkpoint is read by Review and fails the scope row" \
  "commits=2|review=src/outside.sh|blast=False" "commits=$(git rev-list --count HEAD)|review=$_r6_review|blast=$(_row86 commit "blast radius" | cut -d: -f1)"

# --- review 6: budget, only the person grants more repeats, and only at the question that asks for them ---
# The CLI refuses Run it anyway (--fresh) in a run that goes on by itself (budget.py spend), but takes `budget grant` from
# any caller at any time: an unattended run with no failure and no question open grants itself two more repeats a call,
# and stays unattended. With the mod off nothing refuses it (rules.ts personOnly is the only holder).
_unattended build
_r6_lim() { "$TEMPER" budget room gate:build 2>/dev/null | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print("%s/%s" % (d.get("limit"), d.get("run_limit")))' 2>/dev/null; }
_r6_before="$(_r6_lim)"
"$TEMPER" budget grant --key gate:build --reason 'the session says so' >/dev/null 2>&1; _r6_grant=$?
assert_eq "review 6: budget an unattended run with no failure and no question open cannot grant itself more repeats" \
  "refused|autonomous|limits 2/6 -> 2/6" \
  "$([[ $_r6_grant -ne 0 ]] && echo refused || echo granted)|$("$TEMPER" state get run_mode 2>/dev/null)|limits $_r6_before -> $(_r6_lim)"

# --- review 6: rule 8, a finding is resolved only by the CLI; a ledger cleared by a session resolves nothing ---
# `temper evidence clear --stage S` empties a stage's ledger with no check of stage, mode or open finding, and no question
# of the flow offers it: only the mod refuses it (rules.ts personOnly, "clearing a ledger ... is the person's"), and
# neither docs/trust.md nor docs/mod.md names it. With the mod off a session at a failed Review clears the ledger, writes
# the completion row again, and the Review gate passes with the blocking finding gone, in a run that goes on by itself.
_review86() { # a run that goes on by itself, approved and built, at a failed Review with one high finding on src/demo.sh
  fresh; _repo86; sed -i '/block-on/d' .claude/temper.config
  printf 'a=1\n' > src/demo_test.sh; git add src/demo_test.sh; git commit -q -m tests
  git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  echo 'echo changed' > src/demo.sh
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase red -- false >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase green -- true >/dev/null 2>&1
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
  review_done
  "$TEMPER" gate review >/dev/null 2>&1
}
_verdict86() { python3 -c "import json,sys; print((json.load(open('.temper/gates.json')).get(sys.argv[1]) or {}).get('verdict', 'none'))" "$1" 2>/dev/null || echo none; }
_review86
_r6_at="$(_verdict86 review):findings=$(_row86 review "no blocking findings" | cut -d: -f1)|$("$TEMPER" state get run_mode 2>/dev/null)|$("$TEMPER" state get next_stage 2>/dev/null)"
"$TEMPER" evidence clear --stage review >/dev/null 2>&1; _r6_clear=$?
review_done
"$TEMPER" gate review >/dev/null 2>&1
assert_eq "review 6: rule 8 a session's evidence clear at a failed Review is refused, and the blocking finding keeps the Review gate FAIL" \
  "before=FAIL:findings=False|autonomous|review clear=refused after=FAIL" \
  "before=$_r6_at clear=$([[ $_r6_clear -ne 0 ]] && echo refused || echo taken) after=$(_verdict86 review)"

# --- review 6: rule 4, a run that goes on by itself never changes a gate's command or the approved file set ---
# `temper plan patch` is the person's answer (plan_patch.py: "the mod lets only the answer to the CLI's question run it").
# The CLI refuses Run it anyway (--fresh) and a --person row in a run that goes on by itself with no stop open
# (docs/trust.md), but takes a plan patch there: with the mod off the session rewrites a group's Validate line and adds a
# file to the approved set, the approved hash moves with it, and the run stays unattended.
_unattended build
_r6_files0="$("$TEMPER" state get approved_files 2>/dev/null)"
"$TEMPER" plan patch G1 --cmd 'echo weaker' >/dev/null 2>&1; _r6_cmd=$?
"$TEMPER" plan patch task 1 --add-file src/extra.sh >/dev/null 2>&1; _r6_add=$?
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 6: rule 4 an unattended run with no question open cannot patch a gate's command or add a file to the approved set" \
  "cmd=refused|add=refused|validate=true|files same|autonomous" \
  "cmd=$([[ $_r6_cmd -ne 0 ]] && echo refused || echo taken)|add=$([[ $_r6_add -ne 0 ]] && echo refused || echo taken)|validate=$(sed -n 's/^\*\*Validate:\*\* `\(.*\)`$/\1/p' .temper/specs/demo/tasks.md | head -1)|files $([[ "$("$TEMPER" state get approved_files 2>/dev/null)" == "$_r6_files0" ]] && echo same || echo widened)|$("$TEMPER" state get run_mode 2>/dev/null)"

# --- review 6: rule 4, a run that goes on by itself never answers a scope drift ---
# A Scope drift answer (`evidence add --claim "drift P: Add to plan"`) to no question is refused only inside a repair
# window (repair_ops.py answer_of); elsewhere the CLI keeps it, and the commit gate's scope row counts it. With the mod off a
# session of an unattended run, with no drift ask and no stop open, writes the answer for a file nobody planned, the run
# stays unattended, and the scope row passes.
_unattended build; _repo86; git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
echo 'echo outside' > src/outside.sh
"$TEMPER" evidence add --stage build --claim "drift src/outside.sh: Add to plan" >/dev/null 2>&1; _r6_drift=$?
_r6_mode="$("$TEMPER" state get run_mode 2>/dev/null)"
gpass build review check; _at commit; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "review 6: rule 4 an unattended run with no drift question open cannot answer a scope drift for itself" \
  "answer=refused|autonomous|blast=False" \
  "answer=$([[ $_r6_drift -ne 0 ]] && echo refused || echo taken)|$_r6_mode|blast=$(_row86 commit "blast radius" | cut -d: -f1)"

# --- review 6: rule 11, the commit hook is what holds the rules with the mod off; no CLI call of a session takes it away ---
# Mid run, with no question open, an unattended run's session can end the run (`state clear`) or remove the hook (`guards
# uninstall`): the CLI takes both, and then a commit of a file no gate saw passes. Only the mod refuses them (rules.ts:
# UNINSTALL_DENY, personOnly state clear); docs/trust.md tells to run `guards uninstall` after the plugin is disabled, and
# names no limit for a run in progress.
_unattended build; _repo86; git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
"$TEMPER" state clear >/dev/null 2>&1; _r6_clear=$?
echo 'echo unseen' > src/unseen.sh; git add src/unseen.sh; git commit -q -m unseen >/dev/null 2>&1
_r6_c1="$(git rev-list --count HEAD)"
git config --unset core.hooksPath 2>/dev/null
_unattended build; _repo86; git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
"$TEMPER" guards uninstall >/dev/null 2>&1; _r6_un=$?
echo 'echo unseen' > src/unseen.sh; git add src/unseen.sh; git commit -q -m unseen >/dev/null 2>&1
_r6_c2="$(git rev-list --count HEAD)"
git config --unset core.hooksPath 2>/dev/null
assert_eq "review 6: rule 11 mid run, with no question open, state clear and guards uninstall are refused and the unseen file is not committed" \
  "clear=refused:1|uninstall=refused:1" \
  "clear=$([[ $_r6_clear -ne 0 ]] && echo refused || echo taken):$_r6_c1|uninstall=$([[ $_r6_un -ne 0 ]] && echo refused || echo taken):$_r6_c2"

# --- review 6: the run's branch, which the commit hook gates, is a CLI call the mod alone holds after the approval ---
# The commit hook gates a commit on the run's branch only (state branch). `state set branch` is the answer at the branch
# clash question, before the branch exists; the CLI takes it at any stage. With the mod off a session at Build renames the
# run's branch, and a commit on the branch the run stands on (the one its final commit and pull request go to) passes the
# hook with no gate; docs/trust.md says only that a commit on another branch passes.
_unattended build; _repo86; git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
echo 'echo unseen' > src/unseen.sh; git add src/unseen.sh
git commit -q -m before >/dev/null 2>&1; _r6_b0="$(git rev-list --count HEAD)"
"$TEMPER" state set branch feature/elsewhere >/dev/null 2>&1; _r6_br=$?
git commit -q -m after >/dev/null 2>&1; _r6_b1="$(git rev-list --count HEAD)"
git config --unset core.hooksPath 2>/dev/null
assert_eq "review 6: branch after the approval a session cannot move the run's branch away from the branch it stands on, and the hook still refuses" \
  "before=1|set=refused|after=1" "before=$_r6_b0|set=$([[ $_r6_br -ne 0 ]] && echo refused || echo taken)|after=$_r6_b1"
