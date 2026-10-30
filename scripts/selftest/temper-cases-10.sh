# Release 9.7.5, Phase A (F1 to F5). Sourced by test-temper.sh after temper-cases-9.sh; its helpers (nx, vw, fresh,
# gpass, gfail, labels) are used here.

# --- F5. temper next is one Python process: the models, the setup calls, the action and the view come from cli_ctx.py ---
fresh
assert_eq "F5: cli_ctx models names every stage and both task models, as temper model --all does" \
  "$("$TEMPER" model --all | cut -d= -f1 | tr '\n' ' ')" \
  "$(python3 "$REPO_ROOT/scripts/cli_ctx.py" models --plugin "$REPO_ROOT" --config-file .claude/temper.config | cut -d= -f1 | tr '\n' ' ')"
assert_eq "F5: cli_ctx models gives the same model for every name" \
  "$("$TEMPER" model --all | sort | tr '\n' ' ')" \
  "$(python3 "$REPO_ROOT/scripts/cli_ctx.py" models --plugin "$REPO_ROOT" --config-file .claude/temper.config | sort | tr '\n' ' ')"
OUT="$(python3 "$REPO_ROOT/scripts/cli_ctx.py" models --plugin "$REPO_ROOT" --config-file .claude/temper.config --source | grep '^task=')"
assert_eq "F5: --source says the task model comes from its brief" "task=claude-haiku-5-5 (brief)" "$OUT"
rm -f .temper/view.json
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "F5: one next call writes .temper/view.json" "run-ok" \
  "$([[ -s .temper/view.json ]] && python3 -c "import json; d=json.load(open('.temper/view.json')); print('run-ok' if d.get('run') else 'no-run')" || echo missing)"

# --- F1. A note the person types reaches the agent that runs next ---
fresh
assert_exit "F1: evidence add takes --phase note --kind input" 0 "$TEMPER" evidence add --stage intent --phase note --kind input --claim 'use the SSO login, not a password'
assert_exit "F1: --kind takes input or edit, nothing else" 1 "$TEMPER" evidence add --stage intent --phase note --kind other --claim 'x'
assert_eq "F1: the stage agent's prompt carries the note under a Person's note: line" "1" \
  "$(nx "d['agents'][0]['prompt'].count(\"Person's note: use the SSO login, not a password\")")"
gpass intent
python3 - <<'PY'
import json
g = json.load(open('.temper/gates.json')); g['intent']['ts'] = '2000-01-01T00:00:00Z'; json.dump(g, open('.temper/gates.json', 'w'))
PY
assert_eq "F1: a note newer than the verdict runs the stage agent again, with the note" "work|temper:temper-intent|1" \
  "$(nx "'|'.join([d['action'], d['agents'][0]['type'], str(d['agents'][0]['prompt'].count('Person\'s note: use the SSO'))])")"
python3 - <<'PY'
import json
g = json.load(open('.temper/gates.json')); g['intent']['ts'] = '2999-01-01T00:00:00Z'; json.dump(g, open('.temper/gates.json', 'w'))
PY
assert_eq "F1: a note older than the verdict leaves the question as it was" "ask" "$(nx "d['action']")"
"$TEMPER" evidence add --stage intent --phase note --kind edit --claim 'the person fixed AC-02 in intent.md' >/dev/null 2>&1
python3 - <<'PY'
import json
g = json.load(open('.temper/gates.json')); g['intent']['ts'] = '2000-01-01T00:00:00Z'; json.dump(g, open('.temper/gates.json', 'w'))
PY
"$TEMPER" evidence clear --stage intent >/dev/null 2>&1
"$TEMPER" evidence add --stage intent --phase note --kind edit --claim 'the person fixed AC-02 in intent.md' >/dev/null 2>&1
assert_eq "F1: an edit note runs the stage's gate call only, no agent" "work|0|gate intent" \
  "$(nx "'|'.join([d['action'], str(len(d['agents'])), d['calls'][0].split('temper ', 1)[1]])")"
assert_eq "F1: a Task note reaches that task only; a Group note its tasks; an unscoped note all" "Task 2: a;Group G1: b;c" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import flow
rows = [{'claim': 'Task 2: a'}, {'claim': 'Group G1: b'}, {'claim': 'c'}, {'claim': 'Task 3: d'}, {'claim': 'Group G2: e'}]
print(';'.join(flow.scoped_notes(rows, 2, 'G1')))
PYT
)"

# --- F2. The model of each stage, and of the running attempt, is named ---
fresh
assert_eq "F2: model --all --source says a stage's model comes from its brief" "1" "$("$TEMPER" model --all --source | grep -c '^plan=.* (brief)$')"
printf 'models:\n  plan: opus\nbuild:\n  grouped:\n    task-model: sonnet\n' > .claude/temper.config
assert_eq "F2: a config override is named as one" "plan=opus (config)|task=sonnet (config)" \
  "$("$TEMPER" model --all --source | grep -E '^(plan|task)=' | tr '\n' '|' | sed 's/|$//')"
assert_eq "F2: temper status has a Models block with the stage, the model and the source" "1|1" \
  "$("$TEMPER" status | grep -c '^Models$')|$("$TEMPER" status | grep -cE '^  plan +opus +config$')"
assert_eq "F2: status --json holds the models" "opus|config" \
  "$("$TEMPER" status --json | python3 -c "import json,sys; m=[x for x in json.load(sys.stdin)['models'] if x['stage']=='plan'][0]; print(m['model']+'|'+m['source'])")"
printf 'stack: auto\n' > .claude/temper.config
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"worktree": "w", "status": "started"}}, "tasks": {"1": {"status": "running", "attempt": 3, "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F2: the wait action of attempt 3 names the escalation model, in the task and in its gate call" "wait|sonnet|1" \
  "$(nx "'|'.join([d['action'], d['tasks'][0]['model'], str(d['tasks'][0]['after'][0].count('--model sonnet '))])")"
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"worktree": "w", "status": "started"}}, "tasks": {"1": {"status": "running", "attempt": 1, "group": "G1"}}}\n' > .temper/groups.json
assert_eq "F2: attempt 1 names the task model" "claude-haiku-5-5" "$(nx "d['tasks'][0]['model']")"
