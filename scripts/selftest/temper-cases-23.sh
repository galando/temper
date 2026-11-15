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
assert_eq "9.8.5 setup: the config template documents the setup block and the preflight keys" "3" \
  "$(grep -cE '^# *(setup:|  preflight-timeout:|  preflight-skip:)' "$REPO_ROOT/templates/temper.config.default")"

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
