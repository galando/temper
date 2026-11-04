# Release 9.7.5, the checks that hold the rest together (F4, F15, F22, F23). Sourced by test-temper.sh after temper-cases-12.sh
# (helpers: nx, vw, labels, gpass, gfail, fresh, setup, _at, _three_groups, _change_tasks, f9_tasks).

# --- F15. Build runs the same with the mod off: nothing in the CLI reads TEMPER_MOD, and next and the view do not differ ---
_same_with_mod_off() { # _same_with_mod_off: next --json and view.json with TEMPER_MOD unset, off and on
  local a b c va vb
  a="$("$TEMPER" next --json 2>/dev/null)"; va="$(python3 -c "import json; d=json.load(open('.temper/view.json')); d.pop('written', None); print(json.dumps(d, sort_keys=True))")"
  b="$(TEMPER_MOD=off "$TEMPER" next --json 2>/dev/null)"; vb="$(python3 -c "import json; d=json.load(open('.temper/view.json')); d.pop('written', None); print(json.dumps(d, sort_keys=True))")"
  c="$(TEMPER_MOD=on "$TEMPER" next --json 2>/dev/null)"
  [[ "$a" == "$b" && "$a" == "$c" && "$va" == "$vb" ]] && echo same || echo differs
}
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
f9_tasks > .temper/specs/demo/tasks.md; rm -f .temper/groups.json
assert_eq "F15: Build starts its groups the same with the mod off" "same" "$(_same_with_mod_off)"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": ".claude/worktrees/temper-demo-G1"}}, "tasks": {"1": {"status": "pending", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F15: handing out a task is the same with the mod off" "same" "$(_same_with_mod_off)"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {"1": {"status": "running", "group": "G1", "attempt": 1}}}\n' > .temper/groups.json
assert_eq "F15: the wait for a running task is the same with the mod off" "same" "$(_same_with_mod_off)"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F15: the group question is the same with the mod off" "same" "$(_same_with_mod_off)"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
gfail build "criteria validated" "AC-01 FAIL: scenario 'first' (no Test: line) has no row run by the CLI."
assert_eq "F15: the fix pass and the failed gate are the same with the mod off" "same" "$(_same_with_mod_off)"
printf '# Tasks: demo\n\n### Task 1: a\n**File:** `src/a.sh`\n**Test:** `true`\n**Cases:**\n- a\n- [ ] done\n' > .temper/specs/demo/tasks.md; rm -f .temper/groups.json
assert_eq "F15: the stop for a plan with no groups is the same with the mod off, and Build does not stop for the mod" "same|0" \
  "$(_same_with_mod_off)|$(TEMPER_MOD=off "$TEMPER" next --json | grep -c 'TEMPER_MOD')"
assert_eq "F15: nothing in the CLI, the flow or the orchestrator page reads or sets TEMPER_MOD" "0" \
  "$(cd "$REPO_ROOT" && grep -l 'TEMPER_MOD' scripts/temper scripts/flow.py scripts/cli_ctx.py commands/temper.md | wc -l | tr -d ' ')"

# --- F4. A failed call stops its action; an agent's gate call named gate is the one exception ---
assert_eq "F4: commands/temper.md and docs/flow.md state the rule" "1|1" \
  "$(grep -c 'A failed call stops its action' "$REPO_ROOT/commands/temper.md" | sed 's/^[1-9][0-9]*$/1/')|$(grep -c 'A failed call stops its action' "$REPO_ROOT/docs/flow.md" | sed 's/^[1-9][0-9]*$/1/')"
assert_eq "F4: the agent's gate call is the last of its after calls and is named gate" "1" \
  "$(fresh; nx "int(d['agents'][0]['gate'] == d['agents'][0]['after'][-1])")"

# --- F23. Every pull request is a draft: no step, brief or page runs gh pr create without --draft, and none runs gh pr ready ---
assert_eq "F23: no gh pr create without --draft, and no gh pr ready command, in the flow, the references and the briefs" "0|0" \
  "$(cd "$REPO_ROOT" && grep -rhE 'gh pr create' scripts/flow.py scripts/cli_ctx.py reference agents commands | grep -v -e '--draft' -e 'never' -e 'without' | wc -l | tr -d ' ')|$(cd "$REPO_ROOT" && grep -rhE '^[[:space:]]*(\$ )?gh pr ready' reference agents commands scripts/flow.py | wc -l | tr -d ' ')"

# --- F22. A real Maven run needs java and the artifacts; without them the case says SKIP and counts as nothing ---
if command -v mvn >/dev/null 2>&1 && command -v java >/dev/null 2>&1 && [[ -d "${HOME:-/nonexistent}/.m2" ]]; then
  assert_eq "F22: a real Maven is on this machine; the fake mvn cases above are the checks (a real run needs the project's artifacts)" "yes" "yes"
else
  echo "SKIP: F22 real Maven case: java, mvn or the local repository is not here"
fi

# --- The audit of the port: the checks the first pass left to a direct call or to the e2e driver ---
# F27. Nothing to stage: a spec folder that git tracks and that has not changed gives no git add and no git commit
fresh; gpass intent plan build review check commit
git add -A >/dev/null 2>&1; git -c user.email=t@example.com -c user.name=T commit -qm "the spec is committed" >/dev/null 2>&1
_at commit; "$TEMPER" report --end >/dev/null 2>&1; "$TEMPER" report --no-html >/dev/null 2>&1
assert_eq "F27: a committed, unchanged spec folder with no code says there is no record commit, and gives no git add" "1|0" \
  "$(nx "str(sum(1 for s in d['steps'] if s.startswith('There is no record commit'))) + '|' + str(sum(1 for s in d['steps'] if s.startswith('git add')))")"
echo "a changed line" >> .temper/specs/demo/intent.md
assert_eq "F27: a changed spec folder gets its record commit" "0|1" \
  "$(nx "str(sum(1 for s in d['steps'] if s.startswith('There is no record commit'))) + '|' + str(sum(1 for s in d['steps'] if s.startswith('git add')))")"
git checkout -q -- . >/dev/null 2>&1

# F8. The plan gate names a scenario without a Test: line; the CLI refuses a scenario name intent.md does not hold
fresh; f9_intent "true" "true"; sed -i '/^  Test: /d' .temper/specs/demo/intent.md
assert_eq "F8: the plan gate row scenario test commands names a scenario with no Test: line" "1" \
  "$("$TEMPER" gate plan 2>&1 | grep -c "scenario test commands.*alpha")"
f9_intent "true" "true"
assert_eq "F8: evidence run --scenario refuses a name intent.md does not hold" "refused" \
  "$("$TEMPER" evidence run --stage build --scenario 'no such scenario' --claim x -- true >/dev/null 2>&1 && echo ran || echo refused)"

# F12. The schedule's ready line shows the manual flag
printf '# Tasks: demo\n\n**Integration:** `true`\n\n## Group G1: A\n**Depends:** none\n**Validate:** `true`\n**Context:**\nx\n\n### Task 1: hand check\n**File:** `docs/a.md`\n**Test:** manual - a person reads it\n**Cases:**\n- reads well\n- [ ] done\n' > .temper/specs/demo/tasks.md
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w"}}, "tasks": {}}\n' > .temper/groups.json
assert_eq "F12: a manual task's ready line carries manual true" "true" \
  "$("$TEMPER" schedule 2>/dev/null | head -1 | python3 -c "import json,sys; print(str(json.loads(sys.stdin.readline())['manual']).lower())")"

# F14. A gate run from the commit hook neither marks the small change's step nor closes its window
fresh; gpass intent plan build review check
"$TEMPER" adhoc open --stage check --reason 'a small fix' >/dev/null 2>&1
"$TEMPER" gate commit --from-hook >/dev/null 2>&1
assert_eq "F14: the window is still open after a gate run from the hook" "check" \
  "$(python3 -c "import json; print((json.load(open('.temper/build-state.json')).get('adhoc') or {}).get('stage', 'closed'))")"
"$TEMPER" adhoc close >/dev/null 2>&1

# F5 and F15. next --json and view.json agree, and the mod switch changes nothing, at the integrate and the passed gate states too
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
f9_tasks > .temper/specs/demo/tasks.md
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F15: the integrate step (groups passed, not yet merged) is the same with the mod off" "same" "$(_same_with_mod_off)"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "merged", "worktree": "w", "gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
assert_eq "F15: merged groups are the same with the mod off" "same" "$(_same_with_mod_off)"
gpass build
assert_eq "F15: a passed Build gate is the same with the mod off" "same" "$(_same_with_mod_off)"
assert_eq "F5: next --json and view.json carry the same question at a passed Build gate" "same" \
  "$(a="$("$TEMPER" next --json 2>/dev/null | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('ask'), sort_keys=True))")"; b="$(python3 -c "import json; print(json.dumps(json.load(open('.temper/view.json')).get('ask'), sort_keys=True))")"; [[ "$a" == "$b" ]] && echo same || echo differs)"

# F13. Past three tasks, the rest go under More options of the Which task changes? question
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_change_tasks > .temper/specs/demo/tasks.md
printf '\n### Task 5: extra\n**File:** `src/e5.sh`\n**Depends:** none\n**Test:** `true`\n**Cases:**\n- e\n- [x] done\n' >> .temper/specs/demo/tasks.md; second_group
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}, "3": {"status": "passed", "group": "G1"}, "4": {"status": "passed", "group": "G1"}, "5": {"status": "passed", "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F13: with five tasks the question shows three and More options, which holds the rest" "Task 1 (with Task 2)|Task 2|Task 3|More options#Task 4|Task 5" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['change']['question']['options']) + '#' + '|'.join(o['label'] for o in d['ask']['change']['more']['options'])")"

# F1. A note named for a task reaches that task's prompt only
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
f9_tasks > .temper/specs/demo/tasks.md
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": ".claude/worktrees/temper-demo-G1"}}, "tasks": {"1": {"status": "pending", "group": "G1"}}}\n' > .temper/groups.json
"$TEMPER" evidence add --stage build --phase note --kind input --claim 'Task 1: use the retry helper' >/dev/null 2>&1
"$TEMPER" evidence add --stage build --phase note --kind input --claim 'Task 2: leave this alone' >/dev/null 2>&1
assert_eq "F1: the prompt of Task 1 carries its own note and not the note of Task 2" "1|0" \
  "$(nx "str(sum(a['prompt'].count(\"Person's note: Task 1: use the retry helper\") for a in d['agents'])) + '|' + str(sum(a['prompt'].count('leave this alone') for a in d['agents']))")"

# --- Run Check again: a measurement nobody took (a missing coverage tool) is not a defect in the code ---
fresh; gpass intent plan build review; _at check
gfail check "coverage >= threshold" "recorded coverage 'none' vs threshold 80%"
assert_eq "Check: a missing coverage value offers Run Check again first (recommended), then Loop back to Build, and the small change under More options" \
  "Run Check again (Recommended)|Loop back to Build|Override and continue|More options" "$(labels)"
assert_eq "Check: Run Check again runs state redo check with the reason, and moves nothing else" "state redo check|redo|1" \
  "$(nx "o = d['ask']['options'][0]; ' '.join(o['calls'][0].split('temper ', 1)[1].split()[:3]) + '|' + o['move'] + '|' + str(len(o['calls']))")"
assert_eq "Check: the question asks Run Check again, not Loop back" "1" "$(nx "int(d['ask']['question']['question'].endswith('Run Check again?'))")"
gfail check "tests pass" "the latest run of a test command failed: unit/test_cli.py"
assert_eq "Check: a failing test is a defect in the code: Loop back to Build stays first, and there is no Run Check again" "Loop back to Build (Recommended)|0" \
  "$(nx "d['ask']['options'][0]['label'] + '|' + str(sum(1 for o in d['ask']['options'] if o['label'].startswith('Run Check again')))")"
gfail check "coverage >= threshold" "recorded coverage 'none' vs threshold 80%"
"$TEMPER" state redo check --reason "the measurement was missing" >/dev/null 2>&1
assert_eq "Check: after state redo check the verdict is gone and the Check agent runs again" "work|temper:temper-check|none" \
  "$(nx "d['action'] + '|' + d['agents'][0]['type'] + '|' + str(d.get('ask') and 'asked' or 'none')")"
setup
assert_eq "init: the coverage output folder .temper/check/ is excluded from git, so the tree stays clean after a Check" "1" \
  "$(grep -c '^/\.temper/check/$' "$(git rev-parse --git-common-dir)/info/exclude")"

# --- Pipeline reads the checks over REST where GraphQL is not available (Claude Code cloud sessions) ---
assert_eq "Pipeline: the brief, the reference and the trust page name the REST read of the checks" "1|1|1" \
  "$(grep -c 'gh api repos/{owner}/{repo}/commits/{head sha}/check-runs' "$REPO_ROOT/agents/pipeline.md")|$(grep -c 'gh api repos/{owner}/{repo}/commits/{head sha}/check-runs' "$REPO_ROOT/reference/pipeline.md")|$(grep -c 'gh api repos/{owner}/{repo}/commits/{head sha}/check-runs' "$REPO_ROOT/docs/trust.md")"

# --- Pipeline: the fix list names real files (no guessed path), and the whole fix loop run as printed ---
_fixrow() { # _fixrow <fix json>: the `fix paths` row of the Pipeline gate for a red result
  printf '{"status": "red", "round": 1, "failed_jobs": [{"name": "unit", "stage": "test", "id": "1", "error": "boom"}], "fix": %s}\n' "$1" > .temper/specs/demo/pipeline-context.json
  python3 -E -s "$REPO_ROOT/scripts/gate_rows.py" pipeline-gate .temper/specs/demo | python3 -c "
import json, sys
t = sys.stdin.read().strip(); rows = json.loads(t.rsplit(' ', 1)[0])
r = [x for x in rows if x['name'] == 'fix paths'][0]
print(str(r['pass']) + '|' + r['detail'])"
}
fresh; mkdir -p unit; echo x > unit/a.sh
assert_eq "Pipeline: a fix entry that names a file that exists passes the fix paths row" "True" "$(_fixrow '["unit/a.sh: the value is 4"]' | cut -d'|' -f1)"
assert_eq "Pipeline: a fix entry may say no file, and says where to look instead" "True" "$(_fixrow '["no file: the log names none; look in the test that prints boom"]' | cut -d'|' -f1)"
assert_eq "Pipeline: a path taken from a step name and not in the project fails the row, naming the entry" "False|1" \
  "$(_fixrow '["scripts/selftest/test-temper.sh: update the fixture"]' | awk -F'|' '{print $1 "|" (index($0, "entry 1 starts with '"'"'scripts/selftest/test-temper.sh'"'"', which is not a file here") > 0)}')"
assert_eq "Pipeline: a path outside the project, or one climbing out of it, fails the row" "False|False" \
  "$(_fixrow '["/etc/hostname: x"]' | cut -d'|' -f1)|$(_fixrow '["../unit/a.sh: x"]' | cut -d'|' -f1)"
assert_eq "Pipeline: an empty fix list, or an entry with no path, fails the row" "False|False" \
  "$(_fixrow '[]' | cut -d'|' -f1)|$(_fixrow '["fix the thing"]' | cut -d'|' -f1)"

# The whole loop as printed: red -> the steps run literally (a real commit, a real push to a bare origin) -> redo -> Round 2 of 2 -> green -> End
_pl; rm -rf .git ../pl-origin.git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git checkout -q -B feature/demo
echo base > unit/a.sh; printf '.temper/\n.claude/\n' > .gitignore; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git init -q --bare ../pl-origin.git 2>/dev/null; git remote add origin ../pl-origin.git; git push -q -u origin feature/demo >/dev/null 2>&1
_plctx '{"status": "red", "round": 1, "failed_jobs": [{"name": "unit", "stage": "test", "id": "1", "error": "boom"}], "fix": ["unit/a.sh: the value is 4"]}'
"$TEMPER" gate pipeline >/dev/null 2>&1
STEPS="$(nx "'\n'.join(d['ask']['options'][0]['steps'])")"
while IFS= read -r st; do
  case "$st" in
    *"/scripts/temper "*) bash -c "$st" >/dev/null 2>&1 ;;
    Apply*) echo 'the value is 4' > unit/a.sh ;;
    "git add -- "*) git add -- unit/a.sh >/dev/null 2>&1 ;;
    "git commit -m "*) bash -c "$st" >/dev/null 2>&1 ;;
    "git push") git push -q >/dev/null 2>&1 ;;
  esac
done <<<"$STEPS"
assert_eq "Pipeline loop: the printed steps made the fix commit and pushed it to the origin" "fix(ci): apply the Pipeline fix (CI fix round 1)" \
  "$(git --git-dir=../pl-origin.git log --format=%s -n 1 feature/demo)"
assert_eq "Pipeline loop: the round is counted, the old result is gone and the window is closed" "2|no|closed" \
  "$("$TEMPER" state get pipeline_round 2>/dev/null)|$([[ -f .temper/specs/demo/pipeline-context.json ]] && echo yes || echo no)|$(python3 -c "import json; print('open' if json.load(open('.temper/build-state.json')).get('adhoc') else 'closed')")"
assert_eq "Pipeline loop: the Pipeline agent runs again and its launch line says Round: 2 of 2." "work|temper:temper-pipeline|1" \
  "$(nx "d['action'] + '|' + d['agents'][0]['type'] + '|' + str(d['agents'][0]['prompt'].count('Round: 2 of 2.'))")"
_plctx '{"status": "green", "round": 2, "failed_jobs": [], "fix": []}'
"$TEMPER" gate pipeline >/dev/null 2>&1
assert_eq "Pipeline loop: the second read is green and the run may end" "Pipeline: every job passed. End the run?|End the run (Recommended)" \
  "$(nx "d['ask']['question']['question'] + '|' + d['ask']['options'][0]['label']")"
rm -rf ../pl-origin.git
setup
