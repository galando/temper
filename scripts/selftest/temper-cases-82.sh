# Case file 82 (adversarial review 2): rules 3 and 4, every way an unattended run starts and ends, and the never list of
# rule 4 against what `temper next --json` hands an unattended run to run by itself. Sourced by test-temper.sh; its
# helpers (setup, fresh, gpass, riskH, _unattended, _base_known) are used here. Every assertion name starts with
# "review 2:". Options and questions are selected by id, never by label text.

# --- the helpers of this file ---
_x82() { # _x82 <python code over d, the JSON of temper next, that sets r>: prints r
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
# A call an unattended run may never make by itself (rule 4): a step back to Plan or Intent, a change of the plan, of a
# gate's command or of the intent, a skip, an accepted finding, a config write, a push, a pull request, the final commit
_FORBID82='state loop \S+ (plan|intent)|state redo plan|plan patch|override|evidence accept|acceptance (skip|reopen)|baseline (skip|accept-red)|intent (answer|carry)|doctor .*--write|config tidy|git push|gh pr|spec commit .* -- |git commit'
_stop82() { # "stop" when next is a question or a recorded stop (the park call) and no call the run makes by itself (an auto,
            # or a work: the session runs its calls with no question) matches _FORBID82; else what next does
  python3 - "$_FORBID82" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
bad = re.compile(sys.argv[1])
try:
    d = json.loads(sys.argv[2])
except ValueError:
    print("no next")
    sys.exit(0)
a = d.get("action")
calls = list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]
short = ",".join(re.sub(r"^\S*/temper ", "", c)[:60] for c in calls[:2])
if a in ("auto", "work") and any(bad.search(c) for c in calls):
    print("%s runs %s" % (a, short))
elif a == "ask" or (a == "auto" and calls and all(re.search(r"\spark\s", c) and "--end" not in c for c in calls)):
    print("stop")
else:
    print("%s %s" % (a, short))
PY
}
_mode82() { "$TEMPER" state get run_mode 2>/dev/null; }
_go82() { # runs the calls of next while it is an auto or a work with no agents (what the run does by itself), at most 8
  local i c cs
  for i in 1 2 3 4 5 6 7 8; do
    cs="$(_x82 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'auto' or (d.get('action') == 'work' and not d.get('agents')) else ''")"
    [[ -n "$cs" ]] || return 0
    while IFS= read -r c; do [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1; done <<<"$cs"
  done
}

# --- review 2: rule 4, an unattended run never skips a check: the acceptance writer locked nothing in its launches ---
_unattended build
printf '{"spec": ".temper/specs/demo", "launches": 2}\n' > .temper/evidence/acceptance-lock.json
_r82_acc="mode=$(_mode82)|next=$(_stop82)"
"$TEMPER" go >/dev/null 2>&1   # temper go runs the calls of a work with no agents inside the CLI
_r82_acc+="|after-go=$(python3 -c 'import json; print("skipped" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "not skipped")'),$(_mode82)"
assert_eq "review 2: an unattended run whose acceptance writer locked nothing stops and asks; it never runs acceptance skip by itself" \
  "mode=autonomous|next=stop|after-go=not skipped,autonomous" "$_r82_acc"

# The skip is the person's option at that stop (its id override, the skip with a reason): it ends the unattended run.
while IFS= read -r _c82; do [[ -n "$_c82" ]] && bash -c "${_c82//\{reason\}/I accept the risk}" >/dev/null 2>&1; done \
  < <(_x82 "r = '\n'.join((opt(d, 'override') or {}).get('calls') or [])")
assert_eq "review 2: the person's skip of the acceptance tests at that stop is recorded and ends the unattended run" \
  "skipped,interactive" "$(python3 -c 'import json; print("skipped" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "not skipped")'),$(_mode82)"

# --- review 2 (NEW-FLOW-1): the option "Ask me at every stage from here" at that stop switches the run to interactive;
#     the next step must ask the skip question again, never run the rule's own acceptance skip with no question ---
_unattended build
printf '{"spec": ".temper/specs/demo", "launches": 2}\n' > .temper/evidence/acceptance-lock.json
"$TEMPER" go >/dev/null 2>&1   # the stop: the park call ran, next is the question
while IFS= read -r _c82; do [[ -n "$_c82" ]] && bash -c "$_c82" >/dev/null 2>&1; done \
  < <(_x82 "r = '\n'.join((opt(d, 'ask-every-stage') or {}).get('calls') or [])")
assert_eq "review 2: after Ask me at every stage at that stop, next asks a question and carries no acceptance skip call" \
  "ask,no-skip" "$(_x82 "r = ('ask' if d.get('action') == 'ask' else d.get('action')) + ',' + ('no-skip' if not any('acceptance skip' in c for c in list(d.get('calls') or []) + [c for x in d.get('agents') or [] for c in (x.get('before') or []) + (x.get('after') or [])]) else 'skip')")"
#     approve-run (risk H with no fresh review, row D18d), the session's typed call is the only way to start one, and the
#     CLI must refuse it, as it does under never-unattended ---
fresh; sed -i '/^  enabled: false$/d' .claude/temper.config
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; riskH
_r82_arm="riskH-offered=$(_x82 "r = opt(d, 'approve-run') is not None")"
_r82_arm+=",$("$TEMPER" state set run_mode autonomous >/dev/null 2>&1 && echo taken || echo refused),$(_mode82)"
assert_eq "review 2: at risk H with no fresh review the approval offers no approve-run, and the typed call cannot start the unattended run" \
  "riskH-offered=False,refused,interactive" "$_r82_arm"


# --- review 2: rule 4, an unattended run never writes the config: the group fix the rule takes commits and merges
#     whatever the fix agent changed, the project's .claude/temper.config too ---
setup
rm -rf .git README src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
git config user.email t@example.com; git config user.name T
mkdir -p src; echo 'echo demo' > src/demo.sh; echo base > README
git add README src .claude/temper.config; git commit -q -m base; git checkout -q -B feature/demo
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" group start G1 >/dev/null 2>&1
python3 -c "
import json
p = '.temper/groups.json'; d = json.load(open(p))
d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}}; d.pop('integration', None)
d['groups']['G1'].update(fails=1, gate={'verdict': 'FAIL', 'reason': 'group G1 Validate failed (exit 1): make test', 'ran': True, 'fail_lines': ['FAIL: test_a']})
json.dump(d, open(p, 'w'), indent=2)"
_r82_cfg="rule=$(_x82 "r = 'auto group fix' if d.get('action') == 'auto' and any(c.endswith('group fix G1') for c in d.get('calls') or []) else d.get('action')")"
_go82   # the rule takes the group fix; next launches the fix agent
_wt82=.claude/worktrees/temper-demo-G1
sed -i 's/coverage-threshold: 80/coverage-threshold: 0/' "$_wt82/.claude/temper.config"   # what the fix agent changed
while IFS= read -r _c82; do [[ -n "$_c82" ]] && bash -c "${_c82//\{ms\}/1}" >/dev/null 2>&1; done \
  < <(_x82 "r = '\n'.join(c for a in d.get('agents') or [] for c in a.get('after') or [])")   # the agent's after calls
_go82   # the group check, Continue, the merge and the Build check, as the run makes them by itself
_r82_cfg+="|cli-commits=$(git log --format=%s feature/demo -- .claude/temper.config 2>/dev/null | grep -c 'G1 group check')"
_r82_cfg+="|threshold=$("$TEMPER" config get check.coverage-threshold 2>/dev/null)"
assert_eq "review 2: no call an unattended run makes by itself commits or merges a change of the config" \
  "rule=auto group fix|cli-commits=0|threshold=80" "$_r82_cfg"

# --- review 2 (NEW-RULES-4, NEW-FLOW-6): the same in a project below the top of its repository: the group fix reads the
#     staged paths with the project's prefix, so the config, and a file named like the kept copy of the config, still
#     refuse their commit ---
N82="$WORKDIR/r2-nested"; rm -rf "$N82"; mkdir -p "$N82/packages/app/src"
(
  cd "$N82" && git init -q . && echo r > README && echo 'echo demo' > packages/app/src/demo.sh
  git add -A && git -c user.email=t@example.com -c user.name=T commit -qm init && git checkout -q -b feature/demo
  cd packages/app && mkdir -p .claude .temper/specs/demo && cp "$REPO_ROOT/templates/temper.config.default" .claude/temper.config
  "$TEMPER" init >/dev/null 2>&1 && "$TEMPER" state init demo >/dev/null 2>&1
  cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The demo group.

### Task 1: first task
**File:** `src/demo.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- [ ] done
TASKS
  echo '# Plan' > .temper/specs/demo/plan.md
  git add .claude .temper/specs && git -c user.email=t@example.com -c user.name=T commit -qm spec
  "$TEMPER" override intent --reason r >/dev/null 2>&1; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" override plan --reason r >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" group start G1 >/dev/null 2>&1
  python3 -c "
import json
p = '.temper/groups.json'; d = json.load(open(p))
d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}}; d.pop('integration', None)
d['groups']['G1'].update(fails=1, gate={'verdict': 'FAIL', 'reason': 'group G1 Validate failed (exit 1): make test', 'ran': True, 'fail_lines': ['FAIL: test_a']})
json.dump(d, open(p, 'w'), indent=2)"
) >/dev/null 2>&1
_wt82n="$(cd "$N82/packages/app" && python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1'].get('worktree') or '')" 2>/dev/null)"
[[ -n "$_wt82n" && "$_wt82n" != /* ]] && _wt82n="$N82/packages/app/$_wt82n"
_r82_nest="fix=$((cd "$N82/packages/app" && "$TEMPER" group fix G1 >/dev/null 2>&1; echo $?)"
sed -i 's/coverage-threshold: 80/coverage-threshold: 0/' "$_wt82n/packages/app/.claude/temper.config" 2>/dev/null
_r82_nest+="|commit=$(cd "$N82/packages/app" && "$TEMPER" group fix G1 --commit 2>&1 | grep -o 'is the config' | head -n 1); ${_r82_nest##*fix=}"   # the refusal names the config
_r82_nest="${_r82_nest%%; *}|commits=$(git -C "$N82" log --all --format=%s -- packages/app/.claude/temper.config 2>/dev/null | grep -c 'G1 group check')"
_r82_nest+="|threshold=$(cd "$N82/packages/app" && "$TEMPER" config get check.coverage-threshold 2>/dev/null)"
(cd "$N82/packages/app" && "$TEMPER" group fix G1 >/dev/null 2>&1)   # the request again, for Temper's own kept copy
printf 'stack: auto\n' > "$_wt82n/packages/app/.claude/temper.config.before-1"
_r82_nest+="|copy=$(cd "$N82/packages/app" && "$TEMPER" group fix G1 --commit 2>&1 | grep -o "is Temper's own file" | head -n 1); x"
_r82_nest="${_r82_nest%%; x}|copy-commits=$(git -C "$N82" log --all --format=%s -- "packages/app/.claude/temper.config.before-*" 2>/dev/null | grep -c 'G1 group check')"
assert_eq "review 2: below the top of the repository the group fix still refuses the config, and Temper's own kept copy, and commits neither" \
  "fix=0|commit=is the config|commits=0|threshold=80|copy=is Temper's own file|copy-commits=0" "$_r82_nest"

# --- review 2: rule 3, an accepted finding ends the unattended run: clearing the Review ledger would drop the finding as
#     surely as accepting it, with no reason recorded. The CLI refuses the clear (only repair close resolves a finding,
#     and the person keeps one with evidence accept), so the finding stays. Corrected from the reviewer's check, which
#     wanted the clear taken and the run ended: the lane's rule refuses a clear of a ledger with an open finding ---
_unattended review
"$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high --label PROVEN >/dev/null 2>&1
_r82_clr="$("$TEMPER" evidence clear --stage review >/dev/null 2>&1 && echo taken || echo refused)"
assert_eq "review 2: clearing the Review ledger with an open finding is refused, so the finding is never dropped in silence" \
  "clear=refused|findings=1,autonomous" "clear=$_r82_clr|findings=$(python3 -c 'import json; print(len(json.load(open(".temper/evidence/review.json"))))'),$(_mode82)"
