# Release 9.8.5 case file 31: sourced by test-temper.sh after temper-cases-30.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (Q3): a run counts when the CLI ran it; a claimed run counts at no gate; a false pass is voided, and stays ---
_strict() { setup; sed -i '/^evidence:$/d; /claimed-runs:/d' .claude/temper.config; }
_strict
"$TEMPER" evidence add --stage build --claim "unit tests" --exit 1 --phase red >/dev/null 2>&1
"$TEMPER" evidence add --stage build --claim "unit tests" --exit 0 --phase green >/dev/null 2>&1
assert_eq "9.8.5 Q3: RED and GREEN an agent only claimed (evidence add --exit) do not count at the Build gate" "0 0 0" \
  "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json ignore)"
"$TEMPER" evidence run --stage build --claim "unit tests" --phase red -- false >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim "unit tests" --phase green -- true >/dev/null 2>&1
assert_eq "9.8.5 Q3: the same runs through evidence run (the CLI ran them) count" "1 1 1" \
  "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json ignore)"
assert_eq "9.8.5 Q3: with evidence.claimed-runs: count the claims count too, as before" "2 2 2" \
  "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json count)"
_strict
"$TEMPER" evidence add --stage check --claim "tests: unit" --exit 0 >/dev/null 2>&1
assert_eq "9.8.5 Q3: Check does not count a claimed passing test run" "0|" "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" check .temper/evidence/check.json ignore)"

# void: only a pass, with a reason; the row stays and is marked; it counts in neither mode
_strict
"$TEMPER" evidence run --stage build --claim "unit tests" --phase red -- false >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim "unit tests" --phase green -- true >/dev/null 2>&1
assert_exit "9.8.5 Q3: void needs a reason" 1 "$TEMPER" evidence void --stage build --id 2
assert_exit "9.8.5 Q3: a failure is never voided (that would make a gate easier)" 1 "$TEMPER" evidence void --stage build --id 1 --reason 'x'
assert_exit "9.8.5 Q3: a pass is voided with a reason" 0 "$TEMPER" evidence void --stage build --id 2 --reason 'the run failed before it started (wrong JDK)'
assert_eq "9.8.5 Q3: the void pass stays in the ledger, is shown as void, and counts in no mode" "2|True|1 0 0|1 0 0" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$("$TEMPER" evidence list --stage build | grep -q '#2 .*\[void: the run failed before it started (wrong JDK)\]' && echo True || echo False)|$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json ignore)|$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json count)"
assert_exit "9.8.5 Q3: a void row is not voided twice" 1 "$TEMPER" evidence void --stage build --id 2 --reason 'again'
assert_eq "9.8.5 Q3: the build and fix briefs record RED and GREEN with evidence run" "2|2" \
  "$(grep -cE -- '--phase (red|green) -- <the exact test command>' "$REPO_ROOT/agents/build.md")|$(grep -cE -- '--phase (red|green) -- <the exact test command>' "$REPO_ROOT/agents/fix.md")"

# --- 9.8.5: case 6 runs on its own; its helpers are generated from case 5 and kept in step ---
assert_eq "9.8.5: case-helpers-5.sh is what make-helpers-5.sh prints from temper-cases-5.sh" "same" \
  "$(bash "$REPO_ROOT/scripts/selftest/make-helpers-5.sh" | cmp -s - "$REPO_ROOT/scripts/selftest/case-helpers-5.sh" && echo same || echo differs)"
