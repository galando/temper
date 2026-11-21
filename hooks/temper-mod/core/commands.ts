// The first words of `/temper:temper` that the mod answers itself: the ones that show the run, open or close the pane,
// or say how Temper shows and enforces it (the person changes those two in /config). Pure. Every other word goes on to the prompt based /temper:temper: a feature description starts or
// resumes a run, and a decision word (approve, back, override, accept, pause, restart and the like) makes Claude ask
// the `Temper gate` question, where the person decides with a click (ADR 0012).

export const RESERVED = ['status', 'timeline', 'help', 'report', 'mode', 'enforcement', 'pane'] as const

export type Reserved = (typeof RESERVED)[number]

export const isReserved = (w: string): w is Reserved => (RESERVED as readonly string[]).includes(w)

export type Parsed = { word: Reserved }

// null when the text is not one word the mod answers, alone (a feature description, a decision word, a word with text
// after it, or nothing): a word is a word only in its documented form (commands/temper.md, Arguments).
export function parseArgs(args: string): Parsed | null {
  const word = args.trim().toLowerCase()
  return isReserved(word) ? { word } : null
}

export const HELP = [
  'Temper subcommands (type them after /temper:temper):',
  '  status               show where the run is',
  '  timeline             list your decisions in this run',
  '  report               show the run report (with no run active, the last one kept)',
  '  pane                 open or close the Temper pane (full mode)',
  '  mode, enforcement    show what Temper shows and enforces (change both in /config)',
  '  draft <idea>         capture an idea as a draft intent.md, with no run',
  '  init                 set up this project: config, .temper and the commit gate',
  '  pack                 show the quality packs; pack enable guardrails or pack disable guardrails prints the hooks',
  'Each word above counts only alone (draft takes the idea, pack the two forms shown).',
  'You decide in the Temper gate question: approve the plan and the run goes on to the commit, or ask at every stage.',
  'Any other text after /temper:temper is a request: a feature description. It starts or resumes a run. With no text it takes the run up again.',
].join('\n')
