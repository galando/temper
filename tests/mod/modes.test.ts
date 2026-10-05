import { describe, expect, test } from 'claude-code/testing'

import { phaseBarStyle, visible } from '../../hooks/temper-mod/core/modes'
import type { Element } from '../../hooks/temper-mod/core/modes'

const ALL: Element[] = ['denials', 'phaseBar', 'actionButtons', 'pane', 'toasts', 'suggestions', 'hint', 'spinner', 'turnLine', 'questionHeader', 'subcommands']
const shown = (mode: Parameters<typeof visible>[0]) => ALL.filter(e => visible(mode, e))

describe('interaction mode matrix (mods-plan 3.8)', () => {
  test('full shows everything', () => {
    expect(shown('full')).toEqual(ALL)
    expect(phaseBarStyle('full')).toBe('phases-and-actions')
  })

  test('minimal shows denials, the phase bar without buttons, and subcommands', () => {
    expect(shown('minimal')).toEqual(['denials', 'phaseBar', 'subcommands'])
    expect(phaseBarStyle('minimal')).toBe('phases-only')
  })

  test('off draws nothing but keeps denials and subcommands', () => {
    expect(shown('off')).toEqual(['denials', 'subcommands'])
    expect(phaseBarStyle('off')).toBe('none')
  })
})
