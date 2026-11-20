# Release 9.8.5 case file 31: sourced by test-temper.sh after temper-cases-30.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (Q3): a run counts when the CLI ran it; a claimed run counts at no gate; a false pass is voided, and stays ---
_strict() { setup; sed -i '/^evidence:$/d; /claimed-runs:/d' .claude/temper.config; }
_strict
"$TEMPER" evidence add --stage build --claim "unit tests" --exit 1 --phase red >/dev/null 2>&1
"$TEMPER" evidence add --stage build --claim "unit tests" --exit 0 --phase green >/dev/null 2>&1
assert_eq "9.8.5 Q3: RED and GREEN an agent only claimed (evidence add --exit) do not count at the Build gate" "0 0 0" \
  "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json)"
"$TEMPER" evidence run --stage build --claim "unit tests" --phase red -- false >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim "unit tests" --phase green -- true >/dev/null 2>&1
assert_eq "9.8.5 Q3: the same runs through evidence run (the CLI ran them) count" "1 1 1" \
  "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json)"
_strict
"$TEMPER" evidence add --stage check --claim "tests: unit" --exit 0 >/dev/null 2>&1
assert_eq "9.8.5 Q3: Check does not count a claimed passing test run" "0|" "$(python3 -E -s "$REPO_ROOT/scripts/runs.py" check .temper/evidence/check.json)"

# void: only a pass, with a reason; the row stays and is marked; it counts no more
_strict
"$TEMPER" evidence run --stage build --claim "unit tests" --phase red -- false >/dev/null 2>&1
"$TEMPER" evidence run --stage build --claim "unit tests" --phase green -- true >/dev/null 2>&1
assert_exit "9.8.5 Q3: void needs a reason" 1 "$TEMPER" evidence void --stage build --id 2
assert_exit "9.8.5 Q3: a failure is never voided (that would make a gate easier)" 1 "$TEMPER" evidence void --stage build --id 1 --reason 'x'
assert_exit "9.8.5 Q3: a pass is voided with a reason" 0 "$TEMPER" evidence void --stage build --id 2 --reason 'the run failed before it started (wrong JDK)'
assert_eq "9.8.5 Q3: the void pass stays in the ledger, is shown as void, and counts no more" "2|True|1 0 0" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))")|$("$TEMPER" evidence list --stage build | grep -q '#2 .*\[void: the run failed before it started (wrong JDK)\]' && echo True || echo False)|$(python3 -E -s "$REPO_ROOT/scripts/runs.py" build .temper/evidence/build.json)"
assert_exit "9.8.5 Q3: a void row is not voided twice" 1 "$TEMPER" evidence void --stage build --id 2 --reason 'again'
assert_eq "9.8.5 Q3: the build and fix briefs record RED and GREEN with evidence run" "2|2" \
  "$(grep -cE -- '--phase (red|green) -- <the exact test command>' "$REPO_ROOT/agents/build.md")|$(grep -cE -- '--phase (red|green) -- <the exact test command>' "$REPO_ROOT/agents/fix.md")"

# --- 9.8.5 (M7 of WP08): at Check a run the CLI made passes the test row, and no brief records a claimed one ---
_strict
"$TEMPER" evidence run --stage check --claim "tests" -- true >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_m7_row() { python3 -c "
import json
r = [x for x in (json.load(open('.temper/gates.json')).get('check') or {}).get('requirements') or [] if x.get('name') == 'tests pass']
print(r[0].get('pass') if r else 'absent')"; }
assert_eq "9.8.5 M7: evidence run at Check passes tests pass" "True" "$(_m7_row)"
_strict
"$TEMPER" evidence add --stage check --claim "tests" --cmd true --exit 0 --label PROVEN >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
assert_eq "9.8.5 M7: a claimed test run at Check does not" "False" "$(_m7_row)"
assert_eq "9.8.5 M7: the Check brief records no claimed test run" "none" "$(python3 - "$REPO_ROOT" <<'PY2'
import os, re, sys
found = []
for f in ("agents/check.md", "reference/check.md"):
    text = re.sub(r"\\\n\s*", " ", open(os.path.join(sys.argv[1], f), encoding="utf-8").read())
    found += ["%s: %s" % (f, l.strip()[:80]) for l in text.splitlines() if "evidence add" in l and '--claim "tests"' in l]
print("; ".join(found) or "none")
PY2
)"

# --- 9.8.5: case 6 runs on its own; its helpers are generated from case 5 and kept in step ---
assert_eq "9.8.5: case-helpers-5.sh is what make-helpers-5.sh prints from temper-cases-5.sh" "same" \
  "$(bash "$REPO_ROOT/scripts/selftest/make-helpers-5.sh" | cmp -s - "$REPO_ROOT/scripts/selftest/case-helpers-5.sh" && echo same || echo differs)"
