# Implicit state machines made explicit, part 3: the guard hooks' state (pending-stage.json marker, install, the fallback commit guard).
# Sourced by test-temper.sh after temper-cases-18.sh (helpers: nx, vw, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

# --- D1 to D3: the pending-stage.json marker of stage-marker.sh and verify-stage-gate.sh ---
setup
MARKER="$REPO_ROOT/scripts/guards/stage-marker.sh"
VERIFY="$REPO_ROOT/scripts/guards/verify-stage-gate.sh"
_mk() { python3 -c "import json,sys; print(json.load(open('.temper/pending-stage.json')).get(sys.argv[1], ''))" "$1" 2>/dev/null || echo absent; }
_stop() { echo "$1" | bash "$VERIFY" >/dev/null 2>&1; }
_gone() { [[ -f .temper/pending-stage.json ]] && echo present || echo absent; }

# D1: /temper:intent again in the same session, while the debt is unpaid, keeps the refusals already counted;
# otherwise each new prompt would give the loop guard a fresh budget.
rm -f .temper/pending-stage.json .temper/gates.json
echo '{"prompt": "/temper:intent x", "session_id": "s-one"}' | bash "$MARKER"
_stop '{"session_id": "s-one"}'
echo '{"prompt": "/temper:intent x again", "session_id": "s-one"}' | bash "$MARKER"
assert_eq "D1: the same session's /temper:intent again keeps the refusals already counted" "1" "$(_mk blocks)"
_stop '{"session_id": "s-one"}'
assert_exit "D1: so the loop guard still opens after two refusals in all" 0 bash -c "echo '{\"session_id\": \"s-one\"}' | bash '$VERIFY'"
# A new session's /temper:intent starts its own count.
echo '{"prompt": "/temper:intent x", "session_id": "s-one"}' | bash "$MARKER"
_stop '{"session_id": "s-one"}'
echo '{"prompt": "/temper:intent y", "session_id": "s-two"}' | bash "$MARKER"
assert_eq "D1: another session's /temper:intent starts a count of its own, and the marker names that session" "0|s-two" "$(_mk blocks)|$(_mk session_id)"

# D2: the marker names the session that owes the gate; another session's Stop neither blocks on it nor removes it.
rm -f .temper/pending-stage.json .temper/gates.json
echo '{"prompt": "/temper:intent x", "session_id": "s-crashed"}' | bash "$MARKER"
assert_eq "D2: the marker records the session id from the hook's input" "s-crashed" "$(_mk session_id)"
assert_exit "D2: another session's Stop is not blocked by that marker" 0 bash -c "echo '{\"session_id\": \"s-other\"}' | bash '$VERIFY'"
assert_eq "D2: and leaves it as it was (the session that owes it may still be running)" "s-crashed|0" "$(_mk session_id)|$(_mk blocks)"
assert_exit "D2: the session that owes the gate is still blocked" 2 bash -c "echo '{\"session_id\": \"s-crashed\"}' | bash '$VERIFY'"
# A session id with a quote in it is kept as JSON text: the marker stays readable.
rm -f .temper/pending-stage.json
printf '%s' '{"prompt": "/temper:intent x", "session_id": "a\"b"}' | bash "$MARKER"
assert_eq "D2: a session id with a quote is written as JSON text" 'a"b' "$(_mk session_id)"
# Old markers (no session id) and a harness input without one are judged as before.
echo '{"stage": "intent", "blocks": 0}' > .temper/pending-stage.json
assert_exit "D2: a marker with no session id still blocks any session" 2 bash -c "echo '{\"session_id\": \"s-any\"}' | bash '$VERIFY'"
rm -f .temper/pending-stage.json
echo '{"prompt": "/temper:intent x", "session_id": "s-one"}' | bash "$MARKER"
assert_exit "D2: a Stop whose input has no session id is judged as before" 2 bash -c "echo '{}' | bash '$VERIFY'"
# A marker older than a day is a crashed session's leftover: fail open, and clear it.
echo '{"stage": "intent", "blocks": 0, "since": "2020-01-01T00:00:00Z"}' > .temper/pending-stage.json
assert_exit "D2: a marker older than a day does not block" 0 bash -c "echo '{}' | bash '$VERIFY'"
assert_eq "D2: and is cleared" "absent" "$(_gone)"
echo '{"stage": "intent", "blocks": 0, "since": "2020-01-01T00:00:00Z", "session_id": "s-crashed"}' > .temper/pending-stage.json
_stop '{"session_id": "s-other"}'
assert_eq "D2: another session's marker older than a day is cleared too" "absent" "$(_gone)"
echo '{"stage": "intent", "blocks": 0, "since": "not a time"}' > .temper/pending-stage.json
assert_exit "D2: a since that is not a time is not read as old (blocks as before)" 2 bash -c "echo '{}' | bash '$VERIFY'"

# D3: stop_hook_active with our counter at 0 (another Stop hook blocked first) opens this stop but keeps the debt.
rm -f .temper/pending-stage.json .temper/gates.json
echo '{"prompt": "/temper:intent x", "session_id": "s-one"}' | bash "$MARKER"
assert_exit "D3: stop_hook_active with the counter at 0 still fails open" 0 \
  bash -c "echo '{\"stop_hook_active\": true, \"session_id\": \"s-one\"}' | bash '$VERIFY'"
assert_eq "D3: but the marker stays, so the next Stop of the session still asks for the gate" "intent|0" "$(_mk stage)|$(_mk blocks)"
assert_exit "D3: the next Stop blocks" 2 bash -c "echo '{\"session_id\": \"s-one\"}' | bash '$VERIFY'"
rm -f .temper/pending-stage.json

# --- D4: install.sh writes the kept hook before it sets core.hooksPath; a failed set is reported, never a success ---
setup
git config user.email t@example.com; git config user.name T
mkdir -p "$WORKDIR/.git/d4-bin"
REAL_GIT="$(command -v git)"
cat > "$WORKDIR/.git/d4-bin/git" <<EOF
#!/usr/bin/env bash
# git, except that setting core.hooksPath fails
if [[ "\$1 \$2 \$3" == "config --local core.hooksPath" && \$# -eq 4 ]]; then exit 1; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORKDIR/.git/d4-bin/git"
OUT=$(PATH="$WORKDIR/.git/d4-bin:$PATH" bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1); D4_RC=$?
assert_eq "D4: install.sh exits 1 when core.hooksPath cannot be set, says so, and says no success" "1|yes|no" \
  "$D4_RC|$(grep -q 'FAIL: core.hooksPath could not be set' <<<"$OUT" && echo yes || echo no)|$(grep -q '^Installed' <<<"$OUT" && echo yes || echo no)"
assert_eq "D4: and names the kept hook, with the line to add by hand" "yes|unset" \
  "$(grep -q 'The Temper hook is kept in' <<<"$OUT" && echo yes || echo no)|$(git config --get core.hooksPath || echo unset)"
rm -rf "$WORKDIR/.git/d4-bin"

# --- D6: "a run is active" (build-state.json exists) and the regression-test shield follow the CLI's lifecycle ---
# state clear and state init both remove build-state.json, and a new run's state holds no regression_test.
setup
PRT="$REPO_ROOT/scripts/guards/protect-regression-test.sh"
"$TEMPER" state init bug1 --command fix >/dev/null 2>&1
mkdir -p spec && echo "exit 1" > spec/bug1.test.sh   # the CLI records only a test file that exists (A6)
"$TEMPER" state set regression_test spec/bug1.test.sh >/dev/null 2>&1
_prt() { echo '{"tool_input": {"file_path": "spec/bug1.test.sh"}}' | CLAUDE_PROJECT_DIR="$WORKDIR" bash "$PRT" >/dev/null 2>&1; echo $?; }
assert_eq "D6: during the fix run the recorded test is shielded" "2" "$(_prt)"
"$TEMPER" state init bug2 --command fix >/dev/null 2>&1
assert_eq "D6: a new fix run does not inherit the shield of the one before" "0|" "$(_prt)|$("$TEMPER" state get regression_test 2>/dev/null)"
mkdir -p spec && echo "exit 1" > spec/bug1.test.sh   # the CLI records only a test file that exists (A6)
"$TEMPER" state set regression_test spec/bug1.test.sh >/dev/null 2>&1
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "D6: a cleared run is no run: no build-state.json, and the shield is lifted" "absent|0" \
  "$([[ -e .temper/build-state.json || -L .temper/build-state.json ]] && echo present || echo absent)|$(_prt)"

# --- D5: verify-tests-ran.sh (the fallback commit guard) reads build-state's stage ---
# Check passed is check_complete; the one stage after it, Commit (commit_complete, before Pipeline), is past Check too,
# so a Pipeline fix round's commit is not refused. A stage before Check still is.
setup
"$TEMPER" state init demo >/dev/null 2>&1
_vtr_at() { python3 -c "
import json, sys
p = '.temper/build-state.json'; d = json.load(open(p)); d['stage'] = sys.argv[1]; json.dump(d, open(p, 'w'))" "$1"; }
for _st in check_complete commit_complete; do
  _vtr_at "$_st"
  assert_exit "D5: verify-tests-ran.sh lets a commit go on at stage $_st" 0 bash "$REPO_ROOT/scripts/guards/verify-tests-ran.sh"
done
for _st in started plan_complete build_complete review_complete; do
  _vtr_at "$_st"
  assert_exit "D5: verify-tests-ran.sh refuses a commit at stage $_st" 2 bash "$REPO_ROOT/scripts/guards/verify-tests-ran.sh"
done
