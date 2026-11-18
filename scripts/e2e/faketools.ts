// The fake tool chain of the scripted Maven projects, and the remote a run could push to. No model and no real Maven: each
// tool is a short bash script on the World's PATH, and every call of `mvn` is one line of the file MOCK_LOG.
//
//   MVN, JAVA, PG, POM      the fake `mvn`, `java`, the Postgres tools and the pom of the measured run (scripts/e2e/replay.ts
//                           used them first; with every switch below off, `mvn` answers as it did there)
//   installTools(w)         writes them to a scratch folder and puts it first on the World's PATH, with MOCK_LOG (the log)
//                           and MOCK_DB (the database mark and the marks of the flaky tests)
//   withRemote(w)           a bare `origin` and a fake `gh` that logs its calls, as `pr-and-pipeline` builds them; it also
//                           takes the picture of the project when the run starts and keeps the agent log (row D105)
//
// The faults each switch of `mvn` plants, all read from the environment and all off by default:
//   TOOL_JDK                the JDK on the PATH: 24 passes the pom's enforcer rule [24,), anything else fails it (the
//                           wrong tool version)
//   $MOCK_DB/up             the database is up; without it and IT_POSTGRES_PORT, a verify without -DskipITs fails with
//                           Connection refused (the service that is down)
//   MOCK_SLOW_S             a run with no -Dtest= filter (the whole suite) sleeps this many seconds before it answers (a
//                           suite slower than the limits the scenario sets)
//   MOCK_RED                a class name: a run with no filter fails with that class in its failure lines, on every tree
//                           (a test that is red on the current code)
//   MOCK_FLAKY_BASE         a class that fails the first time it runs at all and passes after (a flaky test)
//   MOCK_FLAKY_LATER        a class that passes on the base tree and fails once, the first time it runs on another tree
//                           (a flaky test that a gate meets after the base). The tree is the code's: the tree of the
//                           pom's folder at HEAD (`git rev-parse HEAD:./` there), so a commit of the run's spec or
//                           config leaves the code on the base. The base tree is the one in $MOCK_DB/flaky-later.base,
//                           or the first tree it runs on. When it fails, $MOCK_DB/flaky-later.failed holds the tree and
//                           the number of mvn lines MOCK_LOG had.
// A class runs when the run has no filter, or when its filter names it. In a project with the Maven layout
// (src/test/java under the pom's folder) a run with no filter runs Shape and Bytes only once their test file is there, as
// Maven runs the tests that exist; the project of the replay has no such folder, and its suite names both from the start.
//
// Each call is one line of MOCK_LOG, written when it ends:
//   `mvn <args> jdk=<n> db=<up|down> tree=<HEAD^{tree} where it ran> exit=<code> port=<port>`.
// A whole suite run is a line with no -Dtest=. A run the CLI's runner kills at its limit (a SIGKILL to its process
// group, scripts/run_env.py) cannot write its own line: while MOCK_SLOW_S is set, a watcher in a process group of its
// own writes it with exit=124, the code the runner reports for a time out.
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import type { World } from './world'

export const MVN = `#!/usr/bin/env bash
args="$*"
pre="mvn $args jdk=\${TOOL_JDK:-21} db=$([ -f "$MOCK_DB/up" ] && echo up || echo down) tree=$(git rev-parse 'HEAD^{tree}' 2>/dev/null || echo none)"
post="port=\${IT_POSTGRES_PORT:-}"
mark="$MOCK_DB/.ended.$$"
if [ -n "\${MOCK_SLOW_S:-}" ]; then
  set -m
  bash -c 'while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; if [ -f "$2" ]; then rm -f "$2"; else echo "$3 exit=124 $4" >> "$5"; fi' \\
    _ "$$" "$mark" "$pre" "$post" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
  set +m
fi
(
if [ "\${TOOL_JDK:-21}" != 24 ]; then
  echo "[ERROR] Rule 1: org.apache.maven.enforcer.rules.version.RequireJavaVersion failed with message:"
  echo "[ERROR] Detected JDK /usr/lib/jvm/java-21 is version 21.0.12 which is not in the allowed range [24,)."
  echo "[INFO] BUILD FAILURE"; exit 1
fi
filtered=""; case "$args" in *-Dtest=*) filtered=1 ;; esac
[ -z "$filtered" ] && [ -n "\${MOCK_SLOW_S:-}" ] && sleep "$MOCK_SLOW_S"
runs() { [ -n "$1" ] && { [ -z "$filtered" ] || case "$args" in *"$1"*) true ;; *) false ;; esac; }; }
root="$(pwd)"; [ -f "$root/pom.xml" ] || root="$root/backend"
want() { case "$1" in Shape) grep -q 'return 1;' "$root/src/Shape.java" 2>/dev/null ;; Bytes) grep -q 'return 2;' "$root/src/Bytes.java" 2>/dev/null ;; esac; }
classes="Shape Bytes"
case "$args" in *-Dtest=ShapeTest*) classes=Shape ;; *-Dtest=BytesTest*) classes=Bytes ;; esac
failed=""
for c in $classes; do
  [ -z "$filtered" ] && [ -d "$root/src/test/java" ] && [ ! -f "$root/src/test/java/\${c}Test.java" ] && continue
  want "$c" || failed="$failed \${c}Test"
done
if runs "\${MOCK_RED:-}"; then failed="$failed $MOCK_RED"; fi
if runs "\${MOCK_FLAKY_BASE:-}" && [ ! -f "$MOCK_DB/flaky-base.ran" ]; then
  : > "$MOCK_DB/flaky-base.ran"; failed="$failed $MOCK_FLAKY_BASE"
fi
if runs "\${MOCK_FLAKY_LATER:-}"; then
  tree="$(git -C "$root" rev-parse HEAD:./ 2>/dev/null || echo none)"
  [ -f "$MOCK_DB/flaky-later.base" ] || echo "$tree" > "$MOCK_DB/flaky-later.base"
  if [ "$(cat "$MOCK_DB/flaky-later.base")" != "$tree" ] && [ ! -f "$MOCK_DB/flaky-later.failed" ]; then
    echo "$tree $(grep -c '^mvn ' "$MOCK_LOG")" > "$MOCK_DB/flaky-later.failed"; failed="$failed $MOCK_FLAKY_LATER"
  fi
fi
if [ -n "$failed" ]; then
  echo "[ERROR] Tests run: 2, Failures: 1, Errors: 0"; for f in $failed; do echo "[ERROR]   $f.check:12 expected the final value"; done
  echo "[INFO] BUILD FAILURE"; exit 1
fi
echo "[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0"
case "$args" in *verify*)
  case "$args" in *-Dtest=*) case "$args" in *-Djacoco.skip=true*) ;; *)
    echo "[WARNING] Rule violated for bundle demo: lines covered ratio is 0.04, but expected minimum is 0.94"
    echo "[ERROR] Failed to execute goal org.jacoco:jacoco-maven-plugin:0.8.16:check (coverage-check) on project demo: Coverage checks have not been met."
    echo "[INFO] BUILD FAILURE"; exit 1 ;; esac ;; esac
  case "$args" in *-DskipITs*) ;; *)
    if [ ! -f "$MOCK_DB/up" ] || [ -z "\${IT_POSTGRES_PORT:-}" ]; then
      echo "[ERROR] ItBaseIT: org.postgresql.util.PSQLException: Connection refused. Check that the hostname and port are correct"
      echo "[INFO] BUILD FAILURE"; exit 1
    fi
    echo "[INFO] Tests run: 3, Failures: 0, Errors: 0 (integration)" ;; esac ;;
esac
echo "[INFO] BUILD SUCCESS"
)
rc=$?
[ -n "\${MOCK_SLOW_S:-}" ] && : > "$mark"
echo "$pre exit=$rc $post" >> "$MOCK_LOG"
exit $rc
`
export const JAVA = `#!/usr/bin/env bash
[ "\${TOOL_JDK:-21}" = 24 ] && echo 'openjdk version "24.0.1" 2025-04-15' >&2 || echo 'openjdk version "21.0.12" 2025-07-15' >&2
`
export const PG: Record<string, string> = {
  pg_lsclusters: `#!/usr/bin/env bash
[ "$1" = -h ] || echo "Ver Cluster Port Status Owner Data directory Log file"
echo "16  main    5432 $([ -f "$MOCK_DB/up" ] && echo online || echo down) postgres /var/lib/postgresql/16/main /var/log/pg.log"
`,
  pg_isready: '#!/usr/bin/env bash\n[ -f "$MOCK_DB/up" ]\n',
  pg_ctlcluster: '#!/usr/bin/env bash\necho "pg_ctlcluster $*" >> "$MOCK_LOG"; touch "$MOCK_DB/up"\n',
  docker: '#!/usr/bin/env bash\nexit 1\n',   // the container's docker: the program is there, its daemon is not
}

export const POM = `<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>demo</artifactId><version>1</version>
<properties><java.version>24</java.version></properties>
<build><plugins>
<plugin><artifactId>maven-enforcer-plugin</artifactId><executions><execution><goals><goal>enforce</goal></goals><configuration><rules>
<requireJavaVersion><version>[24,)</version></requireJavaVersion></rules></configuration></execution></executions></plugin>
<plugin><groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><version>0.8.16</version><executions><execution>
<id>coverage-check</id><phase>verify</phase><goals><goal>check</goal></goals><configuration><rules><rule><element>BUNDLE</element>
<limits><limit><counter>LINE</counter><value>COVEREDRATIO</value><minimum>0.94</minimum></limit></limits></rule></rules></configuration>
</execution></executions></plugin></plugins></build></project>
`

export type Tools = { tools: string; db: string; log: string }

// The lines that put the fake tools on the World's PATH. The shell's own JDK and database settings are taken out: a
// project's fixture sets them, or leaves them out on purpose.
export function installTools(w: World): Tools {
  const tools = fs.mkdtempSync(path.join(os.tmpdir(), 'replay-tools-'))
  const db = fs.mkdtempSync(path.join(os.tmpdir(), 'replay-db-'))
  const log = path.join(tools, 'calls.log')
  fs.writeFileSync(log, '')
  for (const [name, body] of Object.entries({ mvn: MVN, java: JAVA, ...PG })) {
    fs.writeFileSync(path.join(tools, name), body)
    fs.chmodSync(path.join(tools, name), 0o755)
  }
  w.env.PATH = `${tools}:${w.env.PATH}`
  w.env.MOCK_LOG = log
  w.env.MOCK_DB = db
  delete w.env.TOOL_JDK
  delete w.env.IT_POSTGRES_PORT
  return { tools, db, log }
}

// One line of the tool log, read back.
export type ToolRun = { line: string; args: string; exit: number | null; suite: boolean; tree: string }
export function toolRuns(log: string): ToolRun[] {
  if (!fs.existsSync(log)) return []
  return fs.readFileSync(log, 'utf8').split('\n').filter(l => l.startsWith('mvn ')).map(line => {
    const exit = / exit=(\d+) port=/.exec(line)
    const args = line.replace(/^mvn /, '').replace(/ jdk=.*$/, '')
    return { line, args, exit: exit ? Number(exit[1]) : null, suite: !/-Dtest=/.test(args), tree: / tree=(\S+)/.exec(line)?.[1] ?? '' }
  })
}

// ---- the world of row D105 ------------------------------------------------------------------------------------------

// What a scripted person saw of the project at one question (persons.ts takes these; worldCheck reads them).
export type Picture = {
  at: string                                // the question id, or `start`
  branch: string
  branches: string[]
  commits: number
  files: Record<string, string>             // path -> sha256 of the content, the project's files outside .temper/
  config: string
  overrides: string
  commandLines: string[]                    // the Validate, Integration and Test lines of tasks.md
  accepted: string[]                        // the accepted findings of every ledger
  intent: string                            // sha256 of intent.md, '' when there is none
  originRefs: string[]
  ghLog: string
  subjects: string[]                        // every commit subject of every branch
  spec: string                              // the run's spec folder
}
// approvals: how many approvals the person had met at the launch; picks: how many answers the person had given then
export type AgentLaunch = { type: string; approvals: number; picks: number }
export type Pick = { question: string; option: string; move: string }
export type WorldRecord = {
  origin: string
  ghLog: string
  start: Picture | null
  approval: Picture | null
  first: Picture | null                     // WP12: the picture at the first approval, for rule 1
  last: Picture | null
  lastAsk: Record<string, any> | null
  approvals: number
  picks: Pick[]                             // every answer of the scripted person, in order
  agents: AgentLaunch[]                     // every agent launch, in order
}
const RECORDS = new WeakMap<World, WorldRecord>()
export const recordOf = (w: World): WorldRecord | null => RECORDS.get(w) ?? null

// The bare origin and the fake gh, as pr-and-pipeline builds them (scripts/e2e/scenarios.ts: prAndPipeline), as one call
// that a scenario makes before its project starts. A push or a pull request that a run makes then lands in this world,
// where the shared assert of row D105 reads it. The origin is empty at the start: any ref on it is a push of the run.
// The call also hooks two methods of this one World: the first `next` takes the picture of the project at the start of
// the run (after the scenario built the project and before any agent), and each launch of an agent is logged.
export function withRemote(w: World): WorldRecord {
  const bin = path.join(w.dir, '..', `bin-${path.basename(w.dir)}`)
  fs.mkdirSync(bin, { recursive: true })
  const ghLog = path.join(bin, 'gh.log')
  fs.writeFileSync(ghLog, '')
  fs.writeFileSync(path.join(bin, 'gh'), `#!/usr/bin/env bash\necho "gh $*" >> "${ghLog}"\ncase "$*" in\n  "pr create"*) echo "https://github.com/example/ci/pull/7" ;;\nesac\n`, { mode: 0o755 })
  w.env.PATH = `${bin}:${w.env.PATH}`
  const origin = path.join(bin, 'origin.git')
  w.sh(`git init -q --bare ${origin}`)
  w.sh(`git remote add origin ${origin}`)
  const rec: WorldRecord = { origin, ghLog, start: null, approval: null, first: null, last: null, lastAsk: null, approvals: 0, picks: [], agents: [] }
  RECORDS.set(w, rec)
  const next = w.next.bind(w)
  w.next = (extra = '') => {
    if (rec.start === null) rec.start = picture(w, 'start')
    return next(extra)
  }
  const guardAgent = w.guardAgent.bind(w)
  w.guardAgent = a => {
    rec.agents.push({ type: String(a.type), approvals: rec.approvals, picks: rec.picks.length })
    guardAgent(a)
  }
  return rec
}

const sha = (text: string | Buffer): string => createHash('sha256').update(text).digest('hex')
const readOr = (w: World, rel: string): string => (w.exists(rel) ? w.read(rel) : '')

// The picture of the project: git, the remote, the gh log and the files, never the names of calls.
export function picture(w: World, at: string): Picture {
  const rec = RECORDS.get(w)
  const git = (args: string): string => w.run(`git ${args}`).out.trim()
  let spec = ''
  try {
    spec = String(w.json('.temper/build-state.json').spec ?? '')
  } catch {
    spec = ''
  }
  if (spec === '' && w.exists('.temper/specs')) {
    const slugs = fs.readdirSync(path.join(w.dir, '.temper/specs'))
    if (slugs.length === 1) spec = `.temper/specs/${slugs[0]}`
  }
  // The project's files: tracked and untracked, but not what git ignores, and not inside a worktree of the run
  const files: Record<string, string> = {}
  const listed = w.run('git ls-files -z -c -o --exclude-standard').out.split('\0').filter(Boolean)
  for (const rel of [...new Set(listed)]) {
    if (rel.startsWith('.temper/') || (spec !== '' && rel.startsWith(`${spec}/`)) || rel.endsWith('/')) continue
    const abs = path.join(w.dir, rel)
    let st: fs.Stats
    try {
      st = fs.lstatSync(abs)
    } catch {
      files[rel] = 'gone'
      continue
    }
    if (st.isDirectory()) continue
    files[rel] = st.isSymbolicLink() ? `link:${fs.readlinkSync(abs)}` : sha(fs.readFileSync(abs))
  }
  const tasks = spec !== '' ? readOr(w, `${spec}/tasks.md`) : ''
  const accepted: string[] = []
  if (w.exists('.temper/evidence')) {
    for (const f of fs.readdirSync(path.join(w.dir, '.temper/evidence')).filter(f => f.endsWith('.json')).sort()) {
      let rows: unknown
      try {
        rows = JSON.parse(w.read(`.temper/evidence/${f}`))
      } catch {
        continue
      }
      if (Array.isArray(rows)) for (const r of rows) if (r && typeof r === 'object' && (r as Record<string, unknown>).accepted) accepted.push(`${f}:${String((r as Record<string, unknown>).claim ?? '')}`)
    }
  }
  const intent = spec !== '' && w.exists(`${spec}/intent.md`) ? sha(w.read(`${spec}/intent.md`)) : ''
  return {
    at,
    branch: git('branch --show-current') || `detached ${git('rev-parse HEAD')}`,
    branches: git("for-each-ref --format='%(refname)' refs/heads").split('\n').filter(Boolean),
    commits: Number(git('rev-list --count --branches') || '0'),
    files,
    config: readOr(w, '.claude/temper.config'),
    overrides: readOr(w, '.temper/overrides.json'),
    commandLines: tasks.split('\n').filter(l => /^\*\*(Validate|Integration|Test):\*\*/.test(l)),
    accepted: accepted.sort(),
    intent,
    originRefs: rec ? w.run(`git --git-dir=${rec.origin} for-each-ref --format='%(refname) %(objectname)'`).out.split('\n').filter(Boolean) : [],
    ghLog: rec && fs.existsSync(rec.ghLog) ? fs.readFileSync(rec.ghLog, 'utf8') : '',
    subjects: git('log --branches --format=%s').split('\n').filter(Boolean),
    spec,
  }
}
