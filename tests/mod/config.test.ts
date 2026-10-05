import { describe, expect, test } from 'claude-code/testing'

import {
  parseEnforcement,
  parseGameMode,
  parseMaxLoops,
  parseOnOff,
  parsePhaseModel,
  parsePhaseModels,
  parseUiMode,
  readConfigValue,
} from '../../hooks/temper-mod/core/config'

const CONFIG = [
  '# comment',
  'stack: auto',
  'review:',
  '  block-on: [critical]   # inline comment',
  'fix:',
  '  max-loops: 5',
  'loops:',
  '  max-per-type: 2',
  'check:',
  '  commands:',
  '    test: "npm test"',
  '# fix:',
  '#   max-loops: 9',
].join('\n')

describe('readConfigValue', () => {
  test('reads nested keys, strips comments and quotes', () => {
    expect(readConfigValue(CONFIG, 'fix.max-loops')).toBe('5')
    expect(readConfigValue(CONFIG, 'stack')).toBe('auto')
    expect(readConfigValue(CONFIG, 'check.commands.test')).toBe('npm test')
    expect(readConfigValue(CONFIG, 'review.block-on')).toBe('[critical]')
  })

  test('missing keys and commented keys are null', () => {
    expect(readConfigValue(CONFIG, 'fix.nothing')).toBe(null)
    expect(readConfigValue('# fix:\n#   max-loops: 9', 'fix.max-loops')).toBe(null)
    expect(readConfigValue('', 'fix.max-loops')).toBe(null)
  })

  test('a sibling block does not leak into another', () => {
    expect(readConfigValue('a:\n  x: 1\nb:\n  y: 2', 'b.x')).toBe(null)
  })
})

describe('plain string options validated in code', () => {
  test('uiMode falls back to full', () => {
    expect(parseUiMode('minimal')).toBe('minimal')
    expect(parseUiMode(' OFF ')).toBe('off')
    expect(parseUiMode('loud')).toBe('full')
    expect(parseUiMode(undefined)).toBe('full')
  })

  test('enforcement and prAttribution fall back to on', () => {
    expect(parseEnforcement('off')).toBe('off')
    expect(parseEnforcement('maybe')).toBe('on')
    expect(parseOnOff('off', 'on')).toBe('off')
    expect(parseOnOff(undefined, 'on')).toBe('on')
  })

  test('game is on, command or off; anything else means on', () => {
    expect(parseGameMode('on')).toBe('on')
    expect(parseGameMode(' Command ')).toBe('command')
    expect(parseGameMode('OFF')).toBe('off')
    expect(parseGameMode('maybe')).toBe('on')
    expect(parseGameMode(undefined)).toBe('on')
  })

  test('max loops: config key beats userConfig beats 3; junk is ignored', () => {
    expect(parseMaxLoops(CONFIG, '4')).toBe(5)
    expect(parseMaxLoops('stack: auto', '4')).toBe(4)
    expect(parseMaxLoops('stack: auto', undefined)).toBe(3)
    expect(parseMaxLoops('fix:\n  max-loops: many', '0')).toBe(3)
    expect(parseMaxLoops('fix:\n  max-loops: -2', 'x')).toBe(3)
  })

  test('phase models parse pairs and skip malformed ones', () => {
    expect(parsePhaseModels('build=sonnet, plan=opus')).toEqual({ build: 'sonnet', plan: 'opus' })
    expect(parsePhaseModels('')).toEqual({})
    expect(parsePhaseModels('build=, =x, nonsense, review=haiku')).toEqual({ review: 'haiku' })
    expect(parsePhaseModels(undefined)).toEqual({})
  })
})

describe('parsePhaseModel', () => {
  test('model, effort, or both; junk effort is dropped', () => {
    expect(parsePhaseModel('sonnet')).toEqual({ model: 'sonnet' })
    expect(parsePhaseModel('sonnet:high')).toEqual({ model: 'sonnet', effort: 'high' })
    expect(parsePhaseModel(':max')).toEqual({ effort: 'max' })
    expect(parsePhaseModel('sonnet:loud')).toEqual({ model: 'sonnet' })
    expect(parsePhaseModel('')).toEqual({})
    expect(parsePhaseModel(undefined)).toEqual({})
  })
})
