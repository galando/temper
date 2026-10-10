# --- Grouped Build (9.7.0): config keys and task model resolution ---
# Scenario: Grouped mode off keeps the per-task Build unchanged [AC-01]
setup
assert_eq "grouped off (no build.mode): model --all prints exactly the 8 stage lines" "8" "$("$TEMPER" model --all | wc -l | tr -d ' ')"
printf 'build:\n  mode: per-task\n' >> .claude/temper.config
assert_eq "grouped off (build.mode: per-task): model --all prints exactly the 8 stage lines" "8" "$("$TEMPER" model --all | wc -l | tr -d ' ')"
assert_eq "grouped off: model --all has no task= line" "0" "$("$TEMPER" model --all | grep -c '^task')"

# Scenario: Task and escalation models resolve from config with defaults [AC-06, AC-01]
setup
printf 'build:\n  mode: grouped\n' >> .claude/temper.config
assert_eq "model task defaults to claude-haiku-5-5" "claude-haiku-5-5" "$("$TEMPER" model task)"
assert_eq "model task-escalation defaults to sonnet" "sonnet" "$("$TEMPER" model task-escalation)"
assert_eq "grouped on: model --all appends task= and task-escalation=" "10|task=claude-haiku-5-5|task-escalation=sonnet" \
  "$("$TEMPER" model --all | wc -l | tr -d ' ')|$("$TEMPER" model --all | grep '^task=')|$("$TEMPER" model --all | grep '^task-escalation=')"
setup
printf 'build:\n  mode: grouped\n  grouped:\n    task-model: haiku\n    escalation-model: opus\n' >> .claude/temper.config
assert_eq "configured task and escalation models win" "haiku|opus" "$("$TEMPER" model task)|$("$TEMPER" model task-escalation)"
setup

# --- Grouped Build (9.7.0): serialized writes to shared run files ---
# Scenario: Parallel evidence writes lose no rows [AC-04]
setup
mkdir -p .temper/evidence
for i in 1 2 3 4 5 6 7 8; do
  "$TEMPER" evidence add --stage build --claim "Task $(( (i + 1) / 2 )) run $i" --phase red >/dev/null 2>&1 &
done
wait
assert_eq "parallel evidence add: all 8 rows land and the ledger is valid JSON" "8" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))" 2>/dev/null || echo invalid)"
assert_eq "parallel evidence add: the lock folder is released" "no" "$([[ -e .temper/.lock ]] && echo yes || echo no)"
assert_eq "parallel evidence add: no temp file is left behind" "0" "$(find .temper -name '*.tmp*' | wc -l | tr -d ' ')"

# a lock left by a crashed holder is broken once it is older than 30 s
setup
mkdir -p .temper/evidence .temper/.lock
python3 -c "import os,time; t=time.time()-120; os.utime('.temper/.lock',(t,t))"
out="$("$TEMPER" evidence add --stage build --claim "after stale lock" 2>&1)"; rc=$?
assert_eq "stale lock: the write succeeds without a warning" "0|0" "$rc|$(printf '%s' "$out" | grep -c WARN)"
assert_eq "stale lock: the row is recorded and the lock is gone" "1|no" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$([[ -e .temper/.lock ]] && echo yes || echo no)"

# a fresh lock held by someone else: fail open after the wait, warn, never release it
setup
mkdir -p .temper/evidence .temper/.lock
out="$(TEMPER_LOCK_WAIT_S=1 "$TEMPER" evidence add --stage build --claim "while locked" 2>&1)"; rc=$?
assert_eq "held lock: writes anyway with a WARN after the wait" "0|1" "$rc|$(printf '%s' "$out" | grep -c 'WARN.*lock')"
assert_eq "held lock: the row is recorded and the foreign lock is left alone" "1|yes" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$([[ -d .temper/.lock ]] && echo yes || echo no)"

# the lock folder is on the symlink refusal list
setup
mkdir -p .temper/evidence "$WORKDIR/lock-target"
ln -s "$WORKDIR/lock-target" .temper/.lock
assert_exit "a symlinked .temper/.lock is refused" 3 "$TEMPER" evidence add --stage build --claim "via link"
rm -f .temper/.lock
