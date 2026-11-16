# Release 9.8.5 case file 24: sourced by test-temper.sh after temper-cases-23.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5: a task gate that failed on the environment keeps its attempt and its worktree (task_ops verdict ENV) ---
_envplan() { cat <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The demo group.

### Task 1: first task
**File:** `src/a.sh`
**Depends:** none
**Test:** `faketest`
**Cases:**
- a holds
- [ ] done
TASKS
}
_envrun() { # _envrun <green mode>: a RED that fails on an assertion, the file made, a GREEN in the given mode
  _envplan | m_setup
  mkdir -p "$WORKDIR/.git/envbin"
  printf '#!/usr/bin/env bash\ncase "$(cat "$(dirname "$0")/mode")" in\n  assert) echo "AssertionError: expected 3, got 2"; exit 1 ;;\n  jdk) echo "[ERROR] Detected JDK /usr/lib/jvm/java-21 is version 21.0.12 which is not in the allowed range [24,)." >&2; exit 1 ;;\n  hang) sleep 30 ;;\n  *) exit 0 ;;\nesac\n' > "$WORKDIR/.git/envbin/faketest"
  chmod +x "$WORKDIR/.git/envbin/faketest"
  export PATH="$WORKDIR/.git/envbin:$PATH"
  "$TEMPER" task start 1 >/dev/null 2>&1
  echo assert > "$WORKDIR/.git/envbin/mode"; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  mkdir -p .claude/worktrees/temper-demo-T1/src; echo built > .claude/worktrees/temper-demo-T1/src/a.sh
  echo "$1" > "$WORKDIR/.git/envbin/mode"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
}
_envrun jdk
OUT="$("$TEMPER" task gate 1 --model haiku 2>&1)"; rc=$?
assert_eq "9.8.5 ENV: the gate says ENV, exits 0, spends no attempt, keeps the worktree and the status" \
  "0|True|0|running|True|True" \
  "$rc|$(grep -q '^ENV: Task 1 failed on the environment, not on the code: needs JDK \[24,) (found 21.0.12)' <<<"$OUT" && echo True || echo False)|$(m_field 1 attempts | python3 -c "import sys,ast; print(len(ast.literal_eval(sys.stdin.read().strip() or '[]')))")|$(m_field 1 status)|$([[ -f .claude/worktrees/temper-demo-T1/src/a.sh ]] && echo True || echo False)|$(m_field 1 env_fault | grep -q 'needs JDK' && echo True || echo False)"
assert_eq "9.8.5 ENV: temper next asks Check it again (Recommended), It is the code, or Save for later" "Check it again (Recommended)|True|True|1" \
  "$(nx "o = d['ask']['options'] + (d['ask'].get('more') or {}).get('options', []); '|'.join([o[0]['label'], str(any(x.get('id') == 'it-is-the-code' for x in o)), str(any(x['label'] == 'Save for later' for x in o)), str(sum('(Recommended)' in x['label'] for x in o))])")"
assert_eq "9.8.5 ENV: Check it again runs the GREEN test and the gate again" "True" \
  "$(nx "c = d['ask']['options'][0]['calls']; c[0].endswith('task test 1 --phase green') and ' task gate 1 --model ' in c[1]")"
echo ok > "$WORKDIR/.git/envbin/mode"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1; "$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
assert_eq "9.8.5 ENV: once the environment is repaired the task passes with one attempt and the env_fault mark is gone" "passed||" \
  "$(m_field 1 status)||$(m_field 1 env_fault)"
# WP08 (M9): a fault judged the environment's may be the code's: the person sends the task back, the attempt is spent
_envrun jdk; "$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
assert_eq "ENV: the question offers it-is-the-code" "True" \
  "$(nx "import re; o = [x for x in d['ask']['options'] + (d['ask'].get('more') or {}).get('options', []) if x.get('id') == 'it-is-the-code']; len(o) == 1 and len(o[0]['calls']) == 1 and bool(re.search(r' task gate 1 --model \\S+ --no-env$', o[0]['calls'][0]))")"
OUT="$("$TEMPER" task gate 1 --model haiku --no-env 2>&1)"
assert_eq "ENV: running it-is-the-code prints FAIL and the attempt count rises by one" "True|False|False|1" \
  "$(grep -q '^FAIL: ' <<<"$OUT" && echo True || echo False)|$(grep -q 'unknown flag' <<<"$OUT" && echo True || echo False)|$(grep -q '^ENV:' <<<"$OUT" && echo True || echo False)|$(m_field 1 attempts | python3 -c "import sys,ast; print(len(ast.literal_eval(sys.stdin.read().strip() or '[]')))")"
_envrun jdk; "$TEMPER" task gate 1 --model haiku >/dev/null 2>&1
"$TEMPER" task test 1 --phase green >/dev/null 2>&1; OUT="$("$TEMPER" task gate 1 --model haiku 2>&1)"
assert_eq "ENV: the same reason twice does not recommend Check it again" "True|Save for later (Recommended)|False" \
  "$(grep -q '^ENV: Task 1 failed on the environment' <<<"$OUT" && echo True || echo False)|$(nx "o = d['ask']['options']; o[0]['label'] + '|' + str(any(x['label'] == 'Check it again (Recommended)' for x in o))")"
_envrun assert
OUT="$("$TEMPER" task gate 1 --model haiku 2>&1)"; rc=$?
assert_eq "9.8.5 ENV: an assertion failure still spends its attempt and discards the worktree" "1|True|False|False" \
  "$rc|$(grep -q '^NEXT: retry Task 1' <<<"$OUT" && echo True || echo False)|$(grep -q '^ENV:' <<<"$OUT" && echo True || echo False)|$([[ -d .claude/worktrees/temper-demo-T1 ]] && echo True || echo False)"
_envrun jdk
echo stray > .claude/worktrees/temper-demo-T1/undeclared.txt
OUT="$("$TEMPER" task gate 1 --model haiku 2>&1)"
assert_eq "9.8.5 ENV: an environment fault with an undeclared change is still FAIL" "False|True" \
  "$(grep -q '^ENV:' <<<"$OUT" && echo True || echo False)|$(grep -q '^FAIL:' <<<"$OUT" && echo True || echo False)"
assert_eq "9.8.5 ENV: a time-out at the task gate is the code's (env_fault timeout_is_env=False)" "|time limit 5 s" \
  "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import preflight; print(preflight.env_fault('', 124, 'x', 5, timeout_is_env=False) + '|' + preflight.env_fault('', 124, 'x', 5))" "$REPO_ROOT/scripts")"
export PATH="${PATH#"$WORKDIR/.git/envbin:"}"
