import type { RenderElement } from 'claude-code'

import { LEGEND, MARK, whereText } from '../core/view'
import type { View } from '../core/view'
import type { TaskCell } from '../core/clifiles'
import type { Kit } from './kit'
import { BLUE, CARD_BG, FG, GREEN, MUTED, ORANGE, PINK, YELLOW } from './palette'

export const PANE_ID = 'temper'

// Explicit colours only, never a dim: see ui/palette.ts. Stages to come are muted, not dimmed.
const MARK_COLOR = { passed: GREEN, failed: ORANGE, skipped: YELLOW, current: BLUE, pending: MUTED } as const
const TASK = { waiting: ['○', MUTED], running: ['◐', BLUE], passed: ['✓', GREEN], failed: ['✗', ORANGE], parked: ['⏸', YELLOW] } as const

const taskText = (t: TaskCell): string => {
  const how = t.state === 'running' ? ` (attempt ${t.attempt ?? 1})` : t.model ? ` (${t.model.replace(/^claude-/, '')})` : ''
  return `${TASK[t.state][0]} Task ${t.n}${t.title ? `: ${t.title}` : ''}${how}`
}

// The pane: the whole run on one card, read only. The intent and its criteria, the stages with their verdicts and the
// person's skips, the status, the groups and tasks of Build, the open findings, the failed checks, the loops and the
// person's decisions. The person decides in the `Temper gate` question (ADR 0012): the pane has no button.
//
// The card sets its own background and every text its own colour, so it reads the same on a light terminal theme and on
// a dark one.
export function renderPane(
  kit: Kit,
  view: View,
  inline = false,
): RenderElement {
  const { Box, Text } = kit
  if (view.stage === null) {
    return (
      <Box flexDirection="column" backgroundColor={CARD_BG}>
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>No Temper run is active. Start one with /temper:temper and a feature description.</Text>
      </Box>
    )
  }
  const criteria = inline ? view.criteria.slice(0, 4) : view.criteria
  const decisions = inline ? view.decisions.slice(-3) : view.decisions.slice(-8)
  const section = (key: string, title: string, rows: RenderElement[]) => (
    <Box key={key} flexDirection="column">
      <Text color={MUTED}>{title}</Text>
      {rows}
    </Box>
  )
  return (
    <Box flexDirection="column" rowGap={1} backgroundColor={CARD_BG}>
      <Box flexDirection="column">
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>Intent</Text>
        <Text bold color={FG}>{view.title ?? 'Untitled run'}</Text>
      </Box>

      {section('stages', `Stages · ${whereText(view)}`, [
        <Box key="stage-row" flexDirection="row" flexWrap="wrap" columnGap={2}>
          {view.stages.map(s => (
            <Text key={`pane-stage-${s.id}`} bold={s.mark === 'current'} color={s.mark === 'current' && s.failed ? ORANGE : MARK_COLOR[s.mark]}>
              {`${MARK[s.mark]} ${s.label}`}
            </Text>
          ))}
        </Box>,
        ...view.stages
          .filter(s => s.skip !== null)
          .map(s => (
            <Text key={`skip-${s.id}`} color={YELLOW}>{`${s.label} skipped: ${s.skip}`}</Text>
          )),
        ...(inline ? [] : [<Text key="legend" color={MUTED}>{LEGEND}</Text>]),
        <Text key="status" color={view.wait === 'gate' || view.wait === 'saved' ? YELLOW : FG}>{view.status}</Text>,
        ...(view.line ? [<Text key="line" color={YELLOW}>{view.line}</Text>] : []),
      ])}

      {view.stage === 'build' && view.groups !== null
        ? section(
            'groups',
            'Build groups',
            view.groups.map(g => (
              <Box key={`group-${g.id}`} flexDirection="column">
                <Text bold color={g.state === 'parked' ? YELLOW : g.state === 'passed' ? GREEN : FG}>{`${g.id}${g.title ? ` ${g.title}` : ''}${g.state === 'parked' ? ' (parked)' : g.state === 'passed' ? ' (passed)' : ''}`}</Text>
                {(inline ? g.tasks.filter(t => t.state !== 'passed') : g.tasks).map(t => (
                  <Text key={`task-${t.n}`} color={TASK[t.state][1]}>{`  ${taskText(t)}`}</Text>
                ))}
              </Box>
            )),
          )
        : null}

      {view.findings.length > 0
        ? section(
            'findings',
            `Open findings · ${view.findings.length}`,
            view.findings.map(f => <Text key={`finding-${f.id}`} color={FG}>{`#${f.id} ${f.severity}: ${f.claim}`}</Text>),
          )
        : null}

      {view.failedChecks.length > 0
        ? section(
            'checks',
            'Failed checks',
            view.failedChecks.map((q, i) => <Text key={`check-${i}`} color={ORANGE}>{`✗ ${q.name}${q.detail ? `: ${q.detail}` : ''}`}</Text>),
          )
        : null}

      {section('criteria', `Acceptance criteria · ${view.passed} of ${view.total} met`, [
        ...(view.criteria.length === 0 ? [<Text key="none" color={MUTED}>No criteria found in intent.md.</Text>] : []),
        ...criteria.map(c => (
          <Text key={`criterion-${c.id}`} color={c.status === 'passed' ? GREEN : FG}>{`${c.status === 'passed' ? '✔' : '○'} ${c.text}`}</Text>
        )),
        ...(inline && view.criteria.length > 4 ? [<Text key="more" color={MUTED}>{`and ${view.criteria.length - 4} more`}</Text>] : []),
      ])}

      {view.loops.length > 0 ? section('loops', 'Loops back (used of budget)', view.loops.map((l, i) => <Text key={`loop-${i}`} color={FG}>{l}</Text>)) : null}

      {decisions.length > 0 ? section('decisions', 'Your decisions', decisions.map((d, i) => <Text key={`decision-${i}`} color={FG}>{`· ${d}`}</Text>)) : null}

    </Box>
  )
}
