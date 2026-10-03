// The phase machine. Event sourced and pure: `reduce` folds the event log (plus the
// verdicts the CLI wrote) into a RunState, `decide` turns one command into drafts of
// new events or an error. Nothing here reads a file or knows how events are stored.

import { compareEvents } from './events'
import type { Draft, DriftChoice, Origin, Phase, TemperEvent } from './events'

export type Verdict = { verdict: 'PASS' | 'FAIL'; ts: number }

// The CLI's verdicts per stage (from .temper/gates.json); the mod only reads them.
export type Verdicts = Partial<Record<Phase, Verdict>>

export type GateState = 'fresh' | 'stale' | 'fail' | 'none'

export type ReduceOptions = {
  maxLoops?: number
  // Decision events failing this test are listed as unverified and not folded.
  isTrusted?: (ev: TemperEvent) => boolean
}

export type OverrideRecord = { id: string; phase: Phase; reason: string; author?: string; ts: number }
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
}

export const ONLY_USER = 'Only the user can approve this. Ask them to press 1 or run /temper:temper approve.'

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
  }
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
          enter(ev.to, ev.ts)
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
        if (s.phase === ev.phase) {
          s.overrides.push({ id: ev.id, phase: ev.phase, reason: ev.reason, author: ev.author, ts: ev.ts })
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
    }
  }

  s.loopLimitReached = s.phase === 'fix' && s.loops > s.maxLoops

  for (const p of FLOW) {
    const v = verdicts[p]
    const boundary = Math.max(s.since[p] ?? -Infinity, s.invalidated[p] ?? -Infinity)
    // gates.json times have whole second resolution and phase entry times are in
    // milliseconds, so compare whole seconds and treat equal as fresh.
    if (!v) s.gate[p] = 'none'
    else if (Math.floor(v.ts / 1000) < Math.floor(boundary / 1000)) s.gate[p] = 'stale'
    else s.gate[p] = v.verdict === 'PASS' ? 'fresh' : 'fail'
  }
  s.stale = FLOW.filter(p => s.invalidated[p] !== undefined && p !== s.phase && s.gate[p] !== 'fresh')
  return s
}

export type Command = { origin: Origin; author?: string } & (
  | { type: 'start'; slug: string; title: string; phase?: Phase }
  | { type: 'approve' }
  | { type: 'advance' }
  | { type: 'back'; to: Phase; reason: string }
  | { type: 'override'; reason: string; phase?: Phase }
  | { type: 'acceptFinding'; id: string; reason: string }
  | { type: 'drift'; path: string; choice: DriftChoice; reason: string }
  | { type: 'useDrift'; path: string }
  | { type: 'checkResult'; result: 'pass' | 'fail' }
  | { type: 'pause' }
  | { type: 'resume' }
)

export type Decision = { events: Draft[] } | { error: string }

const fail = (error: string): Decision => ({ error })

function loopLimitMessage(s: RunState): string {
  return (
    `Fix loop limit reached (${s.loops} failed Check runs, limit ${s.maxLoops}). ` +
    'Next: re-plan (/temper:temper back plan <reason>), override with a reason (/temper:temper override <reason>), ' +
    'or take over (/temper:temper pause).'
  )
}

export function decide(state: RunState, cmd: Command): Decision {
  const who = { origin: cmd.origin, ...(cmd.author !== undefined ? { author: cmd.author } : {}) }
  const phase = state.phase
  const isPerson = cmd.origin === 'person'

  if (cmd.type === 'start') {
    if (phase !== null && phase !== 'done') return fail('A Temper run is already active. Finish it or /temper:temper pause first.')
    return { events: [{ type: 'start', slug: cmd.slug, title: cmd.title, ...(cmd.phase ? { phase: cmd.phase } : {}), ...who }] }
  }
  if (phase === null) return fail('No Temper run is active. Next: start one with /temper:temper <feature description>.')

  if (cmd.type === 'resume') {
    if (!isPerson) return fail(ONLY_USER)
    return { events: [{ type: 'resume', ...who }] }
  }
  if (state.paused) return fail('The Temper run is paused. Next: /temper:temper resume.')
  if (phase === 'done') return fail('The Temper run is complete. Next: commit, or start a new run with /temper:temper <feature description>.')

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
        const g = state.gate[phase]
        const name = phaseLabel(phase)
        if (g === 'stale' && state.invalidated[phase] !== undefined) {
          return fail(`${name} needs a fresh verdict after it was invalidated`)
        }
        if (g === 'stale' || g === 'none') {
          return fail(`${name} has no PASS verdict yet. Next: run the ${phase} gate (temper gate ${phase}).`)
        }
        if (g === 'fail') return fail(`${name} verdict is FAIL. Next: fix the findings, then rerun the ${phase} gate.`)
      }
      return { events: [{ type: 'advance', from: phase, to: phase === 'check' ? 'done' : phase === 'fix' ? 'check' : nextOf(phase), ...who }] }
    }
    case 'back': {
      if (!isPerson) return fail(ONLY_USER)
      if (!cmd.reason.trim()) return fail('Going back needs a reason: /temper:temper back <phase> <reason>')
      if (cmd.to === 'fix' || !(order(cmd.to) < order(phase))) {
        return fail(`Back needs an earlier phase than ${phaseLabel(phase)}.`)
      }
      return { events: [{ type: 'back', to: cmd.to, reason: cmd.reason.trim(), ...who }] }
    }
    case 'override': {
      if (!isPerson) return fail(ONLY_USER)
      if (!cmd.reason.trim()) return fail('Override needs a reason: /temper:temper override <reason>')
      if (cmd.phase !== undefined && cmd.phase !== phase) return fail(`Override applies to the current phase, ${phaseLabel(phase)}.`)
      return { events: [{ type: 'override', phase, reason: cmd.reason.trim(), ...who }] }
    }
    case 'acceptFinding': {
      if (!isPerson) return fail(ONLY_USER)
      if (phase !== 'review' && phase !== 'fix') return fail('Findings are accepted in Review or Fix.')
      if (!cmd.reason.trim()) return fail('Accepting a finding needs a reason: /temper:temper accept <id> <reason>')
      return { events: [{ type: 'accept', findingId: cmd.id, reason: cmd.reason.trim(), ...who }] }
    }
    case 'drift': {
      if (!isPerson) return fail(ONLY_USER)
      if (phase !== 'build' && phase !== 'fix') return fail('Scope drift decisions apply in Build or Fix.')
      if (cmd.choice === 'allow-once' && !cmd.reason.trim()) return fail('Allow once needs a reason.')
      return { events: [{ type: 'drift', path: cmd.path, choice: cmd.choice, reason: cmd.reason.trim(), ...who }] }
    }
    case 'useDrift':
      if (!state.allowOnce.includes(cmd.path)) return fail(`No allowance for ${cmd.path}.`)
      return { events: [{ type: 'driftUsed', path: cmd.path, ...who }] }
    case 'checkResult':
      if (phase !== 'check') return fail('Check results only count in the Check phase.')
      return { events: [{ type: 'checkResult', result: cmd.result, ...who }] }
    case 'pause':
      if (!isPerson) return fail(ONLY_USER)
      return { events: [{ type: 'pause', ...who }] }
  }
}
