import type { CommandRunResult, EngineInterface, PluginOptions, Register } from 'claude-code'

import { apply, composeText, consumeDecision, idleSnapshot, loadSnapshot, statusText, syncCheck, timelineText, writeReport } from './adapter'
import type { Io, Snapshot } from './adapter'
import { classifyBash } from './core/bash'
import { HELP, parseArgs, planCommand } from './core/commands'
import type { Parsed } from './core/commands'
import { evaluate } from './core/rules'
import type { RuleContext } from './core/rules'
import { SECTION_ID } from './core/section'

type Api = EngineInterface

// Module state. A hot reload runs register() again and session.start fires again, so
// nothing here has to outlive a reload.
let options: PluginOptions = {}
let current: Promise<Snapshot> | null = null
let root = ''
// The out of plan path a scope drift choice is waiting on (set when a write is denied).
let pendingDrift: string | null = null

// `$` is spelled only in this file, as `$.noun.method(...)` at each call site, so the
// adapter and the pure core stay free of it.
function makeIo($: Api): Io {
  return {
    read: path => $.fs.read(path).then(t => (typeof t === 'string' ? t : null)),
    list: path => $.fs.list(path),
    write: (path, text) => $.fs.write(path, text),
    storeGet: key => $.store.get(key),
    storeSet: (key, value) => $.store.set(key, value),
    version: () => $.session.version().then(v => v.version),
    setRun: async run => {
      await $.state.set({ plugin: 'temper', key: 'run' } as const, run)
    },
  }
}

// A failed load is a no-run snapshot (nothing enforced), never a thrown error.
function load($: Api): Promise<Snapshot> {
  return loadSnapshot(makeIo($), options).catch(() => idleSnapshot(options, false))
}

function ensure($: Api): Promise<Snapshot> {
  current ??= load($)
  return current
}

async function refresh($: Api): Promise<Snapshot> {
  current = load($)
  const snap = await current
  await makeIo($).setRun({ slug: snap.slug, phase: snap.state.phase, title: snap.title, summary: composeText(snap) }).catch(() => undefined)
  return snap
}

// The session's directory, to make absolute tool paths project relative: the cwd the
// session reported, else where `.` resolves.
async function rootOf($: Api): Promise<string> {
  if (root) return root
  const stat = await $.fs.stat('.', { resolve: true }).catch(() => undefined)
  return stat?.realPath ?? ''
}

// Asks the person what to do about a write outside the plan, through the engine's own
// dialog. Null when nobody can be asked (`claude -p`) or the dialog was dismissed.
async function askDrift($: Api, path: string): Promise<{ choice: 'add' | 'revert' | 'allow-once'; reason: string } | null> {
  try {
    const answer = await $.ui.ask(`Scope drift: ${path} is not in the plan. What should Temper do?`, {
      options: ['Add to plan', 'Revert', 'Allow once'],
      header: 'Scope drift',
    })
    if (answer === 'Add to plan') return { choice: 'add', reason: '' }
    if (answer === 'Revert') return { choice: 'revert', reason: '' }
    if (answer !== 'Allow once') return null
    // Allow once needs a reason: ask again while the answer is empty, then give up.
    for (let tries = 0; tries < 3; tries++) {
      const reason = (
        await $.ui.ask(`Why allow ${path} once?`, { options: ['Needed for this task', 'Temporary experiment'], header: 'Reason' })
      ).trim()
      if (reason) return { choice: 'allow-once', reason }
    }
    return null
  } catch {
    return null
  }
}

// A write outside the plan: offer the three choices and log the decision as an event.
// Returns the deny text, or null when the person let the write through.
async function resolveDrift($: Api, snap: Snapshot, path: string, fallback: string): Promise<string | null> {
  pendingDrift = path
  const choice = await askDrift($, path)
  if (choice === null) return fallback
  const io = makeIo($)
  const done = await apply(io, options, snap, { type: 'drift', path, choice: choice.choice, reason: choice.reason, origin: 'person', author: 'user' })
  current = Promise.resolve(done.snap)
  if (done.error) return `Temper: scope drift on ${path} could not be recorded. ${done.error}`
  pendingDrift = null
  if (choice.choice === 'revert') {
    // prompt.submit cannot be called from a tool.call hook (the engine says it would wait
    // on this very turn), so the instruction rides in the deny text Claude reads next.
    return `Temper: scope drift. The user chose to revert ${path}; it stays out of the plan. Next: restore ${path} to its committed state and continue inside the plan files.`
  }
  // Add to plan, or allow once: the decision now lets this write through.
  const again = evaluate(done.snap.state, ruleContext(done.snap, await rootOf($)), { tool: 'Edit', input: { file_path: path } })
  if ('deny' in again) return again.deny
  if (again.consume === 'drift' && again.driftPath) {
    current = Promise.resolve((await apply(io, options, done.snap, { type: 'useDrift', path: again.driftPath, origin: 'system' })).snap)
  }
  return null
}

function ruleContext(snap: Snapshot, rootDir: string): RuleContext {
  return { root: rootDir, specDir: snap.specDir, planFiles: snap.planFiles, humanDecisions: snap.humanDecisions }
}

// The one place this module denies. Returns the deny text, or null to pass the call on.
async function guard($: Api, tool: string, input: Record<string, unknown>): Promise<string | null> {
  let snap = await ensure($)
  if (snap.inert || snap.enforcement === 'off') return null
  const io = makeIo($)
  const command = typeof input.command === 'string' ? input.command : ''
  if (tool === 'Bash' && classifyBash(command).commits) {
    // The commit gate reads the CLI's latest verdict, so reload before deciding.
    snap = await syncCheck(io, options, await refresh($), false)
    current = Promise.resolve(snap)
  }
  const r = evaluate(snap.state, ruleContext(snap, await rootOf($)), { tool, input })
  if ('deny' in r) return r.drift ? resolveDrift($, snap, r.drift, r.deny) : r.deny
  if (r.consume === 'drift' && r.driftPath) {
    current = Promise.resolve((await apply(io, options, snap, { type: 'useDrift', path: r.driftPath, origin: 'system' })).snap)
  } else if (r.consume && r.consume !== 'drift') {
    await consumeDecision(io, snap, r.consume)
    await refresh($)
  }
  return null
}

// `/temper <reserved word>`: null means "not mine", and the prompt based command runs.
async function handleTemper($: Api, parsed: Parsed, originKind: string): Promise<CommandRunResult | null> {
  const snap = await ensure($)
  if (snap.inert) return null
  const plan = planCommand(parsed, pendingDrift)
  if (plan.kind === 'error') return { text: plan.text }

  if (plan.kind === 'local') {
    switch (plan.word) {
      case 'help':
        return { text: HELP }
      case 'status':
        return { text: statusText(await refresh($)) }
      case 'timeline':
        return { text: timelineText(await refresh($)) }
      case 'report':
        if (snap.slug === null) return { text: 'No Temper run is active, so there is no report to write.' }
        await writeReport(makeIo($), await refresh($))
        return { text: 'Wrote .temper/report.md' }
      case 'pr':
        // Claude writes the description: the prompt based command handles it.
        return null
      case 'mode':
        return { text: `Temper mode: ${snap.mode}` }
      case 'enforcement':
        return { text: `Temper enforcement: ${snap.enforcement}` }
      default:
        return { text: 'The Temper pane is not drawn in this build yet.' }
    }
  }

  // A decision: only the person's own composer creates one. The event is the record the
  // commit gate and the rules trust; Claude's part (mirroring it in the CLI, continuing
  // the phase) is the prompt based /temper, which runs next. prompt.submit is not used
  // here: the engine refuses it from inside command.run.
  const fresh = await refresh($)
  const done = await apply(makeIo($), options, fresh, { ...plan.command, origin: originKind === 'composer' ? 'person' : 'model', author: 'user' })
  current = Promise.resolve(done.snap)
  if (done.error) return { text: done.error }
  if (plan.command.type === 'pause' || plan.command.type === 'resume') {
    return { text: `Temper run ${plan.command.type === 'pause' ? 'paused: you have the wheel' : 'resumed'}.` }
  }
  return null
}

async function afterGateCheck($: Api): Promise<void> {
  const snap = await syncCheck(makeIo($), options, await refresh($), true)
  current = Promise.resolve(snap)
}

// Wiring only. Every hook fails open: an exception passes the call through, except the
// detected violation, which is the one place this module denies.
export const register: Register = (on, opts) => {
  options = opts
  current = null
  root = ''

  on('session.start', async ($, e, next) => {
    root = e.cwd
    await refresh($).catch(() => undefined)
    return next(e)
  })

  on('classic.SessionStart', async ($, e, next) => {
    if (e.cwd) root = e.cwd
    await refresh($).catch(() => undefined)
    return next(e)
  })

  // Only the reserved first words of /temper are handled here; anything else (a feature
  // description) goes on to the prompt based command unchanged.
  on('command.run', async ($, e, next) => {
    if (e.command !== 'temper' && e.command !== 'temper:temper') return next(e)
    const parsed = parseArgs(e.args)
    if (parsed === null) return next(e)
    const out = await handleTemper($, parsed, e.origin?.kind ?? '').catch(() => null)
    return out ?? next(e)
  })

  // One Temper line on a generated pull request description, while a run is on and the
  // prAttribution option is on.
  on('attribution.text', { kind: 'pr' }, async ($, e, next) => {
    const result = await next(e)
    try {
      const snap = await ensure($)
      if (snap.inert || snap.prAttribution !== 'on' || snap.slug === null) return result
      return { text: `${result.text}\n\nBuilt under Temper: gated phases with an audit trail in .temper/report.md.` }
    } catch {
      return result
    }
  })

  // Subagent calls arrive here too (e.agentId names the loop); they are held to the same
  // phase rules as the main loop.
  on('tool.call', async ($, e, next) => {
    const deny = await guard($, e.tool, { ...e }).catch(() => null)
    if (deny !== null) return { deny }
    const result = await next(e)
    const cmd = 'command' in e && typeof e.command === 'string' ? e.command : ''
    if (e.tool === 'Bash' && /\btemper["']?\s+gate\s+check\b/.test(cmd)) await afterGateCheck($).catch(() => undefined)
    return result
  })

  // One session scope section, last, rebuilt from the cached state on every request, so it
  // survives /compact by construction. Absent when the mod is inert: with no marker line
  // the skills announce that enforcement is off here.
  on('prompt.compose', async ($, e, next) => {
    const result = await next(e)
    try {
      const snap = await ensure($)
      if (snap.inert) return result
      const others = result.sections.filter(s => s.id !== SECTION_ID)
      return { sections: [...others, { id: SECTION_ID, text: composeText(snap), scope: 'session' as const }] }
    } catch {
      return result
    }
  })
}
