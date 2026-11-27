// WP31 (9.8.5): no text the mod draws uses a retired word. The words were retired by the plan (armed, parked, phase), or
// name what is gone or has a second name (door, Autonomous Build, Stage by stage, preflight, band, hand back); what
// replaces each is in scripts/words.json, which a plugin test cannot read, so the list is written here. A retired word
// is matched as a whole word in any letter case; inside a name (`phases.pipeline`, `run-armed`) it is no word.
// Read: HELP, the bar and the pane drawn in full mode for every view of the two fixture files, a pane with every state
// of a task and of a group, the Build lines of a stopped group, and every toast; and the text the mod gives Claude and
// answers the word status with (P8, R8-W31-1: it said Phase and "the run is armed"), for every fixture view and for a
// /temper:fix run. Case file 75 holds this list to the retired list of scripts/words.json.
import { describe, expect, test } from 'claude-code/testing'

import { HELP } from '../../hooks/temper-mod/core/commands'
import { groupLine, stageToast, stopToast } from '../../hooks/temper-mod/core/view'
import { VIEWS as FIRST } from '../../scripts/selftest/view-fixtures'
import { EXTRA_VIEWS } from '../../scripts/selftest/view-fixtures-2'
import { runFiles } from './run-files'
import { COMPOSE, world } from './world'

const RETIRED = ['armed', 'arm', 'arms', 'arming', 'parked', 'park', 'parks', 'phase', 'phases', 'door', 'doors',
  'Autonomous Build', 'Stage by stage', 'preflight', 'band', 'hand back']
const esc = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/ /g, '\\s+')
const WORD = new RegExp(`(?<![\\w./-])(?:${RETIRED.map(esc).join('|')})(?![\\w/-]|\\.\\w)`, 'i')

// The retired words a text holds ('' for none), with code spans and dotted key names left out.
function retired(text: string): string {
  const plain = text.replace(/`[^`\n]*`/g, ' ')
  const hits: string[] = []
  const all = new RegExp(WORD.source, 'gi')
  for (let m = all.exec(plain); m; m = all.exec(plain)) hits.push(m[0])
  return hits.join(', ')
}

// Every string a drawn tree shows: the children of its nodes, never a prop (a key such as `temper-band` is not shown).
type Node = { type?: string; props?: Record<string, unknown>; children?: unknown }
function shown(tree: unknown, out: string[] = []): string[] {
  if (typeof tree === 'string') out.push(tree)
  else if (typeof tree === 'number') out.push(String(tree))
  else if (Array.isArray(tree)) for (const k of tree) shown(k, out)
  else if (typeof tree === 'object' && tree !== null) shown((tree as Node).children, out)
  return out
}

type J = Record<string, unknown>
const ALL: Record<string, unknown> = { ...FIRST, ...EXTRA_VIEWS }
const copy = (name: string): J => JSON.parse(JSON.stringify(ALL[name])) as J
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const BAR = { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 120, scroll: { offset: 0, bodyRows: 12 }, view: {} } as const
const PANE = { title: 'Temper', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
type Mounted = { drawn: () => Promise<unknown> }
type Ui = { ui: { mount: (a: unknown) => Promise<Mounted> } }
const mount = (api: unknown, component: 'AbovePrompt' | 'Pane', props: unknown, requestId?: string): Promise<Mounted> =>
  (api as Ui).ui.mount({ plugin: 'temper', surface: 'terminal', component, props, ...(requestId ? { requestId } : {}) })

type Talk = {
  prompt: { compose: (a: unknown) => Promise<{ sections: Array<{ id: string; text: string }> }> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
}
// What the mod tells Claude (its system prompt section) and its answer to the word status: each with a retired word.
async function toldWith(api: unknown): Promise<string[]> {
  const t = api as Talk
  const section = (await t.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? ''
  const status = (await t.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })).text ?? ''
  return [section ? `section: ${section}` : 'no section', `status: ${status}`].filter(x => x === 'no section' || retired(x.replace(/^\w+: /, '')))
}

// The bar and the pane of one view, the toasts the world saw, the section and the status answer: each text with a
// retired word, as "<where>: <text>". `lines` gets every text the bar and the pane show.
async function drawnWith(api: unknown, on: Parameters<typeof world>[0], v: J, lines: string[] = []): Promise<string[]> {
  const w = world(on, { '.temper/view.json': JSON.stringify(v) })
  await (api as { session: { start: (s: unknown) => Promise<unknown> } }).session.start(START)
  const bar = shown(await (await mount(api, 'AbovePrompt', BAR)).drawn())
  const pane = shown(await (await mount(api, 'Pane', PANE, 'temper')).drawn())
  lines.push(...bar, ...pane)
  return [
    ...bar.filter(t => retired(t)).map(t => `bar: ${t}`),
    ...pane.filter(t => retired(t)).map(t => `pane: ${t}`),
    ...w.toasts.filter(t => retired(t)).map(t => `toast: ${t}`),
    ...(await toldWith(api)),
  ]
}

describe('w31 the mod draws no retired word', () => {
  test('the list matches whole words only', () => {
    expect(retired('The armed run parks before the commit')).toBe('armed, parks')
    expect(retired('a sparkline, an alarm, phaseModels, `phases.pipeline`, park-on-touch, run-armed, bandwidth')).toBe('')
    expect(retired('Pick Autonomous  Build or hand back; the Phase bar')).toBe('Autonomous  Build, hand back, Phase')
  })

  test('HELP holds no retired word', () => {
    expect(retired(HELP)).toBe('')
  })

  test('no toast holds a retired word', () => {
    const stages = ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit', 'pipeline'] as const
    const texts = [...stages.map(s => stageToast(s) ?? ''), ...stages.map(s => stopToast(s)), stopToast('a stage of its own')]
    expect(texts.filter(t => retired(t))).toEqual([])
  })

  for (const name of Object.keys(ALL)) {
    test(`the bar and the pane of the fixture view ${name}`, async ($, on) => {
      expect(await drawnWith($, on, copy(name))).toEqual([])
    })
  }

  test('the pane with every state of a task and of a group', async ($, on) => {
    const v = copy('check-fail')
    const groups = (v.build as { groups: Array<{ status: string; tasks: J[] }> }).groups
    const states = ['waiting', 'running', 'red', 'green', 'covered', 'pass', 'fail', 'parked']
    const first = groups[0] as { status: string; tasks: J[] }
    const t0 = first.tasks[0] as J
    first.tasks = states.map((state, i) => ({ ...t0, n: i + 1, title: `task ${i + 1}`, state, attempts: 1 }))
    first.status = 'parked'
    expect(await drawnWith($, on, v)).toEqual([])
  })

  // P8 (R8-W31-2): the Build lines of the bar and the pane for a stopped group, so a return of "(parked)" fails here.
  test('the Build lines of a stopped group, with every state of a task', async ($, on) => {
    const states = ['waiting', 'running', 'passed', 'failed', 'parked'] as const
    const row = { id: 'G1', title: 'Payments', state: 'parked' as const, tasks: states.map((state, i) => ({ n: i + 1, title: `task ${i + 1}`, state, model: null, attempt: 1 })) }
    expect(groupLine(row)).toContain('(stopped)')
    expect(retired(groupLine(row))).toBe('')
    const v = copy('build-fail')
    const groups = (v.build as { groups: Array<{ status: string; tasks: J[] }> }).groups
    const first = groups[0] as { status: string; tasks: J[] }
    const t0 = first.tasks[0] as J
    first.tasks = ['waiting', 'running', 'red', 'green', 'covered', 'pass', 'fail', 'parked'].map((state, i) => ({ ...t0, n: i + 1, title: `task ${i + 1}`, state, attempts: 1 }))
    first.status = 'parked'
    const lines: string[] = []
    expect(await drawnWith($, on, v, lines)).toEqual([])
    // The bar draws the group's line (groupLine), and the pane its own row: both say stopped.
    expect(lines.filter(l => /^G1\b.*\(stopped\)/.test(l)).length).toBeGreaterThanOrEqual(1)
  })

  // P8 (R8-W31-1): the status answer of a /temper run says Stage, as the section does.
  test('the status answer of a /temper run', async ($, on) => {
    world(on, runFiles({ nextStage: 'build' }))
    await ($ as unknown as { session: { start: (s: unknown) => Promise<unknown> } }).session.start(START)
    const t = $ as unknown as Talk
    expect((await t.command.run({ command: 'temper:temper', args: 'status', origin: { kind: 'composer' } })).text ?? '').toContain('Stage: Build')
    expect(await toldWith($)).toEqual([])
  })

  // P8 (R8-W31-1): a /temper:fix run, where the mod stands aside: its section and its status answer.
  test('the section and the status answer of a /temper:fix run', async ($, on) => {
    const files = runFiles({ nextStage: 'fix' })
    const bs = JSON.parse(files['.temper/build-state.json']!) as J
    files['.temper/build-state.json'] = JSON.stringify({ ...bs, command: 'fix', next_stage: 'fix' })
    world(on, files)
    await ($ as unknown as { session: { start: (s: unknown) => Promise<unknown> } }).session.start(START)
    const t = $ as unknown as Talk
    expect((await t.prompt.compose(COMPOSE)).sections.at(-1)?.text ?? '').toContain('a /temper:fix run')
    expect(await toldWith($)).toEqual([])
  })
})
