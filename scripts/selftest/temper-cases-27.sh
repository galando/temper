# Release 9.8.5 case file 27: sourced by test-temper.sh after temper-cases-26.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5: temper doctor --propose writes the setup block from the project's own facts; the person adds it with one click ---
_dp() { # _dp: a project that needs JDK 24 (Maven enforcer), ships scripts/ensure-jdk24.sh --export, and reads IT_POSTGRES_PORT
  fresh; mkdir -p backend/src/test/java scripts fakepg
  printf '<project><build><plugins><plugin><configuration><rules><requireJavaVersion><version>[24,)</version></requireJavaVersion></rules></configuration></plugin></plugins></build></project>\n' > backend/pom.xml
  printf '#!/usr/bin/env bash\n[[ "$1" == --export ]] && echo "export JAVA_HOME=/opt/jdk24"\n' > scripts/ensure-jdk24.sh; chmod +x scripts/ensure-jdk24.sh
  printf 'class ItPostgres { String p = System.getenv("IT_POSTGRES_PORT"); }\n' > backend/src/test/java/ItPostgres.java
  printf '#!/usr/bin/env bash\necho "16  main    5432 down   postgres /var/lib/postgresql/16/main /var/log/x.log"\n' > fakepg/pg_lsclusters; chmod +x fakepg/pg_lsclusters
}
_dp
OUT="$(PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose 2>&1)"
assert_eq "9.8.5 propose: the JDK script, the database start, the port the code reads, the service and the tools" "True|True|True|True|True" \
  "$(python3 -c "
import sys; o = sys.stdin.read()
print('|'.join(map(str, ['  run: eval \"\$(scripts/ensure-jdk24.sh --export)\" && (pg_isready -q -h 127.0.0.1 -p 5432 || pg_ctlcluster 16 main start)' in o,
      '    IT_POSTGRES_PORT: 5432' in o, '    postgres: 127.0.0.1:5432' in o, '  tools: [java, mvn]' in o, 'found: backend/pom.xml needs JDK 24' in o])))" <<<"$OUT")"
before="$(cksum < .claude/temper.config)"
assert_eq "9.8.5 propose: without --write the config is unchanged" "$before" "$(cksum < .claude/temper.config)"
PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose --write >/dev/null 2>&1
assert_eq "9.8.5 propose: --write adds the block, which load_setup then reads" "5432|True" \
  "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import run_env; s = run_env.load_setup('.claude/temper.config'); print(s['env']['IT_POSTGRES_PORT'] + '|' + str('ensure-jdk24.sh' in s['run']))" "$REPO_ROOT/scripts")"
assert_exit "9.8.5 propose: --write never writes over a setup block that is there" 1 env PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose --write
rm -rf backend scripts fakepg; fresh
assert_eq "9.8.5 propose: a project with no such facts gets no proposal" "True" \
  "$("$TEMPER" doctor --propose 2>&1 | grep -q '^Nothing to propose' && echo True || echo False)"

# --- 9.8.5: a plan gate whose preflight hit the environment offers the proposed block first ---
_dp; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
gfail plan "preflight" "1 command(s): 1 environment fault
environment fault \`mvn verify\`: needs JDK [24,) (found 21.0.12)"
assert_eq "9.8.5 propose: the failed plan question's first option adds the block, runs the preflight again and gates the plan" \
  "Add the proposed setup block (Recommended)|doctor --propose --write|plan preflight|gate plan|True" \
  "$(PATH="$PWD/fakepg:$PATH" nx "o = d['ask']['options'][0]; '|'.join([o['label']] + [c.split('temper ', 1)[1] for c in o['calls']] + [str('IT_POSTGRES_PORT=5432' in o['description'])])")"
printf 'setup:\n  env:\n    X: 1\n' >> .claude/temper.config
assert_eq "9.8.5 propose: with a setup block already there, nothing is proposed at the question" "False" \
  "$(PATH="$PWD/fakepg:$PATH" nx "any(o['label'].startswith('Add the proposed setup block') for o in d['ask']['options'])")"
rm -rf backend scripts fakepg

# --- 9.8.5: propose reads Gradle, version files, Docker Compose services and a Python virtual environment too ---
fresh; mkdir -p app fakedock .venv/bin; : > .venv/bin/activate
printf 'java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }\n' > app/build.gradle.kts
printf 'java temurin-21.0.4\n' > .tool-versions
printf 'services:\n  db:\n    image: postgres:16\n    ports:\n      - "5433:5432"\n  cache:\n    image: redis:7\n    ports:\n      - 6380:6379\n' > compose.yaml
printf 'String p = System.getenv("APP_POSTGRES_PORT"); String r = System.getenv("APP_REDIS_PORT");\n' > app/Conf.java
printf '#!/usr/bin/env bash\nexit 0\n' > fakedock/docker; chmod +x fakedock/docker
OUT="$(PATH="$PWD/fakedock:$PATH" "$TEMPER" doctor --propose 2>&1)"
assert_eq "9.8.5 propose: Gradle and .tool-versions name the JDK; Compose services start with their ports; the venv is activated" \
  "True|True|True|True|True|True" \
  "$(python3 -c "
import sys; o = sys.stdin.read()
print('|'.join(map(str, ['app/build.gradle.kts needs JDK 21' in o, '.tool-versions names JDK 21' in o, 'docker compose -f compose.yaml up -d db cache' in o,
      '    APP_POSTGRES_PORT: 5433' in o and '    APP_REDIS_PORT: 6380' in o, '    db: 127.0.0.1:5433' in o, '. .venv/bin/activate' in o])))" <<<"$OUT")"
OUT="$(python3 -I -c "
import sys, shutil; sys.path.insert(0, sys.argv[1]); import doctor
real = shutil.which; doctor.shutil.which = lambda n: None if n == 'docker' else real(n)
block, facts = doctor.propose('.'); print('\n'.join(facts + block))" "$REPO_ROOT/scripts")"
assert_eq "9.8.5 propose: without docker the Compose services are named as a fact, not started" "True|False" \
  "$(grep -q 'docker does not answer here' <<<"$OUT" && echo True || echo False)|$(grep -q 'docker compose' <<<"$OUT" && echo True || echo False)"
rm -rf app fakedock .venv .tool-versions compose.yaml
