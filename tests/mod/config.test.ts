import { describe, expect, test } from 'claude-code/testing'

import {
  parseEnforcement,
  parseOnOff,
  parsePhaseModel,
  parsePhaseModels,
  parseUiMode,
} from '../../hooks/temper-mod/core/config'

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
