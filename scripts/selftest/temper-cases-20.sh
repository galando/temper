# Release 9.8.4: the faults one failed run of a complex feature exposed (8 criteria, about 30 files, risk H). Sourced by
# test-temper.sh after temper-cases-19.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 6a. The GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n, GIT_CONFIG_VALUE_n family passes whole to a command the CLI runs ---
setup
assert_eq "9.8.4 6a: git configured through GIT_CONFIG_* still works under run_env (no 'unable to parse command-line config')" "0|false|1" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.interactive GIT_CONFIG_VALUE_0=false python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['git config --get credential.interactive; echo "rc=$?"; echo "${GIT_CONFIG_COUNT:-unset}"'])
lines = out.decode().split()
print('%s|%s|%s' % (rc, lines[0] if lines else '', lines[-1] if lines else ''))
PYT
)"
assert_eq "9.8.4 6a: a credential named variable is still left out" "none" \
  "$(MY_API_KEY_0=abc python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['echo "${MY_API_KEY_0:-none}"'])
print(out.decode().strip())
PYT
)"

assert_eq "9.8.4 6a: a family with a credential key (an extra header) is left out whole, so git parses and the header is gone" "unset|unset|ok" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0='Authorization: basic abc' python3 -I - "$REPO_ROOT/scripts" "$PWD" <<'PYT'
import sys; sys.path.insert(0, sys.argv[1])
import run_env
out, rc = run_env.run_cmd(sys.argv[2], 20, ['echo "${GIT_CONFIG_COUNT:-unset}|${GIT_CONFIG_VALUE_0:-unset}|$(git status >/dev/null 2>&1 && echo ok || echo broken)"'])
print(out.decode().strip())
PYT
)"

# --- 7b. .temper/brief.md is local run state: init lists it in the clone's info/exclude ---
setup
"$TEMPER" brief --text "a change" >/dev/null 2>&1 || printf '# brief\n' > .temper/brief.md
assert_eq "9.8.4 7b: init lists .temper/brief.md in info/exclude, so it is never an untracked file" "1|0" \
  "$(grep -cx '/.temper/brief.md' "$(git rev-parse --git-common-dir)/info/exclude")|$(git status --porcelain --untracked-files=all | grep -c 'brief.md')"
