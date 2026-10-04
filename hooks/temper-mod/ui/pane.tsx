import type { RenderElement } from 'claude-code'

import { LEGEND, MARK, whereText } from '../core/view'
import type { View } from '../core/view'
import type { Kit, OnAction, OnFinding } from './kit'

export const PANE_ID = 'temper'

const clip = (s: string): string => (s.length > 8000 ? `${s.slice(0, 8000)}\n...` : s)

const STEP_COLOR = { done: 'green', current: 'blue', pending: undefined, stale: 'yellow' } as const

// The pane: a card with the intent title, the acceptance criteria one per row (green check
// when met, an empty circle when not), where you are in the six phases with a legend, a short
// timeline, per finding Fix / Accept with reason / Explain, and the actions. Hotkeys are
// unique here: 1, 2, 3 for the main actions, 9 for override, 0 for "More actions", which
// expands the full list, each of those with its own letter.
export function renderPane(
  kit: Kit,
  view: View,
  onAction: OnAction,
  onFinding: OnFinding,
  inline = false,
  // The game offer: shown while a phase is working (the game setting is on). Key 8, as in the band.
  game: { show: boolean; open: boolean } = { show: false, open: false },
): RenderElement {
  const { Box, Text, Button, Markdown } = kit
  const playButton = game.show ? (
    <Button
      key="pane-play"
      label={game.open ? 'Close game' : 'Play while you wait'}
      hotkey="8"
      plain
      onPress={() => onAction({ key: '1', id: 'play', label: 'Play', command: 'play' })}
    />
  ) : null

  if (view.phase === null) {
    return (
      <Box flexDirection="column">
        <Text bold>{'◈ Temper'}</Text>
        <Text dimColor>No Temper run is active. Start one with /temper:temper and a feature description.</Text>
      </Box>
    )
  }

  const task = view.task ? ` · task ${view.task.n} of ${view.task.of}` : ''
  const timeline = inline ? '' : view.timeline.map((line, i) => `${i + 1}. ${line}`).join('\n')
  // Seated inline above the prompt (a narrow terminal) the pane stays short so the band is not
  // pushed off screen: the buttons live in the band there, and a long checklist is cut.
  // When the person asks for the full list (key 0), it shows even here.
  const a = inline && !view.expanded ? null : view.actions
  const criteria = inline ? view.criteria.slice(0, 4) : view.criteria

  return (
    <Box flexDirection="column" rowGap={1}>
      <Box flexDirection="column">
        <Text bold>{'◈ Temper'}</Text>
        <Text dimColor>Intent</Text>
        <Text bold>{view.title ?? 'Untitled run'}</Text>
      </Box>

      <Box flexDirection="column">
        <Text dimColor>{`Acceptance criteria · ${view.passed} of ${view.total} met`}</Text>
        {view.criteria.length === 0 ? <Text dimColor>No criteria found in intent.md.</Text> : null}
        {criteria.map(c => (
          <Text key={`criterion-${c.id}`} color={c.status === 'passed' ? 'green' : undefined}>
            {`${c.status === 'passed' ? '✔' : '○'} ${c.text}`}
          </Text>
        ))}
        {inline && view.criteria.length > 4 ? <Text dimColor>{`and ${view.criteria.length - 4} more. Open the pane in a wider terminal.`}</Text> : null}
      </Box>

      <Box flexDirection="column">
        <Text dimColor>{`Phase · ${whereText(view)}${task}${view.paused ? ' · paused' : ''}`}</Text>
        <Box flexDirection="row" flexWrap="wrap" columnGap={2}>
          {view.steps.map(s => (
            <Text key={`pane-step-${s.id}`} bold={s.status === 'current'} color={STEP_COLOR[s.status]} dimColor={s.status === 'pending'}>
              {`${MARK[s.status]} ${s.label}`}
            </Text>
          ))}
        </Box>
        {inline ? null : <Text dimColor>{LEGEND}</Text>}
        {view.now ? <Text>{`Next: ${view.now}`}</Text> : null}
      </Box>

      {timeline ? (
        <Box flexDirection="column">
          <Text dimColor>Timeline, oldest first</Text>
          <Markdown key="timeline" text={clip(timeline)} />
        </Box>
      ) : null}

      {view.findings.length > 0 ? (
        <Box flexDirection="column">
          <Text dimColor>{`Open findings · ${view.findings.length}`}</Text>
          {view.findings.map(f => (
            <Box key={`finding-${f.id}`} flexDirection="row" columnGap={1} flexWrap="wrap">
              <Text>{`#${f.id} ${f.severity}: ${f.claim}`}</Text>
              <Button key={`fix-${f.id}`} label="Fix" onPress={() => onFinding('fix', f.id)} />
              <Button key={`accept-${f.id}`} label="Accept with reason" onPress={() => onFinding('accept', f.id)} />
              <Button key={`explain-${f.id}`} label="Explain" onPress={() => onFinding('explain', f.id)} />
            </Box>
          ))}
        </Box>
      ) : null}

      {a ? (
        <Box flexDirection="column">
          <Text dimColor>Actions</Text>
          {(inline ? [] : [...a.primary, a.override]).map(x => (
            <Button key={`pane-${x.id}`} label={x.label} hotkey={x.key} plain onPress={() => onAction(x)} />
          ))}
          <Button
            key="pane-more-actions"
            label={view.expanded ? 'Fewer actions' : 'More actions'}
            hotkey="0"
            plain
            dimColor
            onPress={() => onAction({ key: '0', id: 'more-actions', label: 'More actions', command: 'pane-expand' })}
          />
          {view.expanded
            ? a.more.map(x => <Button key={`pane-${x.id}`} label={x.label} hotkey={x.key} plain dimColor onPress={() => onAction(x)} />)
            : null}
          {playButton}
        </Box>
      ) : playButton ? (
        <Box flexDirection="column">{playButton}</Box>
      ) : null}
    </Box>
  )
}
