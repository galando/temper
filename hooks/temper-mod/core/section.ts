// The text of the `temper:phase` system prompt section (mods-plan 3.5). Pure: the
// adapter appends the returned text as a session scope section on every request.

import type { Phase } from './events'
import { nextStep, type ActionContext } from './actions'
import { phaseLabel } from './machine'

export const SECTION_ID = 'temper:phase'

export type SectionInput = {
  enforcement: 'on' | 'off'
  phase: Phase | 'done' | null
  title: string | null
  task?: { n: number; of: number } | null
  progress: { passed: number; total: number; passedIds: readonly string[] } | null
  paused?: boolean
  loopLimitReached?: boolean
  stale?: readonly Phase[]
  actionContext?: ActionContext
}

export function sectionText(input: SectionInput): string {
  const lines: string[] = [input.enforcement === 'on' ? 'Temper enforcement: active' : 'Temper enforcement: off (UI only)']

  if (input.phase === null) {
    lines.push('Phase: none (no active Temper run)')
    return lines.join('\n')
  }

  let phase = `Phase: ${phaseLabel(input.phase)}`
  if (input.task) phase += ` (task ${input.task.n} of ${input.task.of})`
  if (input.paused) phase += ' (paused)'
  if (input.title) phase += ` · Intent: "${input.title}"`
  lines.push(phase)

  const p = input.progress
  if (p && p.total > 0) {
    const ids = p.passedIds.length > 0 ? ` (${p.passedIds.join(', ')})` : ''
    lines.push(`Criteria: ${p.passed} of ${p.total} passed${ids}`)
  }

  if (input.stale && input.stale.length > 0) {
    lines.push(`Stale: ${input.stale.map(phaseLabel).join(', ')} (invalidated by going back; each needs a fresh verdict)`)
  }

  lines.push(`Next: ${nextStep(input.phase, { ...input.actionContext, loopLimitReached: input.loopLimitReached })}`)
  return lines.join('\n')
}
