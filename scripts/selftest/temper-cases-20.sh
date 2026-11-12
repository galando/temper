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

# --- 2. The group gate keeps the FAIL lines of its Validate output and counts its failures; group fix commits a fix agent's work ---
m_setup <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `bash -c 'echo collecting; echo "FAIL: alpha is missing"; test -f src/ok.txt'`
**Context:**
The core.

### Task 1: first
**File:** `src/a.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- a bad input is refused
- [x] done
TASKS
python3 -c "
import json; p = '.temper/groups.json'; d = json.load(open(p)); d['tasks'] = {'1': {'status': 'passed', 'group': 'G1'}}; json.dump(d, open(p, 'w'))"
"$TEMPER" group gate G1 >/dev/null 2>&1
_g1() { python3 -c "import json,sys; g = json.load(open('.temper/groups.json'))['groups']['G1']; print(eval(sys.argv[1]))" "$1"; }
assert_eq "9.8.4 2a: the group gate keeps the FAIL lines of its Validate output, and counts the failure" "FAIL|['FAIL: alpha is missing']|True|1" \
  "$(_g1 "'|'.join([g['gate']['verdict'], str(g['gate'].get('fail_lines')), str(g['gate'].get('ran')), str(g.get('fails'))])")"
"$TEMPER" group gate G1 >/dev/null 2>&1
assert_eq "9.8.4 2c: a second failed group check counts 2" "2" "$(_g1 "g.get('fails')")"
assert_exit "9.8.4 2b: group fix asks for the fix agent on a failed group" 0 "$TEMPER" group fix G1
assert_eq "9.8.4 2b: and records the request" "True" "$(_g1 "bool((g.get('fix') or {}).get('requested'))")"
WT="$(_g1 "g['worktree']")"; mkdir -p "$WT/src"; echo ok > "$WT/src/ok.txt"
assert_exit "9.8.4 2b: group fix --commit commits the fix agent's work on the group branch as the CLI's own commit" 0 "$TEMPER" group fix G1 --commit
assert_eq "9.8.4 2b: the commit is recorded as the CLI's, the request is done, and the worktree is clean" "True|False|0" \
  "$(python3 -c "
import json, subprocess
d = json.load(open('.temper/groups.json')); g = d['groups']['G1']
head = subprocess.run(['git', '-C', g['worktree'], 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
print('%s|%s' % (head in d.get('cli_commits', []), 'fix' in g))")|$(git -C "$WT" status --porcelain | grep -vc '^?? .temper/' )"
assert_exit "9.8.4 2b: the group gate passes on the fixed tree" 0 "$TEMPER" group gate G1
assert_exit "9.8.4 2b: group fix is refused on a group whose gate did not fail" 1 "$TEMPER" group fix G1
