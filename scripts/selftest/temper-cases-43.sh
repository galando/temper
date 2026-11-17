# Case file 43 (WP07, the mechanism of done.md): sourced by test-temper.sh after the case files before it. The expected
# to fail rule of the selftest runner (scripts/selftest/expected-fail.txt read by test-temper.sh and added up by
# run-selftest.sh), scripts/check_done.py and scripts/check_changed_tests.py. Each case runs on a throwaway copy, a two
# case file suite or a made up root of two rows, never on the real suite. Tokens: xfail:, done:.

_c43="$WORKDIR/c43"
rm -rf "$_c43"; mkdir -p "$_c43"
_c43_git() { # _c43_git <dir> <git words...>: git in a throwaway repository, with a name of its own
  local d="$1"; shift
  git -C "$d" -c user.name=c43 -c user.email=c43@example.com -c commit.gpgsign=false "$@"
}
_c43_commit() { _c43_git "$1" add -A >/dev/null 2>&1; _c43_git "$1" commit -q --allow-empty -m "$2" >/dev/null 2>&1; }

# --- the selftest runner on a throwaway copy: test-temper.sh and run-selftest.sh beside two made up case files ---
# file 11: one assert_eq that passes (T11a) and one that fails (T11b); file 12: the same with assert_exit (T12a, T12b).
# The stub CLI exits 3, as the real one does outside the self test folder, so the runner's own safety checks pass.
_c43_suite() { # _c43_suite <list lines...>: the copy at $_c43/suite with that list
  local d="$_c43/suite"
  rm -rf "$d"; mkdir -p "$d/scripts/selftest"
  cp "$REPO_ROOT/scripts/selftest/test-temper.sh" "$REPO_ROOT/scripts/selftest/run-selftest.sh" "$d/scripts/selftest/"
  printf '#!/bin/sh\nexit 3\n' > "$d/scripts/temper"; chmod +x "$d/scripts/temper"
  : > "$d/scripts/selftest/case-helpers.sh"
  printf '%s\n' 'assert_eq "T11a passes" a a' 'assert_eq "T11b fails" a b' > "$d/scripts/selftest/temper-cases-11.sh"
  printf '%s\n' 'assert_exit "T12a passes" 0 true' 'assert_exit "T12b fails" 0 false' > "$d/scripts/selftest/temper-cases-12.sh"
  printf '%s\n' '# suite:name   passes after   promise' "$@" > "$d/scripts/selftest/expected-fail.txt"
}
_c43_run() { # _c43_run [TEMPER_CASES_ONLY]: the copy's test-temper.sh, its output in $_c43/out; prints its exit code
  if [[ -n "${1:-}" ]]; then
    TEMPER_CASES_ONLY="$1" bash "$_c43/suite/scripts/selftest/test-temper.sh" > "$_c43/out" 2>&1
  else
    env -u TEMPER_CASES_ONLY bash "$_c43/suite/scripts/selftest/test-temper.sh" > "$_c43/out" 2>&1
  fi
  echo "$?"
}
_c43_tail() { tail -n 2 "$_c43/out" | tr '\n' '|'; }

_c43_suite 'selftest:T11b WP07 D01' 'selftest:T12b WP07 D01'
rc="$(_c43_run)"
assert_eq "xfail: a listed selftest check that fails is counted apart and the file still ends FAIL: 0" \
  "0|XFAIL: 2|PASS: 5  FAIL: 0||1|1" \
  "$rc|$(_c43_tail)|$(grep -c '^XFAIL: T11b fails$' "$_c43/out")|$(grep -c '^XFAIL: T12b fails$' "$_c43/out")"
assert_eq "xfail: the parallel runner adds up the expected failures and prints them before its last line" \
  "0|XFAIL: 2|PASS: 8  FAIL: 0|" \
  "$(bash "$_c43/suite/scripts/selftest/run-selftest.sh" --jobs 2 > "$_c43/par" 2>&1; echo "$?")|$(tail -n 2 "$_c43/par" | tr '\n' '|')"

_c43_suite 'selftest:T11a WP07 D01' 'selftest:T11b WP07 D01' 'selftest:T12b WP07 D01'
rc="$(_c43_run)"
assert_eq "xfail: a listed selftest check that passes is a failure that names the list" \
  "1|1|XFAIL: 2|PASS: 4  FAIL: 1|" \
  "$rc|$(grep -c '^UNEXPECTED PASS: T11a passes .* take T11a off scripts/selftest/expected-fail.txt$' "$_c43/out")|$(_c43_tail)"
assert_eq "xfail: the parallel runner shows an unexpected pass and fails" "1|1" \
  "$(bash "$_c43/suite/scripts/selftest/run-selftest.sh" --jobs 2 > "$_c43/par" 2>&1; echo "$?")|$(grep -c 'UNEXPECTED PASS: T11a passes' "$_c43/par")"

_c43_suite 'selftest:T11b WP07 D01'
rc="$(_c43_run)"
assert_eq "xfail: a check that is not listed and fails is a failure" "1|1|XFAIL: 1|PASS: 5  FAIL: 1|" \
  "$rc|$(grep -c '^FAIL: T12b fails' "$_c43/out")|$(_c43_tail)"

_c43_suite 'selftest:T11b WP07 D01' 'selftest:T12b WP07 D01' 'selftest:T19 WP07 D01'
r1="$(_c43_run)|$(grep -c '^FAIL: selftest:T19 on scripts/selftest/expected-fail.txt matches no check' "$_c43/out")|$(tail -n 1 "$_c43/out")"
assert_eq "xfail: an entry that matches no check is a failure (the whole suite; a run of some case files leaves it to check_done.py)" \
  "1|1|PASS: 5  FAIL: 1|0" "$r1|$(_c43_run "11 12")"

# the scenario half (step 3 of the mechanism) is scripts/e2e/xfail.ts, run by verify.sh as its own step: the selftest
# job of CI has no bun
assert_eq "xfail: the scenario half of the rule is a step of verify.sh (bun scripts/e2e/xfail.ts --check)" "1" \
  "$(grep -c '^step "xfail: xfail.ts --check.*bun scripts/e2e/xfail.ts --check$' "$REPO_ROOT/scripts/verify.sh")"

# --- check_done.py on a made up root: two rows, two case files, two scenarios of accept.ts, a caps file ---
_c43_root() { # _c43_root: a fresh made up root at $_c43/root, committed, on which check_done.py passes
  local d="$_c43/root"
  rm -rf "$d"; mkdir -p "$d/docs/plans/one-go" "$d/scripts/selftest" "$d/scripts/e2e"
  git init -q "$d"
  cat > "$d/docs/plans/one-go/done.md" <<'DONE'
# Done

## The table

| Id | Promise | Check | No model call | Passes after |
|---|---|---|---|---|
| D01 | one | `case 11 D01`; `scenario two-up` plain | yes | WP07 |
| D02 | two | `case 12 D02a`; `caps things` = 5 | yes | WP07 |
| D03 | three | No automated check | person | WP32 |

## Notes
DONE
  printf '%s\n' 'assert_eq "D01 one" a a' > "$d/scripts/selftest/temper-cases-11.sh"
  printf '%s\n' 'assert_eq "D02a two" a a' 'assert_eq "D100 a hundred" a a' > "$d/scripts/selftest/temper-cases-12.sh"
  cat > "$d/scripts/e2e/accept.ts" <<'TS'
import { worldCheck } from './persons'
export const twoUp = (w: World): void => {
  start(w)
  worldCheck(w)
}
function twoDownBody(w: World): void {
  worldCheck(w)
}
export const twoDown = (w: World): void => twoDownBody(w)
export const ACCEPT_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'two-up': { run: twoUp, modes: ['plain', 'mod'] },
  'two-down': { run: twoDown, modes: ['plain'] },
}
TS
  printf '%s\n' "export const SCENARIOS = { 'full-run': fullRun }" > "$d/scripts/e2e/scenarios.ts"
  printf '%s\n' '{"version": 1, "caps": {"things": {"now": 5, "final": 5}}}' > "$d/scripts/caps.json"
  printf '%s\n' '# suite:name   passes after   promise' > "$d/scripts/selftest/expected-fail.txt"
  _c43_commit "$d" "the made up root"
}
_c43_done() { # _c43_done [--final]: check_done.py on the made up root, its output in $_c43/done.out; prints its exit code
  python3 -I "$REPO_ROOT/scripts/check_done.py" --root "$_c43/root" "$@" > "$_c43/done.out" 2>&1
  echo "$?"
}
_c43_list() { printf '%s\n' "$@" >> "$_c43/root/scripts/selftest/expected-fail.txt"; }

_c43_root
assert_eq "done: the made up root passes, with a line a row and the count of the list" "0|0|D01 ok|D02 ok|D03 open|1" \
  "$(_c43_done)|$(_c43_done --final)|$(grep -E '^D0[123] ' "$_c43/done.out" | sed 's/ (.*//' | tr '\n' '|')$(grep -c '^check_done: the list holds 0 expected failures' "$_c43/done.out")"

_c43_list 'selftest:D01 WP08 D01'
assert_eq "xfail: the final mode fails while the list has an entry" "0|D01 expected to fail|1|1" \
  "$(_c43_done)|$(grep '^D01 ' "$_c43/done.out")|$(_c43_done --final)|$(grep -c 'final: selftest:D01 is still on the expected to fail list' "$_c43/done.out")"

_c43_root
sed -i 's/"D02a two"/"D02x two"/' "$_c43/root/scripts/selftest/temper-cases-12.sh"
r1="$(_c43_done)|$(grep -c '^D02 FAIL: case 12 D02a' "$_c43/done.out")"
_c43_root
sed -i 's/`scenario two-up` plain/`scenario two-gone` plain/' "$_c43/root/docs/plans/one-go/done.md"
r2="$(_c43_done)|$(grep -c '^D01 FAIL: scenario two-gone' "$_c43/done.out")"
_c43_root
sed -i 's/| D02 | two | `case 12 D02a`; `caps things` = 5 | yes |/| D02 | two | to be written | yes |/' "$_c43/root/docs/plans/one-go/done.md"
r3="$(_c43_done)|$(grep -c 'D02: the row needs no model and names no check' "$_c43/done.out")"
assert_eq "done: every row of done.md that needs no model names a check that exists" "1|1 1|1 1|1" "$r1 $r2 $r3"

_c43_root
sed -i 's/^| D03 | three |/| D02 | three |/' "$_c43/root/docs/plans/one-go/done.md"
r1="$(_c43_done)|$(grep -c 'D02: the row id is used twice' "$_c43/done.out")"
_c43_root
printf '%s\n' "test.skip('a skipped test', () => {})" > "$_c43/root/a.test.ts"
r2="$(_c43_done)|$(grep -c 'a test is skipped: a.test.ts' "$_c43/done.out")"
assert_eq "done: a row id used twice fails, and so does a skipped test of the mod" "1|1 1|1" "$r1 $r2"

# rule 11: a row of D30 to D39 names a case or a scenario that runs in plain mode
_c43_root
sed -i 's/^| D01 | one | `case 11 D01`; `scenario two-up` plain |/| D30 | one | `scenario two-up` mod |/' "$_c43/root/docs/plans/one-go/done.md"
r1="$(_c43_done)|$(grep -c 'D30: rule 11' "$_c43/done.out")"
sed -i 's/^| D30 | one | `scenario two-up` mod |/| D30 | one | `scenario two-up` plain, mod |/' "$_c43/root/docs/plans/one-go/done.md"
assert_eq "done: a rule row with neither a case nor a scenario in plain mode fails (rule 11)" "1|1 0" "$r1 $(_c43_done)"

_c43_root
_c43_list 'selftest:D01 WP08 D01'; _c43_commit "$_c43/root" "listed"
r1="$(_c43_done)"
sed -i '/^selftest:D01 /d' "$_c43/root/scripts/selftest/expected-fail.txt"; _c43_commit "$_c43/root" "D01 passes"
r2="$(_c43_done)"
_c43_list 'selftest:D01 WP09 D01'; _c43_commit "$_c43/root" "listed again"
r3="$(_c43_done)|$(grep -c 'selftest:D01 was taken off the list by an earlier commit and is on it again' "$_c43/done.out")"
assert_eq "done: a token that left the list cannot come back" "0 0 1|1" "$r1 $r2 $r3"

_c43_root
sed -i 's/`case 11 D01`/`case 12 D10`/' "$_c43/root/docs/plans/one-go/done.md"
r1="$(_c43_done)|$(grep -c '^D01 FAIL: case 12 D10 ' "$_c43/done.out")"
_c43_root
_c43_list 'selftest:D10 WP08 D01'
r2="$(_c43_done)|$(grep -c 'selftest:D10 matches no check' "$_c43/done.out")"
assert_eq "done: a token is a whole word" "1|1 1|1" "$r1 $r2"

_c43_root
_c43_list 'selftest:D100 WP08 D01' 'e2e:full-run WP08 D01' 'e2e:two-up WP08 D01'
assert_eq "done: a line of the list names a token of the table or a scenario of the three files" "1|1|1|0" \
  "$(_c43_done)|$(grep -c 'selftest:D100 is not a token of the table' "$_c43/done.out")|$(grep -c 'e2e:full-run is not a scenario of' "$_c43/done.out")|$(grep -c 'e2e:two-up is not' "$_c43/done.out")"

# D75b: each final equals the value the table writes after =, and none is above its value in the commit that first added it
_c43_root
printf '%s\n' '{"version": 1, "caps": {"things": {"now": 5, "final": 4}}}' > "$_c43/root/scripts/caps.json"
r1="$(_c43_done)|$(_c43_done --final)|$(grep -c 'D75b: caps things: the final is 4, the table says 5' "$_c43/done.out")"
_c43_root
printf '%s\n' '{"version": 1, "caps": {"things": {"now": 5, "final": 6}}}' > "$_c43/root/scripts/caps.json"
sed -i 's/`caps things` = 5/`caps things` = 6/' "$_c43/root/docs/plans/one-go/done.md"
_c43_commit "$_c43/root" "a final raised to match the table"
r2="$(_c43_done --final)|$(grep -c 'D75b: scripts/caps.json things: the final 6 is above 5, its value in the commit that first added it' "$_c43/done.out")"
assert_eq "done: the final mode compares each final with the number of done.md" "0|1|1 1|1" "$r1 $r2"

# D105: every scenario of the three files calls the shared assert (twoDown reaches it through a function it calls)
_c43_root
sed -i 's/^  worldCheck(w)$/  void w/' "$_c43/root/scripts/e2e/accept.ts"
assert_eq "done: a scenario of the three files that does not call the shared assert fails" "1|1|1" \
  "$(_c43_done)|$(grep -c 'D105: the scenario two-up of scripts/e2e/accept.ts (twoUp) does not call the shared assert' "$_c43/done.out")|$(grep -c 'D105: the scenario two-down' "$_c43/done.out")"

# D105 reads every entry of the object, whatever its key and the order of its fields: a key with no hyphen, run after
# modes, a run written in place; an entry it cannot read fails (phase 2 review, F3)
_c43_root
cat >> "$_c43/root/scripts/e2e/accept.ts" <<'TS'
export const lateOne = (w: World): void => { void w }
export const repairX = (w: World): void => { void w }
TS
sed -i "s/^  'two-down': { run: twoDown, modes: \['plain'\] },$/&\\
  'late-one': { modes: ['plain'], run: lateOne },\\
  repair: { run: repairX, modes: ['plain'] },\\
  'in-place': { run: (w: World) => { void w }, modes: ['plain'] },\\
  'no-run': { modes: ['plain'] },/" "$_c43/root/scripts/e2e/accept.ts"
r1="$(_c43_done)"
for x in 'the scenario late-one of' 'the scenario repair of' 'the scenario in-place of' 'registers no-run: an entry with no run'; do
  r1="$r1|$(grep -c "D105: .*$x" "$_c43/done.out")"
done
sed -i 's/{ run: (w: World) => { void w }/{ run: (w: World) => { worldCheck(w) }/' "$_c43/root/scripts/e2e/accept.ts"
assert_eq "done: the shared assert rule reads every entry of the scenario object, and fails one it cannot read" \
  "1|1|1|1|1 0" "$r1 $(_c43_done >/dev/null; grep -c 'D105: the scenario in-place' "$_c43/done.out")"

# the modes a scenario of the three files registers are read: a row cannot name a mode it does not run, it cannot run
# in none, a list line cannot name a mode it does not run, and rule 11 reads the registered modes (phase 2 review, F4)
_c43_root
sed -i 's/`scenario two-up` plain/`scenario two-up` plain, driver/' "$_c43/root/docs/plans/one-go/done.md"
r1="$(_c43_done)|$(grep -c '^D01 FAIL: scenario two-up driver (the scenario registers the modes plain, mod only)' "$_c43/done.out")"
_c43_root
sed -i "s/'two-down': { run: twoDown, modes: \['plain'\] }/'two-down': { run: twoDown, modes: [] }/" "$_c43/root/scripts/e2e/accept.ts"
r2="$(_c43_done)|$(grep -c 'registers two-down: an entry that registers no mode' "$_c43/done.out")"
_c43_root
_c43_list 'e2e:two-up:driver WP08 D01'
r3="$(_c43_done)|$(grep -c 'e2e:two-up:driver names a mode the scenario does not run' "$_c43/done.out")"
_c43_root
sed -i 's/^| D01 | one | `case 11 D01`; `scenario two-up` plain |/| D30 | one | `scenario two-up` |/' "$_c43/root/docs/plans/one-go/done.md"
sed -i "s/'two-up': { run: twoUp, modes: \['plain', 'mod'\] }/'two-up': { run: twoUp, modes: ['mod'] }/" "$_c43/root/scripts/e2e/accept.ts"
r4="$(_c43_done)|$(grep -c 'D30: rule 11' "$_c43/done.out")"
assert_eq "done: a row or a list line names no mode its scenario does not register, and rule 11 reads those modes" \
  "1|1 1|1 1|1 1|1" "$r1 $r2 $r3 $r4"

# --- check_changed_tests.py on a made up repository: the base, then the work tree ---
_c43_ct() { # _c43_ct <base>: check_changed_tests.py on $_c43/ct against the base; prints its exit code
  python3 -I "$REPO_ROOT/scripts/check_changed_tests.py" --root "$_c43/ct" --base "$1" > "$_c43/ct.out" 2>&1
  echo "$?"
}
_c43_ct_listed() { printf '| `%s` | a file | what | why | WP07 |\n' "$1" >> "$_c43/ct/docs/plans/one-go/changed-tests.md"; }
_c43_ct_repo() {
  local d="$_c43/ct"
  rm -rf "$d"; mkdir -p "$d/docs/plans/one-go" "$d/scripts/selftest"
  git init -q "$d"
  printf '%s\n' 'assert_eq "T1 one" "1" "$(echo 1)"' 'assert_exit "T2 two" 0 \' '  true' > "$d/scripts/selftest/temper-cases-11.sh"
  printf '%s\n' '| Name | File | What changed | Why | Package |' '|---|---|---|---|---|' > "$d/docs/plans/one-go/changed-tests.md"
  _c43_commit "$d" "the base"
  _c43_git "$d" rev-parse HEAD
}
CT_BASE="$(_c43_ct_repo)"
r0="$(_c43_ct "$CT_BASE")"
sed -i '/T1 one/d' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
r1="$(_c43_ct "$CT_BASE")"
_c43_ct_listed 'T1 one'
r2="$(_c43_ct "$CT_BASE")"
CT_BASE="$(_c43_ct_repo)"
sed -i 's/"T1 one" "1"/"T1 one" "2"/' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
r3="$(_c43_ct "$CT_BASE")"
_c43_ct_listed 'T1 one'
r4="$(_c43_ct "$CT_BASE")"
CT_BASE="$(_c43_ct_repo)"
sed -i 's/^  true$/  false/' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
r5="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED .*T2 two' "$_c43/ct.out")"
assert_eq "done: a removed or changed assertion of a test of the base fails until changed-tests.md lists it" \
  "0 1 0 1 0 1|1" "$r0 $r1 $r2 $r3 $r4 $r5"

# a name is listed only by the code span that is the first cell of a row: a span in the intro or in another column
# names nothing (phase 2 review, F1)
CT_BASE="$(_c43_ct_repo)"
sed -i '/T1 one/d' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
sed -i '1i This page lists `T1 one` in its intro.\n' "$_c43/ct/docs/plans/one-go/changed-tests.md"
printf '| %s | a file | `T1 one` was removed | why | WP07 |\n' '`T2 two`' >> "$_c43/ct/docs/plans/one-go/changed-tests.md"
r1="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED .*T1 one' "$_c43/ct.out")"
_c43_ct_listed 'T1 one'
assert_eq "done: a name counts as listed only in the code span of the first cell of a row of changed-tests.md" \
  "1|1 0" "$r1 $(_c43_ct "$CT_BASE")"

# a statement is compared whole line by whole line: an assertion commented out, or with a word added at its end, still
# holds its old text as a part of a line and is a change all the same; so is a row of done.md with a cell added
# (phase 2 review, F2)
CT_BASE="$(_c43_ct_repo)"
sed -i 's/^assert_eq "T1 one"/# &/' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
r1="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED .*T1 one' "$_c43/ct.out")"
CT_BASE="$(_c43_ct_repo)"
sed -i 's/^assert_eq "T1 one" "1" "$(echo 1)"$/& || true/' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
r2="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED .*T1 one' "$_c43/ct.out")"
CT_BASE="$(_c43_ct_repo)"
printf '%s\n' '## The table' '' '| Id | Promise | Check | No model call | Passes after |' '|---|---|---|---|---|' \
  '| D01 | one | `case 44 D01` | yes | WP07 |' > "$_c43/ct/docs/plans/one-go/done.md"
_c43_commit "$_c43/ct" "the table"
sed -i 's/^| D01 .*|$/& WP08 |/' "$_c43/ct/docs/plans/one-go/done.md"
r3="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED docs/plans/one-go/done.md:5 .*: D01$' "$_c43/ct.out")"
assert_eq "done: an assertion commented out or with a word added at its end, and a row with a cell added, are changes" \
  "1|1 1|1 1|1" "$r1 $r2 $r3"

# the paths of the diff are read the same under a person's diff.noprefix or diff.mnemonicPrefix: the check never passes
# with nothing read (phase 2 review, F7)
CT_BASE="$(_c43_ct_repo)"
sed -i '/T1 one/d' "$_c43/ct/scripts/selftest/temper-cases-11.sh"
_c43_git "$_c43/ct" config diff.noprefix true
r1="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED scripts/selftest/temper-cases-11.sh:1 .*T1 one' "$_c43/ct.out")"
_c43_git "$_c43/ct" config --unset diff.noprefix; _c43_git "$_c43/ct" config diff.mnemonicPrefix true
r2="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED scripts/selftest/temper-cases-11.sh:1 .*T1 one' "$_c43/ct.out")"
assert_eq "done: a removed assertion is found under diff.noprefix and under diff.mnemonicPrefix" "1|1 1|1" "$r1 $r2"

# D84b: the second base, the commit that first added the file, for done.md and the case files 43 to 46
CT_BASE="$(_c43_ct_repo)"
mkdir -p "$_c43/ct/docs/plans/one-go"
printf '%s\n' '## The table' '' '| Id | Promise | Check | No model call | Passes after |' '|---|---|---|---|---|' \
  '| D01 | one | `case 44 D01` | yes | WP07 |' > "$_c43/ct/docs/plans/one-go/done.md"
printf '%s\n' 'assert_eq "D01 one" "1" "$(echo 1)"' > "$_c43/ct/scripts/selftest/temper-cases-44.sh"
_c43_commit "$_c43/ct" "the table and its case"
r0="$(_c43_ct "$CT_BASE")"
sed -i 's/`case 44 D01`/`case 44 D01` or less/' "$_c43/ct/docs/plans/one-go/done.md"
sed -i 's/"D01 one" "1"/"D01 one" "0"/' "$_c43/ct/scripts/selftest/temper-cases-44.sh"
r1="$(_c43_ct "$CT_BASE")|$(grep -c 'UNLISTED docs/plans/one-go/done.md:5 .*: D01$' "$_c43/ct.out")|$(grep -c 'UNLISTED scripts/selftest/temper-cases-44.sh:1 .*: D01 one$' "$_c43/ct.out")"
_c43_ct_listed 'D01'; _c43_ct_listed 'D01 one'
assert_eq "done: a changed check of done.md fails until it is listed" "0 1|1|1 0" "$r0 $r1 $(_c43_ct "$CT_BASE")"
