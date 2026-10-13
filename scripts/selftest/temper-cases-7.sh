# ADR 0012: the CLI marks each step of a run, and going back clears what is redone.
# Sourced by test-temper.sh (assert_eq, assert_exit, setup, $TEMPER).

bs() { python3 -c "import json,sys; d=json.load(open('.temper/build-state.json')); print(d.get(sys.argv[1], ''))" "$1"; }

setup
"$TEMPER" state init demo >/dev/null 2>&1
RUN1="$(bs run_id)"
assert_eq "ADR 0012: state init writes a run id and step 0" "yes|0|intent" \
  "$([[ "$RUN1" =~ ^[0-9a-f]{16}$ ]] && echo yes || echo no)|$(bs step)|$(bs next_stage)"
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "ADR 0012: every change of next_stage counts one step" "2|build" "$(bs step)|$(bs next_stage)"
out="$("$TEMPER" state set next_stage build 2>&1)"
assert_eq "ADR 0012: state set next_stage to the stage the run is at changes nothing" "2|1" \
  "$(bs step)|$(grep -c 'unchanged' <<<"$out")"
"$TEMPER" state advance build_complete build >/dev/null 2>&1
assert_eq "ADR 0012: an advance that names the stage the run is at counts no step" "2" "$(bs step)"
assert_exit "ADR 0012: state set step is refused" 1 "$TEMPER" state set step 9
assert_exit "ADR 0012: state set run_id is refused" 1 "$TEMPER" state set run_id 0123456789abcdef
assert_eq "ADR 0012: the refused sets changed nothing" "2|$RUN1" "$(bs step)|$(bs run_id)"
"$TEMPER" state init demo >/dev/null 2>&1
assert_eq "ADR 0012: a new state init is a new run, at step 0" "yes|0" \
  "$([[ "$(bs run_id)" != "$RUN1" ]] && echo yes || echo no)|$(bs step)"

# A loop back redoes the stages from its target: their verdicts leave gates.json and their skips move to the archive.
setup
"$TEMPER" state init demo >/dev/null 2>&1
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
printf '{"plan":{"verdict":"PASS"},"build":{"verdict":"PASS"},"review":{"verdict":"FAIL"},"check":{"verdict":"FAIL"}}\n' > .temper/gates.json
"$TEMPER" override plan --reason "plan skip stays" >/dev/null 2>&1
"$TEMPER" override review --reason "seen by hand" >/dev/null 2>&1
"$TEMPER" state advance build_complete review >/dev/null 2>&1
"$TEMPER" state advance review_complete check >/dev/null 2>&1
STEP="$(bs step)"
"$TEMPER" state loop check build --reason "a test fails" >/dev/null 2>&1
assert_eq "ADR 0012: a loop moves the run back and counts one step" "build|$((STEP + 1))" "$(bs next_stage)|$(bs step)"
assert_eq "ADR 0012: the loop removed the verdicts of build and every later stage, and kept plan's" "plan" \
  "$(python3 -c "import json; print(','.join(sorted(json.load(open('.temper/gates.json')))))")"
assert_eq "ADR 0012: the skip of review moved to the archive; the skip of plan stays" "plan|review|build" \
  "$(python3 -c "import json; print(','.join(o['stage'] for o in json.load(open('.temper/overrides.json'))))")|$(python3 -c "import json; r=json.load(open('.temper/archive/overrides-redone.json')); print(','.join(o['stage'] for o in r))")|$(python3 -c "import json; print(json.load(open('.temper/archive/overrides-redone.json'))[0]['redone_from'])")"
"$TEMPER" gate commit >/dev/null 2>&1
assert_eq "ADR 0012: after the loop the commit gate no longer counts the old skip of review" "0" \
  "$(python3 -c "import json; r=json.load(open('.temper/gates.json')).get('commit',{}).get('requirements',[]); print(sum(1 for x in r if 'review' in x['name'] and x['pass']))")"

# A state set next_stage to an earlier stage redoes like a loop; to a later stage it redoes nothing.
setup
"$TEMPER" state init demo >/dev/null 2>&1
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" state advance build_complete review >/dev/null 2>&1
printf '{"plan":{"verdict":"PASS"},"build":{"verdict":"PASS"},"review":{"verdict":"FAIL"}}\n' > .temper/gates.json
"$TEMPER" state set next_stage plan >/dev/null 2>&1
assert_eq "ADR 0012: state set next_stage to an earlier stage clears the verdicts from it" "|plan" \
  "$(python3 -c "import json; print(','.join(sorted(json.load(open('.temper/gates.json')))))")|$(bs next_stage)"
printf '{"plan":{"verdict":"PASS"}}\n' > .temper/gates.json
"$TEMPER" state set next_stage design >/dev/null 2>&1
assert_eq "ADR 0012: state set next_stage to a later stage keeps the verdicts" "plan|design" \
  "$(python3 -c "import json; print(','.join(sorted(json.load(open('.temper/gates.json')))))")|$(bs next_stage)"

# A fix run's gates are build, review and check: a loop back to fix redoes all three.
setup
"$TEMPER" state init demo --command fix >/dev/null 2>&1
printf '{"build":{"verdict":"PASS"},"review":{"verdict":"FAIL"},"check":{"verdict":"FAIL"}}\n' > .temper/gates.json
"$TEMPER" override review --reason "fix review skip" >/dev/null 2>&1
"$TEMPER" state loop check fix --reason again >/dev/null 2>&1
assert_eq "ADR 0012: a fix run's loop back to fix clears build, review and check, and their skips" "|" \
  "$(python3 -c "import json; print(','.join(sorted(json.load(open('.temper/gates.json')))))")|$(python3 -c "import json; print(','.join(o['stage'] for o in json.load(open('.temper/overrides.json'))))")"

# A run state written before ADR 0012 gets its run id and step on the next state call (write through, ADR 0004).
setup
printf '{"stage":"plan_complete","spec":"demo","spec_path":".temper/specs/demo","command":"temper","next_stage":"build","run_mode":"interactive"}\n' > .temper/build-state.json
"$TEMPER" state get next_stage >/dev/null 2>&1
assert_eq "ADR 0012: an old run state gets a run id and step 0 on the next state call" "yes|0|build" \
  "$([[ "$(bs run_id)" =~ ^[0-9a-f]{16}$ ]] && echo yes || echo no)|$(bs step)|$(bs next_stage)"
RUNL="$(bs run_id)"
"$TEMPER" state get next_stage >/dev/null 2>&1
assert_eq "ADR 0012: the migration runs once" "$RUNL" "$(bs run_id)"
setup
