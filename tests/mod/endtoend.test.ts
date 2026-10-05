// A scripted run from the seeded Plan to Done, against a fake CLI that applies the mirror commands
// with the real stage sequence, through the real guard and the real adapter (no human decision is
// handed to the guard by the test: the mod finds it in its own event files). Between steps, chaos:
// reload, restart, /clear, a deleted events folder, a duplicate press, a stale press, a refused mirror.
//
// The rules the test keeps:
//  - the bar follows the CLI: after every step the CLI next_stage and the phase of the bar agree;
//  - the phase never goes back except by a person `back` that was mirrored to the CLI;
//  - a deny never blocks a write that the CLI phase allows;
//  - when they cannot agree, the bar says so in one line and the mod fails open.
import { describe, expect, test } from 'claude-code/testing'

import { LATER, SPEC, runFiles } from './run-files'
import { world } from './world'
import type { World } from './world'

const START = { cwd: '/repo', surface: null, isInteractive: false } as const
const BAND = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
type Mounted = { press: (a: { key: string }) => Promise<void>; find: (a: { key: string }) => Promise<unknown>; drawn: () => Promise<unknown> }
type Api = {
  ui: { mount: (a: unknown) => Promise<Mounted> }
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string; isError?: boolean; text?: string }> }
}

const PHASE_OF_STAGE: Record<string, string> = { intent: 'Intent', plan: 'Plan', design: 'Plan', build: 'Build', review: 'Review', check: 'Check', commit: 'Done' }

export class Run {
  constructor(
    readonly $: Api,
    readonly w: World,
  ) {}

  cliNext = (): string => (JSON.parse(this.w.files.get('.temper/build-state.json') ?? '{}') as { next_stage?: string }).next_stage ?? ''
  cliStage = (): string => (JSON.parse(this.w.files.get('.temper/build-state.json') ?? '{}') as { stage?: string }).stage ?? ''

  // A gate verdict the CLI would write, then a refresh the way a turn end does it.
  async gate(stage: string, verdict: 'PASS' | 'FAIL' = 'PASS'): Promise<void> {
    const gates = JSON.parse(this.w.files.get('.temper/gates.json') ?? '{}') as Record<string, unknown>
    gates[stage] = { verdict, ts: LATER }
    this.w.files.set('.temper/gates.json', JSON.stringify(gates))
    await this.refresh()
  }
  async tasks(done: number, of = 2): Promise<void> {
    this.w.files.set(`${SPEC}/tasks.md`, Array.from({ length: of }, (_, i) => `### Task ${i + 1}: t\n- [${i < done ? 'x' : ' '}] x`).join('\n') + '\n')
    await this.refresh()
  }
  async refresh(): Promise<void> {
    await this.$.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })
  }
  async band(): Promise<Mounted> {
    return this.$.ui.mount({ plugin: 'temper', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  }
  async barText(): Promise<string> {
    return JSON.stringify(await (await this.band()).drawn())
  }
  // Presses the button with this key and returns what the mod submitted for Claude.
  async press(id: string): Promise<string[]> {
    const before = this.w.prompts.length
    await (await this.band()).press({ key: `action-${id}` })
    return this.w.prompts.slice(before)
  }
  private seenRuns = 0
  // The orchestrator did not run (the hand over was lost): its commands are never issued.
  skipRuns(): void {
    this.seenRuns = this.w.commandRuns.length
  }
  // The orchestrator and Claude do what the mod handed over, as the model: through the guard.
  //  - `/temper:temper continue <stage>`: the orchestrator's On Continue steps run `state advance` for
  //    the stage (and for design after plan in a medium or complex run);
  //  - a mirror prompt (back, override, accept) names the CLI command to run.
  async mirror(prompts: string[], complexity: 'simple' | 'complex' = 'simple'): Promise<Array<{ cmd: string; deny?: string }>> {
    const out: Array<{ cmd: string; deny?: string }> = []
    const runs = this.w.commandRuns.slice(this.seenRuns)
    this.seenRuns = this.w.commandRuns.length
    for (const run of runs) {
      const m = /^continue (\w+)$/.exec(run.args)
      if (!m) continue
      const stage = m[1] ?? ''
      const NEXT: Record<string, string> = { intent: 'plan', plan: complexity === 'complex' ? 'design' : 'build', design: 'build', build: 'review', review: 'check', check: 'commit' }
      const steps = stage === 'plan' && complexity === 'complex' ? [['plan', 'design'], ['design', 'build']] : [[stage, NEXT[stage] ?? '']]
      for (const [from, to] of steps) {
        const cmd = `/Users/x/plugin/scripts/temper state advance ${from}_complete ${to}`
        const r = await this.$.tool.call({ tool: 'Bash', command: cmd })
        out.push({ cmd, ...(r.deny ? { deny: r.deny } : {}) })
      }
    }
    for (const p of prompts) {
      for (const m of p.matchAll(/`([^`]*scripts\/temper (?:state advance|state set next_stage|override|evidence accept)[^`]*)`/g)) {
        const cmd = m[1] ?? ''
        const r = await this.$.tool.call({ tool: 'Bash', command: cmd })
        out.push({ cmd, ...(r.deny ? { deny: r.deny } : {}) })
      }
    }
    return out
  }
  events = (): Array<Record<string, unknown>> =>
    [...this.w.files.entries()].filter(([p]) => p.startsWith(`${SPEC}/events/`)).map(([, t]) => JSON.parse(t) as Record<string, unknown>)
  async write(path: string): Promise<string | undefined> {
    const r = await this.$.tool.call({ tool: 'Write', file_path: path, content: 'x' })
    return r.deny
  }
}

const start = async ($: Api, on: Parameters<typeof world>[0], gates: Record<string, 'PASS' | 'FAIL'> = { intent: 'PASS', plan: 'PASS' }): Promise<Run> => {
  const w = world(on, runFiles({ nextStage: 'plan', gates }), { fakeCli: true, projectRoot: '/repo' })
  // The seeded demo: the CLI is at intent_complete and the run waits at Plan, on main; the run has its own branch.
  w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'intent_complete', spec: 'pw', spec_path: SPEC, next_stage: 'plan', command: 'temper', branch: 'feature/pw' }))
  w.files.set('/repo/.git/HEAD', 'ref: refs/heads/main\n')
  await $.session.start(START)
  return new Run($, w)
}

describe('the bar and the CLI move together through a full run', () => {
  test('Plan, Build task 1, Build task 2, Review, Check, Done', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    await r.tasks(0)
    // Plan -> Build
    let out = await r.mirror(await r.press('continue'))
    expect(out.map(o => o.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('build')
    // Build task 1 and 2 are launches: no decision, the CLI does not move.
    await r.press('run-stage')
    await r.tasks(1)
    await r.press('run-stage')
    await r.tasks(2)
    await r.gate('build')
    expect(r.cliNext()).toBe('build')
    // Build -> Review: the person's event is found by the guard, the mirror runs, the CLI follows.
    // (A second move within one second of the first is dropped on purpose; the test option turns that off.)
    out = await r.mirror(await r.press('continue'))
    expect(out, JSON.stringify(out)).toEqual([{ cmd: expect.stringContaining('state advance build_complete review') }])
    expect(r.cliNext()).toBe('review')
    // Review -> Check
    await r.gate('review')
    out = await r.mirror(await r.press('continue'))
    expect(out.map(o => o.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('check')
    // Check -> Done: the check passes, the CLI is moved on to commit
    await r.gate('check')
    out = await r.mirror(await r.press('continue'))
    expect(out.map(o => o.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('commit')
    expect(PHASE_OF_STAGE[r.cliNext()]).toBe('Done')
  })
})

// ---- chaos -------------------------------------------------------------------------------------------

// The step the bar shows, as a number (Done is 7), read from what is drawn.
const barStep = async (r: Run): Promise<number> => {
  const m = /Step (\d) of 6/.exec(await r.barText())
  return m ? Number(m[1]) : 7
}
const STEP_OF_NEXT: Record<string, number> = { intent: 1, plan: 2, design: 2, build: 3, review: 4, check: 5, commit: 7 }

// A source file in the plan: the phase rules allow it in Build and Done only.
const ALLOWED_AT: Record<number, boolean> = { 1: false, 2: false, 3: true, 4: false, 5: false, 7: true }

type Chaos = { name: string; run: (r: Run, $: Api) => Promise<void> }
const CHAOS: Chaos[] = [
  { name: 'nothing', run: async () => undefined },
  { name: 'session restart', run: async (_r, $) => void (await $.session.start(START)) },
  { name: '/clear (classic SessionStart)', run: async (_r, $) => void (await ($ as unknown as { classic: { SessionStart: (a: unknown) => Promise<unknown> } }).classic.SessionStart({ source: 'clear' })) },
  { name: 'the events folder deleted', run: async r => void [...r.w.files.keys()].filter(p => p.includes('/events/')).forEach(p => r.w.files.delete(p)) },
  { name: 'a corrupted event file', run: async r => void [...r.w.files.keys()].filter(p => p.includes('/events/')).forEach(p => r.w.files.set(p, '{not json')) },
  { name: 'a stale button', run: async r => void (await r.band()) },
  {
    name: 'a cd into the plugin folder and a hot reload there',
    run: async (r, $) => {
      r.w.cwdNow = '/plugin'
      await $.session.start({ cwd: '/plugin', surface: null, isInteractive: false })
    },
  },
]

const FULL = async (r: Run, $: Api, between: Chaos): Promise<string[]> => {
  const log: string[] = []
  // After every step: the bar and the CLI agree, the phase never goes back, no deny blocks what the phase allows.
  let last = 0
  const check = async (where: string) => {
    await between.run(r, $)
    await r.refresh()
    const step = await barStep(r)
    const want = STEP_OF_NEXT[r.cliNext()] ?? -1
    log.push(`${where}: bar ${step}, CLI ${r.cliNext()}`)
    expect(step, `${where} after ${between.name}: the bar shows step ${step} but the CLI is at ${r.cliNext()}`).toBe(want)
    expect(step, `${where}: the phase went back`).toBeGreaterThanOrEqual(last)
    last = step
    const deny = await r.write('src/app.ts')
    expect(deny === undefined, `${where}: a write in the plan is ${deny === undefined ? 'allowed' : 'denied'} at step ${step}`).toBe(ALLOWED_AT[step] ?? true)
  }
  await check('start')
  let out = await r.mirror(await r.press('continue'))
  expect(out.map(o => o.deny)).toEqual([undefined])
  await check('plan to build')
  // The On Continue steps of the original Plan gate: the feature branch, then the commit of the approved
  // plan artifacts in two calls. The commit gate lets an artifact only commit through.
  const git = async (cmd: string) => (await r.$.tool.call({ tool: 'Bash', command: cmd })).deny
  expect(await git('git checkout -b feature/pw')).toBeUndefined()
  expect(await git(`git add ${SPEC}/`)).toBeUndefined()
  expect(await git('git commit -m "docs(plan): approve plan - pw"'), 'the plan artifact commit').toBeUndefined()
  await r.press('run-stage')
  await r.tasks(1)
  await check('task 1')
  // A Build checkpoint commit: on the run's branch with a green test run it lands; on main it does not.
  r.w.files.set('.temper/evidence/build.json', JSON.stringify([{ claim: 'unit tests', exit_code: 0, phase: 'green' }]))
  expect(await git('git add src/app.ts')).toBeUndefined()
  expect(await git('git commit -m "feat(pw): scenario 1 [AC-01]"'), 'the Build checkpoint commit').toBeUndefined()
  r.w.files.set('/repo/.git/HEAD', 'ref: refs/heads/main\n')
  expect(await git('git add src/app.ts')).toBeUndefined()
  expect(await git('git commit -m "feat(pw): wrong branch"')).toContain('feature/pw')
  r.w.files.set('/repo/.git/HEAD', 'ref: refs/heads/feature/pw\n')
  await r.press('run-stage')
  await r.tasks(2)
  await r.gate('build')
  await check('task 2')
  out = await r.mirror(await r.press('continue'))
  expect(out.map(o => o.deny)).toEqual([undefined])
  await check('build to review')
  await r.gate('review')
  out = await r.mirror(await r.press('continue'))
  expect(out.map(o => o.deny)).toEqual([undefined])
  await check('review to check')
  await r.gate('check')
  out = await r.mirror(await r.press('continue'))
  expect(out.map(o => o.deny)).toEqual([undefined])
  await check('check to done')
  return log
}

describe('chaos between every step: the bar follows the CLI, never goes back, never blocks what the CLI phase allows', () => {
  for (const chaos of CHAOS) {
    test(chaos.name, { options: { moveCooldownMs: 0 } }, async ($, on) => {
      const r = await start($ as unknown as Api, on)
      await r.tasks(0)
      await FULL(r, $ as unknown as Api, chaos)
    })
  }

  test('a duplicate press at once records one move, one mirror and one launch', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    const ui = await r.band()
    await Promise.all([ui.press({ key: 'action-continue' }), ui.press({ key: 'action-continue' })])
    expect(r.events().filter(e => e.type === 'advance')).toHaveLength(1)
    // One hand over to the orchestrator (no mirror prompt of the mod), one launch.
    expect(r.w.prompts).toHaveLength(0)
    expect(r.w.commandRuns).toHaveLength(1)
  })
})

describe('the project root is remembered: a later session folder never replaces it', () => {
  const rooted = async ($: Api, on: Parameters<typeof world>[0]): Promise<Run> => {
    const w = world(on, runFiles({ nextStage: 'plan', gates: { plan: 'PASS' } }), { fakeCli: true, projectRoot: '/repo' })
    w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'intent_complete', spec: 'pw', spec_path: SPEC, next_stage: 'plan' }))
    await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
    return new Run($, w)
  }

  test('Claude cd into another folder, then a hot reload starts the session there', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await rooted($ as unknown as Api, on)
    await r.tasks(0)
    expect(await barStep(r)).toBe(2)
    // The engine session is in the plugin folder now, and the reload reports that folder.
    r.w.cwdNow = '/plugin'
    await r.$.session.start({ cwd: '/plugin', surface: null, isInteractive: false })
    await r.refresh()
    expect(await barStep(r)).toBe(2)
    // Every file the mod reads and writes is under the project, not the folder the shell is in.
    expect(r.w.rawPaths.filter(p => p.startsWith('/plugin') || !p.startsWith('/')).slice(-5)).toEqual([])
    // A decision still works, and the mirror moves the CLI of the project.
    const out = await r.mirror(await r.press('continue'))
    expect(out.map(o => o.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('build')
    expect(r.events().filter(e => e.type === 'advance')).toHaveLength(1)
  })

  test('Claude cd into another repo with its own .temper: the mod still follows the original project', async ($, on) => {
    const r = await rooted($ as unknown as Api, on)
    r.w.cwdNow = '/other'
    await r.$.session.start({ cwd: '/other', surface: null, isInteractive: false })
    await r.refresh()
    expect(await barStep(r)).toBe(2)
    expect(await r.write('src/app.ts')).toContain('Plan phase')
  })

  test('a reload with the classic SessionStart in another folder changes nothing either', async ($, on) => {
    const r = await rooted($ as unknown as Api, on)
    r.w.cwdNow = '/elsewhere'
    await (r.$ as unknown as { classic: { SessionStart: (a: unknown) => Promise<unknown> } }).classic.SessionStart({ source: 'resume', cwd: '/elsewhere' })
    await r.refresh()
    expect(await barStep(r)).toBe(2)
  })
})

describe('a mirror the CLI refuses once: the choice stays pending and key 1 records it again', () => {
  test('the decision is not spent, the bar says so, the second try moves the CLI', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    await r.tasks(0)
    r.w.cliFailures = 1
    const prompts = await r.press('continue')
    const first = await r.mirror(prompts)
    // The guard let the call through (the person decided); the CLI refused it.
    expect(first.map(f => f.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('plan')
    await r.refresh()
    // The bar stays at Plan, says why in one line, and offers to record the choice again.
    const bar = await r.barText()
    expect(bar).toContain('Step 2 of 6')
    expect(bar).toContain('Temper state: the run is at Plan. Your last choice is not recorded yet. Press 1 to record it.')
    expect(bar).toContain('Record my choice')
    const events = r.events().filter(e => e.type === 'advance')
    expect(events).toHaveLength(1)
    // Key 1 submits the mirror prompt again for the SAME decision: no new event.
    const again = await r.mirror(await r.press('record'))
    expect(again.map(f => f.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('build')
    expect(r.events().filter(e => e.type === 'advance')).toHaveLength(1)
    await r.refresh()
    expect(await r.barText()).not.toContain('not recorded yet')
    // The decision is single use: a third call is refused.
    const third = await r.$.tool.call({ tool: 'Bash', command: 'scripts/temper state advance plan_complete build' })
    expect(third.deny).toContain('Only the user')
  })

  test('a call that took the decision and never ran gives it back when key 1 records it again', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    await r.press('continue')
    expect(r.w.commandRuns).toHaveLength(1)
    // The orchestrator never ran its `state advance` (nothing ran).
    r.skipRuns()
    // The bar offers to record again, and the second hand over is allowed.
    await r.refresh()
    expect(await r.barText()).toContain('Record my choice')
    const out = await r.mirror(await r.press('record'))
    expect(out.map(o => o.deny)).toEqual([undefined])
    expect(r.cliNext()).toBe('build')
  })
})

describe('the CLI moved ahead of the events: the bar follows it and writes nothing', () => {
  test('the orchestrator advanced the CLI by a passed check', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    const before = r.events().length
    r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'build_complete', spec: 'pw', spec_path: SPEC, next_stage: 'review' }))
    await r.refresh()
    expect(await barStep(r)).toBe(4)
    expect(await r.barText()).not.toContain('not recorded yet')
    expect(r.events().length).toBe(before)
  })
})

describe('fail safe: when the mod cannot tell where the run is it blocks nothing and writes nothing', () => {
  const unsure: Array<[string, (r: Run) => void]> = [
    ['a build-state with another stage name', r => void r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'x', spec: 'pw', spec_path: SPEC, next_stage: 'banana' }))],
    ['a build-state with no next_stage', r => void r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'x', spec: 'pw', spec_path: SPEC }))],
  ]
  // A file that turns unreadable, corrupt or missing during a run does not end the run (hardening round, finding 2):
  // the last known state keeps applying, so hiding the file is not a way to switch the guard off.
  const held: Array<[string, (r: Run) => void]> = [
    ['an unreadable build-state', r => void r.w.files.set('.temper/build-state.json', '{ nope')],
    ['a deleted build-state', r => void r.w.files.delete('.temper/build-state.json')],
  ]
  for (const [name, break_] of held) {
    test(`${name}: the last known state keeps applying`, async ($, on) => {
      const r = await start($ as unknown as Api, on)
      const before = r.events().map(e => e.id)
      break_(r)
      await r.refresh()
      expect(await r.write('src/app.ts')).toContain('Plan phase')
      expect((await r.$.tool.call({ tool: 'Bash', command: 'git commit -m x' })).deny).toContain('commit blocked')
      expect((await r.$.tool.call({ tool: 'Bash', command: 'scripts/temper gate plan' })).deny).toBeUndefined()
      expect(r.events().map(e => e.id)).toEqual(before)
      expect(await r.barText()).toContain('missing or unreadable')
    })
  }
  for (const [name, break_] of unsure) {
    test(name, async ($, on) => {
      const r = await start($ as unknown as Api, on)
      const before = r.events().map(e => e.id)
      break_(r)
      await r.refresh()
      // No block: a source write, a commit, a decision call all pass.
      expect(await r.write('src/app.ts')).toBeUndefined()
      expect((await r.$.tool.call({ tool: 'Bash', command: 'git commit -m x' })).deny).toBeUndefined()
      expect((await r.$.tool.call({ tool: 'Bash', command: 'scripts/temper gate plan' })).deny).toBeUndefined()
      // No event is written.
      expect(r.events().map(e => e.id)).toEqual(before)
    })
  }

  test('an unknown next_stage says so in one line', async ($, on) => {
    const r = await start($ as unknown as Api, on)
    r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'x', spec: 'pw', spec_path: SPEC, next_stage: 'banana' }))
    await r.refresh()
    expect(await r.barText()).toContain('the mod cannot tell where the run is')
  })
})

describe('the CLI looks reset while later checks passed: no work is blocked, one line says so', () => {
  test('next_stage intent with a fresh build PASS', async ($, on) => {
    const r = await start($ as unknown as Api, on, { plan: 'PASS', build: 'PASS' })
    r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'intent' }))
    await r.refresh()
    expect(await r.barText()).toContain('Temper state looks reset')
    // The phase rules do not block a source write; a protected path stays protected.
    expect(await r.write('src/app.ts')).toBeUndefined()
    expect(await r.write('.temper/gates.json')).toContain('Temper')
    // The CLI phase is still what is shown and what denies use for the decision calls.
    expect(await barStep(r)).toBe(1)
  })

  test('a reset that clears the gate ledger too (state init): the choices went further, nothing is pending', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on)
    await r.tasks(0)
    await r.mirror(await r.press('continue'))
    expect(r.cliNext()).toBe('build')
    // `state init` from a shell: the CLI is at intent, the ledger is empty.
    r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'intent' }))
    r.w.files.set('.temper/gates.json', '[]')
    const events = r.events().map(e => e.id)
    await r.refresh()
    expect(await barStep(r)).toBe(1)
    expect(await r.barText()).toContain('Temper state looks reset')
    // Nothing is blocked, nothing is written.
    expect(await r.write('src/app.ts')).toBeUndefined()
    expect(r.events().map(e => e.id)).toEqual(events)
  })

  test('a skip that the orchestrator has not advanced past yet is not a reset', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on, { plan: 'PASS' })
    await r.tasks(0)
    await r.mirror(await r.press('continue'))
    await r.gate('build', 'FAIL')
    await $.command.run({ command: 'temper:temper', args: 'override reviewer is on leave', origin: { kind: 'composer' } } as never)
    await r.mirror(['`' + '/x/scripts/temper override build --reason x' + '`'])
    await r.refresh()
    expect(await r.barText()).not.toContain('looks reset')
  })

  test('a person back to Plan is not a reset: the later checks are stale', { options: { moveCooldownMs: 0 } }, async ($, on) => {
    const r = await start($ as unknown as Api, on, { plan: 'PASS', build: 'PASS' })
    await r.tasks(0)
    await r.mirror(await r.press('continue'))
    expect(r.cliNext()).toBe('build')
    // The build check passed long before the person went back (its verdict is older than the step back).
    r.w.files.set('.temper/gates.json', JSON.stringify({ plan: { verdict: 'PASS', ts: '2999-01-01T00:00:00Z' }, build: { verdict: 'PASS', ts: '2020-01-01T00:00:00Z' } }))
    // The person goes back to Plan; the mirror call moves the CLI there.
    await $.command.run({ command: 'temper:temper', args: 'back plan rework', origin: { kind: 'composer' } } as never)
    expect(r.events().some(e => e.type === 'back')).toBe(true)
    r.w.files.set('.temper/build-state.json', JSON.stringify({ stage: 'started', spec: 'pw', spec_path: SPEC, next_stage: 'plan' }))
    await r.refresh()
    expect(await barStep(r)).toBe(2)
    expect(await r.barText()).not.toContain('looks reset')
  })
})
