# ADR 0013: the CLI says what comes next (temper next --json), writes the view the mod reads
# (.temper/view.json), and refuses to leave a stage whose check failed unless the person skipped it.
# Sourced by test-temper.sh (assert_eq, assert_exit, setup, $TEMPER).

# The helpers this file and the later ones use (_ev, nx, vw, labels, gpass, gfail, fresh) are in case-helpers.sh.

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
"$TEMPER" evidence add --stage intent --phase note --claim 'keep the demo to one screen' >/dev/null 2>&1   # WP13: a note at Intent keeps its question
gpass intent
assert_eq "next: Intent PASS asks the Temper gate question with its four options, exactly" \
  "ask|Temper gate|Intent: the check passed. Accept the intent and continue to Plan?" \
  "$(nx "d['action'] + '|' + d['ask']['question']['header'] + '|' + d['ask']['question']['question']")"
assert_eq "next: the Intent PASS options" "Continue to Plan (Recommended)|Grill Me|Teach Me|Save for later" "$(labels)"
_b="$(git symbolic-ref -q HEAD)"; git branch -f temper-test-other HEAD >/dev/null 2>&1; git symbolic-ref HEAD refs/heads/temper-test-other   # on another branch than the run's, at the same commit
assert_eq "next: Continue to Plan is the person's answer: accept the intent, then advance; no branch and no commit before the approval (WP12)" \
  "approve|intent accept|state advance intent_complete plan|2" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['move']] + [c.split('temper ', 1)[1] for c in (o['calls'][0], o['calls'][-1])] + [str(len(o['calls']))])")"
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
assert_eq "next: a project with nothing set up lists the config, the scaffold and the commit gate, each a call of the CLI" "3|1|1|1" \
  "$(cd "$WORKDIR/bare" && _ev "s = d.get('setup', []); '|'.join([str(len(s)), str(int(s[0].endswith('scripts/temper config init'))), str(int(s[1].endswith('temper init'))), str(int(s[2].endswith('scripts/temper guards install')))])" "$("$TEMPER" next --json)")"
# 9.8.1: each setup call is the CLI with plain words (the mod runs it with no shell): run them as listed, word by word.
(cd "$WORKDIR/bare" && "$TEMPER" next --json | python3 -I -c 'import json,sys; [print(c) for c in json.load(sys.stdin).get("setup", [])]' \
  | while read -r -a W; do "${W[@]}" >/dev/null 2>&1; done)
assert_eq "next: once set up by its own calls, it lists nothing; config init leaves a config that is there" "None|1|1" \
  "$(cd "$WORKDIR/bare" && _ev "d.get('setup')" "$("$TEMPER" next --json)")|$(cmp -s "$WORKDIR/bare/.claude/temper.config" "$REPO_ROOT/templates/temper.config.default" && echo 1)|$(cd "$WORKDIR/bare" && "$TEMPER" config init | grep -c 'already there')"
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
assert_eq "next: Plan PASS with no Design to follow offers ask at every stage or the run to the commit, then Fresh review first (WP11)" \
  "ask-every-stage,True|approve-run,False|fresh-review,False|more,False" \
  "$(nx "'|'.join('%s,%s' % (o['id'], bool(o.get('recommended'))) for o in d['ask']['options'])")"
assert_eq "next: More options holds the rest, as its own question, Run Design first in Teach Me's place (WP14)" "Open HTML review|Run Design first|Loop back to Intent|Save for later" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['more']['question']['options'])")"
cp .claude/temper.config .claude/temper.config.keep; printf 'plan:\n  fresh-review: off\n' >> .claude/temper.config
assert_eq "next: with plan.fresh-review off the Plan question has no Fresh review first" \
  "ask-every-stage|approve-run|html-review|more|run-design|grill-me|back|save" \
  "$(nx "'|'.join(o['id'] for o in d['ask']['options'])")|$(nx "'|'.join(o['id'] for o in d['ask']['more']['options'])")"
mv .claude/temper.config.keep .claude/temper.config
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "advance: leaving Plan keeps the plan's files as approved, and the commit the diff is read against" \
  "src/demo.sh|yes" \
  "$(python3 -c "import json; d = json.load(open('.temper/build-state.json')); print(','.join(sorted(d.get('approved_files', []))) + '|' + ('yes' if d.get('base_sha') else 'no'))")"
printf '| `src/widened.sh` | added during Build |\n' >> .temper/specs/demo/plan.md
"$TEMPER" evidence add --stage build --claim "a row" >/dev/null 2>&1
assert_eq "view: Build is held to the approved files, not to a plan.md edited since" "src/demo.sh|True" \
  "$(vw "','.join(sorted(d['guard']['plan_files'])) + '|' + str(d['plan']['approved'])")"

fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gpass plan
printf 'autonomy:\n  enabled: true\n' >> .claude/temper.config
assert_eq "next: with autonomy on, the Plan question offers the run to the commit first and recommended (WP11)" \
  "approve-run,True|ask-every-stage,False|fresh-review,False|more,False" \
  "$(nx "'|'.join('%s,%s' % (o['id'], bool(o.get('recommended'))) for o in d['ask']['options'])")"
assert_eq "next: Approve and build starts the run to the commit before it advances" "arm|state set run_mode autonomous" \
  "$(nx "o = [x for x in d['ask']['options'] if x['id'] == 'approve-run'][0]; o['move'] + '|' + o['calls'][0].split('temper ', 1)[1].split(' --shown ')[0]")"
assert_eq "next: the Plan question has no walk through: More options holds the rest" "Open HTML review|Run Design first|Loop back to Intent|Save for later" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['more']['question']['options'])")"

fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; gpass plan
"$TEMPER" state set complexity medium >/dev/null 2>&1; riskH; fresh_reviewed
assert_eq "next: a medium plan at risk H goes on to Build: Design runs only when asked (WP14), with the digests shown (WP12)" \
  "ask-every-stage,True|state advance plan_complete build|shown" \
  "$(nx "o = d['ask']['options'][0]; c = o['calls'][-1]; '%s,%s' % (o['id'], bool(o.get('recommended'))) + '|' + c.split('temper ', 1)[1].split(' --shown ')[0] + ('|shown' if ' --shown intent.md=' in c and ' --shown tasks.md=' in c else '|no digests')")"
"$TEMPER" state set want_design true >/dev/null 2>&1   # the person asked for Design (the option run-design)
assert_eq "next: a plan whose person asked for Design goes on to Design, with the digests shown (WP12)" \
  "Continue to Design (Recommended)|state advance plan_complete design|shown" \
  "$(nx "o = d['ask']['options'][0]; c = o['calls'][-1]; o['label'] + '|' + c.split('temper ', 1)[1].split(' --shown ')[0] + ('|shown' if ' --shown intent.md=' in c and ' --shown tasks.md=' in c else '|no digests')")"
assert_exit "advance: a run whose person asked for Design may not skip it" 1 "$TEMPER" state advance plan_complete build

# --- Review, Check, the loop budget ---
fresh; gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim "src/demo.sh:3 the input is not checked" --severity critical >/dev/null 2>&1
gfail review "no blocking findings" "1 open finding"
# WP24: Repair again is offered exactly where its call may start (repair_ops.can_start); this run has no reviewed HEAD,
# so it is not, and the loop back is the first answer (case file 65 holds the question where the repair may start)
assert_eq "WP24 next: Review FAIL with an open finding and no reviewed HEAD: no Repair again, the loop back first and recommended, accept a finding, override" \
  "back,True,back|back,accept-finding,override|no repair-again" \
  "$(nx "o = d['ask']['options'][0]; a = d['ask']['options'] + d['ask'].get('more', {}).get('options', []); i = [x['id'] for x in a]; '%s,%s,%s' % (o['id'], bool(o.get('recommended')), o.get('move')) + '|' + ','.join(x for x in ('back', 'accept-finding', 'override') if x in i) + '|' + ('repair-again offered' if 'repair-again' in i else 'no repair-again')")"
assert_eq "next: the accept question lists the open finding by id, with its own reason question" \
  "Accept finding 1|accept|True|evidence accept --stage review --id 1 --reason '{reason}'" \
  "$(nx "o = d['ask']['accept']['options'][0]; '|'.join([o['label'], o['move'], str(o['reason']), o['calls'][0].split('temper ', 1)[1]])")"
assert_eq "WP24 next: the step back is a state loop with the person's reason" "back|state loop review build --reason '{reason}'" \
  "$(nx "o = [x for x in d['ask']['options'] + d['ask'].get('more', {}).get('options', []) if x['id'] == 'back'][0]; o['move'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
printf 'budget:\n  per-failure: 1\n' >> .claude/temper.config   # WP10: the budget's key, in the place of loops.max-per-type
"$TEMPER" state loop review build --reason "first" >/dev/null 2>&1
gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
gfail review "no blocking findings" "1 open finding"
assert_eq "next: with the loop budget spent there is no Loop back option" "0" "$(labels | grep -c 'Loop back')"

fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gpass check
assert_eq "next: Check PASS is the one Commit question, with a loop back for what it passed with a warning" "Commit (Recommended)|Loop back to Build|Commit and open PR|More options|state advance check_complete commit" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['options']) + '|' + d['ask']['options'][0]['calls'][0].split('temper ', 1)[1]")"
echo '[]' > .temper/specs/demo/config-suggestions.json
assert_eq "next: config suggestions add their option; the small change goes under More options" "Commit (Recommended)|Loop back to Build|Commit and open PR|More options" "$(labels)"

# --- the commit stage ---
"$TEMPER" state advance check_complete commit >/dev/null 2>&1
rm -f .temper/specs/demo/config-suggestions.json
assert_eq "next: at Commit with no verdict, the commit gate runs" "work|gate commit" "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
gpass commit
assert_eq "next: a passed commit gate gives the report steps first: the intent completed, the report printed for the person to see" \
  "work|intent complete|report --end|1" \
  "$(nx "s = d['steps']; '|'.join([d['action'], s[0].split('temper ', 1)[1], s[2].split('temper ', 1)[1], str(int('into your reply' in s[3] and 'Bash call' in s[3]))])")"
"$TEMPER" report --end >/dev/null 2>&1
assert_eq "next: after the report, the page is written with no question (9.8.0)" "work|report --html" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
assert_exit "state set: end_report is the CLI's" 1 "$TEMPER" state set end_report none
"$TEMPER" report --no-html >/dev/null 2>&1
assert_eq "next: after the answer, the commit steps: the ledger archived, the commit (9.8.0: one temper call), the state cleared" \
  "work|state archive|spec commit|state clear|3" \
  "$(nx "s = d['steps']; '|'.join([d['action'], s[0].split('temper ', 1)[1], s[1].split('temper ', 1)[1][:11], s[-1].split('temper ', 1)[1], str(len(s))])")"
"$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --html >/dev/null 2>&1
assert_eq "report: --end and the answer count once each, in order: a second report --end changes nothing" "none|1" \
  "$("$TEMPER" state get end_report)|$(nx "int(d['action'] == 'work' and d['steps'][0].endswith('state archive'))")"
gfail commit "review gate" "FAIL, no override recorded"
assert_eq "next: a failed commit gate asks to override the failed stages, with a reason" \
  "Override and commit|commitOverride|override review --reason '{reason}'|gate commit" \
  "$(nx "o = d['ask']['options'][0]; '|'.join([o['label'], o['move'], o['calls'][0].split('temper ', 1)[1], o['calls'][-1].split('temper ', 1)[1]])")"

# --- WP11: the run to the commit, started at the approval: a passed check moves on by itself and keeps the mode; a stop
# keeps the mode too, and the person gets the gate question ---
_unattended build; gpass build
assert_eq "next: an unattended run's passed Build goes on to Review by itself and keeps its mode (WP11)" \
  "auto|state advance build_complete review|1" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1] + '|' + str(len(d['calls']))")"
"$TEMPER" state advance build_complete review >/dev/null 2>&1; "$TEMPER" state set run_mode interactive >/dev/null 2>&1
gpass review
assert_eq "next: after the unattended Build, a passed Review asks the person" "ask|Continue to Check (Recommended)" \
  "$(nx "d['action'] + '|' + d['ask']['options'][0]['label']")"
_unattended review; gpass review
assert_eq "next: an unattended run's passed Review goes on to Check by itself (WP11)" "auto|state advance review_complete check" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
gfail review "no blocking findings" "1 open finding"
assert_eq "next: an unattended run's failed Review with no blocking finding on record stops: the park call first (WP11)" \
  "auto|park --verdict PARKED-NEEDS-DECISION" "$(nx "d['action'] + '|' + ' '.join(d['calls'][0].split('temper ', 1)[1].split()[:3])")"
"$TEMPER" park --verdict PARKED-NEEDS-DECISION --reason "a test" >/dev/null 2>&1
assert_eq "park: the run keeps its mode, is marked parked, and the report says where it waits (WP11)" "autonomous|review|1" \
  "$("$TEMPER" state get run_mode)|$("$TEMPER" state get parked)|$(grep -c 'The run waits for you at the question of the stage where it stopped' .temper/autonomy-report.md)"
assert_eq "WP24 next: after a park the person gets the gate question, the loop back first and recommended where the repair may not start" "ask|back,True" \
  "$(nx "d['action'] + '|' + '%s,%s' % (d['ask']['options'][0]['id'], bool(d['ask']['options'][0].get('recommended')))")"

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
"$TEMPER" acceptance skip --reason "the scheduling cases below" >/dev/null 2>&1   # 9.8.0: else the acceptance writer comes first
assert_eq "next: Build starts the group whose dependencies are met" "work|group start G1" \
  "$(nx "d['action'] + '|' + d['calls'][-1].split('temper ', 1)[1]")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": ".claude/worktrees/temper-demo-G1"}}, "tasks": {"1": {"status": "pending", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a ready task gets its own launch: task start, the task agent, then its time and its task gate" \
  "work|temper:temper-build-task|task start 1|usage add --stage build|task gate 1 --model" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], a['before'][0].split('temper ', 1)[1], ' '.join(a['after'][0].split('temper ', 1)[1].split()[:4]), ' '.join(a['after'][1].split('temper ', 1)[1].split()[:4])])")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "running", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a running task is waited for" "wait|1" "$(nx "d['action'] + '|' + str(d['tasks'][0]['task'])")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: the one group of a plan, passed, goes on by itself (9.8.0: the Build question follows at once)" "auto|group continue G1" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"
assert_exit "group continue: refused for a group that has not passed" 1 "$TEMPER" group continue G2
assert_exit "group continue: recorded for a passed group" 0 "$TEMPER" group continue G1
assert_eq "next: once every group continued, the groups are merged and Build is checked" "integrate|gate build" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['calls'])")"

# --- intent accept and complete ---
setup; sed -i.bak 's/^\*\*Status:\*\* accepted/**Status:** draft/' .temper/specs/demo/intent.md
"$TEMPER" intent accept >/dev/null 2>&1
assert_eq "intent accept: the Status turns accepted and Accepted-by is added once" "1|1" \
  "$(grep -c '^\*\*Status:\*\* accepted' .temper/specs/demo/intent.md)|$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent accept >/dev/null 2>&1
assert_eq "intent accept: a second call changes nothing" "1" "$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
assert_eq "intent accept: Accepted-by records the person at the gate, never git's name or email" "**Accepted-by:** the person at the Intent gate" \
  "$(grep '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent complete >/dev/null 2>&1
assert_eq "intent complete: the Status turns completed with today's date" "1|1" \
  "$(grep -c '^\*\*Status:\*\* completed' .temper/specs/demo/intent.md)|$(grep -c "^\*\*Completed:\*\* $(date -u +%Y-%m-%d)" .temper/specs/demo/intent.md)"

# --- the view: written on every change, read only by the mod ---
fresh
assert_eq "view: state init writes the view of the new run" "1|demo|intent|here" \
  "$(vw "str(d['version']) + '|' + d['run']['slug'] + '|' + d['run']['stage'] + '|' + d['stages'][0]['mark']")"
gpass intent; "$TEMPER" evidence add --stage intent --claim "c" >/dev/null 2>&1
"$TEMPER" evidence add --stage intent --phase note --claim 'keep the demo to one screen' >/dev/null 2>&1   # WP13: a note at Intent keeps its question
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
"$TEMPER" state set want_design true >/dev/null 2>&1   # the person asked for Design at the approval (WP14: only then it runs)
"$TEMPER" state advance plan_complete design >/dev/null 2>&1
assert_eq "next: Design runs its brief" "temper:temper-design|gate design" "$(nx "d['agents'][0]['type'] + '|' + d['agents'][0]['after'][-1].split('temper ', 1)[1]")"
gpass design
assert_eq "next: Design PASS is the approval when the person asked for Design: ask at every stage or the run to the commit (WP11)" \
  "ask-every-stage,True|approve-run,False|walk-through,False|more,False" \
  "$(nx "'|'.join('%s,%s' % (o['id'], bool(o.get('recommended'))) for o in d['ask']['options'])")"
gfail design "areas of concern" "missing"
assert_eq "next: Design FAIL" "Loop back to Plan|Override and continue|Save for later" "$(labels)"

fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "next: Check FAIL on a missing measurement (no test run recorded) offers Run Check again first, the small change under More options" "Run Check again (Recommended)|Loop back to Build|Override and continue|More options" "$(labels)"
assert_eq "next: a question names the gate of its stage" "gate check" "$(nx "d['gate'].split('temper ', 1)[1]")"
assert_eq "next: the question names the failed row" "1" "$(nx "int('no passing test-run evidence recorded' in d['ask']['question']['question'])")"


# --- groups that stop: a failed group gate, a parked group ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "gate": {"verdict": "FAIL", "reason": "Validate failed"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a failed group gate asks to run its tasks again" "Run the group's tasks again (Recommended)|group reopen G1 --task 1|1" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1] + '|' + str(int('Validate failed' in d['ask']['question']['question']))")"
_g8="$(cat .temper/groups.json)"; _unattended build; printf '%s\n' "$_g8" > .temper/groups.json
assert_eq "next: an unattended run takes the recommended repair of a failed group gate by rule, once (WP11)" \
  "auto|group reopen G1 --task 1|1" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1] + '|' + str(len(d['calls']))")"
"$TEMPER" state set run_mode interactive >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "parked_reason": "Task 1 failed on haiku, haiku and sonnet"}}, "tasks": {"1": {"status": "failed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "next: a group parked on failed attempts" "Run the task again (Recommended)|group reopen G1 --task 1" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + o['calls'][0].split('temper ', 1)[1]")"
_p8_run_again() { nx "d['ask']['options'][0]['description']"; }
_p8_default="$(_p8_run_again)"; printf 'models:\n  task: opus\n' >> .claude/temper.config
assert_eq "next: Run the task again names the task model its tasks run on again, the table's or the config's (WP27)" \
  "The tasks run again from their first attempt, on sonnet.|The tasks run again from their first attempt, on opus." \
  "$_p8_default|$(_p8_run_again)"
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
setup; rm -f .temper/specs/demo/*.md; "$TEMPER" state init demo >/dev/null 2>&1; _base_known
# WP17: trivial_exit says the run state holds the trivial verdict (`temper intent trivial`), the window of its one write
_tv8="before=$(vw "d['guard']['trivial_exit']")"
"$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true
assert_eq "view: a new run with an empty spec folder opens the trivial window once the verdict is recorded (WP17)" \
  "before=False|after=True" "$_tv8|after=$(vw "d['guard']['trivial_exit']")"

# --- the independent review of 9.7.0 (step 9): each finding, reproduced ---
# 1. No advance from a stage the run is not at: `started` is the state before Intent, never a stage to leave.
fresh
assert_exit "review 1: state advance started build is refused" 1 "$TEMPER" state advance started build
assert_exit "review 1: state advance started nowhere is refused" 1 "$TEMPER" state advance started nowhere
assert_eq "review 1: the run is still at Intent" "intent" "$("$TEMPER" state get next_stage)"
# 2. Text from a failed row or a finding is never shell code in a call the orchestrator runs as printed.
_unattended build   # WP11: the run to the commit is started at the approval
gfail build "tests pass" 'src/a.sh:4 runs $(touch PWNED1) and `touch PWNED2` on install'
CALL="$(nx "d['calls'][0]")"; ( bash -c "$CALL" ) >/dev/null 2>&1
assert_eq "review 2: an armed run's park runs no text of the failed row, and keeps it as written" "0|0|1" \
  "$([[ -e PWNED1 ]] && echo 1 || echo 0)|$([[ -e PWNED2 ]] && echo 1 || echo 0)|$(grep -q 'touch PWNED1' .temper/autonomy-report.md && echo 1 || echo 0)"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "tests pass" 'npm test exited 1: `touch PWNED3` $(touch PWNED4)'
CALL="$(nx "d['ask']['options'][0]['calls'][0]")"; ( bash -c "$CALL" ) >/dev/null 2>&1
assert_eq "review 2: Run Build again runs no text of the failed row" "0|0" "$([[ -e PWNED3 ]] && echo 1 || echo 0)|$([[ -e PWNED4 ]] && echo 1 || echo 0)"
# 4. The files the person approved are the CLI's: no state set changes them.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_exit "review 4: state set approved_files is refused" 1 "$TEMPER" state set approved_files none
# 9. The trivial window still holds after the Intent agent's after calls ran its gate (WP17: once the verdict is
#    recorded).
setup; rm -f .temper/specs/demo/*.md; "$TEMPER" state init demo >/dev/null 2>&1; _base_known
"$TEMPER" intent trivial --why "a typo in the help text" >/dev/null 2>&1 || true; "$TEMPER" gate intent >/dev/null 2>&1
assert_eq "review 9: the trivial window still holds after the Intent agent's gate ran (WP17: the verdict recorded)" "True" \
  "$(vw "d['guard']['trivial_exit']")"

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
_ran_unattended; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "round 2, 5: a committed change under a park-on-touch pattern fails the row" "False|1" \
  "$(python3 -c "import json; r=[x for x in json.load(open('.temper/gates.json'))['commit']['requirements'] if x['name']=='sensitive paths']; print(str(r[0]['pass']) + '|' + str(int('src/auth/login.ts' in r[0]['detail'])))")"
git rm -q -r src/auth >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm unauth --no-verify >/dev/null 2>&1
# 6, 7. The commit steps add what the run changed: no untracked file that was there before the run, every name quoted.
fresh; touch -d '2020-01-01' local.env
mkdir -p docs; : > 'docs/café.md'; : > 'x$(touch PWNED5).txt'
_walk_to_commit; gpass commit; "$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --no-html >/dev/null 2>&1
ADD="$(nx "[x for x in d['steps'] if ' spec commit ' in x][0]")"
assert_eq "round 2, 6: an untracked file older than the run is not added" "0|1" \
  "$(grep -c 'local.env' <<<"$ADD")|$(grep -c 'café.md' <<<"$ADD")"
git config user.email t@t; git config user.name t   # the step commits as printed: CI has no global identity
_pre="$(git rev-parse HEAD)"; ( bash -c "$ADD" ) >/dev/null 2>&1; rc=$?
assert_eq "round 2, 7: the commit step runs as printed (9.8.0: temper spec commit): no file name runs, a non ASCII name is committed" "0|0|1" \
  "$rc|$([[ -e PWNED5 ]] && echo 1 || echo 0)|$(git diff --name-only -z "$_pre" HEAD | tr '\0' '\n' | grep -c 'café.md')"
git reset -q --soft "$_pre" >/dev/null 2>&1; git reset -q >/dev/null 2>&1; rm -f local.env 'docs/café.md' 'x$(touch PWNED5).txt'
# 10. The person's own text goes into a call as one single quoted word, so a backquote in it is text.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "tests pass" "1 failed"
CALL="$(nx "[o for o in d['ask']['options'] if o['label'] == 'Override and continue'][0]['calls'][0]")"
REASON="it is \`touch PWNED6\` and it's fine"; Q="${REASON//\'/\'\\\'\'}"
( bash -c "${CALL//\{reason\}/$Q}" ) >/dev/null 2>&1
assert_eq "round 2, 10: a reason put in its placeholder as the page says is kept as written, and runs nothing" "0|1" \
  "$([[ -e PWNED6 ]] && echo 1 || echo 0)|$(grep -c 'touch PWNED6' .temper/overrides.json)"
assert_eq "round 2, 10: no call of flow.py puts a placeholder of the person's text in double quotes" "0" "$(_flow_text | grep -cE '\"\{(reason|text)\}|#\{K\}: \{text\}\"')"
# 11. A commit row of its own (blast radius) is not cleared by an override of the commit check (9.8.5, Q8: the same question
# came back after it), so the override is not offered there; Add to plan is.
fresh; _walk_to_commit; gfail commit "blast radius" "changed outside declared files: src/x"
assert_eq "round 2, 11: no Override and commit for the commit gate's own row; Add to plan is first" "Add to plan (Recommended)|0" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + str(sum(1 for x in o if x['label'] == 'Override and commit'))")"
# 11b. M11 of WP08: the state of 5 (no plan, so no scope row), at the commit stage and parked: only the commit gate's own
# row failed, so an option runs the commit gate again, first and with no mark (the question says "then check again").
fresh; gpass intent plan build review check; _at commit; rm -f .temper/specs/demo/tasks.md
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base --no-verify >/dev/null 2>&1
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
mkdir -p src/auth; echo x > src/auth/login.ts; git add src/auth/login.ts; git -c user.email=t@t -c user.name=t commit -qm auth --no-verify >/dev/null 2>&1
_ran_unattended; "$TEMPER" gate commit >/dev/null 2>&1
_park8="$(nx "' '.join(d.get('calls') or [])")"; [[ "$_park8" == *" park --verdict "* ]] && bash -c "$_park8" >/dev/null 2>&1
assert_eq "round 2, 11b: only the commit gate's own row failed: Check again is first" "commit.fail|check-again|False|gate commit" \
  "$(nx "q = d.get('ask') or {}; o = (q.get('options') or [{}])[0]; '%s|%s|%s|%s' % (q.get('id'), o.get('id'), bool(o.get('recommended')), ((o.get('calls') or ['none'])[-1]).split('temper ', 1)[-1])")"
git rm -q -r src/auth >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm unauth --no-verify >/dev/null 2>&1
# 13. Stop at a group question saves the run; it records no Build verdict.
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1; second_group
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "round 2, 13: the group question's Stop makes no call" "Stop|0" "$(nx "o = [o for o in d['ask']['options'] if o['label'] == 'Stop'][0]; o['label'] + '|' + str(len(o.get('calls') or []))")"

# --- round 3: a narrow check of round 2 and a live run that looped back to Build ---
# 1. A task with a **File:** line for each file declares them all (the live run's task agent was held to the last one).
printf '# Tasks: x\n\n## Group G1: One\n**Depends:** none\n**Validate:** `true`\n\n### Task 1: a\n**File:** `orders.py`\n**File:** `unit/test_orders.py`, `orders.py`\n**Depends:** none\n**Test:** `true`\n' > r3-tasks.md
assert_eq "round 3, 1: a task with two **File:** lines declares the files of both, each once" "orders.py unit/test_orders.py" \
  "$(python3 "$REPO_ROOT/scripts/tasks_md.py" parse r3-tasks.md | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['tasks'][0]['files']))")"
rm -f r3-tasks.md
# 2. next_stage takes only a stage of the run's own sequence, so no other value opens a forward move.
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1; _base_known
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
# WP08 (U19): the run files pull request 115 added are local run state too, and a cleared run leaves none of them
_ex="$(git rev-parse --git-common-dir)/info/exclude"
# (WP21: the two stores of the plan's old per command check are gone; decisions.json and the files of the repeats and
# of the rule log are the run files left of that list)
_u19_listed="$(for f in decisions.json budget.json rule-log.json; do grep -qxF "/.temper/$f" "$_ex" && echo yes || echo no; done | paste -sd' ' -)"
for f in decisions.json budget.json rule-log.json; do echo '{}' > ".temper/$f"; done
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "the run files of pull request 115 are listed and cleared" "yes yes yes|0" \
  "$_u19_listed|$(for f in decisions.json budget.json rule-log.json; do [[ -e ".temper/$f" ]] && echo "$f"; done | wc -l | tr -d ' ')"

# --- a /temper:fix run ---
setup; "$TEMPER" state init demo-bug --command fix >/dev/null 2>&1; _base_known
# R3-1: with no rca.md written there is nothing to approve, so the same question offers the root cause agent again, or Save
assert_eq "next: a fix run starts at the RCA question with nothing to approve yet, read by its id and its options (WP17)" \
  "rca.approve|redo,save" "$(nx "a = d['ask']; a['id'] + '|' + ','.join(o.get('id') for o in a['options'])")"
mkdir -p .temper/specs/demo-bug; printf 'CAUSE: the demo bug\nFIX: the demo fix\n' > .temper/specs/demo-bug/rca.md   # as the root cause agent writes it
assert_eq "next: with a cause and a fix on rca.md the RCA question's approve option advances the run" \
  "state advance rca_complete fix" \
  "$(nx "import re; cs = [re.sub(r' --shown \\S+', '', c.split('temper ', 1)[1])
  for o in d['ask']['options'] for c in o.get('calls') or []]; adv = 'state advance rca_complete fix'; adv if adv in cs else ','.join(cs)")"
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
assert_eq "next: a fix run's report steps no longer write the lesson (9.8.0: the Fix agent writes it, agents/fix.md)" "work|0|1" \
  "$(nx "s = d['steps']; d['action'] + '|' + str(int(any('lessons.md' in x for x in s)))")|$(grep -c 'append one' "$REPO_ROOT/agents/fix.md")"
"$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --no-html >/dev/null 2>&1
assert_eq "next: a fix run's commit steps commit .temper/lessons.md" "work|1" \
  "$(nx "s = d['steps']; d['action'] + '|' + str(int(any(' spec commit ' in x and '.temper/lessons.md' in x for x in s)))")"
setup

# --- the view fixtures the mod's tests import are the CLI's own output ---
# The mod's tests read view.json as the CLI writes it at each point of a run (the mod's tests cannot read a file, so the
# views are a generated module). Regenerated here: a change of the view or of a question shows up as a difference.
assert_eq "view fixtures: the module the mod's tests import is what the CLI writes now (run make-view-fixtures.sh)" "same" \
  "$(bash "$REPO_ROOT/scripts/selftest/make-view-fixtures.sh" 2>/dev/null | cmp -s - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" && echo same || echo differs)"
assert_eq "view fixtures: the second module (the states 9.7.5 added) is what the CLI writes now (make-view-fixtures.sh extra)" "same" \
  "$(bash "$REPO_ROOT/scripts/selftest/make-view-fixtures.sh" extra 2>/dev/null | cmp -s - "$REPO_ROOT/scripts/selftest/view-fixtures-2.ts" && echo same || echo differs)"
# trap 5 of WP24 (lane E, RE13): a fixture view stands where a repair may start, so the mod's audit of every option of
# every fixture view makes the Repair again call with no matching answer
assert_eq "view fixtures: a view offers Repair again (repair-again), with its call repair start --again" "yes" \
  "$(python3 - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" "$REPO_ROOT/scripts/selftest/view-fixtures-2.ts" <<'PY'
import json, sys
found = []
def walk(o):
    if isinstance(o, dict):
        if o.get("id") == "repair-again" and any("repair start --stage" in c and c.endswith("--again") for c in o.get("calls") or []):
            found.append(o)
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
for f in sys.argv[1:]:
    walk(json.loads(open(f).read().split("= ", 1)[1]))
print("yes" if found else "no")
PY
)"
assert_eq "view fixtures: the next field carries the calls of the CLI's own action" "state advance build_complete review" \
  "$(python3 - "$REPO_ROOT/scripts/selftest/view-fixtures.ts" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read().split("= ", 1)[1])
print(d["armed-build-pass"]["next"]["calls"][0].split("temper ", 1)[1])
PY
)"
# WP16: what the fixture views hold of the closed list. _fx8 <python code>: runs the code with `views`, every view of
# both generated modules by name, `walk(x)`, every dict inside x, and prints r.
_fx8() {
  python3 -B - "$REPO_ROOT" "$1" <<'PY'
import json, re, sys
root = sys.argv[1]
views = {}
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    text = open("%s/scripts/selftest/%s" % (root, f)).read()
    views.update(json.loads(text.split("= ", 1)[1].strip().rstrip(";")))
def walk(x):
    if isinstance(x, dict):
        yield x
        for v in x.values():
            yield from walk(v)
    elif isinstance(x, list):
        for v in x:
            yield from walk(v)
CLI = "/plugin/scripts/temper "
SEVEN = ["config-suggestions", "depth-review", "html-review", "pipeline-fix", "pull-request", "small-change", "talk"]
STAY = ["accept", "cancel", "more"]
r = None
exec(sys.argv[2])
print(r)
PY
}
assert_eq "view fixtures: no call of the flow is a foreign program: every string of every calls list starts with the CLI's path (WP16)" "0 []" \
  "$(_fx8 "bad = ['%s: %s' % (n, str(c)[:60]) for n, v in sorted(views.items()) for d in walk(v) if isinstance(d.get('calls'), list) for c in d['calls'] if not str(c).startswith(CLI)]
r = '%d %s' % (len(bad), bad[:2])")"
assert_eq "view fixtures: every needs kind is on the closed list, and no option carries a do text without a needs (WP16)" \
  "config-suggestions,depth-review,html-review,pipeline-fix,pull-request,small-change,talk|0 []|0 []|yes" \
  "$(_fx8 "sys.path.insert(0, root + '/scripts')
try:
    from flow_base import NEEDS
    kinds = ','.join(sorted(set(NEEDS) - set(STAY))) if set(NEEDS) <= set(SEVEN + STAY) else 'NEEDS holds %s' % sorted(NEEDS)
except ImportError:
    kinds = 'no NEEDS in scripts/flow_base.py'
odd = ['%s: %s' % (n, d.get('needs')) for n, v in sorted(views.items()) for d in walk(v) if 'needs' in d and d.get('needs') not in SEVEN + STAY]
bare = ['%s: %s' % (n, d.get('id')) for n, v in sorted(views.items()) for d in walk(v) if d.get('do') and not d.get('needs')]
seen = any('needs' in d for v in views.values() for d in walk(v))
r = '%s|%d %s|%d %s|%s' % (kinds, len(odd), odd[:2], len(bare), bare[:2], 'yes' if seen else 'no option carries a needs')")"
assert_eq "view fixtures: a gate question carries typed calls, with the state redo call only at Intent, Plan, Design, Build and Fix (WP16)" "0 []|yes" \
  "$(_fx8 "FIVE = ('intent', 'plan', 'design', 'build', 'fix')
bad, redone = [], 0
for n, v in sorted(views.items()):
    a = v.get('ask') or {}
    if a.get('kind') != 'gate':
        continue
    stage = a.get('stage') or (v.get('run') or {}).get('stage') or ''
    t = a.get('typed')
    calls = t.get('calls') if isinstance(t, dict) else None
    if not calls:
        bad.append('%s: no typed calls' % n)
        continue
    note = any(re.search(r\" evidence add --stage \\S+ --phase note --kind input --claim '\\{text\\}'\$\", c) for c in calls)
    redo = [c for c in calls if ' state redo ' in c]
    again = t.get('again') is True
    redone += 1 if redo else 0
    if not note:
        bad.append('%s: no note call' % n)
    if redo and not all(re.search(r\" state redo %s --reason '\\{text\\}'\$\" % stage, c) for c in redo):
        bad.append('%s: %s' % (n, redo[0][-60:]))
    if bool(redo) != (stage in FIVE and not again):
        bad.append('%s: stage %s, again %s, redo %s' % (n, stage, again, bool(redo)))
r = '%d %s|%s' % (len(bad), bad[:2], 'yes' if redone else 'no gate question holds a redo')")"
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
"$TEMPER" usage add --stage plan --model claude-sonnet-4-6 --ms 120000 >/dev/null 2>&1
"$TEMPER" usage add --stage build --model claude-haiku-4-5 --ms 3000 >/dev/null 2>&1
"$TEMPER" report --html >/dev/null 2>&1
assert_eq "report --html: time by stage (with the model each stage ran on) and by model, in words, and no token count" "1|1|1|1|0" \
  "$(grep -c '<td>claude-haiku-4-5</td><td>1</td><td>3 s</td>' .temper/specs/demo/report.html)|$(grep -c '<td>claude-sonnet-4-6</td><td>1</td><td>2 min</td>' .temper/specs/demo/report.html)|$(grep -c '<th>Model</th><th>Launches</th><th>Time</th>' .temper/specs/demo/report.html)|$(grep -c '<td>plan</td><td>claude-sonnet-4-6</td><td>1</td><td>2 min</td>' .temper/specs/demo/report.html)|$(grep -c '<th>Tokens</th>' .temper/specs/demo/report.html)"
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

# --- 9.8.4 7a: "Include what is left out" passes the whole list to Plan, never the first 100 characters ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state set complexity simple >/dev/null 2>&1
printf 'plan:\n  context-check: always\n' >> .claude/temper.config   # WP13: a map that fits is folded into the approval
cat > .temper/specs/demo/plan.md <<'PEOF'
## Context Map
- use: src/ (3 files)
- ignore: ledger/export.py: refunds in exports are out of scope for this change and stay as they are
- ignore: ledger/report.py: the monthly report is already correct and reads the same rows
- reviewed: pending

## Plan
PEOF
assert_eq "9.8.4 7a: the Include call carries the whole text, the second left out source and its last word included" "yes" \
  "$(nx "c = d['context_check']['options'][1]['calls'][0]; 'yes' if 'reads the same rows' in c and c.endswith('--redo') else c")"
# phase 4b review: a typed answer at the Context check runs the question's own answer call, as at a gate
gfail plan "context map reviewed" "the Context check is pending: the person's answer is not recorded yet"
assert_eq "WP16: the Context check carries typed: its own answer call, which sends Plan back (again false)" \
  "plan.context|plan review --answer '{text}' --redo|False" \
  "$(nx "a = d.get('ask') or {}; t = a.get('typed') or {}; cs = [c.split('temper ', 1)[1] for c in t.get('calls') or []]; \
'%s|%s|%s' % (a.get('id'), '|'.join(cs), t.get('again'))")"
assert_eq "view fixtures: the Context check carries typed, its own answer call (WP16)" \
  "plan review --answer '{text}' --redo|False" \
  "$(_fx8 "a = views['context-check'].get('ask') or {}
t = a.get('typed') or {}
r = '%s|%s' % ('|'.join(c.split('temper ', 1)[1] for c in t.get('calls') or []), t.get('again'))")"

# --- 9.8.4 fault 2: a failed group check names what failed, and stops recommending a blind retry ---
_g2() { # _g2 <gate JSON>: a run at Build with group G1 (Task 1 passed) whose gate is the JSON given
  fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "$1" > .temper/groups.json
}
_g2 '"fails": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a", "FAIL: test_b", "FAIL: test_c", "FAIL: test_d"]}'
assert_eq "9.8.4 2b: every task passed and the group check failed: one fix agent on the merged tree is first and recommended" \
  "Fix the group's merged work (Recommended)|group fix G1|Run the group's tasks again" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + o[0]['calls'][0].split('temper ', 1)[1] + '|' + o[1]['label']")"
assert_eq "9.8.4 2a: the question shows the first FAIL lines of the group's Validate output, not all of them" "1|1|0" \
  "$(nx "q = d['ask']['question']['question']; '%d|%d|%d' % ('FAIL: test_a' in q, 'FAIL: test_c' in q, 'FAIL: test_d' in q)")"
_g2 '"fails": 2, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.4 2c: the second failure says how many times the group failed, and never recommends running the tasks again" "1|0" \
  "$(nx "q = d['ask']['question']; '%d|%d' % ('failed its check 2 times' in q['question'], any(o['label'] == \"Run the group's tasks again (Recommended)\" for o in q['options']))")"
_g2 '"fails": 2, "gate": {"verdict": "FAIL", "reason": "uncommitted changes in the group worktree, not on its branch: src/a.sh"}'
assert_eq "9.8.4 2c: a second failure that ran no check recommends the loop back to Plan, not the tasks again" "Loop back to Plan (Recommended)|Run the group's tasks again" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + o[1]['label']")"
_g2 '"fails": 1, "gate": {"verdict": "FAIL", "reason": "uncommitted changes in the group worktree, not on its branch: src/a.sh"}'
assert_eq "9.8.4 2c: the first failure that ran no check still recommends running the tasks again" "Run the group's tasks again (Recommended)" \
  "$(nx "d['ask']['options'][0]['label']")"
_g2 '"fails": 1, "fix": {"requested": "2026-01-01T00:00:00Z"}, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.4 2b: the fix asked for launches one Build fix agent on the group's worktree; the CLI commits its work after it" \
  "work|temper:temper-build|1|1|1|group fix G1 --commit|none" \
  "$(nx "a = d['agents']; p = a[0]['prompt']; '|'.join([d['action'], a[0]['type'], str(len(a)), str(int('Group fix: group G1' in p)), str(int('FAIL: test_a' in p)), a[0]['after'][-1].split('temper ', 1)[1], str(a[0].get('gate') or 'none')])")"
# the commit clears the gate, so the group is checked again as an ordinary call of the CLI (a FAIL there asks the question again)
_g2 '"fails": 1, "gate": null'
assert_eq "9.8.4 2b: after the fix's commit the next action checks the group again" "work|group gate G1" \
  "$(nx "d['action'] + '|' + d['calls'][0].split('temper ', 1)[1]")"

# --- 9.8.4 fault 3: a loop back carries what was learned ---
# 3a: a loop from Plan back to Intent keeps the open fresh review finding and the person's reason, and the next Plan agent gets both
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" evidence add --stage plan --phase fresh --severity high --claim "[readiness] Task 2: AC-03 has no test that can fail" >/dev/null 2>&1
"$TEMPER" state loop plan intent --reason "AC-03 must be measurable" >/dev/null 2>&1
assert_eq "9.8.4 3a: the Intent agent after the loop back gets the reason and the open fresh review finding" "1|1" \
  "$(nx "p = d['agents'][0]['prompt']; '%d|%d' % ('AC-03 must be measurable' in p, 'AC-03 has no test that can fail' in p)")"
gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
assert_eq "9.8.4 3a: the Plan agent after Intent gets the reason and the open fresh review finding too" "temper:temper-plan|1|1" \
  "$(nx "a = d['agents'][0]; p = a['prompt']; '%s|%d|%d' % (a['type'], 'AC-03 must be measurable' in p, 'AC-03 has no test that can fail' in p)")"
# 3c: a loop from Build to Plan puts the group gate's reason and FAIL lines first, and never the expected RED runs of the tasks
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do
  ev_red build "Task $n unit test red"
done
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "fails": 3, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: cases 8 expect the old message"]}}}, "tasks": {}}\n' > .temper/groups.json
"$TEMPER" state loop build plan --reason "G1 cannot pass" >/dev/null 2>&1
assert_eq "9.8.4 3c: the Plan prompt after a loop from Build names the group gate's reason and FAIL lines first, and no RED run" "1|1|0" \
  "$(nx "p = d['agents'][0]['prompt']; i = p.find('What Build left open'); '%d|%d|%d' % (p.find('1. group G1', i) > 0, 'FAIL: cases 8 expect the old message' in p, 'unit test red' in p)")"

# --- 9.8.4 fault 2: the group question converges: a fix that did not make the group pass is not recommended again ---
_g2c() { # _g2c <gate JSON>: as _g2, with group G1's fields given
  fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", %s}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' "$1" > .temper/groups.json
}
_g2c '"fails": 2, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}'
assert_eq "9.8.4 2c: after a fix of the merged tree that did not pass, Loop back to Plan is recommended and the fix is still offered" \
  "Loop back to Plan (Recommended)|Fix the group's merged work|1" \
  "$(nx "o = d['ask']['options']; q = d['ask']['question']['question']; o[0]['label'] + '|' + o[1]['label'] + '|' + str(int('A fix of its merged work did not make it pass' in q))")"
# WP10: a step back from a failed group check spends group:G1; two spend it, and the question is run.budget
for _g2ci in 1 2; do
  "$TEMPER" state loop build plan --reason "x" >/dev/null 2>&1; gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w", "branch": "temper/demo/G1", "fails": 3, "fix_tries": 1, "gate": {"verdict": "FAIL", "reason": "group G1 Validate failed (exit 1): make test", "ran": true, "fail_lines": ["FAIL: test_a"]}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
done
assert_eq "9.8.4 2c: with the step back to Plan spent, Save for later is recommended: no retry is" "Save for later (Recommended)|0" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + str(sum(1 for x in o if '(Recommended)' in x['label'] and x['label'] != 'Save for later (Recommended)'))")"

# --- 9.8.4 reverify: the fix pass ends with the CLI's scenario run; Build that fails the same way after running again is not run again ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "confirmed": "t", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
# 9.8.5 (S7): a fix pass needs a fault to fix; here the person's note is that fault
"$TEMPER" evidence add --stage build --phase note --kind input --claim "the export drops refunds" >/dev/null 2>&1
assert_eq "9.8.4 reverify: the fix pass of an integrated run reruns the scenario tests before the Build gate" "integrate|gate build" \
  "$(nx "a = d['agents'][0]['after']; a[-2].split('temper ', 1)[1] + '|' + a[-1].split('temper ', 1)[1]")"
gfail build "tests pass" "the last test run failed"
assert_eq "9.8.4 reverify: a first failure recommends running Build again" "Run Build again (Recommended)" "$(nx "d['ask']['options'][0]['label']")"
"$TEMPER" state redo build --reason "tests pass: the last test run failed" >/dev/null 2>&1; gfail build "tests pass" "the last test run failed"
assert_eq "9.8.4 reverify: the same failure after running again recommends Save for later, and says so" "Save for later (Recommended)|Run Build again|1" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + o[1]['label'] + '|' + str(int('failed the same way after it ran again' in d['ask']['question']['question']))")"

# --- 9.8.4 bench: Check that misses the same measurement after running again is not run again by the recommendation ---
fresh; gpass intent plan build review
for s in intent_complete:plan plan_complete:build build_complete:review review_complete:check; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "9.8.4 bench: a missing measurement first recommends running Check again" "Run Check again (Recommended)" "$(nx "d['ask']['options'][0]['label']")"
"$TEMPER" state redo check --reason "$(nx "d['ask']['options'][0]['calls'][0].split('--reason ', 1)[1]" | python3 -c "import shlex, sys; print(shlex.split(sys.stdin.read())[0])")" >/dev/null 2>&1
gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "9.8.4 bench: the same gap after running again recommends Save for later, and says so" "Save for later (Recommended)|Run Check again|1" \
  "$(nx "o = d['ask']['options']; o[0]['label'] + '|' + o[1]['label'] + '|' + str(int('failed the same way after it ran again' in d['ask']['question']['question']))")"

# --- 9.8.4 bench: a group parked on a blocked task asks for the plan first, naming the file and the task that declares it ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "parked", "worktree": "w", "parked_reason": "Task 1 needs src/b.sh, outside its declared files"}}, "tasks": {"1": {"status": "failed", "group": "G1", "blocked": {"needs": "src/b.sh", "owners": [2], "reason": "the test needs the b event"}}}}\n' > .temper/groups.json
assert_eq "9.8.4 blocked: Loop back to Plan is recommended at once, and the question names the file, its task and why" "Loop back to Plan (Recommended)|Run the task again|1" \
  "$(nx "o = d['ask']['options']; q = d['ask']['question']['question']; o[0]['label'] + '|' + o[1]['label'] + '|' + str(int('Task 1 needs src/b.sh, which Task 2 declares' in q and 'the test needs the b event' in q))")"
setup

# --- WP23: at a failed Build gate the next step is read from the open failure records. A record of class environment
#     is the setup question, with no fix agent, in a run the person drives; a run that goes on by itself stops there.
#     The record is written as scripts/failure.py writes it (docs/plans/one-go/wp/phase-5-checks.md, mechanism 11) ---
_env8() { # a run at Build whose integrate failed on a setup line that failed, with its one open record
  fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "confirmed": "t", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "FAIL", "reason": "integration suite failed (exit 125): bash suite.sh", "merged": true}}\n' > .temper/groups.json
  gfail build "integration" "integration suite failed (exit 125): bash suite.sh"
  python3 - <<'PY'
import json
json.dump([{"id": "F1", "ts": "2026-11-19T00:00:00Z", "stage": "build", "scope": "gate:build", "check": "suite",
            "cmd": "bash suite.sh", "exit": 125, "ran_by": "cli", "tree": "t8", "setup": "s8", "limit_s": 600, "key": "k8",
            "class": "environment", "kind": "setup-line", "class_by": "exit",
            "why": "the setup block failed (temper-setup: FAIL (exit 1))", "fail_lines": ["temper-setup: FAIL (exit 1)"],
            "row": "build#1", "n": 1, "step": "", "resolved": None}], open(".temper/evidence/failures.json", "w"), indent=2)
# the record's row on the Build ledger, as integrate leaves it (a record stands only while its failure is there)
json.dump([{"claim": "unit tests", "phase": "green", "cmd": "true", "exit_code": 0, "executed_by": "cli"},
           {"claim": "Integration suite", "phase": "integration", "cmd": "bash suite.sh", "exit_code": 125, "executed_by": "cli",
            "key": "k8", "tree": "t8", "output": "temper-setup: FAIL (exit 1)"}], open(".temper/evidence/build.json", "w"), indent=2)
PY
}
_env8
_r8="driven=$(nx "o = d['ask'].get('options', []) + (d['ask'].get('more') or {}).get('options', []) if d.get('ask') else []; ids = [x.get('id') for x in o]; '%s:%s:%s' % (d.get('action'), ','.join(i for i in ('check-again', 'it-is-the-code', 'save') if i in ids) or 'no setup options', 'no agent' if not d.get('agents') else 'agents')")"
_env8; _ran_unattended
_r8+="|by itself=$(nx "c = ' '.join(d.get('calls') or []); 'stop' if d.get('action') == 'auto' and ' park ' in c and not d.get('agents') else '%s %s' % (d.get('action'), [a.get('type') for a in d.get('agents') or []])")"
assert_eq "WP23: an open record of class environment at the failed Build gate is the setup question with no fix agent; a run that goes on by itself stops there" \
  "driven=ask:check-again,it-is-the-code,save:no agent|by itself=stop" "$_r8"
setup
