# ADR 0013: the CLI says what comes next (temper next --json), writes the view the mod reads
# (.temper/view.json), and refuses to leave a stage whose check failed unless the person skipped it.
# Sourced by test-temper.sh (assert_eq, assert_exit, setup, $TEMPER).

_ev() { # _ev <code> <json text>: runs the code over d (the JSON); the last "; " part is printed
  python3 - "$1" "$2" <<'PY' 2>&1
import json, sys
code, text = sys.argv[1], sys.argv[2]
d = json.loads(text)
*stmts, last = code.split('; ')
env = {'d': d}
for st in stmts:
    exec(st, env)
print(eval(last, env))
PY
}
nx() { _ev "$1" "$("$TEMPER" next --json 2>/dev/null)"; }   # one value of `temper next --json`
vw() { _ev "$1" "$(cat .temper/view.json 2>/dev/null)"; }      # one value of .temper/view.json
labels() { nx "'|'.join(o['label'] for o in d['ask']['question']['options'])"; }
gpass() { # gpass <stage>...: record a PASS verdict for each stage, as a gate run would
  python3 - "$@" <<'PY'
import json, sys
p = '.temper/gates.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
for s in sys.argv[1:]:
    d[s] = {'verdict': 'PASS', 'requirements': [{'name': 'all', 'pass': True, 'detail': 'ok'}]}
json.dump(d, open(p, 'w'))
PY
}
gfail() { # gfail <stage> <row name> <detail>: record a FAIL verdict with one failed row
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
p = '.temper/gates.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
d[sys.argv[1]] = {'verdict': 'FAIL', 'requirements': [{'name': sys.argv[2], 'pass': False, 'detail': sys.argv[3]}]}
json.dump(d, open(p, 'w'))
PY
}
fresh() { # a new run of the demo spec at Intent, with the run state written by the CLI
  setup
  rm -f .temper/groups.json .temper/view.json
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
}

# --- no run ---
setup; "$TEMPER" state clear >/dev/null 2>&1
assert_eq "next: with no run the action is none" "none|None" "$(nx "d['action'] + '|' + str(d['run'])")"
assert_eq "view: with no run, the view says so (version 1, no run)" "1|None" "$(vw "str(d['version']) + '|' + str(d['run'])")"

# --- Intent: the stage runs, then its question ---
fresh
assert_eq "next: a new run launches the Intent brief, with the feature, then records usage and runs the gate" \
  "work|temper:temper-intent|1|1|usage add --stage intent|gate intent" \
  "$(nx "'|'.join([d['action'], d['agents'][0]['type'], str(int('Feature: the demo thing.' in d['agents'][0]['prompt'])), str(int('/agents/intent.md exactly' in d['agents'][0]['prompt'])), ' '.join(d['agents'][0]['after'][0].split('temper ', 1)[1].split()[:4]), d['agents'][0]['after'][1].split('temper ', 1)[1]])")"
assert_eq "next: the run's identity is in every action" "demo|intent|0" "$(nx "d['run']['slug'] + '|' + d['run']['stage'] + '|' + str(d['run']['step'])")"
gpass intent
assert_eq "next: Intent PASS asks the Temper gate question with its four options, exactly" \
  "ask|Temper gate|Intent: the check passed. Accept the intent and continue to Plan?" \
  "$(nx "d['action'] + '|' + d['ask']['question']['header'] + '|' + d['ask']['question']['question']")"
assert_eq "next: the Intent PASS options" "Continue to Plan (Recommended)|Grill Me|Teach Me|Save for later" "$(labels)"
_b="$(git symbolic-ref -q HEAD)"; git branch -f temper-test-other HEAD >/dev/null 2>&1; git symbolic-ref HEAD refs/heads/temper-test-other   # on another branch than the run's, at the same commit
assert_eq "next: Continue to Plan is the person's approval: switch to the run's branch, accept the intent, commit it, then advance" \
  "approve|git checkout feature/demo|intent accept|git add -- .temper/specs/demo/|state advance intent_complete plan" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['move'], o['calls'][0].replace('checkout -b ', 'checkout '), o['calls'][1].split('temper ', 1)[1], o['calls'][2], o['calls'][-1].split('temper ', 1)[1]])")"
git symbolic-ref HEAD "$_b"
assert_eq "next: Save for later stops the run and is a pause" "pause|True" "$(nx "o = d['ask']['options'][3]; o['move'] + '|' + str(o['stop'])")"
assert_eq "next: the ask carries the run id and step it belongs to" "yes|0" "$(nx "('yes' if d['ask']['run_id'] == d['run']['id'] else 'no') + '|' + str(d['ask']['step'])")"
gfail intent "problem stated" "no Problem section"
assert_eq "next: Intent FAIL offers a skip with a reason, and names the failed row" \
  "Override and continue|Grill Me|Save for later|True|1" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['options']) + '|' + str(d['ask']['options'][0]['reason']) + '|' + str(int('no Problem section' in d['ask']['question']['question']))")"
assert_eq "next: a move that needs a reason carries its reason question, exactly" \
  "Override and continue. What is the reason?|I accept the risk|It is not a real issue|Cancel" \
  "$(nx "q = d['ask']['options'][0]['reason_question']; q['question'] + '|' + '|'.join(o['label'] for o in q['options'])")"

# --- Blocking questions come first ---
fresh; gpass intent
printf '\n### Open Questions\n- Blocking: Should N count from zero?\n- Deferred: later question\n\n### Decisions\n' >> .temper/specs/demo/intent.md
assert_eq "next: a Blocking open question is listed before the gate question" "Should N count from zero?" "$(nx "'|'.join(d.get('blocking', []))")"

# --- setup: next lists what the project still lacks ---
mkdir -p "$WORKDIR/bare" && (cd "$WORKDIR/bare" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base)
assert_eq "next: a project with nothing set up lists the config, the scaffold and the commit gate" "3|1|1|1" \
  "$(cd "$WORKDIR/bare" && _ev "s = d.get('setup', []); '|'.join([str(len(s)), str(int('templates/temper.config.default' in s[0])), str(int(s[1].endswith('temper init'))), str(int(s[2].endswith('guards/install.sh')))])" "$("$TEMPER" next --json)")"
(cd "$WORKDIR/bare" && mkdir -p .claude && cp "$REPO_ROOT/templates/temper.config.default" .claude/temper.config && "$TEMPER" init >/dev/null 2>&1 && bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1)
assert_eq "next: once set up, it lists nothing" "None" "$(cd "$WORKDIR/bare" && _ev "d.get('setup')" "$("$TEMPER" next --json)")"
cd "$WORKDIR" || exit 1

# --- the CLI refuses to leave a stage it should not ---
fresh
assert_exit "advance: refused while Intent has no verdict" 1 "$TEMPER" state advance intent_complete plan
assert_eq "advance: the refusal names the gate to run" "1" "$("$TEMPER" state advance intent_complete plan 2>&1 | grep -c 'run temper gate intent first')"
gfail intent "problem stated" "missing"
assert_exit "advance: refused while Intent failed and nobody skipped it" 1 "$TEMPER" state advance intent_complete plan
assert_eq "advance: the refusal says only the person may skip it" "1" "$("$TEMPER" state advance intent_complete plan 2>&1 | grep -c 'ask the person')"
"$TEMPER" override intent --reason "the person said so" >/dev/null 2>&1
assert_exit "advance: allowed once the person skipped the failed check" 0 "$TEMPER" state advance intent_complete plan
assert_exit "advance: refused from a stage the run is not at" 1 "$TEMPER" state advance intent_complete plan
gpass plan
assert_exit "advance: refused to a stage that is not the next one" 1 "$TEMPER" state advance plan_complete review
assert_exit "state set next_stage forward: refused past a stage that has no passing check" 1 "$TEMPER" state set next_stage review

# --- Plan: approval records what the person approved ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
printf '# Plan\n\n## Files to Modify\n| File | Change |\n|---|---|\n| `src/demo.sh` | the demo |\n| `README.md` | a line |\n' > .temper/specs/demo/plan.md
gpass plan
assert_eq "next: Plan PASS asks to approve the plan, three options and More options" \
  "Continue to Build (Recommended)|Open HTML review|Share HTML review|More options" "$(labels)"
assert_eq "next: More options holds the rest, as its own question" "Grill Me|Teach Me|Save for later" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['more']['question']['options'])")"
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "advance: leaving Plan keeps the plan's files as approved, and the commit the diff is read against" \
  "README.md,src/demo.sh|yes" \
  "$(python3 -c "import json; d = json.load(open('.temper/build-state.json')); print(','.join(sorted(d.get('approved_files', []))) + '|' + ('yes' if d.get('base_sha') else 'no'))")"
printf '| `src/widened.sh` | added during Build |\n' >> .temper/specs/demo/plan.md
"$TEMPER" evidence add --stage build --claim "a row" >/dev/null 2>&1
assert_eq "view: Build is held to the approved files, not to a plan.md edited since" "README.md,src/demo.sh|True" \
  "$(vw "','.join(sorted(d['guard']['plan_files'])) + '|' + str(d['plan']['approved'])")"

fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gpass plan
printf 'autonomy:\n  enabled: true\n' >> .claude/temper.config
assert_eq "next: with autonomy on, the Plan question offers the arming choice" \
  "Stage by stage (Recommended)|Autonomous: run the rest unattended|Open HTML review|More options" "$(labels)"
assert_eq "next: Autonomous arms the run before it advances" "arm|state set run_mode autonomous" \
  "$(nx "o = d['ask']['options'][1]; o['move'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
assert_eq "next: the Plan question has no walk through: More options holds the rest" "Share HTML review|Grill Me|Teach Me|Save for later" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['more']['question']['options'])")"

fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gpass plan
"$TEMPER" state set complexity medium >/dev/null 2>&1
assert_eq "next: a medium plan goes on to Design" "Continue to Design (Recommended)|state advance plan_complete design" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][-1].split('temper ', 1)[1]")"
assert_exit "advance: a medium plan may not skip Design" 1 "$TEMPER" state advance plan_complete build

# --- Review, Check, the loop budget ---
fresh; gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim "src/demo.sh:3 the input is not checked" --severity critical >/dev/null 2>&1
gfail review "no blocking findings" "1 open finding"
assert_eq "next: Review FAIL with an open finding: loop back first, accept a finding, override" \
  "Loop back to Build (Recommended)|Accept a finding|Override and continue|More options" "$(labels)"
assert_eq "next: the accept question lists the open finding by id, with its own reason question" \
  "Accept finding 1|accept|True|evidence accept --stage review --id 1 --reason '{reason}'" \
  "$(nx "o = d['ask']['accept']['options'][0]; '|'.join([o['label'], o['move'], str(o['reason']), o['calls'][0].split('temper ', 1)[1]])")"
assert_eq "next: the step back is a state loop with the person's reason" "back|state loop review build --reason '{reason}'" \
  "$(nx "o = d['ask']['options'][0]; o['move'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
printf 'loops:\n  max-per-type: 1\n' >> .claude/temper.config
"$TEMPER" state loop review build --reason "first" >/dev/null 2>&1
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
gfail review "no blocking findings" "1 open finding"
assert_eq "next: with the loop budget spent there is no Loop back option" "0" "$(labels | grep -c 'Loop back')"

fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gpass check
assert_eq "next: Check PASS is the one Commit question, with a loop back for what it passed with a warning" "Commit (Recommended)|Loop back to Build|Save for later|state advance check_complete commit" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['options']) + '|' + d['ask']['options'][0]['calls'][0].split('temper ', 1)[1]")"
echo '[]' > .temper/specs/demo/config-suggestions.json
assert_eq "next: config suggestions add their option" "Commit (Recommended)|Loop back to Build|Review config suggestions|Save for later" "$(labels)"

# --- the commit stage ---
"$TEMPER" state advance check_complete commit >/dev/null 2>&1
rm -f .temper/specs/demo/config-suggestions.json
assert_eq "next: at Commit with no verdict, the commit gate runs" "work|gate commit" "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
gpass commit
assert_eq "next: a passed commit gate gives the commit steps: the report page first, ending with the report and then state clear" \
  "work|intent complete|report --html|state archive|report|state clear" \
  "$(nx "s = d['steps']; '|'.join([d['action'], s[0].split('temper ', 1)[1], s[2].split('temper ', 1)[1], s[3].split('temper ', 1)[1], s[-2].split('temper ', 1)[1], s[-1].split('temper ', 1)[1]])")"
gfail commit "review gate" "FAIL, no override recorded"
assert_eq "next: a failed commit gate asks to override the failed stages, with a reason" \
  "Override and commit|commitOverride|override review --reason '{reason}'|gate commit" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['label'], o['move'], o['calls'][0].split('temper ', 1)[1], o['calls'][-1].split('temper ', 1)[1]])")"

# --- an armed run decides its own moves, and parks for the person ---
fresh; printf 'autonomy:\n  enabled: true\n' >> .claude/temper.config
gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1
gpass review
assert_eq "next: an armed run goes on by itself after a passed Review" "auto|state advance review_complete check" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
gfail review "no blocking findings" "1 open finding"
assert_eq "next: an armed run loops a failed Review back to Build by itself" "auto|state loop review build" \
  "$(nx "d['action'] + '|' + ' '.join(d['calls'][0].split('temper ', 1)[1].split()[:4])")"
"$TEMPER" park --verdict PARKED-NEEDS-DECISION --reason "a test" >/dev/null 2>&1
assert_eq "park: the run is interactive again, marked parked, and the report says where it waits" "interactive|review|1" \
  "$("$TEMPER" state get run_mode)|$("$TEMPER" state get parked)|$(grep -c 'The run waits for you at the gate it parked at' .temper/autonomy-report.md)"
assert_eq "next: after a park the person gets the gate question" "ask|Loop back to Build (Recommended)" \
  "$(nx "d['action'] + '|' + d['ask']['options'][0]['label']")"

# --- Run Build again ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "red then green" "no RED evidence for Task 1"
assert_eq "next: Build FAIL offers Run Build again first" "Run Build again (Recommended)|redo" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['move']")"
"$TEMPER" state redo build --reason "no RED evidence for Task 1" >/dev/null 2>&1
assert_eq "redo: the Build verdict goes, the run stays at Build and keeps its step" "none|build|2" \
  "$(python3 -c "import json; print(json.load(open('.temper/gates.json')).get('build', {}).get('verdict', 'none'))")|$("$TEMPER" state get next_stage)|$("$TEMPER" state get step)"
assert_eq "next: Build runs again as the fix pass, with what to mend" "temper:temper-build|1|gate build" \
  "$(nx "a = d['agents'][0]; a['type'] + '|' + str(int('Feedback re-entry: no RED evidence for Task 1' in a['prompt'])) + '|' + a['after'][-1].split('temper ', 1)[1]")"
assert_exit "redo: only the stage the run is at runs again" 1 "$TEMPER" state redo review

# --- grouped Build: groups start, tasks are handed out, the group question ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
rm -f .temper/groups.json
assert_eq "next: Build starts the group whose dependencies are met" "work|group start G1" \
  "$(nx "d['action'] + '|' + d['calls'][-1].split('temper ', 1)[1]")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": ".claude/worktrees/temper-demo-G1"}}, "tasks": {"1": {"status": "pending", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a ready task gets its own launch: task start, the task agent, then its task gate" \
  "work|temper:temper-build-task|task start 1|task gate 1 --model" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], a['before'][0].split('temper ', 1)[1], ' '.join(a['after'][0].split('temper ', 1)[1].split()[:4])])")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "running", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a running task is waited for" "wait|1" "$(nx "d['action'] + '|' + str(d['tasks'][0]['task'])")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a passed group gets the Build group question" "Build group|Continue (Recommended)|Change|Stop" \
  "$(nx "d['ask']['question']['header'] + '|' + '|'.join(o['label'] for o in d['ask']['question']['options'])")"
assert_exit "group continue: refused for a group that has not passed" 1 "$TEMPER" group continue G2
assert_exit "group continue: recorded for a passed group" 0 "$TEMPER" group continue G1
assert_eq "next: once every group continued, the groups are merged and Build is checked" "integrate|gate build" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['calls'])")"

# --- doors: a run started at a later stage checks the stages before it ---
setup; "$TEMPER" state init demo --enter review >/dev/null 2>&1
assert_eq "next: a door's earlier stage is checked, not run" "work|gate intent|0" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1] + '|' + str(len(d['agents']))")"
gpass intent
assert_eq "next: and then asked, with Continue and Save for later" "Continue to Plan (Recommended)|Save for later" "$(labels)"
assert_exit "state init: --enter takes a stage of the run" 1 "$TEMPER" state init demo --enter nowhere

# --- intent accept and complete ---
setup; sed -i.bak 's/^\*\*Status:\*\* accepted/**Status:** draft/' .temper/specs/demo/intent.md
"$TEMPER" intent accept >/dev/null 2>&1
assert_eq "intent accept: the Status turns accepted and Accepted-by is added once" "1|1" \
  "$(grep -c '^\*\*Status:\*\* accepted' .temper/specs/demo/intent.md)|$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent accept >/dev/null 2>&1
assert_eq "intent accept: a second call changes nothing" "1" "$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent complete >/dev/null 2>&1
assert_eq "intent complete: the Status turns completed with today's date" "1|1" \
  "$(grep -c '^\*\*Status:\*\* completed' .temper/specs/demo/intent.md)|$(grep -c "^\*\*Completed:\*\* $(date -u +%Y-%m-%d)" .temper/specs/demo/intent.md)"

# --- the view: written on every change, read only by the mod ---
fresh
assert_eq "view: state init writes the view of the new run" "1|demo|intent|here" \
  "$(vw "str(d['version']) + '|' + d['run']['slug'] + '|' + d['run']['stage'] + '|' + d['stages'][0]['mark']")"
gpass intent; "$TEMPER" evidence add --stage intent --claim "c" >/dev/null 2>&1
assert_eq "view: the current question is the one temper next gives" "yes" \
  "$(python3 -c "import json, subprocess, sys; v = json.load(open('.temper/view.json'))['ask']; n = json.loads(subprocess.run([sys.argv[1], 'next', '--json'], capture_output=True, text=True).stdout)['ask']; print('yes' if v == n else 'no')" "$TEMPER")"
before="$(stat -c %Y .temper/view.json 2>/dev/null || stat -f %m .temper/view.json)"; touch -d '2001-01-01' .temper/view.json 2>/dev/null || touch -t 200101010000 .temper/view.json
"$TEMPER" state get next_stage >/dev/null 2>&1
assert_eq "view: a read (state get) does not rewrite it" "2001" "$(date -r .temper/view.json +%Y 2>/dev/null || stat -f %Sm -t %Y .temper/view.json)"
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "view: temper next writes it again (a view lost or from an older Temper comes back)" "no" \
  "$([[ "$(date -r .temper/view.json +%Y 2>/dev/null || stat -f %Sm -t %Y .temper/view.json)" == 2001 ]] && echo yes || echo no)"
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1
assert_eq "view: an advance rewrites it: Intent passed, Plan here" "passed|here|plan" \
  "$(vw "d['stages'][0]['mark'] + '|' + d['stages'][1]['mark'] + '|' + d['run']['stage']")"
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "view: state clear leaves a view with no run" "None" "$(vw "d['run']")"
fresh; mkdir -p "$WORKDIR/elsewhere"; echo keep > "$WORKDIR/elsewhere/target.json"
rm -f .temper/view.json; ln -s "$WORKDIR/elsewhere/target.json" .temper/view.json
"$TEMPER" evidence add --stage intent --claim "c" >/dev/null 2>&1
assert_eq "view: a link at .temper/view.json is replaced, never written through" "keep|no" \
  "$(cat "$WORKDIR/elsewhere/target.json")|$([[ -L .temper/view.json ]] && echo yes || echo no)"
cp .temper/build-state.json "$WORKDIR/state-before.json"; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "next: it is a read: the run state is unchanged" "same" "$(cmp -s .temper/build-state.json "$WORKDIR/state-before.json" && echo same || echo changed)"

# --- Design, Check FAIL, a door's failed stage ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state set complexity complex >/dev/null 2>&1
"$TEMPER" state advance plan_complete design >/dev/null 2>&1
assert_eq "next: Design runs its brief" "temper:temper-design|gate design" "$(nx "d['agents'][0]['type'] + '|' + d['agents'][0]['after'][-1].split('temper ', 1)[1]")"
gpass design
assert_eq "next: Design PASS" "Continue to Build (Recommended)|Walk through step by step|Grill Me|More options" "$(labels)"
gfail design "areas of concern" "missing"
assert_eq "next: Design FAIL" "Loop back to Plan|Override and continue|Save for later" "$(labels)"

fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "next: Check FAIL" "Loop back to Build (Recommended)|Override and continue|Save for later" "$(labels)"
assert_eq "next: a question names the gate of its stage" "gate check" "$(nx "d['gate'].split('temper ', 1)[1]")"
assert_eq "next: the question names the failed row" "1" "$(nx "int('no passing test-run evidence recorded' in d['ask']['question']['question'])")"

setup; "$TEMPER" state init demo --enter check >/dev/null 2>&1; gfail intent "problem stated" "missing"
assert_eq "next: a door's failed earlier stage offers to run it, a skip with a reason, or Save for later" "Run Intent (Recommended)|Override and continue|Save for later" "$(labels)"

# --- groups that stop: a failed group gate, a parked group ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "gate": {"verdict": "FAIL", "reason": "Validate failed"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a failed group gate asks to run its tasks again" "Run the group's tasks again (Recommended)|group reopen G1 --task 1|1" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1] + '|' + str(int('Validate failed' in d['ask']['question']['question']))")"
printf 'autonomy:\n  enabled: true\n' >> .claude/temper.config; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_eq "next: an armed run parks on a failed group gate, as on every stop (nobody is there to answer)" "auto|park --verdict PARKED-NEEDS-DECISION|1" \
  "$(nx "d['action'] + '|' + ' '.join(d['calls'][0].split('temper ', 1)[1].split()[:3]) + '|' + str(int('Validate failed' in d['calls'][0]))")"
"$TEMPER" state set run_mode interactive >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "parked_reason": "Task 1 failed on haiku, haiku and sonnet"}}, "tasks": {"1": {"status": "failed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a group parked on failed attempts" "Run the task again (Recommended)|group reopen G1 --task 1" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "parked_foreign": ["abcdef1234567890"]}}, "tasks": {"1": {"status": "failed", "group": "G1", "worktree": "wt1"}}}\n' > .temper/groups.json
assert_eq "next: a group parked on an agent's commits: take them out, or keep them with a reason" \
  "Take the commits out and run the task again (Recommended)|Keep the agent's commits|Save for later|keep|True|group reopen G1 --task 1 --accept-foreign abcdef1" \
  "$(nx "o = d['ask']['options'][1]; '|'.join(x['label'] for x in d['ask']['options']) + '|' + o['move'] + '|' + str(o['reason']) + '|' + ' '.join(o['calls'][0].split('temper ', 1)[1].split()[:7])")"

# --- what the view carries for the drawing ---
fresh; gpass intent
"$TEMPER" evidence add --stage review --claim "src/demo.sh:12 the loop never ends" --severity high >/dev/null 2>&1
assert_eq "view: a finding keeps its file and line, and is open" "src/demo.sh|12|open|high" \
  "$(vw "f = d['findings'][0]; '|'.join([f['file'], str(f['line']), f['state'], f['severity']])")"
assert_eq "view: the intent's criteria, with their status" "AC-01:open|AC-02:open" "$(vw "'|'.join(c['id'] + ':' + c['status'] for c in d['criteria'])")"
assert_eq "view: a run that never left Intent with no spec file written is the TRIVIAL exit's case" "False" "$(vw "d['guard']['trivial_exit']")"
setup; rm -f .temper/specs/demo/*.md; "$TEMPER" state init demo >/dev/null 2>&1
assert_eq "view: a new run with an empty spec folder may take the TRIVIAL exit" "True" "$(vw "d['guard']['trivial_exit']")"

# --- the independent review of 9.7.0 (step 9): each finding, reproduced ---
# 1. No advance from a stage the run is not at: `started` is the state before Intent, never a stage to leave.
fresh
assert_exit "review 1: state advance started build is refused" 1 "$TEMPER" state advance started build
assert_exit "review 1: state advance started nowhere is refused" 1 "$TEMPER" state advance started nowhere
assert_eq "review 1: the run is still at Intent" "intent" "$("$TEMPER" state get next_stage)"
# 2. Text from a failed row or a finding is never shell code in a call the orchestrator runs as printed.
fresh; printf 'autonomy:\n  enabled: true\n' >> .claude/temper.config
gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1
gfail review "no blocking findings" 'src/a.sh:4 runs $(touch PWNED1) and `touch PWNED2` on install'
CALL="$(nx "d['calls'][0]")"; ( bash -c "$CALL" ) >/dev/null 2>&1
assert_eq "review 2: an armed loop back runs no text of the finding, and keeps it as written" "0|0|1" \
  "$([[ -e PWNED1 ]] && echo 1 || echo 0)|$([[ -e PWNED2 ]] && echo 1 || echo 0)|$(grep -c 'touch PWNED1' .temper/feedback-loops.json)"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "tests pass" 'npm test exited 1: `touch PWNED3` $(touch PWNED4)'
CALL="$(nx "d['ask']['options'][0]['calls'][0]")"; ( bash -c "$CALL" ) >/dev/null 2>&1
assert_eq "review 2: Run Build again runs no text of the failed row" "0|0" "$([[ -e PWNED3 ]] && echo 1 || echo 0)|$([[ -e PWNED4 ]] && echo 1 || echo 0)"
# 4. The files the person approved are the CLI's: no state set changes them.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_exit "review 4: state set approved_files is refused" 1 "$TEMPER" state set approved_files none
# 9. The TRIVIAL exit still holds after the Intent agent's after calls ran its gate.
setup; rm -f .temper/specs/demo/*.md; "$TEMPER" state init demo >/dev/null 2>&1; "$TEMPER" gate intent >/dev/null 2>&1
assert_eq "review 9: a run that never left Intent, with no spec file, may take the TRIVIAL exit after its gate ran" "True" "$(vw "d['guard']['trivial_exit']")"
# 10. A door's walked stage that fails its check names the failed rows in its question.
fresh; "$TEMPER" state clear >/dev/null 2>&1; "$TEMPER" state init demo --enter review >/dev/null 2>&1; gfail intent "problem stated" "no Problem section"
assert_eq "review 10: the walked stage's question names what failed" "1" "$(nx "int('problem stated: no Problem section' in d['ask']['question']['question'])")"

# --- the independent review of 9.7.0, round 2: each finding, reproduced ---
_walk_to_commit() { # a run of the demo spec with every stage passed, at the commit stage
  gpass intent plan build review check
  for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check check_complete:commit; do
    "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
}
# 1. A commit verdict written before the run reached Commit (a spec commit's hook) is not the commit gate's verdict.
fresh; gpass intent plan build review check
python3 -c "import json; p='.temper/gates.json'; d=json.load(open(p)); d['commit']={'verdict':'PASS','requirements':[]}; json.dump(d,open(p,'w'))"
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check check_complete:commit; do
  "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
assert_eq "round 2, 1: entering Commit drops an earlier commit verdict, so next runs the commit gate" "no|work|gate commit" \
  "$(python3 -c "import json; print('yes' if 'commit' in json.load(open('.temper/gates.json')) else 'no')")|$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
# 2. A run leaves a stage only by state advance: a forward state set next_stage is refused.
fresh; gpass intent plan
assert_exit "round 2, 2: state set next_stage forward is refused (Intent is left only by state advance)" 1 "$TEMPER" state set next_stage plan
assert_eq "round 2, 2: the run is still at Intent" "intent" "$("$TEMPER" state get next_stage)"
# 4. A loop goes back: to a stage before the one the run is at, never forward past a gate.
fresh; gfail intent "problem stated" "missing"
assert_exit "round 2, 4: state loop forward is refused" 1 "$TEMPER" state loop review build --reason x
assert_eq "round 2, 4: the run is still at Intent" "intent" "$("$TEMPER" state get next_stage)"
# 5. Park-on-touch reads the committed changes since base_sha too, not only the uncommitted ones.
fresh; printf 'autonomy:\n  enabled: true\n  park-on-touch: ["**/auth/**"]\n' >> .claude/temper.config
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base --no-verify >/dev/null 2>&1
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
mkdir -p src/auth; echo x > src/auth/login.ts; git add src/auth/login.ts; git -c user.email=t@t -c user.name=t commit -qm auth --no-verify >/dev/null 2>&1
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "round 2, 5: a committed change under a park-on-touch pattern fails the row" "False|1" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/gates.json'))['commit']['requirements'] if x['name']=='park-on-touch paths']; print(str(r[0]['pass']) + '|' + str(int('src/auth/login.ts' in r[0]['detail'])))")"
git rm -q -r src/auth >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm unauth --no-verify >/dev/null 2>&1
# 6, 7. The commit steps add what the run changed: no untracked file that was there before the run, every name quoted.
fresh; touch -d '2020-01-01' local.env
mkdir -p docs; : > 'docs/café.md'; : > 'x$(touch PWNED5).txt'
_walk_to_commit; gpass commit
ADD="$(nx "[x for x in d['steps'] if x.startswith('git add')][0]")"
assert_eq "round 2, 6: an untracked file older than the run is not added" "0|1" \
  "$(grep -c 'local.env' <<<"$ADD")|$(grep -c 'café.md' <<<"$ADD")"
( bash -c "$ADD" ) >/dev/null 2>&1; rc=$?
assert_eq "round 2, 7: the git add step runs as printed: no file name runs, a non ASCII name is added" "0|0|1" \
  "$rc|$([[ -e PWNED5 ]] && echo 1 || echo 0)|$(git diff --cached --name-only -z | tr '\0' '\n' | grep -c 'café.md')"
git reset -q >/dev/null 2>&1; rm -f local.env 'docs/café.md' 'x$(touch PWNED5).txt'
# 10. The person's own text goes into a call as one single quoted word, so a backquote in it is text.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "tests pass" "1 failed"
CALL="$(nx "[o for o in d['ask']['options'] if o['label'] == 'Override and continue'][0]['calls'][0]")"
REASON="it is \`touch PWNED6\` and it's fine"; Q="${REASON//\'/\'\\\'\'}"
( bash -c "${CALL//\{reason\}/$Q}" ) >/dev/null 2>&1
assert_eq "round 2, 10: a reason put in its placeholder as the page says is kept as written, and runs nothing" "0|1" \
  "$([[ -e PWNED6 ]] && echo 1 || echo 0)|$(grep -c 'touch PWNED6' .temper/overrides.json)"
assert_eq "round 2, 10: no call of flow.py puts a placeholder of the person's text in double quotes" "0" "$(grep -cE '\"\{(reason|text)\}|#\{K\}: \{text\}\"' "$REPO_ROOT/scripts/flow.py")"
# 11. Override and commit after a park on a commit row of its own (blast radius) records the person's skip.
fresh; _walk_to_commit; gfail commit "blast radius" "changed outside declared files: src/x"
assert_eq "round 2, 11: Override and commit skips the commit check with the person's reason" "override commit --reason" \
  "$(nx "' '.join([o for o in d['ask']['options'] if o['label'] == 'Override and commit'][0]['calls'][0].split('temper ', 1)[1].split()[:3])")"
# 12. The Design door of a run with no Design stage enters at Build: the stages before are walked, not run again.
setup; "$TEMPER" state init demo --enter design >/dev/null 2>&1; "$TEMPER" state set complexity simple >/dev/null 2>&1
assert_eq "round 2, 12: --enter design with no Design stage walks Intent" "work|gate intent|0" \
  "$(nx "d['action'] + '|' + (d['calls'][0].split('temper ', 1)[1] if d['calls'] else '') + '|' + str(len(d.get('agents') or []))")"
# 13. Stop at a group question saves the run; it records no Build verdict.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "round 2, 13: the group question's Stop makes no call" "Stop|0" "$(nx "o = [o for o in d['ask']['options'] if o['label'] == 'Stop'][0]; o['label'] + '|' + str(len(o.get('calls') or []))")"

# --- round 3: a narrow check of round 2 and a live run that looped back to Build ---
# 1. A task with a **File:** line for each file declares them all (the live run's task agent was held to the last one).
printf '# Tasks: x\n\n## Group G1: One\n**Depends:** none\n**Validate:** `true`\n\n### Task 1: a\n**File:** `orders.py`\n**File:** `tests/test_orders.py`, `orders.py`\n**Depends:** none\n**Test:** `true`\n' > r3-tasks.md
assert_eq "round 3, 1: a task with two **File:** lines declares the files of both, each once" "orders.py tests/test_orders.py" \
  "$(python3 "$REPO_ROOT/scripts/tasks_md.py" parse r3-tasks.md | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['tasks'][0]['files']))")"
rm -f r3-tasks.md
# 2. next_stage takes only a stage of the run's own sequence, so no other value opens a forward move.
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1
assert_exit "round 3, 2: state set next_stage to a value that is no stage of the run is refused" 1 "$TEMPER" state set next_stage bogus
assert_exit "round 3, 2: and Commit stays refused from RCA" 1 "$TEMPER" state set next_stage commit
assert_eq "round 3, 2: the fix run is still at RCA" "rca" "$("$TEMPER" state get next_stage)"
# 3. A project below the top of its git repository (a package of a monorepo): git names a file from the top, the
#    commit steps run in the project folder, so the changed files are named from there.
R3M="$WORKDIR/r3mono"; rm -rf "$R3M"; mkdir -p "$R3M/pkg/src" "$R3M/lib"; git -C "$R3M" init -q
echo x > "$R3M/pkg/src/made.py"; echo y > "$R3M/lib/shared.py"
assert_eq "round 3, 3: in a package of a monorepo the changed files are named from the project folder" '["../lib/shared.py", "src/made.py"]' \
  "$(cd "$R3M/pkg" && python3 "$REPO_ROOT/scripts/flow.py" changed "" "2020-01-01T00:00:00Z")"
assert_eq "round 3, 3: and git add finds them there" "0" "$(cd "$R3M/pkg" && git add -- src/made.py ../lib/shared.py >/dev/null 2>&1; echo $?)"
rm -rf "$R3M"
# 4. Every brief, reference page, command and pack puts the text an agent fills in single quotes, as the run page does.
assert_eq "round 3, 4: no placeholder of text stands in double quotes in a call of a brief, page, command or pack" "" \
  "$(grep -rnE -- '--[a-z-]+ "[^"]*(<[a-z]|\.\.\.)' "$REPO_ROOT/agents" "$REPO_ROOT/reference" "$REPO_ROOT/commands" "$REPO_ROOT/packs" "$REPO_ROOT/skills" "$REPO_ROOT/docs/grouped-build.md" | cut -d: -f1,2)"

# --- the view is local run state ---
fresh; "$TEMPER" init >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "init: view.json is listed in the clone's info/exclude, so it is never an untracked file of the project" "1|0" \
  "$(grep -cx '/.temper/view.json' "$(git rev-parse --git-common-dir)/info/exclude")|$(git status --porcelain --untracked-files=all | grep -c 'view.json')"

# --- a /temper:fix run ---
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1
assert_eq "next: a fix run starts at the RCA question" "Proceed to Fix (Recommended)|state advance rca_complete fix" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
mkdir -p .temper/specs/demo-bug; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
assert_eq "next: Fix runs its brief and is judged by the build gate" "temper:temper-fix|gate build" \
  "$(nx "d['agents'][0]['type'] + '|' + d['agents'][0]['after'][-1].split('temper ', 1)[1]")"
gpass build
assert_eq "next: a question names the gate to run again after a typed change; at Fix it is the build gate" "ask|fix|gate build" \
  "$(nx "d['action'] + '|' + d['stage'] + '|' + d['gate'].split('temper ', 1)[1]")"
gpass build; "$TEMPER" state advance fix_complete review >/dev/null 2>&1
assert_eq "next: a fix run's Review reads rca.md (fix mode)" "temper:temper-review|1" \
  "$(nx "d['agents'][0]['type'] + '|' + str(int('Fix mode: there is no intent.md' in d['agents'][0]['prompt']))")"
gpass review check; "$TEMPER" state advance review_complete check >/dev/null 2>&1; "$TEMPER" state advance check_complete commit >/dev/null 2>&1; gpass commit
assert_eq "next: a fix run's commit steps add the incident to .temper/lessons.md, which the next RCA reads, and commit it" "work|1|1" \
  "$(nx "s = d['steps']; d['action'] + '|' + str(int(any('.temper/lessons.md' in x and 'reference/fix.md' in x for x in s))) + '|' + str(int(any(x.startswith('git add') and '.temper/lessons.md' in x for x in s)))")"
setup

# --- the view fixtures the mod's tests import are the CLI's own output ---
# The mod's tests read view.json as the CLI writes it at each point of a run (the mod's tests cannot read a file, so the
# views are a generated module). Regenerated here: a change of the view or of a question shows up as a difference.
assert_eq "view fixtures: the module the mod's tests import is what the CLI writes now (run make-view-fixtures.sh)" "same" \
  "$(bash "$REPO_ROOT/scripts/selftest/make-view-fixtures.sh" 2>/dev/null | cmp -s - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" && echo same || echo differs)"
assert_eq "view fixtures: the next field carries the calls of the CLI's own action" "state advance build_complete review" \
  "$(python3 - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read().split("= ", 1)[1])
print(d["armed-build-pass"]["next"]["calls"][0].split("temper ", 1)[1])
PY
)"
# --- the end of run report page (scripts/run_report.py) ---
fresh; printf '# Intent: </style><script>x</script>\n' > .temper/specs/demo/intent.md
"$TEMPER" evidence add --stage review --claim "src/a.ts:3 a token </td> leaks" --severity high --confidence 0.85 >/dev/null 2>&1
assert_eq "report --html: writes report.html in the spec folder" "OK: wrote $WORKDIR/.temper/specs/demo/report.html|1" \
  "$("$TEMPER" report --html 2>&1)|$([[ -f .temper/specs/demo/report.html ]] && echo 1 || echo 0)"
assert_eq "report --html: run text is escaped, so it cannot break the page" "0|yes" \
  "$(grep -c '</style><script>' .temper/specs/demo/report.html)|$(grep -q '&lt;/style&gt;&lt;script&gt;' .temper/specs/demo/report.html && echo yes || echo no)"
assert_eq "report --html: a finding shows its confidence and where it is" "1|1" \
  "$(grep -c '<td>0.85</td>' .temper/specs/demo/report.html)|$(grep -c '<code>src/a.ts:3</code>' .temper/specs/demo/report.html)"
assert_eq "report --html: -o - prints the page" "1" "$("$TEMPER" report --html -o - | grep -c '<!doctype html>')"
assert_exit "report --html: never writes inside the plugin folder" 2 "$TEMPER" report --html -o "$REPO_ROOT/x.html"
assert_exit "evidence add: a confidence outside 0 to 1 is refused" 1 "$TEMPER" evidence add --stage review --claim x --confidence 1.5
"$TEMPER" usage add --stage plan --model claude-sonnet-4-6 --tokens 1500000 --ms 120000 >/dev/null 2>&1
"$TEMPER" usage add --stage build --model claude-haiku-4-5 --tokens 2500 --ms 3000 >/dev/null 2>&1
"$TEMPER" report --html >/dev/null 2>&1
assert_eq "report --html: time and tokens by stage (with the model each stage ran on) and by model, in words" "1|1|1|1" \
  "$(grep -c '<td>claude-haiku-4-5</td><td>1</td><td>2k</td><td>3 s</td>' .temper/specs/demo/report.html)|$(grep -c '<td>claude-sonnet-4-6</td><td>1</td><td>1.5M</td><td>2 min</td>' .temper/specs/demo/report.html)|$(grep -c '<th>Model</th><th>Launches</th>' .temper/specs/demo/report.html)|$(grep -c '<td>plan</td><td>claude-sonnet-4-6</td><td>1</td><td>1.5M</td><td>2 min</td>' .temper/specs/demo/report.html)"
# Done only once the Commit gate has passed; a run at Commit before that is still in progress.
python3 - "$WORKDIR" <<'PY'
import json, sys
base = {"version": 1, "run": {"slug": "demo", "title": "t", "spec": ".temper/specs/demo", "stage": "commit"},
        "loops": [{"from": "review", "to": "build", "reason": "a real bug", "iteration": 1, "max": 2}]}
for name, verdict in (("passed", "PASS"), ("waiting", None)):
    v = dict(base, stages=[{"id": "build", "label": "Build", "mark": "passed", "verdict": "PASS"},
                           {"id": "review", "label": "Review", "mark": "passed", "verdict": "PASS"},
                           {"id": "commit", "label": "Commit", "mark": "here", "verdict": verdict}])
    json.dump(v, open("%s/commit-%s.json" % (sys.argv[1], name), "w"))
PY
assert_eq "report --html: Done once the Commit gate passed, In progress before" "1|0|1" \
  "$(python3 "$REPO_ROOT/scripts/run_report.py" render --view commit-passed.json -o - | grep -c ' · Done</div>')|$(python3 "$REPO_ROOT/scripts/run_report.py" render --view commit-waiting.json -o - | grep -c ' · Done</div>')|$(python3 "$REPO_ROOT/scripts/run_report.py" render --view commit-waiting.json -o - | grep -c 'In progress (Commit)')"
assert_eq "report --html: a loop back reads with the stage names and its reason" "1" \
  "$(python3 "$REPO_ROOT/scripts/run_report.py" render --view commit-passed.json -o - | grep -c '↺ Review to Build (1 of 2): a real bug')"
setup
