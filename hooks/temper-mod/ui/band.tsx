import type { RenderElement } from 'claude-code'

import type { UiMode } from '../core/config'
import { barStyle } from '../core/modes'
import { MARK, clockText, loopText, whereText } from '../core/view'
import type { StageView, View } from '../core/view'
import type { Kit } from './kit'

// Below this width the band uses its compact form: no borders, the stages as plain words. Nothing wraps into a mess.
export const COMPACT_BELOW = 100

// The most detail lines the band shows under the status (the pane shows them all).
const MAX_DETAIL = 5

const COLOR: Record<StageView['mark'], string | undefined> = { passed: 'green', failed: 'red', skipped: 'yellow', current: 'blue', pending: undefined }

// One chip of the stage timeline: passed is green with a check, failed red with a cross, a skipped stage yellow, the
// current stage a filled blue chip (red when its check failed), stages to come dim and outlined.
function chip(kit: Kit, step: StageView, compact: boolean) {
  const { Box, Text } = kit
  const isCurrent = step.mark === 'current'
  const bad = isCurrent && step.failed
  const text = (
    <Text bold={isCurrent} color={isCurrent ? 'white' : COLOR[step.mark]} dimColor={step.mark === 'pending'}>
      {`${MARK[step.mark]} ${step.label}`}
    </Text>
  )
  const fill = isCurrent ? (bad ? 'red' : 'blue') : undefined
  if (compact) {
    return (
      <Box key={`stage-${step.id}`} paddingX={1} backgroundColor={fill}>
        {text}
      </Box>
    )
  }
  return (
    <Box key={`stage-${step.id}`} borderStyle="round" borderColor={fill ?? COLOR[step.mark] ?? 'gray'} borderDimColor={step.mark === 'pending'} backgroundColor={fill} paddingX={1}>
      {text}
    </Box>
  )
}

// The band above the prompt. It has no button and decides nothing: the person decides in the `Temper gate` question,
// and takes a run up again by typing /temper:temper. Full mode: TEMPER, the title, where the run is, its time and tokens,
// the stage timeline with its loops back and their reasons, the status of the stage and its details (the groups in
// Build, the findings in Review, the failed checks). Minimal draws the timeline only. Off draws nothing (the caller
// passes next(e)).
export function renderBand(kit: Kit, view: View, mode: UiMode, columns = 120): RenderElement | null {
  const style = barStyle(mode)
  if (style === 'none' || view.stage === null) return null
  const { Box, Text } = kit
  const compact = columns < COMPACT_BELOW

  const chips = (
    <Box flexDirection="row" columnGap={compact ? 0 : 1} flexWrap="wrap">
      {view.stages.map(s => chip(kit, s, compact))}
    </Box>
  )

  if (style === 'stages') {
    return (
      <Box flexDirection="row" columnGap={1} alignItems="center" key="temper-band">
        <Text bold color="magenta">TEMPER</Text>
        {chips}
      </Box>
    )
  }

  const head = (
    <Box flexDirection="row" columnGap={1} key="row-head" flexWrap="wrap">
      <Text bold color="magenta">TEMPER</Text>
      {view.title ? <Text bold>{view.title}</Text> : null}
      <Text dimColor>{`· ${whereText(view)}`}</Text>
      {view.total > 0 ? <Text dimColor>{`· criteria ${view.passed} of ${view.total}`}</Text> : null}
      {clockText(view) ? <Text dimColor>{`· ${clockText(view)}`}</Text> : null}
      <Text dimColor={view.enforcement === 'on'} color={view.enforcement === 'on' ? undefined : 'yellow'}>{`· enforcement ${view.enforcement}`}</Text>
    </Box>
  )
  const waiting = view.wait === 'gate' || view.wait === 'saved'
  const status = (
    <Text bold={waiting} color={waiting ? 'yellow' : undefined}>
      {view.status}
    </Text>
  )
  const detail = view.detail.slice(0, MAX_DETAIL)
  const more = view.detail.length - detail.length
  return (
    <Box flexDirection="column" key="temper-band">
      {head}
      {chips}
      {view.loopMarks.map((l, i) => (
        <Text key={`loop-${i}`} color="cyan">
          {loopText(l)}
        </Text>
      ))}
      {status}
      {detail.map((line, i) => (
        <Text key={`detail-${i}`} dimColor>
          {line}
        </Text>
      ))}
      {more > 0 ? <Text dimColor>{`and ${more} more lines in the pane (/temper:temper pane)`}</Text> : null}
      {view.line ? <Text color="yellow">{view.line}</Text> : null}
    </Box>
  )
}
