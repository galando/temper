# Case file 88 (review 8): migration and surface. A user of 9.8.4 (7c7a1c1) after the upgrade, a project that ran the
# base (10e965a), the one time config question and the one time notice. Each check here fails on the code under review
# and names the rule or the row of docs/plans/one-go/done.md it holds. Sourced by test-temper.sh; its helpers (nx, _ev,
# gpass) are used here. The runs and configs of an older Temper come from scripts/selftest/saved-old.json, as case file
# 46 reads them. A call that may fail stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
SAVED88="$TESTS_DIR/saved-old.json"
_clean88() { # an empty work folder (a worktree of an earlier check is forgotten by git with it)
  cd "$WORKDIR" || exit 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  cd "$WORKDIR" || exit 1
}
_git88() { git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null; git config user.email t@example.com; git config user.name T; }
_tpl88() { # _tpl88 <commit>: the config template that Temper shipped
  python3 -I - "$SAVED88" "$1" <<'PY'
import json, sys
sys.stdout.write(json.load(open(sys.argv[1]))[sys.argv[2]]["template"])
PY
}
_restore88() { # _restore88 <commit> <state>: the project as that Temper left it at that state (as _restore46 of case 46)
  _clean88; _git88
  printf 'x\n' > README.md; git add README.md; git commit -q -m init
  local b
  b="$(python3 -I - "$SAVED88" "$1" "$2" "$WORKDIR" "$REPO_ROOT" "$(git rev-parse HEAD)" <<'PY'
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
_row88() { # _row88 <gate> <row name>: the pass of that row of the gate's last verdict in gates.json, or none
  python3 -I - "$1" "$2" <<'PY'
import json, sys
try:
    g = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    g = {}
print(next((str(r.get("pass")) for r in g.get("requirements") or [] if r.get("name") == sys.argv[2]), "none"))
PY
}

# --- review 8, rule 2: a run approved by 9.8.4 or by the base and taken up after the upgrade still binds its plan ---
# The saved state holds plan_hash (9.8.4 records it at the plan gate), so the CLI knows the plan the person approved.
# After the upgrade the plan's gate commands are changed (Integration and Validate become `true`): the row "intent
# unchanged since the approval" of the commit gate must fail, naming tasks.md. It passes with "no digest was recorded at
# the approval (a run saved before 9.8.5)", because scripts/approval.py binding_row returns before it compares plan_hash.
_r2_88=""
for _c in 7c7a1c1 10e965a; do
  _restore88 "$_c" review-finding
  "$TEMPER" next --json >/dev/null 2>&1 || true   # the run is taken up by 9.8.5 (migrate_legacy stamps it)
  sed -i 's/^\*\*Integration:\*\* `npm test`/**Integration:** `true`/; s/^\*\*Validate:\*\* `npm test`/**Validate:** `true`/' \
    .temper/specs/pw/tasks.md
  "$TEMPER" gate commit >/dev/null 2>&1 || true
  _r2_88+="${_r2_88:+|}$([[ $_c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$(_row88 commit "intent unchanged since the approval")"
done
assert_eq "review 8: a plan approved by 9.8.4 or by the base whose gate commands change after the upgrade fails the row intent unchanged since the approval" \
  "9.8.4=False|base=False" "$_r2_88"
# The lane's checks beside the finding (WP32): a run of those versions binds its intent as found when 9.8.5 takes it
# up, so a criterion changed after the upgrade fails the row too; and a run whose plan holds what 9.8.5 binds besides
# (the text a manual Test asks the person to confirm) still goes on unchanged (row D60), its plan_hash moved.
_i88=""
for _c in 7c7a1c1 10e965a; do
  _restore88 "$_c" review-finding
  "$TEMPER" next --json >/dev/null 2>&1 || true
  "$TEMPER" gate commit >/dev/null 2>&1 || true
  _i88+="${_i88:+|}$([[ $_c == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$(_row88 commit "intent unchanged since the approval")"
  printf '\n- [ ] AC-09 [required]: a criterion added after the upgrade\n' >> .temper/specs/pw/intent.md
  "$TEMPER" gate commit >/dev/null 2>&1 || true
  _i88+=",$(_row88 commit "intent unchanged since the approval")"
done
assert_eq "review 8, lane: a run of 9.8.4 or of the base taken up as it was passes the row, and a criterion added after the upgrade fails it" \
  "9.8.4=True,False|base=True,False" "$_i88"
_restore88 7c7a1c1 review-finding
python3 - "$REPO_ROOT/scripts" <<'PY'
import json, re, sys
sys.path.insert(0, sys.argv[1])
import approval, tasks_md
p = ".temper/specs/pw/tasks.md"
t = open(p).read()
t = re.sub(r"(?m)^\*\*Test:\*\* .*$", "**Test:** manual — the reset mail arrives", t, count=1)
open(p, "w").write(t)
st = json.load(open(".temper/build-state.json"))
st["plan_hash"] = approval.plan_digest(tasks_md.parse(p), legacy=True)   # the digest 9.8.4 recorded for this plan
json.dump(st, open(".temper/build-state.json", "w"), indent=2)
PY
"$TEMPER" next --json >/dev/null 2>&1 || true
"$TEMPER" gate commit >/dev/null 2>&1 || true
_m88="$(_row88 commit "intent unchanged since the approval")"
sed -i 's/the reset mail arrives/nothing at all/' .temper/specs/pw/tasks.md
"$TEMPER" gate commit >/dev/null 2>&1 || true
assert_eq "review 8, lane: a saved run of 9.8.4 with a manual Test goes on after the upgrade, and its confirm text is bound" \
  "True|False" "$_m88|$(_row88 commit "intent unchanged since the approval")"

# --- review 8, D102: the one time notice is for a project that ran 9.8.4 or the base, never for one that only ran 9.8.5 ---
# A project set up by 9.8.5 (temper init wrote the mark) commits a run's spec folder, as the run's own commit does. A
# second worktree of it (claude --worktree, the way Getting Started says to start other work), or a fresh clone, has the
# committed .temper/specs but not the ignored mark, so its first next says "Temper 9.8.5 asks twice" to a project that
# never ran an earlier Temper.
_clean88; mkdir -p p; cd p || exit 1; _git88
printf 'x\n' > README.md; git add README.md; git commit -q -m init
"$TEMPER" config init >/dev/null 2>&1; "$TEMPER" init >/dev/null 2>&1
mkdir -p .temper/specs/done1; printf '# Intent: a finished run\n' > .temper/specs/done1/intent.md
git add -A; git commit -q -m 'docs(done1): record the run' 2>/dev/null
_d102_88="first=$(_ev "'told' if str(d.get('say') or '').startswith('Temper 9.8.5 asks twice') else 'quiet'" "$("$TEMPER" next --json 2>/dev/null)")"
git worktree add -q "$WORKDIR/wt" 2>/dev/null; cd "$WORKDIR/wt" || exit 1
_d102_88+="|worktree=$(_ev "'told' if str(d.get('say') or '').startswith('Temper 9.8.5 asks twice') else 'quiet'" "$("$TEMPER" next --json 2>/dev/null)")"
cd "$WORKDIR" || exit 1
assert_eq "review 8: a worktree of a project that only ran 9.8.5 is never told Temper 9.8.5 asks twice" \
  "first=quiet|worktree=quiet" "$_d102_88"

# --- review 8, D62: the one time config question is never asked again ---
# The person answers Remove them (the recommended answer) on the template of 9.8.4. Later they set a coverage floor of
# 80 on purpose, a value the old template happened to ship: the next run asks config.tidy again and recommends removing
# their own line. Remove them writes no mark (only Keep my file writes upgrade.asked), so the question comes back.
_clean88; _git88; mkdir -p .claude; _tpl88 7c7a1c1 > .claude/temper.config
printf 'x\n' > README.md; git add -A; git commit -q -m init
"$TEMPER" init >/dev/null 2>&1; "$TEMPER" state init pw --feature 'Password reset by email' >/dev/null 2>&1
_d62_88="first=$(nx "(d.get('ask') or {}).get('id')")"
"$TEMPER" config tidy --apply >/dev/null 2>&1 || true
"$TEMPER" state clear >/dev/null 2>&1 || true
printf 'check:\n  coverage-threshold: 80\n' >> .claude/temper.config
"$TEMPER" state init pw2 --feature 'Export totals' >/dev/null 2>&1
_d62_88+="|later=$(nx "(d.get('ask') or {}).get('id')")"
assert_eq "review 8: after Remove them the one time question config.tidy is never asked again, also when the person later sets a value an old template shipped" \
  "first=config.tidy|later=None" "$_d62_88"
# The lane's check beside the finding (WP32): a new project, whose config config init wrote, sets the same value on
# purpose; it never ran an older Temper, so it is never asked the upgrade question.
_clean88; _git88; "$TEMPER" config init >/dev/null 2>&1
printf 'x\n' > README.md; git add -A; git commit -q -m init
"$TEMPER" init >/dev/null 2>&1
printf 'check:\n  coverage-threshold: 80\n' >> .claude/temper.config
"$TEMPER" state init pw --feature 'Password reset by email' >/dev/null 2>&1
assert_eq "review 8, lane: a new project whose config config init wrote is never asked config.tidy, also with a value an old template shipped" \
  "None" "$(nx "(d.get('ask') or {}).get('id')")"
