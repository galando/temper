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
_pfsetup
sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `mvn verify -Pjacoco -Dcase=jdk`/; s/^\*\*Integration:\*\* `true`$/**Integration:** `mvn verify -Pjacoco -Dcase=cov`/; 0,/^\*\*Test:\*\* `true`$/s//**Test:** `bash unit\/a_test.sh`/' .temper/specs/demo/tasks.md
_pfcommit
OUT="$(PATH="$WORKDIR/fakebin:$PATH" _pfhas passes 'needs new code' 'environment fault' 'command fault' 'needs JDK [24,) (found 21.0.12)' 'Rule violated for bundle' 'unit/a_test.sh')"
assert_eq "9.8.5 preflight: four commands, four classes, the JDK range and the JaCoCo line quoted, the absent file named" \
  "preflight|False|True|True|True|True|True|True|True" "$OUT"
assert_eq "9.8.5 preflight: the base is as it was after the run (no worktree left, no file changed)" "1|" \
  "$(git worktree list | wc -l)|$(git status --porcelain | grep -v '^?? fakebin' | grep -v '^?? .temper/preflight.json' | head -1)"
_pfsetup; sed -i 's/^\*\*Validate:\*\* `true`$/**Validate:** `sleep 5`/' .temper/specs/demo/tasks.md
printf 'plan:\n  preflight-timeout: 2\n' >> .claude/temper.config; _pfcommit
assert_eq "9.8.5 preflight: a command over plan.preflight-timeout is an environment fault naming the limit" "preflight|False|True|True" "$(_pfhas 'environment fault' 'time limit 2 s')"
assert_eq "9.8.5 preflight: the default time limit is 300 s" "300" "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import preflight; print(preflight.DEFAULT_TIMEOUT)" "$REPO_ROOT/scripts")"
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
