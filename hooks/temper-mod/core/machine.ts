// The phase machine. Event sourced and pure: `reduce` folds the event log (plus the
// verdicts the CLI wrote) into a RunState, `decide` turns one command into drafts of
// new events or an error. Nothing here reads a file or knows how events are stored.

import { compareEvents } from './events'
import type { Draft, DriftChoice, Origin, Phase, TemperEvent } from './events'

export type Verdict = { verdict: 'PASS' | 'FAIL'; ts: number }

// The CLI's verdicts per stage (from .temper/gates.json); the mod only reads them. Design is part of Plan in the mod: its
// verdict judges the Design gate (RunState.designGate) while the CLI is at design.
export type Verdicts = Partial<Record<Phase | 'design', Verdict>>

export type GateState = 'fresh' | 'stale' | 'fail' | 'none'

export type ReduceOptions = {
  maxLoops?: number
  // Decision events failing this test are listed as unverified and not folded.
  isTrusted?: (ev: TemperEvent) => boolean
}

export type OverrideRecord = { id: string; phase: Phase; reason: string; author?: string; ts: number; stage?: string }
export type AcceptRecord = { id: string; findingId: string; reason: string; author?: string; ts: number }
export type DriftRecord = { id: string; path: string; choice: DriftChoice; reason: string; author?: string; ts: number }
export type HistoryRecord = {
  ts: number
  kind: 'start' | 'advance' | 'back' | 'override' | 'check'
  from: Phase | null
  to: Phase | 'done'
}

export type RunState = {
  started: boolean
  slug: string | null
  title: string | null
  phase: Phase | 'done' | null
  paused: boolean
  // Entry time of each phase, and the time a back step invalidated it.
  since: Partial<Record<Phase, number>>
  invalidated: Partial<Record<Phase, number>>
  gate: Record<Phase, GateState>
  stale: Phase[]
  loops: number
  maxLoops: number
  loopLimitReached: boolean
  checkOverridden: boolean
  overrides: OverrideRecord[]
  accepted: AcceptRecord[]
  drift: DriftRecord[]
  addedPaths: string[]
  allowOnce: string[]
  history: HistoryRecord[]
  unverified: string[]
  // The CLI is at its design stage (part of Plan in the mod), and the state of the design check there. Set by the adapter
  // from build-state.json; a fold of the events alone leaves them false and none.
  atDesign: boolean
  designGate: GateState
}

// Where only the person decides. The bar's text names its buttons; with no buttons (minimal and off modes) the person
// chooses in the `Temper gate` question. Neither names a typed command.
export const ONLY_USER = 'Only the user decides this. Next: ask the user to choose on the Temper bar, then wait.'
export const ONLY_USER_ASK = 'Only the user decides this. Next: ask the user with AskUserQuestion, header `Temper gate`, then wait.'

const FLOW: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check']

export const phaseLabel = (p: Phase | 'done'): string => (p === 'done' ? 'Done' : p.charAt(0).toUpperCase() + p.slice(1))

// Position in the forward flow; Fix sits between Check and Done.
function order(p: Phase): number {
  return p === 'fix' ? FLOW.indexOf('check') + 0.5 : FLOW.indexOf(p)
}

function nextOf(p: Phase): Phase | 'done' {
  if (p === 'fix') return 'done'
  const i = FLOW.indexOf(p)
  return FLOW[i + 1] ?? 'done'
}

function emptyGate(): Record<Phase, GateState> {
  return { intent: 'none', plan: 'none', build: 'none', review: 'none', check: 'none', fix: 'none' }
}

export function initialState(maxLoops = 3): RunState {
  return {
    started: false,
    slug: null,
    title: null,
    phase: null,
    paused: false,
    since: {},
    invalidated: {},
    gate: emptyGate(),
    stale: [],
    loops: 0,
    maxLoops,
    loopLimitReached: false,
    checkOverridden: false,
    overrides: [],
    accepted: [],
    drift: [],
    addedPaths: [],
    allowOnce: [],
    history: [],
    unverified: [],
    atDesign: false,
    designGate: 'none',
  }
}

// The check of the step the run is at: the design check at the Design gate (part of Plan in the mod), else the phase's own.
export function phaseGate(s: RunState): GateState {
  if (s.phase === null || s.phase === 'done') return 'none'
  return s.phase === 'plan' && s.atDesign ? s.designGate : s.gate[s.phase]
}

// The state of one stage's check: its verdict against the time the stage was entered or invalidated. gates.json times
// have whole second resolution and phase entry times are in milliseconds, so compare whole seconds and treat equal as fresh.
export function gateOf(v: Verdict | undefined, since: number | undefined, invalidated: number | undefined): GateState {
  const boundary = Math.max(since ?? -Infinity, invalidated ?? -Infinity)
  if (!v) return 'none'
  if (Math.floor(v.ts / 1000) < Math.floor(boundary / 1000)) return 'stale'
  return v.verdict === 'PASS' ? 'fresh' : 'fail'
}

export function reduce(events: readonly TemperEvent[], verdicts: Verdicts = {}, opts: ReduceOptions = {}): RunState {
  const s = initialState(opts.maxLoops ?? 3)
  const sorted = [...events].sort(compareEvents)

  const enter = (to: Phase | 'done', ts: number) => {
    s.phase = to
    if (to !== 'done') s.since[to] = ts
  }

  for (const ev of sorted) {
    // Every kind of event changes what is enforced (pause lifts the rules, checkResult
    // ends the run, start resets it), so an event file the mod did not write counts for
    // none of them. The adapter trusts only ids it recorded itself.
    if (opts.isTrusted && !opts.isTrusted(ev)) {
      s.unverified.push(ev.id)
      continue
    }
    switch (ev.type) {
      case 'start': {
        const keepUnverified = s.unverified
        Object.assign(s, initialState(s.maxLoops), { unverified: keepUnverified })
        s.started = true
        s.slug = ev.slug
        s.title = ev.title
        enter(ev.phase ?? 'intent', ev.ts)
        s.history.push({ ts: ev.ts, kind: 'start', from: null, to: ev.phase ?? 'intent' })
        break
      }
      case 'advance':
        if (s.phase === ev.from) {
          const failedAt = s.since.fix
          enter(ev.to, ev.ts)
          // Back from Fix to Check: the check that failed is the one this Check answers. A verdict written after
          // that failure (the orchestrator ran the check again while the run was in Fix) counts for this Check, so
          // the person is not sent through the same check run again.
          if (ev.from === 'fix' && ev.to === 'check' && failedAt !== undefined) s.since.check = failedAt
          s.history.push({ ts: ev.ts, kind: 'advance', from: ev.from, to: ev.to })
        }
        break
      case 'back':
        if (s.phase !== null && s.phase !== 'done') {
          const from = s.phase
          for (const p of FLOW) if (order(p) >= order(ev.to)) s.invalidated[p] = ev.ts
          s.loops = 0
          enter(ev.to, ev.ts)
          s.history.push({ ts: ev.ts, kind: 'back', from, to: ev.to })
        }
        break
      case 'override':
        // Keeping a task agent's commits skips no stage: the run stays where it is, and Build is not overridden.
        if (ev.stage === 'foreign-commit') break
        // A skip at the Design gate is made while the Plan approval has taken the fold to Build (the CLI is at design).
        if (s.phase === ev.phase || (ev.stage === 'design' && ev.phase === 'plan' && s.phase === 'build')) {
          s.overrides.push({ id: ev.id, phase: ev.phase, reason: ev.reason, author: ev.author, ts: ev.ts, ...(ev.stage ? { stage: ev.stage } : {}) })
          if (ev.phase === 'check' || ev.phase === 'fix') s.checkOverridden = true
          const to = nextOf(ev.phase)
          enter(to, ev.ts)
          s.history.push({ ts: ev.ts, kind: 'override', from: ev.phase, to })
        }
        break
      case 'accept':
        s.accepted.push({ id: ev.id, findingId: ev.findingId, reason: ev.reason, author: ev.author, ts: ev.ts })
        break
      case 'drift':
        s.drift.push({ id: ev.id, path: ev.path, choice: ev.choice, reason: ev.reason, author: ev.author, ts: ev.ts })
        if (ev.choice === 'add') s.addedPaths.push(ev.path)
        if (ev.choice === 'allow-once') s.allowOnce.push(ev.path)
        break
      case 'driftUsed': {
        const i = s.allowOnce.indexOf(ev.path)
        if (i >= 0) s.allowOnce.splice(i, 1)
        break
      }
      case 'checkResult':
        if (s.phase === 'check') {
          if (ev.result === 'pass') {
            enter('done', ev.ts)
            s.history.push({ ts: ev.ts, kind: 'check', from: 'check', to: 'done' })
          } else {
            s.loops += 1
            enter('fix', ev.ts)
            s.history.push({ ts: ev.ts, kind: 'check', from: 'check', to: 'fix' })
          }
        }
        break
      case 'pause':
        s.paused = true
        break
      case 'resume':
        s.paused = false
        break
      case 'restart':
        break
    }
  }

  s.loopLimitReached = s.phase === 'fix' && s.loops > s.maxLoops

  for (const p of FLOW) s.gate[p] = gateOf(verdicts[p], s.since[p], s.invalidated[p])
  s.stale = FLOW.filter(p => s.invalidated[p] !== undefined && p !== s.phase && s.gate[p] !== 'fresh')
  return s
}

// `state init` began a new run on a spec folder whose record holds an earlier one: the CLI writes the stage `started`
// only there (with the first stage next: intent, or rca for a fix run), and after the record's last start a person's advance was mirrored (its `state advance` took the CLI past
// `started`) or a check result came in. `spent` says whether a decision was used by its mirror call. The choices of
// the earlier run do not count in the new one, as `state init` clears the CLI's own ledgers.
export function earlierRun(events: readonly TemperEvent[], cliStage: string | null, cliNext: string | null, spent: (id: string) => boolean): boolean {
  if (cliStage !== 'started' || (cliNext !== 'intent' && cliNext !== 'rca')) return false
  let past = false
  for (const ev of [...events].sort(compareEvents)) {
    if (ev.type === 'start') past = false
    else if ((ev.type === 'advance' && ev.origin === 'person' && spent(ev.id)) || ev.type === 'checkResult') past = true
  }
  return past
}

// `anyOrigin`: the person turned enforcement off, so a decision is accepted from any origin (a `claude -p` run, the
// Agent SDK). Its events keep the origin they came from.
export type Command = { origin: Origin; author?: string; anyOrigin?: boolean } & (
  | { type: 'start'; slug: string; title: string; phase?: Phase }
  | { type: 'approve' }
  | { type: 'advance' }
  | { type: 'back'; to: Phase; reason: string }
  | { type: 'override'; reason: string; phase?: Phase; stage?: string }
  | { type: 'acceptFinding'; id: string; reason: string }
  | { type: 'drift'; path: string; choice: DriftChoice; reason: string }
  | { type: 'useDrift'; path: string }
  | { type: 'checkResult'; result: 'pass' | 'fail' }
  | { type: 'pause' }
  | { type: 'resume' }
  | { type: 'restart'; reason: string }
)

export type Decision = { events: Draft[] } | { error: string }

const fail = (error: string): Decision => ({ error })

// The texts below reach the person as a toast when a press is refused: plain words, the choices they can click, and no
// typed command.
function loopLimitMessage(s: RunState): string {
  return `The fix limit is reached (${s.loops} failed check runs, limit ${s.maxLoops}). Next: loop back to Plan, skip with a reason, or save for later.`
}

export function decide(state: RunState, cmd: Command): Decision {
  const who = { origin: cmd.origin, ...(cmd.author !== undefined ? { author: cmd.author } : {}) }
  const phase = state.phase
  const isPerson = cmd.origin === 'person' || cmd.anyOrigin === true

  if (cmd.type === 'start') {
    if (phase !== null && phase !== 'done') return fail('A Temper run is active. Finish it, or save it for later.')
    return { events: [{ type: 'start', slug: cmd.slug, title: cmd.title, ...(cmd.phase ? { phase: cmd.phase } : {}), ...who }] }
  }
  if (phase === null) return fail('No Temper run is active. Next: start one with /temper:temper <feature description>.')

  // Start over works at any point of a run, paused or done too: the person throws the saved run state away. It
  // changes no phase here; it lets the orchestrator's next state archive (or clear) and state init through once.
  if (cmd.type === 'restart') {
    if (!isPerson) return fail(ONLY_USER)
    if (!cmd.reason.trim()) return fail('Start over needs a reason.')
    return { events: [{ type: 'restart', reason: cmd.reason.trim(), ...who }] }
  }
  if (cmd.type === 'resume') {
    if (!isPerson) return fail(ONLY_USER)
    return { events: [{ type: 'resume', ...who }] }
  }
  // A move the person makes on a saved run takes it up again: the resume is recorded first, then the move.
  if (state.paused) {
    const takesUp = isPerson && (cmd.type === 'approve' || cmd.type === 'advance' || cmd.type === 'back' || cmd.type === 'override' || cmd.type === 'acceptFinding' || cmd.type === 'drift')
    if (!takesUp) return fail('The run is saved for later. Next: choose Resume.')
    const inner = decide({ ...state, paused: false }, cmd)
    return 'error' in inner ? inner : { events: [{ type: 'resume', ...who }, ...inner.events] }
  }
  // After the run is done, the commit gate may still FAIL (a stage it reads has no pass): the person's "Override and
  // commit" is the one decision left. It moves nothing; the guard lets the overrides of that commit through.
  if (phase === 'done') {
    if (cmd.type === 'override' && (cmd.stage === undefined || cmd.stage === 'commit')) {
      if (!isPerson) return fail(ONLY_USER)
      if (!cmd.reason.trim()) return fail('A skip needs a reason.')
      return { events: [{ type: 'override', phase: 'check', stage: 'commit', reason: cmd.reason.trim(), ...who }] }
    }
    return fail('The run is done. Next: commit it.')
  }

  // At the fix loop limit only re-plan, override and pause remain.
  if (state.loopLimitReached) {
    const legal =
      cmd.type === 'override' || cmd.type === 'pause' || (cmd.type === 'back' && cmd.to === 'plan')
    if (!legal) return fail(loopLimitMessage(state))
  }

  switch (cmd.type) {
    case 'approve':
    case 'advance': {
      const needsPerson = cmd.type === 'approve' || phase === 'intent' || phase === 'plan'
      if (needsPerson && !isPerson) return fail(ONLY_USER)
      if (phase !== 'fix') {
        const design = phase === 'plan' && state.atDesign
        const g = design ? state.designGate : state.gate[phase]
        const name = design ? 'Design' : phaseLabel(phase)
        if (g === 'stale' && state.invalidated[phase] !== undefined) {
          return fail(`${name} needs a new check. A step back made the old check invalid.`)
        }
        if (g === 'stale' || g === 'none') {
          return fail(`${name} has not passed its check yet. Next: let Claude finish ${name} and check it.`)
        }
        if (g === 'fail') return fail(`${name} did not pass its check. Next: fix the problems, loop back, or skip with a reason.`)
      }
      return { events: [{ type: 'advance', from: phase, to: phase === 'check' ? 'done' : phase === 'fix' ? 'check' : nextOf(phase), ...who }] }
    }
    case 'back': {
      if (!isPerson) return fail(ONLY_USER)
      if (!cmd.reason.trim()) return fail('A loop back needs a reason.')
      // At the Design gate the loop back to Plan redoes the plan the design was made for.
      const redoPlan = state.atDesign && phase === 'plan' && cmd.to === 'plan'
      if (cmd.to === 'fix' || !(order(cmd.to) < order(phase) || redoPlan)) {
        return fail(`A loop back goes to a step before ${phaseLabel(phase)}.`)
      }
      return { events: [{ type: 'back', to: cmd.to, reason: cmd.reason.trim(), ...who }] }
    }
    case 'override': {
      if (!isPerson) return fail(ONLY_USER)
      if (!cmd.reason.trim()) return fail('A skip needs a reason.')
      // The person keeps the commits a task agent made (a parked group of grouped Build): an override of the CLI that moves
      // no phase, only in Build.
      if (cmd.stage === 'foreign-commit') {
        if (phase !== 'build') return fail('Keeping a task agent\'s commits is a choice of Build.')
        return { events: [{ type: 'override', phase, stage: 'foreign-commit', reason: cmd.reason.trim(), ...who }] }
      }
      if (cmd.phase !== undefined && cmd.phase !== phase) return fail(`You can skip only the current step, ${phaseLabel(phase)}.`)
      // At the Design gate the skip is of the design stage: the CLI records it as `override design`.
      const atDesign = phase === 'plan' && state.atDesign ? { stage: 'design' } : {}
      return { events: [{ type: 'override', phase, reason: cmd.reason.trim(), ...atDesign, ...who }] }
    }
    case 'acceptFinding': {
      if (!isPerson) return fail(ONLY_USER)
      if (phase !== 'review' && phase !== 'fix') return fail('You can accept findings in Review or Fix.')
      if (!cmd.reason.trim()) return fail('Accept needs a reason.')
      return { events: [{ type: 'accept', findingId: cmd.id, reason: cmd.reason.trim(), ...who }] }
    }
    case 'drift': {
      if (!isPerson) return fail(ONLY_USER)
      if (phase !== 'build' && phase !== 'fix') return fail('Scope drift decisions work in Build or Fix.')
      if (cmd.choice === 'allow-once' && !cmd.reason.trim()) return fail('Allow once needs a reason.')
      return { events: [{ type: 'drift', path: cmd.path, choice: cmd.choice, reason: cmd.reason.trim(), ...who }] }
    }
    case 'useDrift':
      if (!state.allowOnce.includes(cmd.path)) return fail(`No allowance for ${cmd.path}.`)
      return { events: [{ type: 'driftUsed', path: cmd.path, ...who }] }
    case 'checkResult':
      if (phase !== 'check') return fail('Check results count only in the Check phase.')
      return { events: [{ type: 'checkResult', result: cmd.result, ...who }] }
    case 'pause':
      if (!isPerson) return fail(ONLY_USER)
      return { events: [{ type: 'pause', ...who }] }
  }
}
