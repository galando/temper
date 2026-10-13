// The first words of `/temper:temper` that the mod answers itself: the ones that show the run or set how Temper shows
// and enforces it. Pure. Every other word goes on to the prompt based /temper:temper: a feature description starts or
// resumes a run, and a decision word (approve, back, override, accept, pause, restart and the like) makes Claude ask
// the `Temper gate` question, where the person decides with a click (ADR 0012).

export const RESERVED = ['status', 'timeline', 'help', 'report', 'mode', 'enforcement', 'pane', 'play'] as const

export type Reserved = (typeof RESERVED)[number]

export const isReserved = (w: string): w is Reserved => (RESERVED as readonly string[]).includes(w)

export type Parsed = { word: Reserved; rest: string }

// null when the first word is not one the mod answers (a feature description, a decision word, or nothing).
export function parseArgs(args: string): Parsed | null {
  const text = args.trim()
  const m = /^(\S+)\s*([\s\S]*)$/.exec(text)
  const word = (m?.[1] ?? '').toLowerCase()
  return m && isReserved(word) ? { word, rest: (m[2] ?? '').trim() } : null
}

export const NEEDS_PERSON =
  'Temper: only the user changes what Temper shows and enforces, from the prompt box. This command came from somewhere else, such as a claude -p run, the Agent SDK or Claude. ' +
  'Next: ask the user to run it.'

export const HELP = [
  'Temper subcommands (type them after /temper:temper):',
  '  status               show where the run is',
  '  timeline             list your decisions in this run',
  '  report               show the run report (with no run active, the last one kept)',
  '  pane                 open or close the Temper pane (full mode)',
  '  play                 play Temper Run while you wait (r runs, w jumps, s ducks, q leaves)',
  '  mode, enforcement    show or change what Temper shows and enforces',
  'You decide at every gate in the Temper gate question: Continue, Loop back, Override and continue, Save for later.',
  'Any other text after /temper:temper is a feature description. It starts or resumes a run. With no text it takes the run up again.',
].join('\n')
