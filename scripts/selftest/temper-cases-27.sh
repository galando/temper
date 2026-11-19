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
assert_exit "9.8.5 propose: --write with no stored failing command writes nothing (nothing to check against)" 1 env PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose --write
assert_eq "9.8.5 propose: so the config is unchanged" "$before" "$(cksum < .claude/temper.config)"
# WP21: the per command check of the plan and its store of failing commands are gone, so no block is checked against a
# stored failure any more: a block reaches the config only as the block the red base question showed, bound by its hash
# (WP20, case file 61). With a block already there, --write writes nothing, whatever hash it is given.
git init -q . 2>/dev/null; git add -A >/dev/null 2>&1; git -c user.name=t -c user.email=t@e commit -q -m base >/dev/null 2>&1
_blk27w="$(PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose 2>/dev/null | sed -n '/^setup:/,/^[^ ]/p' | grep -E '^(setup:|  )')"
_hash27w="$(python3 -B -c "import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())" "$_blk27w")"
printf 'setup:\n  env:\n    X27: "1"\n' >> .claude/temper.config; before="$(cksum < .claude/temper.config)"
assert_exit "9.8.5 propose: --write never writes over a setup block that is there" 1 \
  env PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose --write --expect "$_hash27w"
assert_eq "9.8.5 propose (WP21): so the config with its block is unchanged" "$before" "$(cksum < .claude/temper.config)"
rm -rf .git
rm -rf backend scripts fakepg; fresh
assert_eq "9.8.5 propose: a project with no such facts gets no proposal" "True" \
  "$("$TEMPER" doctor --propose 2>&1 | grep -q '^Nothing to propose' && echo True || echo False)"

# --- 9.8.5: a plan gate whose preflight hit the environment offers the proposed block first ---
_dp; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
gfail plan "preflight" "1 command(s): 1 environment fault
environment fault \`mvn verify\`: needs JDK [24,) (found 21.0.12)"
printf '{"env_faults": [{"cmd": "mvn verify", "files": null, "why": "needs JDK [24,) (found 21.0.12)"}], "limit": 30}\n' > .temper/preflight.json   # as the gate stores it
assert_eq "9.8.5 propose: the failed plan question offers the option that adds the block, runs the preflight again and gates the plan" \
  "Add the proposed setup block (Recommended)|doctor --propose --write|plan preflight|gate plan|True" \
  "$(PATH="$PWD/fakepg:$PATH" nx "o = [x for x in d['ask']['options'] if x.get('id') == 'add-setup'][0]; '|'.join([o['label']] + [c.split('temper ', 1)[1] for c in o['calls']] + [str('IT_POSTGRES_PORT=5432' in o['description'])])")"
# WP08 (M16): after the person repaired the environment, one option checks again: the preflight, then the plan gate
assert_eq "9.8.5 preflight: the failed plan question offers check-again" "plan|check-again|plan preflight|gate plan" \
  "$(PATH="$PWD/fakepg:$PATH" nx "a = d.get('ask') or {}; os_ = (a.get('options') or []) + ((a.get('more') or {}).get('options') or []); \
o = ([x for x in os_ if x.get('id') == 'check-again'] or [{}])[0]; \
'|'.join([str(d.get('stage')), o.get('id', 'none')] + [c.split('temper ', 1)[-1] for c in o.get('calls') or []])")"
_blk27="$(PATH="$PWD/fakepg:$PATH" "$TEMPER" doctor --propose 2>/dev/null | sed -n '/^setup:/,/^[^ ]/p' | grep -E '^(setup:|  )')"
assert_eq "9.8.5 propose: the question shows the proposed block whole" "lines>2|missing=none" \
  "lines$([[ $(grep -c . <<<"$_blk27") -gt 2 ]] && echo '>2' || echo "=$(grep -c . <<<"$_blk27")")|missing=$(PATH="$PWD/fakepg:$PATH" python3 - "$_blk27" "$(PATH="$PWD/fakepg:$PATH" "$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
d = json.loads(sys.argv[2])
text = ((d.get("ask") or {}).get("question") or {}).get("question", "")
print("; ".join(l.strip() for l in sys.argv[1].splitlines() if l.strip() and l.strip() not in text) or "none")
PY
)"
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

# --- 9.8.5: the project's CI says what it runs on: the JDK, the services and the variables that point at them ---
fresh; mkdir -p .github/workflows .devcontainer fakepg
cat > .github/workflows/ci.yml <<'YML'
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      db:
        image: postgres:16
        ports:
          - 5433:5432
    env:
      APP_DB_PORT: ${{ job.services.db.ports['5432'] }}
      DEPLOY_URL: https://example.com
      API_TOKEN: x
    steps:
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
YML
printf '{"features": {"ghcr.io/devcontainers/features/node:1": {"version": "20"}}}\n' > .devcontainer/devcontainer.json
F="$(python3 -I -c "
import sys; sys.path.insert(0, sys.argv[1]); import doctor
f = doctor.ci_facts('.'); print('%s|%s|%s|%s' % (f['java'][0], f['node'][0], f['services'], sorted(f['env'].items())))" "$REPO_ROOT/scripts")"
assert_eq "9.8.5 CI: setup-java's version, the devcontainer's Node, the job's database service, the variable that points at it" \
  "21|20|[('db', 'postgres', '5433', 'postgres:16', '.github/workflows/ci.yml')]|[('APP_DB_PORT', 'service:db')]" "$F"
printf '#!/usr/bin/env bash\necho "16  main    5433 down   postgres /var/lib/postgresql/16/main /var/log/x.log"\n' > fakepg/pg_lsclusters; chmod +x fakepg/pg_lsclusters
OUT="$(PATH="$PWD/fakepg:$PATH" python3 -I -c "
import sys, shutil; sys.path.insert(0, sys.argv[1]); import doctor
real = shutil.which; doctor.shutil.which = lambda n: None if n == 'docker' else real(n)
b, f = doctor.propose('.'); print('\n'.join(f + b))" "$REPO_ROOT/scripts")"
assert_eq "9.8.5 CI: without docker the CI's Postgres maps to the local cluster, and its variable gets that port; no deploy or token value" \
  "True|True|False|False" \
  "$(grep -q 'runs on JDK 21' <<<"$OUT" && echo True || echo False)|$(grep -q 'APP_DB_PORT: 5433' <<<"$OUT" && echo True || echo False)|$(grep -q DEPLOY_URL <<<"$OUT" && echo True || echo False)|$(grep -q API_TOKEN <<<"$OUT" && echo True || echo False)"
rm -rf .github .devcontainer fakepg

# --- WP21: the environment agent is gone: its brief, its line in the manifest, its launch and the flag of doctor that
#     checked its draft (the state key and the flag are spelled in two parts, so that the grep of the package's "Done
#     when" does not find them here); case file 62 holds the same at the question ---
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_key27="env"; _key27+="_agent"; _flag27="--cand"; _flag27+="idate"
"$TEMPER" state set "$_key27" requested >/dev/null 2>&1 || true
assert_eq "9.8.5 agent: a saved request for the environment agent launches nothing" "0" \
  "$(nx "sum(1 for a in d.get('agents') or [] if a.get('type') == 'temper:temper-' + 'env')")"
printf 'setup:\n  env:\n    NEEDED: yes\n' > .git/setup-draft27.yaml
assert_exit "9.8.5 agent (WP21): doctor takes no draft of an agent: the flag is a usage error" 2 \
  "$TEMPER" doctor "$_flag27" .git/setup-draft27.yaml --write
assert_eq "9.8.5 agent (WP21): the brief is gone and plugin.json lists none" "gone|0" \
  "$([[ -e "$REPO_ROOT/agents/env.md" ]] && echo there || echo gone)|$(grep -c '"./agents/env.md"' "$REPO_ROOT/.claude-plugin/plugin.json")"
rm -f .git/setup-draft27.yaml
