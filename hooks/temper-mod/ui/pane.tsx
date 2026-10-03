import type { RenderElement } from 'claude-code'

import { phaseLabel } from '../core/machine'
import type { View } from '../core/view'
import type { Kit, OnAction, OnFinding } from './kit'

export const PANE_ID = 'temper'

const clip = (s: string): string => (s.length > 8000 ? `${s.slice(0, 8000)}\n...` : s)

// The pane: title, phase, a live criteria checklist, a short timeline, per finding
// Fix / Accept with reason / Explain, and every action of the phase.
export function renderPane(kit: Kit, view: View, onAction: OnAction, onFinding: OnFinding): RenderElement {
  const { Box, Text, Button, Markdown } = kit

  if (view.phase === null) {
    return (
      <Box flexDirection="column">
        <Text dimColor>No Temper run is active. Start one with /temper and a feature description.</Text>
      </Box>
    )
  }

  const phase = phaseLabel(view.phase)
  const task = view.task ? ` (task ${view.task.n} of ${view.task.of})` : ''
  const checklist = view.criteria.map(c => `- [${c.status === 'passed' ? 'x' : ' '}] **${c.id}** ${c.text}`).join('\n')
  const timeline = view.timeline.map(line => `- ${line}`).join('\n')
  const actions = view.actions ? [...view.actions.primary, ...view.actions.more, view.actions.override] : []

  return (
    <Box flexDirection="column">
      <Text bold>{view.title ?? 'Temper run'}</Text>
      <Text>{`Phase: ${phase}${task}${view.paused ? ' (paused)' : ''}`}</Text>
      {view.next ? <Text dimColor>{`Next: ${view.next}`}</Text> : null}
      <Text bold>{`Criteria: ${view.passed} of ${view.total} passed`}</Text>
      {checklist ? <Markdown key="criteria" text={clip(checklist)} /> : <Text dimColor>No criteria found in intent.md.</Text>}
      {timeline ? <Markdown key="timeline" text={clip(timeline)} /> : null}
      {view.findings.map(f => (
        <Box key={`finding-${f.id}`} flexDirection="row" columnGap={1}>
          <Text>{`#${f.id} ${f.severity}: ${f.claim}`}</Text>
          <Button key={`fix-${f.id}`} label="Fix" onPress={() => onFinding('fix', f.id)} />
          <Button key={`accept-${f.id}`} label="Accept with reason" onPress={() => onFinding('accept', f.id)} />
          <Button key={`explain-${f.id}`} label="Explain" onPress={() => onFinding('explain', f.id)} />
        </Box>
      ))}
      {actions.map(a => (
        <Button key={`pane-${a.id}`} label={a.label} hotkey={a.key} plain onPress={() => onAction(a)} />
      ))}
    </Box>
  )
}
