// The text of the `temper:phase` system prompt section (mods-plan 3.5). Pure: the
// adapter appends the returned text as a session scope section on every request.

import type { Phase } from './events'
import { nextStep, type ActionContext } from './actions'
import { phaseLabel } from './machine'

export const SECTION_ID = 'temper:phase'

// What a message from the user at a gate means. It is the original "Other" choice of the orchestrator:
// the Temper bar (key 4, Discuss) and the prompt box both send it. Also in commands/temper.md.
export const GATE_MESSAGE = 'If the user writes a message at a gate, answer it. If it asks for a change, make the change, run the gate again, then wait for the user again.'

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
  // The line that says the bar and the CLI do not agree (Snapshot.sync.line).
  sync?: string | null
}

export function sectionText(input: SectionInput): string {
  const lines: string[] = [input.enforcement === 'on' ? 'Temper enforcement: active' : 'Temper enforcement: off (UI only)']

  if (input.phase === null) {
    lines.push('Phase: none. No Temper run is active.')
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
    lines.push(`Stale: ${input.stale.map(phaseLabel).join(', ')}. A back step made them invalid. Each needs a new verdict.`)
  }

  lines.push(`Next: ${nextStep(input.phase, { ...input.actionContext, loopLimitReached: input.loopLimitReached })}`)
  if (input.sync) lines.push(input.sync)
  lines.push(GATE_MESSAGE)
  return lines.join('\n')
}
