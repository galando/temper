import { describe, expect, test } from 'claude-code/testing'

import { barStyle, visible } from '../../hooks/temper-mod/core/modes'
import type { Element } from '../../hooks/temper-mod/core/modes'

const ALL: Element[] = ['denials', 'stages', 'details', 'goOn', 'pane', 'toasts', 'hint', 'spinner', 'turnLine', 'questionHeader', 'subcommands']
const shown = (mode: Parameters<typeof visible>[0]) => ALL.filter(e => visible(mode, e))

// ADR 0012: the mode sets only how much is drawn; the person decides in the Temper gate question in every mode.
describe('interaction mode matrix', () => {
  test('full shows everything', () => {
    expect(shown('full')).toEqual(ALL)
    expect(barStyle('full')).toBe('full')
  })

  test('minimal shows denials, the stage timeline, and subcommands', () => {
    expect(shown('minimal')).toEqual(['denials', 'stages', 'subcommands'])
    expect(barStyle('minimal')).toBe('stages')
  })

  test('off draws nothing but keeps denials and subcommands', () => {
    expect(shown('off')).toEqual(['denials', 'subcommands'])
    expect(barStyle('off')).toBe('none')
  })
})
