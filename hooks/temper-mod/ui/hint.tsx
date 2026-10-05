import type { RenderPropsOf } from 'claude-code'

import { hintTail } from '../core/view'
import type { View } from '../core/view'

// Terminal only: the engine keeps its line (pills stay live) and draws `tail` dim at its
// end. Other surfaces draw no tail, so the props pass through unchanged.
export function hintProps(
  props: RenderPropsOf['PromptHint'],
  view: View,
  surface: string,
  // The game is offered (setting `on`). The offer shows only while Claude works.
  offerGame = false,
): RenderPropsOf['PromptHint'] | null {
  if (surface !== 'terminal') return null
  const tail = hintTail(view)
  if (tail === null) return null
  return { ...props, tail: offerGame && props.isWorking ? `Press 8 to play while you wait. ${tail}` : tail }
}
