# Release 9.8.5 case file 22: sourced by test-temper.sh after temper-cases-21.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5: the preflight (scripts/preflight.py): each command of the plan runs once on the clean base, in one of four classes ---
_pfsetup() { # _pfsetup: the demo plan on a repository with one commit (the preflight runs on HEAD)
  fresh; f9_tasks > .temper/specs/demo/tasks.md
  rm -rf .git; git init -q . 2>/dev/null
}
_pfcommit() { git add -A >/dev/null 2>&1; git -c user.name=t -c user.email=t@example.com commit -q -m base >/dev/null 2>&1; }
_pfrun() { python3 -E -s "$REPO_ROOT/scripts/preflight.py" row .temper/specs/demo "$PWD" .claude/temper.config .temper/evidence/plan.json; }
_pfhas() { # _pfhas <fragment>...: the row's pass flag, then whether each fragment is in its detail
  _pfrun | python3 -c "
import json,sys; d=json.load(sys.stdin)
print('|'.join([d['name'], str(d['pass'])] + [str(w in d['detail']) for w in sys.argv[1:]]))" "$@"
}
mkdir -p fakebin
cat > fakebin/mvn <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *case=jdk*) printf '[ERROR] Rule 1: RequireJavaVersion failed with message:\n[ERROR] Detected JDK /usr/lib/jvm/java-21 is version 21.0.12 which is not in the allowed range [24,).\n' >&2; exit 1 ;;
  *case=cov*)
    echo '[INFO] Tests run: 328, Failures: 0, Errors: 0, Skipped: 0'
    echo '[WARNING] Rule violated for bundle demo: lines covered ratio is 0.04, expected 0.94'
    echo '[ERROR] Failed to execute goal org.jacoco:jacoco-maven-plugin:0.8.12:check (check) on project demo: Coverage checks have not been met.'
    echo '[INFO] BUILD FAILURE'
    exit 1 ;;
  *) exit 0 ;;
esac
FAKE
chmod +x fakebin/mvn
_pfsetup; _pfcommit
assert_eq "9.8.5 preflight: Validate true is one command that passes" "preflight|True|1 command(s): 1 passes" \
  "$(_pfrun | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['name']+'|'+str(d['pass'])+'|'+d['detail'])")"
# WP08 (F4): each command of the plan appends its own name to a counter file outside the tree. The row runs the
# Validates and the Integration line, never a task Test (it needs code not written yet) and never a scenario Test.
_pfsetup; mkdir -p .git/pfc; PFC="$PWD/.git/pfc/count"; : > "$PFC"
printf '#!/bin/sh\necho "$1" >> %s\n' "$PFC" > .git/pfc/c; chmod +x .git/pfc/c
f9_intent "$PWD/.git/pfc/c S1" "$PWD/.git/pfc/c S2"
python3 - "$PWD/.git/pfc/c" <<'PY'
import sys
c, p = sys.argv[1], ".temper/specs/demo/tasks.md"
t = open(p).read().replace("**Validate:** `true`", "**Validate:** `%s V`" % c)
t = t.replace("**Integration:** `true`", "**Integration:** `%s I`" % c)
t = t.replace("**Test:** `true`", "**Test:** `%s T1`" % c, 1).replace("**Test:** `true`", "**Test:** `%s T2`" % c, 1)
open(p, "w").write(t)
PY
_pfcommit; _pfrun >/dev/null
assert_eq "9.8.5 preflight: only the Validates and the Integration line run" "V=1|I=1|T=0|S=0" \
  "V=$(grep -c '^V$' "$PFC")|I=$(grep -c '^I$' "$PFC")|T=$(grep -c '^T' "$PFC")|S=$(grep -c '^S' "$PFC")"
assert_eq "9.8.5 preflight: the base is as it was after the run (no worktree left, no file changed)" "1|" \
  "$(git worktree list | wc -l)|$(git status --porcelain | grep -v '^?? fakebin' | grep -v '^?? .temper/preflight.json' | head -1)"
_pfsetup; sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `sleep 5`/' .temper/specs/demo/tasks.md
printf 'plan:\n  preflight-timeout: 2\n' >> .claude/temper.config; _pfcommit
# WP08 (M15): a time out is no environment fault. The row passes and names the three ways on: a longer limit,
# another command (temper plan patch), a skip with a reason.
assert_eq "9.8.5 preflight: a command over the limit is not checked and passes the row" \
  "preflight|True|True|True|True|True|False" \
  "$(_pfhas 'not checked: over 2 s' 'plan.preflight-timeout' 'plan patch' 'plan.preflight-skip' 'environment fault')"
assert_eq "9.8.5 preflight: the default time limit is 300 s" "300" "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import preflight; print(preflight.DEFAULT_TIMEOUT)" "$REPO_ROOT/scripts")"
# WP08 (F4): one limit for the whole row. Two Validates that sleep 2 s each, under a limit of 3 s, with no Integration
# line: the first runs and writes its letter, the second finds the total spent and never writes its own.
_pfsetup; second_group; sed -i '/^\*\*Integration:\*\*/d' .temper/specs/demo/tasks.md
python3 - "$PWD/.git/pf-total" <<'PY'
import sys
f, p = sys.argv[1], ".temper/specs/demo/tasks.md"
t = open(p).read()
for letter in "ab":
    t = t.replace("**Validate:** `true`", "**Validate:** `sleep 2 && echo %s >> %s`" % (letter, f), 1)
open(p, "w").write(t)
PY
printf 'plan:\n  preflight-timeout: 3\n' >> .claude/temper.config; _pfcommit
OUT="$(_pfhas 'not checked: the total limit of 3 s was spent')"
assert_eq "9.8.5 preflight: one total limit" "preflight|True|True|ran=a" \
  "$OUT|ran=$(paste -sd, .git/pf-total 2>/dev/null)"
_pfsetup; sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `mvn verify -Pjacoco -Dcase=jdk`/' .temper/specs/demo/tasks.md
printf 'plan:\n  preflight-skip: "the suite takes 40 minutes"\n' >> .claude/temper.config; _pfcommit
assert_eq "9.8.5 preflight: plan.preflight-skip with a reason skips the run and says so" "preflight|True|True" "$(PATH="$WORKDIR/fakebin:$PATH" _pfhas 'skipped by the person: the suite takes 40 minutes')"
PATH="$WORKDIR/fakebin:$PATH" _pfrun >/dev/null
assert_eq "9.8.5 preflight: two gate runs leave one ledger row for the skip" "1" "$(grep -o 'preflight skipped: the suite takes 40 minutes' .temper/evidence/plan.json | wc -l)"
_pfsetup; printf 'plan:\n  preflight-skip: true\n' >> .claude/temper.config; _pfcommit
assert_eq "9.8.5 preflight: plan.preflight-skip: true without a reason fails the row" "preflight|False|True" "$(_pfhas 'needs a reason text')"
_pfsetup
before="$(git status --porcelain | sort | cksum)"
assert_eq "9.8.5 preflight: a repository with no commit skips the row" "preflight|True|True" "$(_pfhas 'skipped: no commit to run on')"
assert_eq "9.8.5 preflight: the tree and the worktree list are as before" "$before|1" "$(git status --porcelain | sort | cksum)|$(git worktree list | wc -l)"
rm -rf fakebin

# --- 9.8.5: the preflight runs once per plan; the gate reads the stored result while HEAD, commands and setup are unchanged ---
_pfsetup; sed -i "s|^\*\*Validate:\*\* \`true\`\$|**Validate:** \`echo ran >> $PWD/pf-count\`|" .temper/specs/demo/tasks.md; _pfcommit
rm -f pf-count; _pfrun >/dev/null; _pfrun >/dev/null
assert_eq "9.8.5 preflight: a second gate on the same HEAD and commands reads the stored result (one run)" "1" "$(wc -l < pf-count | tr -d ' ')"
python3 -E -s "$REPO_ROOT/scripts/preflight.py" run .temper/specs/demo "$PWD" .claude/temper.config .temper/evidence/plan.json >/dev/null
assert_eq "9.8.5 preflight: preflight.py run (temper plan preflight) runs it again" "2" "$(wc -l < pf-count | tr -d ' ')"
echo change > README2; _pfcommit; _pfrun >/dev/null
assert_eq "9.8.5 preflight: a new HEAD runs it again" "3" "$(wc -l < pf-count | tr -d ' ')"
printf 'setup:\n  env:\n    IT_PORT: 5433\n' >> .claude/temper.config; _pfrun >/dev/null
assert_eq "9.8.5 preflight: a changed setup block runs it again" "4" "$(wc -l < pf-count | tr -d ' ')"
rm -f pf-count README2
# WP08 (M16): only a pass is stored. A Validate that fails on the environment until a marker file exists; the marker is
# written (the environment repaired), and the next row call on the same HEAD runs the command again and passes.
_pfsetup; PFM="$PWD/.git/pf-repaired"; PFN="$PWD/.git/pf-runs"
PFV="echo ran >> $PFN; test -e $PFM || { echo 'java.net.ConnectException: Connection refused'; exit 1; }"
python3 -c "import sys; p = sys.argv[1]; t = open(p).read(); open(p, 'w').write(t.replace('**Validate:** \`true\`', '**Validate:** \`%s\`' % sys.argv[2]))" \
  .temper/specs/demo/tasks.md "$PFV"
_pfcommit; OUT="$(_pfhas 'environment fault')"; touch "$PFM"
assert_eq "9.8.5 preflight: a stored failure is not returned" \
  "first=preflight|False|True|then=preflight|True|False|runs=2" \
  "first=$OUT|then=$(_pfhas 'environment fault')|runs=$(wc -l < "$PFN" | tr -d ' ')"
