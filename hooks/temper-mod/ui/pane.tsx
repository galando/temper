import type { RenderElement } from 'claude-code'

import { LEGEND, MARK, whereText } from '../core/view'
import type { View } from '../core/view'
import type { Kit, OnAction, OnFinding } from './kit'
import { BLUE, CARD_BG, FG, GREEN, MUTED, PINK, YELLOW } from './palette'

export const PANE_ID = 'temper'

const clip = (s: string): string => (s.length > 8000 ? `${s.slice(0, 8000)}\n...` : s)

// Explicit colours only, never a dim: see ui/palette.ts. Pending steps are muted, not dimmed.
const STEP_COLOR = { done: GREEN, current: BLUE, pending: MUTED, stale: YELLOW } as const

// The pane: a card with the intent title, the acceptance criteria one per row (green check
// when met, an empty circle when not), where you are in the six phases with a legend, a short
// timeline, per finding Fix / Accept with reason / Explain, and the actions. Hotkeys are
// unique here: 1, 2, 3 for the main actions, 9 for override, 0 for "More actions", which
// expands the full list, each of those with its own letter.
//
// The card sets its own background and every text sets its own colour, so it reads the same on a
// light terminal theme and on a dark one (the engine's frame colour follows Claude Code's theme,
// not the terminal's).
export function renderPane(
  kit: Kit,
  view: View,
  onAction: OnAction,
  onFinding: OnFinding,
  inline = false,
  // The game offer: shown while a phase is working (the game setting is on). Key 8, as in the band.
  game: { show: boolean; open: boolean } = { show: false, open: false },
): RenderElement {
  const { Box, Text, Button } = kit
  const playButton = game.show ? (
    <Box key="pane-item-play" flexDirection="column">
      <Button
        key="pane-play"
        label={game.open ? '8  Close the game' : '8  Play while you wait'}
        hotkey="8"
        variant="primary"
        onPress={() => onAction({ key: '1', id: 'play', label: 'Play', desc: 'Play a small game.', command: 'play' })}
      />
      <Text color={MUTED}>{'  A small game for the wait.'}</Text>
    </Box>
  ) : null

  if (view.phase === null) {
    return (
      <Box flexDirection="column" backgroundColor={CARD_BG}>
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>No Temper run is active. Start one with /temper:temper and a feature description.</Text>
      </Box>
    )
  }

  const task = view.task ? ` · task ${view.task.n} of ${view.task.of}` : ''
  const timeline = inline ? [] : view.timeline.map((line, i) => `${i + 1}. ${line}`)
  // Seated inline above the prompt (a narrow terminal) the pane stays short so the band is not
  // pushed off screen: the buttons live in the band there, and a long checklist is cut.
  // When the person asks for the full list (key 0), it shows even here.
  const a = inline && !view.expanded ? null : view.actions
  const criteria = inline ? view.criteria.slice(0, 4) : view.criteria

  return (
    <Box flexDirection="column" rowGap={1} backgroundColor={CARD_BG}>
      <Box flexDirection="column">
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>Intent</Text>
        <Text bold color={FG}>{view.title ?? 'Untitled run'}</Text>
      </Box>

      <Box flexDirection="column">
        <Text color={MUTED}>{`Acceptance criteria (what must be true) · ${view.passed} of ${view.total} met`}</Text>
        {view.criteria.length === 0 ? <Text color={MUTED}>No criteria found in intent.md.</Text> : null}
        {criteria.map(c => (
          <Text key={`criterion-${c.id}`} color={c.status === 'passed' ? GREEN : FG}>
            {`${c.status === 'passed' ? '✔' : '○'} ${c.text}`}
          </Text>
        ))}
        {inline && view.criteria.length > 4 ? <Text color={MUTED}>{`and ${view.criteria.length - 4} more. Open the pane in a wider terminal.`}</Text> : null}
      </Box>

      <Box flexDirection="column">
        <Text color={MUTED}>{`Phase · ${whereText(view)}${task}${view.paused ? ' · paused' : ''}`}</Text>
        <Box flexDirection="row" flexWrap="wrap" columnGap={2}>
          {view.steps.map(s => (
            <Text key={`pane-step-${s.id}`} bold={s.status === 'current'} color={STEP_COLOR[s.status]}>
              {`${MARK[s.status]} ${s.label}`}
            </Text>
          ))}
        </Box>
        {inline ? null : <Text color={MUTED}>{LEGEND}</Text>}
        {view.now ? <Text color={FG}>{view.now}</Text> : null}
      </Box>

      {timeline.length > 0 ? (
        <Box key="timeline" flexDirection="column">
          <Text color={MUTED}>Timeline, oldest first</Text>
          {clip(timeline.join('\n'))
            .split('\n')
            .map((line, i) => (
              <Text key={`timeline-${i}`} color={FG}>{line}</Text>
            ))}
        </Box>
      ) : null}

      {view.findings.length > 0 ? (
        <Box flexDirection="column">
          <Text color={MUTED}>{`Open findings · ${view.findings.length}`}</Text>
          {view.findings.map(f => (
            <Box key={`finding-${f.id}`} flexDirection="row" columnGap={1} flexWrap="wrap">
              <Text color={FG}>{`#${f.id} ${f.severity}: ${f.claim}`}</Text>
              <Button key={`fix-${f.id}`} label="Fix" variant="primary" onPress={() => onFinding('fix', f.id)} />
              <Button key={`accept-${f.id}`} label="Accept with reason" variant="primary" onPress={() => onFinding('accept', f.id)} />
              <Button key={`explain-${f.id}`} label="Explain" variant="primary" onPress={() => onFinding('explain', f.id)} />
            </Box>
          ))}
        </Box>
      ) : null}

      {a ? (
        <Box flexDirection="column">
          <Text color={MUTED}>Actions</Text>
          {(inline ? [] : [...a.primary, a.override]).map(x => (
            <Box key={`pane-item-${x.id}`} flexDirection="column">
              <Button key={`pane-${x.id}`} label={`${x.key}  ${x.label}`} hotkey={x.key} variant="primary" onPress={() => onAction(x)} />
              <Text color={MUTED}>{`  ${x.desc}`}</Text>
            </Box>
          ))}
          <Box key="pane-item-more-actions" flexDirection="column">
            <Button
              key="pane-more-actions"
              label={view.expanded ? '0  Fewer actions' : '0  More actions'}
              hotkey="0"
              variant="primary"
              onPress={() => onAction({ key: '0', id: 'more-actions', label: 'More actions', desc: 'Show or hide the other actions.', command: 'pane-expand' })}
            />
            <Text color={MUTED}>{'  Show or hide the other actions.'}</Text>
          </Box>
          {view.expanded
            ? a.more.map(x => (
                <Box key={`pane-item-${x.id}`} flexDirection="column">
                  <Button key={`pane-${x.id}`} label={`${x.key}  ${x.label}`} hotkey={x.key} variant="primary" onPress={() => onAction(x)} />
                  <Text color={MUTED}>{`  ${x.desc}`}</Text>
                </Box>
              ))
            : null}
          {playButton}
        </Box>
      ) : playButton ? (
        <Box flexDirection="column">{playButton}</Box>
      ) : null}
    </Box>
  )
}
