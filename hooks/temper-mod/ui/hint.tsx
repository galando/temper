import type { RenderPropsOf } from 'claude-code'

import { hintTail } from '../core/view'
import type { View } from '../core/view'

// Terminal only: the engine keeps its line (pills stay live) and draws `tail` dim at its
// end. Other surfaces draw no tail, so the props pass through unchanged.
export function hintProps(
  props: RenderPropsOf['PromptHint'],
  view: View,
  surface: string,
): RenderPropsOf['PromptHint'] | null {
  if (surface !== 'terminal') return null
  const tail = hintTail(view)
  return tail === null ? null : { ...props, tail }
}
