// 9.9.0: the main session's own calls during a run (core/session.ts). It relays the CLI and the person: it runs the temper
// CLI and commands that only read, launches the agent the CLI names (type, model, prompt) and asks the question the CLI
// gives; the agents and the CLI write. Round 4 of the benchmark is the reason: a Haiku session edited the spec files and the
// locked acceptance tests and asked a question of its own; a Sonnet session once launched an agent on a cheaper model.
import { describe, expect, test } from 'claude-code/testing'

import type { RuleContext, RuleResult } from '../../hooks/temper-mod/core/rules'
import { SESSION_AGENT_DENY, SESSION_ASK_DENY, SESSION_WRITE_DENY, bashWhy, evaluateSession, factsOf, rememberAgents, skillChosen } from '../../hooks/temper-mod/core/session'
import type { SessionFacts } from '../../hooks/temper-mod/core/session'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import type { Stage } from '../../hooks/temper-mod/core/stages'
import { stateAt } from './helpers'

const CLI = '/plugin/scripts/temper'
const isDeny = (r: RuleResult): r is Extract<RuleResult, { deny: string }> => 'deny' in r

function ctx(stage: Stage | null, o: { allowed?: string[]; adhoc?: string } = {}): RuleContext {
  return {
    run: stage === null ? null : stateAt(stage, o.adhoc ? { adhocStage: o.adhoc } : {}),
    allowed: o.allowed ?? [],
    restart: false,
    drift: { added: [], allowOnce: [] },
  }
}

const PLAN_AGENT = { type: 'temper:temper-plan', model: 'opus', prompt: 'Follow /plugin/agents/plan.md exactly.\nSpec path: .temper/specs/pw.' }
const GATE = { header: 'Temper gate', question: 'Plan: the check passed. Continue to Design?', labels: ['Continue to Design (Recommended)', 'Grill Me', 'Save for later'] }
const facts = (o: Partial<SessionFacts> = {}): SessionFacts => ({ agents: [PLAN_AGENT], questions: [GATE], skill: false, ...o })

const call = (c: RuleContext, tool: string, input: Record<string, unknown>, f = facts()) => evaluateSession(c, f, { tool, input })
const bash = (c: RuleContext, command: string) => call(c, 'Bash', { command })
const ask = (q: { header: string; question: string; labels: string[] }, f = facts(), c = ctx('plan')) =>
  call(c, 'AskUserQuestion', { questions: [{ header: q.header, question: q.question, multiSelect: false, options: q.labels.map(label => ({ label, description: '' })) }] }, f)

describe('writes: the session writes no file during a run', () => {
  for (const tool of ['Write', 'Edit', 'MultiEdit', 'NotebookEdit']) {
    test(`${tool} of a spec file is refused at Plan, with what to do next`, () => {
      const r = call(ctx('plan'), tool, { file_path: '.temper/specs/pw/design.md', notebook_path: 'x.ipynb' })
      expect(isDeny(r) && r.deny).toBe(SESSION_WRITE_DENY)
      expect(SESSION_WRITE_DENY).toContain('Next: ')
    })
  }
  test('a code file at Review and a locked acceptance test at Check are refused too', () => {
    expect(isDeny(call(ctx('review'), 'Edit', { file_path: 'src/app.ts' }))).toBe(true)
    expect(isDeny(call(ctx('check'), 'Write', { file_path: '.temper/specs/pw/acceptance/test_a.py' }))).toBe(true)
  })
  test('no run active: nothing is refused here', () => expect(isDeny(call(ctx(null), 'Write', { file_path: 'src/app.ts' }))).toBe(false))
  test("a small change window the person opened at this stage lets the write through (the stage rules judge it)", () =>
    expect(isDeny(call(ctx('review', { adhoc: 'review' }), 'Edit', { file_path: 'src/app.ts' }))).toBe(false))
  test('a window opened at another stage does not', () => expect(isDeny(call(ctx('check', { adhoc: 'review' }), 'Edit', { file_path: 'src/app.ts' }))).toBe(true))
})

describe('Bash: the CLI and commands that only read', () => {
  const OK = [
    `${CLI} go`,
    `${CLI} usage add --stage plan --model opus --ms 1200\n${CLI} gate plan --brief\n${CLI} go`,
    `cd .temper/specs/pw && ${CLI} gate intent 2>&1 | grep -E 'x\\]|->'`,
    'cat .temper/specs/pw/intent.md',
    'ls .temper/specs 2>/dev/null; git status --short | head -20',
    'git log --oneline -5; git diff --stat; git branch --show-current',
    `${CLI} state set base_sha $(git rev-parse HEAD)`,
    `for f in ledger/*.py; do echo "== $f"; head -5 "$f"; done`,
    "sed -n 1,40p plan.md",
    `${CLI} spec commit 'docs(intent): accept pw'`,
  ]
  for (const c of OK) test(`allows: ${c.split('\n')[0]}`, () => expect(bashWhy(c)).toBe(null))
  const NO: Array<[string, string]> = [
    ["python3 - <<'E'\nopen('intent.md','w').write('x')\nE", 'python3'],
    ['cat > .temper/specs/pw/design.md <<E\nx\nE', 'writes'],
    ['echo x >> src/app.ts', 'writes'],
    ["sed -i 's/a/b/' .temper/specs/pw/tasks.md", 'writes'],
    ['git add -- src/app.ts', 'git add'],
    ['git commit -m x', 'git commit'],
    ['git checkout -- .temper/specs/pw/acceptance/test_a.py', 'git checkout'],
    ['cd .claude/worktrees/temper-pw-T1 && node build.js', 'node'],
    ['find . -name "*.pyc" -delete', 'find'],
    ['echo $(python3 -c "print(1)")', 'python3'],
    ['git branch new-branch', 'git branch'],
    ['xargs rm < list.txt', 'xargs'],
  ]
  for (const [c, why] of NO) {
    test(`refuses: ${c.split('\n')[0]}`, () => {
      const w = bashWhy(c)
      expect(w).not.toBe(null)
      expect(w).toContain(why)
      const r = bash(ctx('build'), c)
      expect(isDeny(r) && r.deny.startsWith('Temper: during a run this conversation runs the temper CLI')).toBe(true)
      expect(isDeny(r) && r.deny).toContain('Next: run temper go')
    })
  }
  test('a command the CLI wrote whole (a step, the calls of an answer) passes as written', () => {
    const switchCall = 't="$(mktemp -d)" && cp -R .temper/specs/pw/. "$t"/ && git checkout feature/pw'
    expect(isDeny(bash(ctx('intent', { allowed: [switchCall] }), switchCall))).toBe(false)
    expect(isDeny(bash(ctx('intent'), switchCall))).toBe(true)
  })
  test('at the commit, the pull request steps push and open it', () => {
    expect(isDeny(bash(ctx('commit'), 'git push -u origin feature/pw && gh pr create --draft --fill'))).toBe(false)
    expect(isDeny(bash(ctx('build'), 'git push -u origin feature/pw'))).toBe(true)
  })
  test('no run active: any command passes here', () => expect(isDeny(bash(ctx(null), "python3 -c 'print(1)'"))).toBe(false))
})

describe('Agent: only the agent the CLI names, as named', () => {
  const launch = (o: Record<string, unknown>) => call(ctx('plan'), 'Agent', { description: 'Plan stage', subagent_type: PLAN_AGENT.type, model: PLAN_AGENT.model, prompt: PLAN_AGENT.prompt, ...o })
  test('the CLI\'s agent, exactly as given, is launched', () => expect(isDeny(launch({}))).toBe(false))
  test('a full model id of the same family is the same model', () => expect(isDeny(launch({ model: 'claude-opus-5-5' }))).toBe(false))
  test('trailing spaces in the prompt do not count', () => expect(isDeny(launch({ prompt: PLAN_AGENT.prompt + '  \n' }))).toBe(false))
  test('the general purpose agent stands in with the same model and prompt', () => expect(isDeny(launch({ subagent_type: 'general-purpose' }))).toBe(false))
  test('a cheaper model than the CLI named is refused (round 3: the root cause agent on Sonnet)', () =>
    expect(isDeny(launch({ model: 'sonnet' })) && SESSION_AGENT_DENY).toBe(SESSION_AGENT_DENY))
  test('another agent type is refused', () => expect(isDeny(launch({ subagent_type: 'temper:temper-design' }))).toBe(true))
  test('a prompt of its own is refused', () => expect(isDeny(launch({ prompt: PLAN_AGENT.prompt + '\nAlso fix the tests.' }))).toBe(true))
  test('no agent in the CLI\'s action: none is launched', () => expect(isDeny(call(ctx('plan'), 'Agent', { subagent_type: PLAN_AGENT.type, model: 'opus', prompt: PLAN_AGENT.prompt }, facts({ agents: [] })))).toBe(true))
  test('Task, the older name of the tool, is held to the same rule', () => expect(isDeny(call(ctx('plan'), 'Task', { subagent_type: 'x', prompt: 'y' }))).toBe(true))
})

describe('AskUserQuestion: only the CLI\'s questions', () => {
  test('the gate question, exactly as given', () => expect(isDeny(ask(GATE))).toBe(false))
  test('a reworded question is refused', () => expect(isDeny(ask({ ...GATE, question: 'Approve the plan?' })) && SESSION_ASK_DENY).toBe(SESSION_ASK_DENY))
  test('an option dropped or renamed is refused', () => {
    expect(isDeny(ask({ ...GATE, labels: GATE.labels.slice(0, 2) }))).toBe(true)
    expect(isDeny(ask({ ...GATE, labels: ['Continue to Design', 'Grill Me', 'Save for later'] }))).toBe(true)
  })
  test('a question of its own is refused (round 4: one whose answer contradicted the request)', () =>
    expect(isDeny(ask({ header: 'Refund who', question: 'Who may refund?', labels: ['Admin', 'Clerk'] }))).toBe(true))
  test('a Scope drift question for a DRIFT row is the session\'s to build', () =>
    expect(isDeny(ask({ header: 'Scope drift', question: 'Outside the plan: src/x.ts\nWhy: y\nChange: z', labels: ['Add to plan', 'Revert', 'Allow once'] }))).toBe(false))
  test('while a skill the person chose runs, its own questions pass', () =>
    expect(isDeny(ask({ header: 'Grill', question: 'What breaks first?', labels: ['A', 'B'] }, facts({ skill: true })))).toBe(false))
  test('no run active: any question passes here', () => expect(isDeny(ask({ header: 'X', question: 'Y?', labels: ['a', 'b'] }, facts(), ctx(null)))).toBe(false))
})

describe('factsOf and skillChosen: what the view allows at this step', () => {
  const view = parseRunView(JSON.stringify({
    version: 1,
    run: { id: 'r1', step: 4, slug: 'pw', stage: 'intent', command: 'temper', spec: '.temper/specs/pw' },
    next: { action: 'ask', stage: 'intent', say: '', calls: [], steps: [], agents: [] },
    ask: {
      stage: 'intent', step: 4, run_id: 'r1',
      question: { header: 'Temper gate', question: 'Intent: the check passed. Continue?', options: [{ label: 'Continue', description: '' }, { label: 'Grill Me', description: '' }, { label: 'Override', description: '' }] },
      options: [
        { label: 'Continue', description: '', move: 'approve', calls: [] },
        { label: 'Grill Me', description: '', move: null, calls: [], do: 'Use the grill-me skill', skill: 'grill-me' },
        { label: 'Override', description: '', move: 'override', calls: [], reason: true, reason_question: { header: 'Temper gate', question: 'Override. What is the reason?', options: [{ label: 'Cancel', description: '' }] } },
      ],
    },
    blocking_asks: [{ question: { header: 'Question 1', question: 'Who may refund?', options: [{ label: 'Admin only', description: 'Recommended' }, { label: 'Carry forward', description: '' }] }, answer: 'x', carry: 'y' }],
    restart: { header: 'Temper resume', question: 'A run of pw is open at Intent. Start over?', options: [{ label: 'Start over', description: '' }, { label: 'Cancel', description: '' }] },
  }))
  const f = factsOf(view, false)
  test('the gate question, its reason question, the Blocking question and the resume question are all the CLI\'s', () => {
    expect(f.questions.map(q => q.question)).toEqual(['Intent: the check passed. Continue?', 'Override. What is the reason?', 'A run of pw is open at Intent. Start over?', 'Who may refund?'])
    expect(f.questions[3]?.labels).toEqual(['Admin only', 'Carry forward'])
  })
  test('an ask action names no agent', () => expect(f.agents).toEqual([]))
  test('the answer Grill Me is a skill; Continue is not', () => {
    expect(skillChosen(view, { result: { questions: [], answers: { 'Intent: the check passed. Continue?': 'Grill Me' } } })).toBe('grill-me')
    expect(skillChosen(view, { result: { questions: [], answers: { 'Intent: the check passed. Continue?': 'Continue' } } })).toBe(null)
  })
  test('a work action\'s agents are what may be launched', () => {
    const w = parseRunView(JSON.stringify({ version: 1, run: { id: 'r1', step: 5, slug: 'pw', stage: 'plan', command: 'temper', spec: 's' },
      next: { action: 'work', stage: 'plan', say: '', calls: [], steps: [], agents: [PLAN_AGENT] } }))
    expect(factsOf(w, false).agents).toEqual([PLAN_AGENT])
  })
})

describe('rememberAgents: a Build task\'s start changes the view before its agent is launched', () => {
  const TASK = { type: 'temper:temper-build-task', model: 'haiku', prompt: 'Follow /plugin/agents/build-task.md exactly.\nTask: 1.' }
  const at = (stage: string, action: string, agents: unknown[]) => parseRunView(JSON.stringify({ version: 1,
    run: { id: 'r1', step: 7, slug: 'pw', stage, command: 'temper', spec: 's' }, next: { action, stage, say: '', calls: [], steps: [], agents } }))
  test('the agent named before `task start` may still be launched while the run waits for it', () => {
    const seen = rememberAgents(rememberAgents(null, at('build', 'work', [TASK])), at('build', 'wait', []))
    const f = factsOf(at('build', 'wait', []), false, seen?.agents ?? [])
    expect(isDeny(call(ctx('build'), 'Agent', { subagent_type: TASK.type, model: 'haiku', prompt: TASK.prompt }, f))).toBe(false)
    expect(isDeny(call(ctx('build'), 'Agent', { subagent_type: TASK.type, model: 'sonnet', prompt: TASK.prompt }, f))).toBe(true)
  })
  test('a new stage, or another run, starts the list again', () => {
    const seen = rememberAgents(null, at('build', 'work', [TASK]))
    expect(rememberAgents(seen, at('review', 'ask', []))?.agents).toEqual([])
  })
})
