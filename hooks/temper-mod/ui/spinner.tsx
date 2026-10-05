import type { RenderPropsOf } from 'claude-code'

import { spinnerWord } from '../core/view'
import type { View } from '../core/view'

// Rewrites the animated word to "Building · criterion 2 of 5". Null leaves the engine's.
export function spinnerProps(props: RenderPropsOf['Spinner'], view: View): RenderPropsOf['Spinner'] | null {
  const word = spinnerWord(view)
  return word === null ? null : { ...props, word }
}
