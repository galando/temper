// The scripted persons of the acceptance scenarios, and the shared assert of row D105 (the world check).
//
//   defaultPerson(allowed)  takes the option whose `recommended` is true, and throws `unexpected question <id>` at a
//                           question whose id is not in `allowed` (no list: every question is allowed). A scenario that
//                           is still expected to fail so fails at its first extra question, in seconds.
//   stagePerson             takes `ask-every-stage` at `plan.approve` and the recommended option elsewhere.
//   worldCheck(w)           the shared assert of row D105, read from the project itself (git, the origin, the gh log, the
//                           files), never from the names of calls. Every scenario of scripts/e2e/accept.ts, slow.ts and
//                           broken.ts starts with withRemote(w) (scripts/e2e/faketools.ts) and ends with one call of it.
//
// Both persons select by id, never by label, and take the picture of the project at each question they answer: at the
// approval (`plan.approve`, `rca.approve`, or `design.pass` when Design asks it) and at the last question. Rule 1 of
// docs/plans/one-go/README.md section 6 cannot hold in the world before WP12, while rows that pass earlier use the same
// scenarios: so while a line of `approval-first` is on scripts/selftest/expected-fail.txt, worldCheck prints what it
// found as `XFAIL world <scenario> [<mode>]: <line>` and returns; once WP12 has taken that line off, a finding fails the
// scenario.
import { picture, recordOf } from './faketools'
import type { AgentLaunch, Picture, Pick, WorldRecord } from './faketools'
import { listed, loadList } from './xfail'
import type { Entry } from './xfail'
import type { Json, Person, World } from './world'

// The approval of a run: the question, and the moves of the options that approve.
export const APPROVALS = ['plan.approve', 'rca.approve', 'design.pass']
const APPROVING_MOVES = ['approve', 'arm']

export const idOf = (ask: Json): string => String(ask.id ?? ask.question?.id ?? '')
const options = (ask: Json): Json[] => (Array.isArray(ask.options) ? ask.options : []) as Json[]

// The person met a question and picked an option: the pictures of the world, and the pick.
function meet(w: World, ask: Json, option: Json): void {
  const rec = recordOf(w)
  if (rec === null) return
  const id = idOf(ask)
  const shot = picture(w, id)
  if (APPROVALS.includes(id) && APPROVING_MOVES.includes(String(option.move ?? ''))) {
    rec.first ??= shot
    rec.approval = shot
    rec.approvals++
  }
  rec.last = shot
  rec.lastAsk = ask
  rec.picks.push({ question: id, option: String(option.id ?? ''), move: String(option.move ?? '') })
}

function pick(w: World, ask: Json, option: Json | undefined): string {
  if (option === undefined) throw new Error(`no recommended option at ${idOf(ask)} (${options(ask).map(o => o.id).join(' | ')})`)
  meet(w, ask, option)
  return String(option.label)
}
const recommendedOf = (ask: Json): Json | undefined => options(ask).find(o => o.recommended === true)

// The option with that id, picked as a person picks: the world's pictures are taken, as for the recommended option.
export function pickId(w: World, ask: Json, id: string): string {
  return pick(w, ask, options(ask).find(o => o.id === id))
}

export function defaultPerson(allowed?: string[]): Person {
  return (ask, w) => {
    const id = idOf(ask)
    if (allowed !== undefined && !allowed.includes(id))
      throw new Error(`unexpected question ${id}: ${String(ask.question?.question ?? '').split('\n')[0]!.slice(0, 160)}`)
    return pick(w, ask, recommendedOf(ask))
  }
}

export const stagePerson: Person = (ask, w) => {
  if (idOf(ask) === 'plan.approve') return pick(w, ask, options(ask).find(o => o.id === 'ask-every-stage') ?? recommendedOf(ask))
  return pick(w, ask, recommendedOf(ask))
}

// ---- the world check of row D105 -----------------------------------------------------------------------------------

// The options that change a part of the world after the approval: an answer of the person, not a rule.
const CHANGES: Record<string, string[]> = {
  config: ['add-setup', 'find-setup', 'tidy-config', 'keep-config'],
  overrides: ['override', 'go-on-anyway'],
  commands: ['change-command', 'more-time'],
  accepted: ['accept-finding'],
}
const PLANNER = 'temper:temper-plan'

// The config without its top level `setup:` block.
export function withoutSetup(config: string): string {
  const out: string[] = []
  let inBlock = false
  for (const line of config.split('\n')) {
    if (/^setup:/.test(line)) {
      inBlock = true
      continue
    }
    if (inBlock && (line === '' || /^\s/.test(line))) continue
    inBlock = false
    out.push(line)
  }
  return out.join('\n').replace(/\n+$/, '\n')
}

// The message of the final commit, as the commit question's option writes it.
function finalMessage(ask: Json | null): string {
  if (ask === null || idOf(ask) !== 'commit.confirm') return ''
  for (const o of options(ask)) {
    for (const c of [...((o.calls ?? []) as string[]), ...((o.steps ?? []) as string[])]) {
      const m = /spec commit '((?:[^']|'\\'')*)'/.exec(c) ?? /git commit -m '((?:[^']|'\\'')*)'/.exec(c)
      if (m) return m[1]!.replace(/'\\''/g, "'")
    }
  }
  return ''
}

// What the row says, at the approval and at the last question. Each line starts with D105.
export function worldFindings(rec: WorldRecord): string[] {
  const found: string[] = []
  const start = rec.start
  if (start === null) return ['D105 no picture at the start: the run never asked `next` after withRemote(w)']
  // Rule 1: at the approval (with no approval, at the last question) the project is as at the start, but for the spec
  // folder, .temper/, the baseline worktree and a setup block an answer added. WP12: rule 1 is of the run before it was
  // approved, so it is read at the first approval; a step back to Plan the person chose, and the approval asked again,
  // keep the branch the first approval made.
  const at: Picture | null = rec.first ?? rec.approval ?? rec.last
  if (at !== null) {
    const where = rec.approval !== null ? 'at the approval' : `at the last question (${at.at}), with no approval`
    if (at.branch !== start.branch) found.push(`D105 ${where} the branch is ${at.branch}, at the start ${start.branch}`)
    if (at.commits !== start.commits) found.push(`D105 ${where} the branches hold ${at.commits} commits, at the start ${start.commits}`)
    const newBranches = at.branches.filter(b => !start.branches.includes(b))
    if (newBranches.length > 0) found.push(`D105 ${where} the run made the branch ${newBranches.join(', ')}`)
    const approving = rec.picks.map((p, i) => (APPROVALS.includes(p.question) && APPROVING_MOVES.includes(p.move) ? i : -1)).filter(i => i >= 0)
    const before = rec.approval !== null ? rec.picks.slice(0, approving[0]! + 1) : rec.picks
    const setupAnswer = before.some(p => CHANGES.config!.includes(p.option))
    const changed = [...new Set([...Object.keys(start.files), ...Object.keys(at.files)])].filter(f => start.files[f] !== at.files[f]).sort()
    const files = changed.filter(f => !(f === '.claude/temper.config' && setupAnswer && withoutSetup(at.config) === withoutSetup(start.config)))
    if (files.length > 0) found.push(`D105 ${where} the run changed project files: ${files.slice(0, 6).join(', ')}${files.length > 6 ? ` and ${files.length - 6} more` : ''}`)
  }
  // Rule 4: at the last question of a run the person started with approve-run
  const armed = rec.picks.some(p => APPROVALS.includes(p.question) && p.option === 'approve-run')
  const ap = rec.approval
  const last = rec.last
  if (armed && ap !== null && last !== null) {
    const after = rec.picks.slice(rec.picks.findIndex(p => p.option === 'approve-run') + 1)
    const answered = (part: string): boolean => after.some(p => CHANGES[part]!.includes(p.option))
    const pushed = last.originRefs.filter(r => !start.originRefs.includes(r))
    if (pushed.length > 0) found.push(`D105 at the last question origin holds a new ref: ${pushed.join(', ')}`)
    if (last.ghLog.trim() !== '') found.push(`D105 at the last question the gh log is not empty: ${last.ghLog.trim().split('\n')[0]}`)
    if (last.config !== ap.config && !answered('config')) found.push('D105 the config changed after the approval, and no answer of the person changed it')
    if (last.overrides !== ap.overrides && !answered('overrides')) found.push('D105 .temper/overrides.json changed after the approval, and no answer of the person changed it')
    if (JSON.stringify(last.commandLines) !== JSON.stringify(ap.commandLines) && !answered('commands'))
      found.push('D105 a command line of tasks.md changed after the approval, and no answer of the person changed it')
    if (JSON.stringify(last.accepted) !== JSON.stringify(ap.accepted) && !answered('accepted'))
      found.push('D105 the accepted findings changed after the approval, and no answer of the person accepted one')
    if (last.intent !== ap.intent) found.push('D105 intent.md does not have the digest recorded at the approval')
    // a planner launched between two approvals is approved by the second only when the person picked a step back (move
    // `back`) after the first approval and before the launch; any other planner launch after an approval is a finding
    // (WP12; a step back that comes after the launch did not launch it)
    const marks = rec.picks.map((p, i) => (APPROVALS.includes(p.question) && APPROVING_MOVES.includes(p.move) ? i : -1)).filter(i => i >= 0)
    const stepped = (a: AgentLaunch): boolean =>
      a.approvals < marks.length && rec.picks.slice(marks[a.approvals - 1]! + 1, a.picks).some(p => p.move === 'back')
    const planners = rec.agents.filter(a => a.approvals > 0 && a.type === PLANNER && !stepped(a)).length
    if (planners > 0) found.push(`D105 the agent log holds ${planners} planner launch(es) after the approval`)
    const message = finalMessage(rec.lastAsk)
    if (message !== '' && last.subjects.includes(message)) found.push(`D105 a commit carries the final commit message before the commit question: ${message}`)
  }
  return found
}

// The shared assert. It reports, and returns, while `approval-first` is on the expected to fail list in this mode.
export function worldCheck(w: World, list: Entry[] = loadList()): void {
  const rec = recordOf(w)
  const found = rec === null ? ['D105 the scenario has no world: it must call withRemote(w) before its project starts'] : worldFindings(rec)
  if (found.length === 0) return
  if (listed(list, 'approval-first', w.mode) !== null) {
    for (const line of found) console.log(`XFAIL world ${w.name} [${w.mode}]: ${line}`)
    return
  }
  throw new Error(found.join('\n'))
}

// ---- the check of this file, on made up input ---------------------------------------------------------------------
//
//   bun scripts/e2e/persons.ts --check   asserts the planner clause of the world check on made up records, with no run
//                                        of the CLI; exit 0 or 1

function check(): number {
  let fails = 0
  const eq = (name: string, got: unknown, want: unknown): void => {
    const ok = JSON.stringify(got) === JSON.stringify(want)
    if (!ok) fails++
    const why = ok ? '' : ` (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`
    console.log(`${ok ? 'PASS' : 'FAIL'}: persons ${name}${why}`)
  }
  const shot: Picture = {
    at: 'start', branch: 'main', branches: ['main'], commits: 1, files: {}, config: '', overrides: '', commandLines: [],
    accepted: [], intent: '', originRefs: [], ghLog: '', subjects: [], spec: '',
  }
  const arm = { question: 'plan.approve', option: 'approve-run', move: 'arm' }
  const back = { question: 'build.fail', option: 'back-to-plan', move: 'back' }
  const retry = { question: 'build.fail', option: 'retry', move: 'retry' }
  // picks: how many answers the person had given at the launch; approvals: how many of them approved
  const planner = (approvals: number, picks: number): AgentLaunch => ({ type: PLANNER, approvals, picks })
  const run = (picks: Pick[], agents: AgentLaunch[]): string[] =>
    worldFindings({
      origin: '', ghLog: '', start: shot, approval: shot, first: shot, last: shot, lastAsk: null,
      approvals: picks.filter(p => p.move === 'arm').length, picks, agents,
    }).filter(l => l.includes('planner'))
  const found = (n: number): string[] => [`D105 the agent log holds ${n} planner launch(es) after the approval`]
  eq('D105 planner: the planner the step back launched, before the approval asked again, is excused',
    run([arm, back, arm], [planner(0, 0), planner(1, 2)]), [])
  eq('D105 planner: a planner launched by rule before a later step back is a finding (F2 of phase 4a)',
    run([arm, back, arm], [planner(0, 0), planner(1, 1)]), found(1))
  eq('D105 planner: a planner launched between two approvals with no step back is a finding',
    run([arm, retry, arm], [planner(0, 0), planner(1, 2)]), found(1))
  eq('D105 planner: a planner launched after the last approval is a finding, a step back before it or not',
    run([arm, back, arm], [planner(0, 0), planner(1, 2), planner(2, 3)]), found(1))
  eq('D105 planner: the planner before the first approval is no finding', run([arm], [planner(0, 0)]), [])
  console.log(`persons --check: ${fails === 0 ? 'PASS' : `FAIL (${fails})`}`)
  return fails === 0 ? 0 : 1
}

if (import.meta.main) {
  if (process.argv[2] === '--check') process.exit(check())
  console.log('usage: bun scripts/e2e/persons.ts --check')
  process.exit(2)
}
