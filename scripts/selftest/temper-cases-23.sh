# Release 9.8.5 case file 23: sourced by test-temper.sh after temper-cases-22.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5: the setup block (scripts/run_env.py): the project's environment contract, applied to every command the CLI runs ---
_re() { python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import run_env; $2" "$REPO_ROOT/scripts" "${@:3}"; }
fresh
assert_eq "9.8.5 setup: no block, load_setup is empty and run_cmd is as before" "{}|(b'hi\\n', 0)" \
  "$(_re x "print(str(run_env.load_setup('.claude/temper.config'))+'|'+str(run_env.run_cmd('.', 10, ['echo hi'], {})))")"
mkdir -p jdk24; printf '#!/usr/bin/env bash\necho "openjdk version \\"24.0.1\\"" >&2\n' > jdk24/java; chmod +x jdk24/java
printf 'setup:\n  run: export PATH="$PWD/jdk24:$PATH"\n  env:\n    IT_POSTGRES_PORT: 5433\n    DB_PASSWORD: x\n' >> .claude/temper.config
assert_eq "9.8.5 setup: the run line reaches the command, env is set, a credential name is left out" "0|5433||['DB_PASSWORD']" \
  "$(_re x "s = run_env.load_setup('.claude/temper.config'); o, rc = run_env.run_cmd('.', 10, ['java -version 2>&1 | grep -q \"24\"; echo \$?; echo \$IT_POSTGRES_PORT; echo \$DB_PASSWORD'], s); print('|'.join(o.decode().split('\\n')[1:4]) + '|' + str(s['dropped']))")"
assert_eq "9.8.5 setup: a list command runs under the block too" "temper-setup: OK|5433" \
  "$(_re x "o, rc = run_env.run_cmd('.', 10, ['bash', '-c', 'echo \$IT_POSTGRES_PORT']); print('|'.join(o.decode().splitlines()))")"
sed -i 's/^  run: .*/  run: exit 3/' .claude/temper.config
assert_eq "9.8.5 setup: a failing run line is exit 125 with temper-setup: FAIL, and the command does not run" "125|temper-setup: FAIL (exit 3)" \
  "$(_re x "o, rc = run_env.run_cmd('.', 10, ['echo never']); print(str(rc) + '|' + o.decode().strip())")"
assert_eq "9.8.5 setup: a credential assignment in the run line is masked when shown" "TOKEN=<left out> X=1 go" "$(_re x "print(run_env.mask('TOKEN=abc X=1 go'))")"
# WP21: the two keys of the plan gate's old per command check are gone from the template (the pattern is spelled so that
# the grep of the package's "Done when" does not find it here)
assert_eq "9.8.5 setup (WP21): the config template documents the setup block, and neither key of the old plan check" "setup=1|old keys=0" \
  "setup=$(grep -cE '^# *setup:' "$REPO_ROOT/templates/temper.config.default")|old keys=$(grep -cE '^# *  pre[f]light-(timeout|skip):' "$REPO_ROOT/templates/temper.config.default")"
# WP08 (M8): the reader merges a repeated key, and the template has no empty key that hides a documented block
# (only the first block from "# build:" to its keep-days line: the fix comments out the empty build key too)
awk '!d && /^# build:$/ {on = 1} on {sub(/^# /, "")} on && /keep-days:/ {on = 0; d = 1} {print}' \
  "$REPO_ROOT/templates/temper.config.default" > .claude/temper.config
assert_eq "the template with the grouped block uncommented keeps it" "claude-haiku-5-5" \
  "$("$TEMPER" config get build.grouped.task-model 2>&1)"
{ cat "$REPO_ROOT/templates/temper.config.default"; printf 'autonomy:\n  policy: decide\n'; } > .claude/temper.config
assert_eq "two autonomy blocks keep park-on-touch" "**/auth/**,**/payment/**,**/billing/**|decide" \
  "$("$TEMPER" config get autonomy.park-on-touch 2>&1 | tr '\037' ',')|$("$TEMPER" config get autonomy.policy 2>&1)"

# --- 9.8.5: every agent prompt carries the setup block (flow.plugin_line) ---
fresh
assert_eq "9.8.5 prompts: no block, no Environment setup line" "0" "$(nx "sum(a['prompt'].count('Environment setup') for a in d.get('agents') or [])")"
printf 'setup:\n  run: eval "$(scripts/ensure-jdk24.sh --export)"\n  env:\n    IT_POSTGRES_PORT: 5433\n    DB_PASSWORD: hunter2\n' >> .claude/temper.config
assert_eq "9.8.5 prompts: the Intent agent's prompt holds the line once, with the run line and the variables, no credential" "1|True|True|False" \
  "$(nx "p = d['agents'][0]['prompt']; '|'.join(map(str, [p.count('Environment setup'), 'ensure-jdk24.sh --export' in p, 'IT_POSTGRES_PORT=5433' in p, 'hunter2' in p or 'DB_PASSWORD' in p]))")"
sed -i '/^  run: /d' .claude/temper.config
assert_eq "9.8.5 prompts: a block with only env says run: (none)" "True" "$(nx "'run: (none)' in d['agents'][0]['prompt']")"

# --- 9.8.5: temper doctor reports the toolchain, the setup block and the services, and changes nothing ---
fresh
printf 'setup:\n  run: touch ran-marker\n  env:\n    IT_PORT: 5433\n    API_TOKEN: x\n  services:\n    closed: 127.0.0.1:9\n  tools: [git, no-such-tool-xyz]\n' >> .claude/temper.config
before="$(find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 cksum | cksum)"
OUT="$("$TEMPER" doctor 2>&1)"; rc=$?
assert_eq "9.8.5 doctor: exit 0, a tool's version, a missing tool, the run line not run, the variables, the service state" \
  "0|True|True|True|True|True|True|False" \
  "$rc|$(python3 -c "
import sys; o = sys.stdin.read()
print('|'.join(map(str, ['git: git version' in o, 'no-such-tool-xyz: not on PATH' in o, 'run: touch ran-marker (not run by doctor' in o,
      'IT_PORT=5433' in o, 'left out (credential name): API_TOKEN' in o, 'closed 127.0.0.1:9: not answering' in o, 'API_TOKEN=' in o])))" <<<"$OUT")"
assert_eq "9.8.5 doctor: no file changed and the setup line did not run" "$before|no" \
  "$(find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 cksum | cksum)|$([[ -e ran-marker ]] && echo yes || echo no)"
fresh
assert_eq "9.8.5 doctor: no block says so" "True" "$("$TEMPER" doctor 2>&1 | grep -c '^Setup block: none' | sed 's/^1$/True/')"
assert_eq "9.8.5 doctor: --help lists it" "1" "$("$TEMPER" --help 2>&1 | grep -c '^  temper doctor ')"
rm -rf jdk24

# --- WP08 (U4): the store of reused passes (run_env.run_cached), a test of shipped code ---
fresh; mkdir -p rs; git -C rs init -q; echo a > rs/a.txt; git -C rs add a.txt; git -C rs -c user.name=t -c user.email=t@e commit -q -m base
_rk() { # _rk <command> <setup json>: one run_cached call in rs; prints the exit, ran or reused, and the first output line
  _re x "import json; o, rc, r = run_env.run_cached(sys.argv[2], 10, [sys.argv[3]], json.loads(sys.argv[4])); print('%d|%s|%s' % (rc, 'reused' if r else 'ran', (o.decode().splitlines() or [''])[0]))" "$PWD/rs" "$1" "$2"
}
_rn() { cat "rs/.git/$1" 2>/dev/null | wc -l | tr -d ' '; }
assert_eq "reuse: a pass on a clean tree is kept and the second call does not run" "0|ran|0|reused|1" \
  "$(_rk 'echo r >> .git/cnt' '{}' | cut -d'|' -f1-2)|$(_rk 'echo r >> .git/cnt' '{}' | cut -d'|' -f1-2)|$(_rn cnt)"
assert_eq "reuse: a failure is never kept" "1|ran|1|ran|2" \
  "$(_rk 'echo f >> .git/cntf; exit 1' '{}' | cut -d'|' -f1-2)|$(_rk 'echo f >> .git/cntf; exit 1' '{}' | cut -d'|' -f1-2)|$(_rn cntf)"
echo changed > rs/a.txt
assert_eq "reuse: a tree with an uncommitted change runs again" "ran|ran|3" \
  "$(_rk 'echo r >> .git/cnt' '{}' | cut -d'|' -f2)|$(_rk 'echo r >> .git/cnt' '{}' | cut -d'|' -f2)|$(_rn cnt)"
git -C rs checkout -q -- a.txt
_other="$(_rk 'echo r >> .git/cnt; true' '{}' | cut -d'|' -f2)"
echo b > rs/b.txt; git -C rs add b.txt; git -C rs -c user.name=t -c user.email=t@e commit -q -m more
_tree="$(_rk 'echo r >> .git/cnt' '{}' | cut -d'|' -f2)"
_setup="$(_rk 'echo r >> .git/cnt' '{"run": "true"}' | cut -d'|' -f2)"
assert_eq "reuse: another command, another tree and another setup block each run again" "ran|ran|ran|6" "$_other|$_tree|$_setup|$(_rn cnt)"
assert_eq "reuse: the output of a reused pass says so" "0|reused|True" \
  "$(_rk 'echo r >> .git/cnt' '{}' | python3 -c "import sys; rc, how, line = sys.stdin.read().rstrip('\n').split('|', 2); print('%s|%s|%s' % (rc, how, line.startswith('[temper: the same command passed on this same tree at') and 'reused, not run again' in line))")"
rm -rf rs
