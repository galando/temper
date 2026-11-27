# Case file 81 (review 1): the adversarial review of rules 1 and 2 of docs/plans/one-go/done.md (rows D30, D31).
# Rule 1: before the approval a run writes only its spec folder and Temper's own run files: no project file, no branch,
# no commit. Rule 2: the approval is of what was shown; a later change to the intent or the plan fails the gates until
# approved again. Sourced by test-temper.sh; its helpers (setup, fresh, gpass, _at) are used here. Every check names its
# option by id. A call the CLI does not have stays inside $( ... ) or ends in || true, so the file runs to its end.

# --- the helpers of this file ---
_r1_repo() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_r1_calls() { # _r1_calls <option id>: the calls of that option of the question next asks, one a line
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
a = d.get("ask") or {}
opts = list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
o = next((o for o in opts if o.get("id") == sys.argv[1]), None) or {}
print("\n".join(c.replace("{reason}", "a reason").replace("{answer}", "the person") for c in o.get("calls") or []))
PY
}
_r1_run() { # _r1_run <option id>: runs the calls of that option as the session would, stopping at the first that fails
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_r1_calls "$1")
}
_r1_row() { # _r1_row <stage> <row name>: pass of that row of the stage's verdict in gates.json, or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else str(r.get("pass")))
PY
}
_r1_card_section() { # _r1_card_section <section id>: the rows of that section of the card next carries, joined by |
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
s = next((s for s in (d.get("card") or {}).get("sections") or [] if s.get("id") == sys.argv[1]), None) or {}
print("|".join(str(r.get("text")) for r in s.get("rows") or []))
PY
}
_r1_at_plan() { fresh; _r1_repo; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; }
_R1_ROW="intent unchanged since the approval"

# --- rule 1: before the approval the CLI makes no commit and no branch, with the commit hook installed, mod off ---
_r1_at_plan; bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
_r1_q="$(python3 -c "import json,sys; print(((json.loads(sys.argv[1]).get('ask') or {}).get('id')))" "$("$TEMPER" next --json 2>/dev/null)")"
_r1_specc="$("$TEMPER" spec commit 'docs: the spec before the approval' >/dev/null 2>&1 && echo committed || echo refused)"
_r1_count="$(git rev-list --count HEAD)"
assert_eq "review 1: R1a at the approval question the CLI's spec commit makes no commit (rule 1: no commit before the approval)" \
  "plan.approve|refused|1" "$_r1_q|$_r1_specc|$_r1_count"
git reset -q --soft "$(git rev-list --max-parents=0 HEAD)" 2>/dev/null; git reset -q 2>/dev/null
git add -f .temper/specs/demo/intent.md >/dev/null 2>&1
_r1_gitc="$(git commit -q -m 'spec before the approval' >/dev/null 2>&1 && echo committed || echo refused)"
assert_eq "review 1: R1b at the approval question the commit hook refuses a commit of the spec folder alone (rule 1)" \
  "refused|1|master" "$_r1_gitc|$(git rev-list --count HEAD)|$(git branch --show-current)"
_r1_at_plan
"$TEMPER" spec branch >/dev/null 2>&1 || true
assert_eq "review 1: R1c at the approval question the CLI's spec branch makes no branch (rule 1: no branch before the approval)" \
  "master|1" "$(git branch --show-current)|$(git branch --list | grep -c .)"
git config --unset core.hooksPath 2>/dev/null

# --- R1d (R2-4): the calls of one approving option run as one shell call that does not stop at the first failure: the
#     tasks.md the question showed is changed, so the approval is stale, and no call of it may advance the run. Each
#     call carries the digests of what the question showed (`--shown`) and compares them itself (scripts/spec_ops.py,
#     WP12), so the spec branch and the spec commit of the stale approval refuse on their own, however they were run.
_r1_at_plan
python3 -c "
import pathlib
p = pathlib.Path('.temper/specs/demo/intent.md')
p.write_text(p.read_text().replace('**Status:** accepted', '**Status:** draft'))"
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_r1_opt="$(_r1_calls approve-run)"
python3 -c "
import pathlib
p = pathlib.Path('.temper/specs/demo/tasks.md')
p.write_text(p.read_text().replace('src/demo.sh', 'src/other.sh'))"
while IFS= read -r _r1_c; do [[ -n "$_r1_c" ]] && bash -c "$_r1_c" >/dev/null 2>&1; done <<<"$_r1_opt"
assert_eq "review 1: R1d the calls of a stale approval run as one shell call that does not stop: no branch and no commit (rule 1)" \
  "master|1|1|plan|interactive" \
  "$(git branch --show-current)|$(git branch --list | grep -c .)|$(git rev-list --count HEAD)|$("$TEMPER" state get next_stage 2>/dev/null)|$("$TEMPER" state get run_mode 2>/dev/null)"

# --- rule 2: the Integration line, read two ways ---
# tasks_md.parse (the digest, the card) keeps the last **Integration:** line; check_run.plan_line (the suite Check runs
# when the config and detect name none) reads the first.
_r1_at_plan
sed -i '2i **Integration:** `echo r1-not-shown`' .temper/specs/demo/tasks.md
_r1_shown="$(_r1_card_section commands)"
_r1_run ask-every-stage; _at check
"$TEMPER" check run >/dev/null 2>&1 || true
_r1_ran="$(python3 -c "
import json
rows = json.load(open('.temper/evidence/check.json'))
print(next((r.get('cmd') for r in rows if 'the suite' in str(r.get('claim'))), 'none'))" 2>/dev/null)"
assert_eq "review 1: R2a the suite Check runs is the Integration command the approval card showed (rule 2: approval of what was shown)" \
  "shown" "$([[ "$_r1_shown" == *"all: $_r1_ran"* ]] && echo shown || echo "card '$_r1_shown', Check ran '$_r1_ran'")"
_r1_at_plan; _r1_run ask-every-stage
sed -i '2i **Integration:** `echo r1-after-the-approval`' .temper/specs/demo/tasks.md
_r1_g=""; for _g in build check commit; do "$TEMPER" gate "$_g" >/dev/null 2>&1; _r1_g+="$_g=$(_r1_row "$_g" "$_R1_ROW")|"; done
assert_eq "review 1: R2b a second Integration line put before the approved one after the approval fails the Build, Check and commit gates" \
  "build=False|check=False|commit=False|" "$_r1_g"

# --- rule 2: the text a manual Test line asks the person to confirm is shown on the card and bound by no digest ---
_r1_at_plan
printf '\n### Task 2: the page\n**File:** `src/page.html`\n**Depends:** none\n**Test:** manual — the page shows the red banner\n**Cases:**\n- the banner\n- [ ] the page\n' >> .temper/specs/demo/tasks.md
_r1_cmds="$(_r1_card_section commands)"
_r1_run ask-every-stage
sed -i 's/the page shows the red banner/nothing at all/' .temper/specs/demo/tasks.md
"$TEMPER" gate build >/dev/null 2>&1
assert_eq "review 1: R2c a changed manual Test line of tasks.md, shown on the approval card, fails the Build gate after the approval" \
  "shown|False" "$([[ "$_r1_cmds" == *"red banner"* ]] && echo shown || echo "not shown: $_r1_cmds")|$(_r1_row build "$_R1_ROW")"

# --- rule 2: the approved file set is the set the card showed ---
_r1_at_plan
printf '# Plan\n\n## Approach\nThe demo.\n\n## Files to modify\n| File | Why |\n|---|---|\n| `src/r1-hidden.sh` | in no task |\n' > .temper/specs/demo/plan.md
_r1_files="$(_r1_card_section files)"
_r1_run ask-every-stage
_r1_appr="$("$TEMPER" state get approved_files 2>/dev/null)"
assert_eq "review 1: R2d every file the approval records in approved_files is a file the approval card showed" \
  "src/demo.sh" "$(python3 -c "
import json, sys
shown = sys.argv[2].split('|')
try:
    a = json.loads(sys.argv[1])
except ValueError:
    a = []
print(','.join(sorted(f for f in a if f in shown)) + ''.join(' not shown: %s' % f for f in a if f not in shown))" "$_r1_appr" "$_r1_files")"
