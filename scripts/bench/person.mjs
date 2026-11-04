// The simulated person: answers every AskUserQuestion the same way in every arm, from the options alone.
// It knows nothing beyond the task text, so it adds no information to any arm. It is a diligent person:
// it approves and continues, it fixes rather than skips, and it never overrides a failed gate.
//
// Policy, per question:
//   1. Drop options that stop, defer, skip, override or accept a defect.
//   2. Of the rest, take one marked "(Recommended)", else the first.
//   3. If every option was dropped, take the first option (the CLI lists its own default first).
// A typed answer (a name or a reason) is "Bench Person" / "benchmark run: the simulated person approves".

const REFUSE = /\b(stop|start over|cancel|override|skip|discard|later|abandon|not now|accept a finding|accept the finding|more options|revert)\b/i;

// moves: optional map label -> the CLI's `move` for that option (Temper's `temper next --json`), so a
// Temper gate is answered by what the option does, not by its wording. Moves a diligent person never
// picks: override, commitOverride, accept (a finding), pause, restart.
const REFUSE_MOVE = new Set(["override", "commitOverride", "accept", "pause", "restart"]);

export function choose(question, moves = {}) {
  const opts = Array.isArray(question.options) ? question.options : [];
  if (opts.length === 0) return typedAnswer(question);
  const kept = opts.filter((o) => !REFUSE.test(`${o.label}`) && !REFUSE_MOVE.has(moves[o.label]));
  const pool = kept.length ? kept : opts;
  const rec = pool.find((o) => /recommended/i.test(`${o.label}`));
  return (rec || pool[0]).label;
}

export function typedAnswer(question) {
  const q = `${question.question || ""}`;
  if (/\bname\b/i.test(q)) return "Bench Person";
  return "benchmark run: the simulated person approves";
}

// Build the AskUserQuestion input with answers filled, and a log line for the audit trail.
export function answer(input, moves = {}) {
  const qs = Array.isArray(input.questions) ? input.questions : [];
  const answers = {};
  const log = [];
  for (const q of qs) {
    const a = choose(q, moves);
    answers[q.question] = a;
    log.push({ header: q.header, question: q.question, options: (q.options || []).map((o) => o.label), answer: a });
  }
  return { updatedInput: { ...input, answers }, log };
}
