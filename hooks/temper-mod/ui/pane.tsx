import type { RenderElement } from 'claude-code'

import { LEGEND, MARK, TASK_STATE, clockText, loopText, whereText } from '../core/view'
import type { GridTask, Marker, View } from '../core/view'
import type { Kit } from './kit'
import { BLUE, CARD_BG, FG, GREEN, MUTED, ORANGE, PINK, YELLOW } from './palette'

export const PANE_ID = 'temper'

// Explicit colours only, never a dim: see ui/palette.ts. Stages to come are muted, not dimmed.
const MARK_COLOR = { passed: GREEN, failed: ORANGE, skipped: YELLOW, current: BLUE, pending: MUTED } as const
const TASK_COLOR: Record<GridTask['state'], string> = { waiting: MUTED, running: BLUE, red: ORANGE, green: GREEN, pass: GREEN, fail: ORANGE, parked: YELLOW }
const MARKER: Record<Marker['state'], [string, string]> = { pass: ['✓', GREEN], fail: ['✗', ORANGE], info: ['•', BLUE], none: ['○', MUTED] }
const SEVERE = new Set(['critical', 'high'])

const taskText = (t: GridTask): string =>
  `${TASK_STATE[t.state][0]} ${TASK_STATE[t.state][1].padEnd(7)} Task ${t.n}${t.title ? `: ${t.title}` : ''}${t.model ? ` · ${t.model.replace(/^claude-/, '')}` : ''}${t.retries > 0 ? ` · ${t.retries} ${t.retries === 1 ? 'retry' : 'retries'}` : ''}`

// The pane: the whole run on one card, read only (ADR 0013), drawn from view.json. The intent, the stages with their
// verdicts, the person's skips and the loops back with their reasons, the status, the plan's files by Build group, the
// Build grid (each task's state, model and retries), the Review findings, the Check markers with their failing lines,
// the acceptance criteria with their evidence, and the person's decisions. The person decides in the question dialog:
// the pane has no button. `inline` (a pane drawn in the conversation) keeps each section short.
//
// The card sets its own background and every text its own colour, so it reads the same on a light terminal theme and on
// a dark one.
export function renderPane(kit: Kit, view: View, inline = false): RenderElement {
  const { Box, Text } = kit
  if (view.stage === null) {
    return (
      <Box flexDirection="column" backgroundColor={CARD_BG}>
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>No Temper run is active yet. A run started with /temper:temper and a feature description shows here.</Text>
      </Box>
    )
  }
  const cut = <T,>(rows: T[], n: number): T[] => (inline ? rows.slice(0, n) : rows)
  const more = (key: string, all: number, n: number) => (inline && all > n ? [<Text key={key} color={MUTED}>{`and ${all - n} more`}</Text>] : [])
  const criteria = cut(view.criteria, 4)
  const decisions = inline ? view.decisions.slice(-3) : view.decisions.slice(-8)
  const section = (key: string, title: string, rows: RenderElement[]) => (
    <Box key={key} flexDirection="column">
      <Text color={MUTED}>{title}</Text>
      {rows}
    </Box>
  )
  const clock = clockText(view)
  const planned = view.stages.findIndex(s => s.id === view.stage) >= view.stages.findIndex(s => s.id === 'plan')
  return (
    <Box flexDirection="column" rowGap={1} backgroundColor={CARD_BG}>
      <Box flexDirection="column">
        <Text bold color={PINK}>{'◈ Temper'}</Text>
        <Text color={MUTED}>Intent</Text>
        <Text bold color={FG}>{view.title ?? 'Untitled run'}</Text>
        {clock ? <Text color={MUTED}>{clock}</Text> : null}
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
        ...view.loopMarks.map((l, i) => (
          <Text key={`loop-${i}`} color={BLUE}>
            {loopText(l)}
          </Text>
        )),
        ...(inline ? [] : [<Text key="legend" color={MUTED}>{LEGEND}</Text>]),
        <Text key="status" color={view.wait === 'gate' || view.wait === 'saved' ? YELLOW : FG}>{view.status}</Text>,
        ...(view.line ? [<Text key="line" color={YELLOW}>{view.line}</Text>] : []),
      ])}

      {view.planTree !== null && planned
        ? section(
            'plan',
            `Plan files · ${view.planTree.approved ? 'as you approved them' : 'as the plan lists them'}`,
            [
              ...cut(view.planTree.groups, 3).map(g => (
                <Box key={`plan-${g.id}`} flexDirection="column">
                  <Text bold color={FG}>{`${g.id}${g.title ? ` ${g.title}` : ''}`}</Text>
                  {cut(g.files, 4).map((f, i) => (
                    <Text key={`plan-${g.id}-${i}`} color={FG}>{`  ${i === Math.min(g.files.length, inline ? 4 : g.files.length) - 1 ? '└' : '├'} ${f}`}</Text>
                  ))}
                  {more(`plan-${g.id}-more`, g.files.length, 4)}
                </Box>
              )),
              ...more('plan-more', view.planTree.groups.length, 3),
              ...(view.planTree.other.length > 0 ? [<Text key="plan-other" color={FG}>{`Other: ${view.planTree.other.join(', ')}`}</Text>] : []),
            ],
          )
        : null}

      {view.grid !== null && view.stage !== 'intent' && view.stage !== 'plan' && view.stage !== 'design'
        ? section(
            'build',
            'Build',
            view.grid.map(g => (
              <Box key={`group-${g.id}`} flexDirection="column">
                <Text bold color={g.status === 'parked' ? YELLOW : g.status === 'passed' || g.status === 'merged' ? GREEN : FG}>
                  {`${g.id}${g.title ? ` ${g.title}` : ''}${g.status === 'pending' ? '' : ` (${g.status})`}`}
                </Text>
                {(inline ? g.tasks.filter(t => t.state !== 'pass') : g.tasks).map(t => (
                  <Text key={`task-${t.n}`} color={TASK_COLOR[t.state]}>{`  ${taskText(t)}`}</Text>
                ))}
              </Box>
            )),
          )
        : null}

      {view.findingRows.length > 0
        ? section('findings', `Review findings · ${view.findingRows.filter(f => f.state === 'open').length} open`, [
            ...cut(view.findingRows, 5).map(f => (
              <Text key={`finding-${f.id}`} color={f.state !== 'open' ? MUTED : SEVERE.has(f.severity) ? ORANGE : FG}>
                {`#${f.id} ${f.severity}${f.confidence !== null ? ` ${f.confidence.toFixed(2)}` : ''}${f.where ? ` ${f.where}` : ''} ${f.claim} · ${f.state}`}
              </Text>
            )),
            ...more('findings-more', view.findingRows.length, 5),
          ])
        : null}

      {view.markers.some(m => m.state !== 'none')
        ? section(
            'check',
            'Check',
            view.markers.map(m => (
              <Box key={`marker-${m.name}`} flexDirection="column">
                <Text color={MARKER[m.state][1]}>{`${MARKER[m.state][0]} ${m.name}${m.detail ? `: ${m.detail}` : ''}`}</Text>
                {cut(m.lines, 2).map((l, i) => (
                  <Text key={`marker-${m.name}-${i}`} color={ORANGE}>{`    ${l}`}</Text>
                ))}
              </Box>
            )),
          )
        : view.failedChecks.length > 0
          ? section(
              'checks',
              'Failed checks',
              view.failedChecks.map((q, i) => <Text key={`check-${i}`} color={ORANGE}>{`✗ ${q.name}${q.detail ? `: ${q.detail}` : ''}`}</Text>),
            )
          : null}

      {section('criteria', `Acceptance criteria · ${view.passed} of ${view.total} met`, [
        ...(view.criteria.length === 0 ? [<Text key="none" color={MUTED}>No criteria found in intent.md.</Text>] : []),
        ...criteria.flatMap(c => [
          <Text key={`criterion-${c.id}`} color={c.status === 'passed' ? GREEN : FG}>{`${c.status === 'passed' ? '✔' : '○'} ${c.id} ${c.text}`}</Text>,
          ...(inline ? [] : c.evidence.slice(0, 1).map((e, i) => <Text key={`criterion-${c.id}-${i}`} color={MUTED}>{`    ${e}`}</Text>)),
        ]),
        ...more('criteria-more', view.criteria.length, 4),
      ])}

      {decisions.length > 0 ? section('decisions', 'Your decisions', decisions.map((d, i) => <Text key={`decision-${i}`} color={FG}>{`· ${d}`}</Text>)) : null}
    </Box>
  )
}
