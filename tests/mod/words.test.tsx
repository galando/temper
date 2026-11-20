// WP31 (9.8.5): no text the mod draws uses a retired word. The words were retired by the plan (armed, parked, phase), or
// name what is gone or has a second name (door, Autonomous Build, Stage by stage, preflight, band, hand back); what
// replaces each is in scripts/words.json, which a plugin test cannot read, so the list is written here. A retired word
// is matched as a whole word in any letter case; inside a name (`phases.pipeline`, `run-armed`) it is no word.
// Read: HELP, the bar and the pane drawn in full mode for every view of the two fixture files, a pane with every state
// of a task and of a group, and every toast.
import { describe, expect, test } from 'claude-code/testing'

import { HELP } from '../../hooks/temper-mod/core/commands'
import { stageToast, stopToast } from '../../hooks/temper-mod/core/view'
import { VIEWS as FIRST } from '../../scripts/selftest/view-fixtures'
import { EXTRA_VIEWS } from '../../scripts/selftest/view-fixtures-2'
import { world } from './world'

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

// The bar and the pane of one view, and the toasts the world saw: each text with a retired word, as "<where>: <text>".
async function drawnWith(api: unknown, on: Parameters<typeof world>[0], v: J): Promise<string[]> {
  const w = world(on, { '.temper/view.json': JSON.stringify(v) })
  await (api as { session: { start: (s: unknown) => Promise<unknown> } }).session.start(START)
  const bar = shown(await (await mount(api, 'AbovePrompt', BAR)).drawn())
  const pane = shown(await (await mount(api, 'Pane', PANE, 'temper')).drawn())
  return [
    ...bar.filter(t => retired(t)).map(t => `bar: ${t}`),
    ...pane.filter(t => retired(t)).map(t => `pane: ${t}`),
    ...w.toasts.filter(t => retired(t)).map(t => `toast: ${t}`),
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
})
