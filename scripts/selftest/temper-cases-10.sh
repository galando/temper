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
