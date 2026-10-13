// The text of the `temper:phase` system prompt section. Pure: the adapter appends the returned text as a session scope
// section on every request. One flow in every mode (ADR 0012): Claude asks every gate in the `Temper gate` question.

import { stageLabel } from './stages'
import type { RunFacts } from './rules'
import { nextStep } from './view'
import type { View } from './view'

export const SECTION_ID = 'temper:phase'

// What a message from the user at a gate means: the gate's "Other" choice. Also in commands/temper.md.
export const GATE_MESSAGE = 'If the user writes a message at a gate, answer it. If it asks for a change, make the change, run the gate again, then ask the gate question again.'

export type SectionInput = {
  enforcement: 'on' | 'off'
  // The run's view; null when no /temper run is active.
  view: View | null
  run?: RunFacts | null
  // The line that says the mod cannot read the run as it should.
  line?: string | null
}

export function sectionText(input: SectionInput): string {
  const lines: string[] = [input.enforcement === 'on' ? 'Temper enforcement: active' : 'Temper enforcement: off (UI only)']
  const v = input.view
  if (v === null || v.stage === null) {
    lines.push('Phase: none. No Temper run is active.')
    if (input.line) lines.push(input.line)
    return lines.join('\n')
  }
  let phase = `Phase: ${v.stage === 'commit' ? 'Done' : stageLabel(v.stage)}`
  if (v.task && v.stage === 'build') phase += ` (task ${v.task.n} of ${v.task.of})`
  if (v.wait === 'saved') phase += ' (saved for later)'
  if (v.title) phase += ` · Intent: "${v.title}"`
  lines.push(phase)
  if (v.total > 0) {
    const ids = v.criteria.filter(c => c.status === 'passed').map(c => c.id)
    lines.push(`Criteria: ${v.passed} of ${v.total} passed${ids.length > 0 ? ` (${ids.join(', ')})` : ''}`)
  }
  const next = nextStep(v, input.run ?? null)
  if (next) lines.push(`Next: ${next}`)
  if (input.line) lines.push(input.line)
  lines.push(GATE_MESSAGE)
  return lines.join('\n')
}
