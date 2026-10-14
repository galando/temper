# The measurement fixtures (evals/README.md): every planted defect is real, and the scorer reads a
# run the way the README says. Sourced by test-temper.sh (assert_eq, $WORKDIR, $REPO_ROOT).

EV="$REPO_ROOT/evals"
EVW="$WORKDIR/evals-cases"
mkdir -p "$EVW"

ev_tests() { (cd "$1" && python3 -m unittest discover -s tests -t . >/dev/null 2>&1) && echo pass || echo fail; }
ev_hidden() { python3 "$EV/score.py" hidden "$1" "$2" >/dev/null 2>&1 && echo pass || echo fail; }

for ev_name in jokes orders reset search; do
  ev_dir="$EVW/$ev_name"
  bash "$EV/make-fixture.sh" "$ev_name" "$ev_dir" >/dev/null 2>&1
  assert_eq "evals: $ev_name builds, its own tests pass and its hidden test fails" "pass|fail" \
    "$(ev_tests "$ev_dir")|$(ev_hidden "$ev_name" "$ev_dir")"
  assert_eq "evals: $ev_name keeps the answer key, the hidden test and the fix out of the project" "0" \
    "$(find "$ev_dir" -name fixture.json -o -name 'test_hidden*' -o -name fix -o -name hidden | wc -l | tr -d ' ')"
  cp -R "$ev_dir" "$ev_dir-fixed"
  cp -R "$EV/fixtures/$ev_name/fix/." "$ev_dir-fixed/"
  assert_eq "evals: $ev_name with the reference fix passes its tests and its hidden test" "pass|pass" \
    "$(ev_tests "$ev_dir-fixed")|$(ev_hidden "$ev_name" "$ev_dir-fixed")"
done

cp -R "$EVW/jokes" "$EVW/jokes-naive"
cp "$EV/fixtures/jokes/naive/jokes.py" "$EVW/jokes-naive/"
assert_eq "evals: a list_jokes built on the planted all_jokes fails the hidden test" "pass|fail" \
  "$(ev_tests "$EVW/jokes-naive")|$(ev_hidden jokes "$EVW/jokes-naive")"

bash "$EV/make-fixture.sh" orders "$EVW/orders-at-review" --at-review >/dev/null 2>&1
assert_eq "evals: --at-review leaves the run at Review, with Intent and Plan passed and Build skipped" "review|PASS|PASS|build" \
  "$(cd "$EVW/orders-at-review" && "$TEMPER" state get next_stage)|$(python3 -c "import json; g=json.load(open('$EVW/orders-at-review/.temper/gates.json')); print(g['intent']['verdict'] + '|' + g['plan']['verdict'])")|$(python3 -c "import json; print(','.join(o['stage'] for o in json.load(open('$EVW/orders-at-review/.temper/overrides.json'))))")"
assert_eq "evals: --at-review leaves the project on the run's feature branch, as leaving Plan does" "feature/order-lookup" \
  "$(git -C "$EVW/orders-at-review" branch --show-current)"
assert_eq "evals: a folder that exists is refused" "2" \
  "$(bash "$EV/make-fixture.sh" orders "$EVW/orders" >/dev/null 2>&1; echo $?)"

# The scorer on a recorded run: a Review row that names the defect, a Check that ran and names the
# untraced scenario, and a session with one gate answer, one move after it and one move with none.
ev_run="$EVW/scored"
cp -R "$EVW/reset" "$ev_run"
mkdir -p "$ev_run/.temper/evidence"
cat > "$ev_run/.temper/evidence/review.json" <<'EOF'
[{"claim": "reset.py:12 the hourly limit of AC-03 is not implemented", "severity": "high"},
 {"claim": "review completed", "exit_code": 0}]
EOF
cat > "$ev_run/.temper/gates.json" <<'EOF'
{"check": {"verdict": "FAIL", "requirements": [
  {"name": "tests pass", "pass": true, "detail": "1 green test run(s) recorded"},
  {"name": "scenarios traced to tests", "pass": false, "detail": "2/3 covered — missing: Too many reset requests in one hour"}]}}
EOF
cat > "$EVW/session.jsonl" <<'EOF'
{"type": "assistant", "timestamp": "2026-10-13T10:00:00Z", "message": {"content": [{"type": "tool_use", "id": "q1", "name": "AskUserQuestion", "input": {"questions": [{"header": "Temper gate", "question": "Intent: PASS", "options": []}]}}]}}
{"type": "user", "timestamp": "2026-10-13T10:01:00Z", "message": {"content": [{"type": "tool_result", "tool_use_id": "q1", "content": "answered"}]}}
{"type": "assistant", "timestamp": "2026-10-13T10:01:10Z", "message": {"content": [{"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": "/p/scripts/temper state advance intent_complete plan"}}]}}
{"type": "user", "timestamp": "2026-10-13T10:01:11Z", "message": {"content": [{"type": "tool_result", "tool_use_id": "b1", "content": "OK"}]}}
{"type": "assistant", "timestamp": "2026-10-13T10:05:00Z", "message": {"content": [{"type": "tool_use", "id": "b2", "name": "Bash", "input": {"command": "/p/scripts/temper state advance plan_complete build"}}]}}
{"type": "user", "timestamp": "2026-10-13T10:05:01Z", "message": {"content": [{"type": "tool_result", "tool_use_id": "b2", "content": "OK"}]}}
{"type": "cost-state", "totalCostUSD": 1.5, "totalDuration": 600000, "totalAPIDuration": 120000, "modelUsage": {"m": {"inputTokens": 10, "outputTokens": 20, "cacheReadInputTokens": 30, "cacheCreationInputTokens": 40}}}
EOF
ev_score="$(python3 "$EV/score.py" run reset "$ev_run" --transcript "$EVW/session.jsonl" 2>&1)"
assert_eq "evals: the scorer reads the hidden test, Review, Check, the gates and the cost of a run" \
  "False|True|high|True|1|2|1|1.5|10.0|10|40|30|20" \
  "$(python3 -c "
import json, sys
d = json.loads(sys.argv[1]); s = d['session']; t = s['tokens']
print('|'.join(str(x) for x in [d['fixed_at_end'], d['review']['flagged'], d['review']['severity'], d['check']['flagged'],
  s['gates_asked'], s['moves'], s['moves_without_answer'], s['cost_usd'], s['minutes'], t['input'], t['cache_write'], t['cache_read'], t['output']]))
" "$ev_score" 2>&1)"
sed -i 's/"pass": true, "detail": "1 green/"pass": false, "detail": "no green/' "$ev_run/.temper/gates.json"
assert_eq "evals: a Check with no green test run of its own does not count as naming the defect" "False" \
  "$(python3 "$EV/score.py" run reset "$ev_run" | python3 -c "import json, sys; print(json.load(sys.stdin)['check']['flagged'])")"
