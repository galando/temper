// The hooks module as the plugin loads it. It imports every file of the mod, so the type check
// (tsconfig.mod.json includes this folder) reaches them all through the import below.
import { describe, expect, test } from 'claude-code/testing'

import { register } from '../../hooks/temper-mod/register'

type On = Parameters<typeof register>[0]
type Options = Parameters<typeof register>[1]

describe('the hooks module', () => {
  test('exports one register function that takes the hook table and the options', () => {
    expect(typeof register).toBe('function')
    expect(register.length).toBe(2)
  })

  test('register adds exactly the hooks the README lists, and nothing else', () => {
    const events = new Set<string>()
    const on = ((event: string) => {
      events.add(event)
    }) as unknown as On
    register(on, {} as Options)
    expect([...events].sort()).toEqual(
      [
        'attribution.text',
        'classic.SessionStart',
        'command.run',
        'prompt.compose',
        'session.start',
        'tool.call',
        'turn.complete',
        'turn.step',
        'ui.close',
        'ui.message',
        'ui.render',
      ].sort(),
    )
  })
})
