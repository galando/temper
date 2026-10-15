// When the pane opens without /temper:temper pane: at a session start during a run (as before), when a run starts later
// in the session, and at once for the person's own /temper:temper with a run word. A pane the person closed is not
// opened for them again in that session.
import { describe, expect, test } from 'claude-code/testing'

import { runFiles } from './run-files'
import { world } from './world'

const CLI = '/home/u/.claude/plugins/temper/scripts/temper'
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
type Api = {
  session: { start: (a: unknown) => Promise<unknown> }
  command: { run: (a: unknown) => Promise<{ text?: string }> }
  tool: { call: (a: unknown) => Promise<{ deny?: string; text?: string }> }
}
// The person's own /temper:temper, from the prompt box. The mode question of a first run is already answered.
const person = (args: string) => ({ command: 'temper', args, origin: { kind: 'composer' } })
const sh = (api: Api, command: string) => api.tool.call({ tool: 'Bash', command })
const fresh = (on: Parameters<typeof world>[0], o: { placed?: boolean } = {}) => world(on, {}, { fakeCli: true, projectRoot: '/repo', store: { modeAsked: 1 }, ...o })

describe('the pane opens for a run that starts in the session', () => {
  test('a run started after the session began opens the pane when it appears, once', async ($, on) => {
    const api = $ as unknown as Api
    const w = fresh(on)
    await api.session.start(START)
    expect(w.opened).toEqual([])
    await sh(api, `${CLI} state init list-cmd`)
    expect(w.opened).toEqual(['temper'])
    await sh(api, 'ls')
    expect(w.opened).toEqual(['temper'])
  })

  test("the person's /temper:temper with a feature description opens it at once, and the run it starts does not open it again", async ($, on) => {
    const api = $ as unknown as Api
    const w = fresh(on)
    await api.session.start(START)
    await api.command.run(person('add a --log option'))
    expect(w.opened).toEqual(['temper'])
    expect(w.commandRuns.map(r => r.args)).toEqual(['add a --log option'])
    await sh(api, `${CLI} state init log-opt`)
    expect(w.opened).toEqual(['temper'])
  })

  test('a /temper:temper that is not typed by the person (the band, a plugin) opens nothing', async ($, on) => {
    const api = $ as unknown as Api
    const w = fresh(on)
    await api.session.start(START)
    await api.command.run({ command: 'temper:temper', args: '', origin: { kind: 'plugin', name: 'temper' } })
    expect(w.opened).toEqual([])
  })

  test('a pane the person closed is not opened for them again, until they open it', async ($, on) => {
    const api = $ as unknown as Api
    const w = fresh(on)
    await api.session.start(START)
    await api.command.run(person('add a --log option'))
    expect((await api.command.run(person('pane'))).text).toBe('The Temper pane is closed.')
    await sh(api, `${CLI} state init log-opt`)
    await api.command.run(person(''))
    expect(w.opened).toEqual(['temper'])
    expect((await api.command.run(person('pane'))).text).toBe('The Temper pane is open.')
    expect(w.opened).toEqual(['temper', 'temper'])
  })

  test('where the surface does not place it (a narrow terminal), the pane is closed again', async ($, on) => {
    const api = $ as unknown as Api
    const w = fresh(on, { placed: false })
    await api.session.start(START)
    await sh(api, `${CLI} state init list-cmd`)
    expect(w.opened).toEqual(['temper'])
    expect(w.closed).toEqual(['temper'])
  })

  for (const uiMode of ['minimal', 'off'] as const) {
    test(`${uiMode} mode: no pane, for a run that starts or for /temper:temper`, { options: { uiMode } }, async ($, on) => {
      const api = $ as unknown as Api
      const w = fresh(on)
      await api.session.start(START)
      await api.command.run(person('add a --log option'))
      await sh(api, `${CLI} state init log-opt`)
      expect(w.opened).toEqual([])
    })
  }

  test('a run in progress at the session start opens it there, as before, and not again', async ($, on) => {
    const api = $ as unknown as Api
    const w = world(on, runFiles({ nextStage: 'build' }), { fakeCli: true, projectRoot: '/repo', store: { modeAsked: 1 } })
    await api.session.start(START)
    expect(w.opened).toEqual(['temper'])
    await api.command.run(person(''))
    await sh(api, 'ls')
    expect(w.opened).toEqual(['temper'])
  })
})
