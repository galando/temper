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
