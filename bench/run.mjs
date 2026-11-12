#!/usr/bin/env node
// One benchmark run: one task, one arm, one repetition.
//
//   node bench/run.mjs --task login-lockout --arm temper --rep 1 [--model M] [--task-model M] [--config-yaml TEXT] [--task-dir DIR] [--timeout-min 60] [--out DIR]
//
// Arms (the task text is the same, word for word, in every arm):
//   vanilla  Claude Code with the task as the prompt. No plugin, no extra words.
//   careful  The strong baseline: the task plus the instructions a careful developer would type
//            (explore, plan, tests first, run the suite). No plugin.
//   temper   `/temper:temper <task>` for a feature, `/temper:fix <task>` for a bug (meta.json kind "bug"),
//            with this repository loaded as a plugin.
//
// Every arm runs with no user or project settings (settingSources: []), so nothing installed on this
// machine leaks in, in the same throwaway git repository built from the task's repo/ folder, and with
// the same simulated person (person.mjs) answering any AskUserQuestion. Permissions are bypassed: the
// folder is a scratch copy. The run writes, under the out folder:
//   transcript.jsonl   every SDK message
//   person.jsonl       every question and the answer given
//   run.json           arm, task, rep, model, cost, time, turns, how it ended
//   work/              the repository as the arm left it (grade.py reads it)
// The out folder defaults to $TEMPER_BENCH_RESULTS/<task>__<arm>__<rep>, else ~/temper-bench-results/...
// It is never part of CI: it costs real model calls. Requires `npm install` in bench once.
import { query } from "@anthropic-ai/claude-agent-sdk";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";
import { answer, choose, typedAnswer } from "./person.mjs";
import { answerQuestion, replyToMessage } from "./person_llm.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN = path.resolve(HERE, "..");
const TEMPER = path.join(PLUGIN, "scripts", "temper");
// Results live outside the plugin folder: Temper's CLI refuses to run a project inside its own plugin.
export const RESULTS = process.env.TEMPER_BENCH_RESULTS || path.join(os.homedir(), "temper-bench-results");

const CAREFUL = `

Work the way a careful senior developer would: first read the relevant code and write a short plan, \
then write failing tests for the required behaviour, then implement, then run the whole test suite and \
fix anything that fails. Wire the change into the application so it is actually used, and do not add \
anything the task does not ask for.`;

// careful-ask: the careful words plus the one line a person who knows to ask for questions would add.
const ASK = `

If the request leaves something important unclear, ask me before you build it.`;

function args() {
  const a = { rep: "1", "timeout-min": "60", out: "" };
  const v = process.argv.slice(2);
  for (let i = 0; i < v.length; i++) if (v[i].startsWith("--")) a[v[i].slice(2)] = v[++i];
  if (!a.task || !["vanilla", "careful", "careful-ask", "temper"].includes(a.arm)) {
    console.error("usage: run.mjs --task ID --arm vanilla|careful|careful-ask|temper [--rep N] [--model M] [--task-model M] [--config-yaml TEXT] [--task-dir DIR] [--timeout-min N] [--out DIR]");
    process.exit(2);
  }
  return a;
}

const sh = (cmd, argv, cwd) => execFileSync(cmd, argv, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

function seed(taskDir, work) {
  fs.rmSync(work, { recursive: true, force: true });
  fs.cpSync(path.join(taskDir, "repo"), work, { recursive: true });
  sh("git", ["init", "-q", "."], work);
  sh("git", ["checkout", "-q", "-B", "main"], work);
  sh("git", ["config", "user.email", "bench@example.com"], work);
  sh("git", ["config", "user.name", "Bench Person"], work);
  sh("git", ["add", "-A"], work);
  sh("git", ["commit", "-qm", "base"], work);
  return sh("git", ["rev-parse", "HEAD"], work).trim();
}

// The moves of the options Temper's CLI offers right now (label -> move), so person.mjs answers a gate
// by what it does. Empty outside a Temper run.
function temperMoves(work) {
  try {
    const n = JSON.parse(sh(TEMPER, ["next", "--json"], work));
    const m = {};
    for (const o of [...(n.ask?.options || []), ...(n.ask?.more?.options || []), ...(n.context_check?.options || [])]) {
      if (o && o.label) m[o.label] = o.move ?? null;
    }
    return { moves: m, action: n.action, stage: n.stage ?? n.run?.stage ?? null };
  } catch {
    return { moves: {}, action: "unknown", stage: null };
  }
}

function copySessionLog(sessionId, dest) {
  if (!sessionId) return;
  const projects = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude"), "projects");
  try {
    for (const p of fs.readdirSync(projects)) {
      const log = path.join(projects, p, `${sessionId}.jsonl`);
      if (!fs.existsSync(log)) continue;
      fs.mkdirSync(dest, { recursive: true });
      fs.copyFileSync(log, path.join(dest, "main.jsonl"));
      const subs = path.join(projects, p, sessionId, "subagents");
      if (fs.existsSync(subs)) fs.cpSync(subs, path.join(dest, "subagents"), { recursive: true });
      return;
    }
  } catch (e) {
    console.error(`session log not copied: ${e?.message || e}`);
  }
}

async function main() {
  const a = args();
  const taskDir = a["task-dir"] ? path.resolve(a["task-dir"]) : path.join(HERE, "tasks", a.task);
  const taskText = fs.readFileSync(path.join(taskDir, "task.md"), "utf8").trim();
  // A bug task goes through Temper's bug flow (/temper:fix); a feature through the whole pipeline.
  const meta = JSON.parse(fs.readFileSync(path.join(taskDir, "meta.json"), "utf8"));
  // meta.command: a task that starts at a door (a prepared plan entered with /temper:build) names it
  const temperCmd = meta.command || (meta.kind === "bug" ? "/temper:fix" : "/temper:temper");
  const out = path.resolve(a.out || path.join(RESULTS, `${a.task}__${a.arm}__${a.rep}`));
  fs.mkdirSync(out, { recursive: true });
  const work = path.join(out, "work");
  // --task-model M: the project's config pins the Build task agents' model (an explicit task-model wins over every default),
  // committed with the base, so a Haiku and a Sonnet arm differ in that one line
  // --config-yaml TEXT: more lines for that config (\n for a new line), e.g. "plan:\n  fresh-review: always"
  const pinned = a["task-model"] || a["config-yaml"];
  if (pinned) {
    seed(taskDir, work);
    fs.mkdirSync(path.join(work, ".claude"), { recursive: true });
    const cfg = fs.readFileSync(path.join(PLUGIN, "templates", "temper.config.default"), "utf8") +
      (a["task-model"] ? `\nbuild:\n  grouped:\n    task-model: ${a["task-model"]}\n` : "") +
      (a["config-yaml"] ? `\n${a["config-yaml"].replace(/\\n/g, "\n")}\n` : "");
    fs.writeFileSync(path.join(work, ".claude", "temper.config"), cfg);
    sh("git", ["add", "-A"], work);
    sh("git", ["commit", "-qm", "base: the task model"], work);
  }
  const base = pinned ? sh("git", ["rev-parse", "HEAD"], work).trim() : seed(taskDir, work);
  const tx = fs.createWriteStream(path.join(out, "transcript.jsonl"));
  const px = fs.createWriteStream(path.join(out, "person.jsonl"));

  const prompt = a.arm === "temper" ? `${temperCmd} ${taskText}` : a.arm === "careful" ? taskText + CAREFUL
    : a.arm === "careful-ask" ? taskText + CAREFUL + ASK : taskText;
  // A vague task has a brief.md: its questions go to the product owner (person_llm.mjs), and a session that ends
  // waiting for an answer gets one.
  const briefPath = path.join(taskDir, "brief.md");
  const brief = fs.existsSync(briefPath) ? fs.readFileSync(briefPath, "utf8").trim() : null;
  const elicited = new Set();
  let personCost = 0;
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), Number(a["timeout-min"]) * 60_000);
  const t0 = Date.now();
  let questions = 0;

  const options = {
    cwd: work,
    abortController: abort,
    settingSources: [],
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    systemPrompt: { type: "preset", preset: "claude_code" },
    plugins: a.arm === "temper" ? [{ type: "local", path: PLUGIN }] : [],
    env: { ...process.env, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1" },
    ...(a.model ? { model: a.model } : {}),
    canUseTool: async (toolName, input) => {
      if (toolName !== "AskUserQuestion") return { behavior: "allow", updatedInput: input };
      questions++;
      if (questions > 60) return { behavior: "deny", message: "The person has left: too many questions.", interrupt: true };
      const ctx = a.arm === "temper" ? temperMoves(work) : { moves: {}, action: null, stage: null };
      if (!brief) {
        const { updatedInput, log } = answer(input, ctx.moves);
        for (const l of log) px.write(JSON.stringify({ t: Date.now() - t0, stage: ctx.stage, ...l }) + "\n");
        return { behavior: "allow", updatedInput };
      }
      // Vague task: a Temper gate (its options are the CLI's) and a request for a typed name keep the fixed
      // policy; every other question goes to the product owner.
      const answers = {};
      for (const q of input.questions || []) {
        const opts = q.options || [];
        // A Temper gate (its options are the CLI's), and a gate's reason follow-up ("... What is the reason?", its options the
        // CLI's suggested reasons), are the fixed policy's: the product owner knows the product, not the run's mechanics.
        const gate = opts.length > 0 && (opts.every((o) => o.label in ctx.moves) || /What is the reason\?$/.test(`${q.question}`));
        let ans, used = [], who = "policy";
        if (gate) ans = choose(q, ctx.moves);
        else if (/\bname\b/i.test(`${q.question}`) && /\b(type|other)\b/i.test(`${q.question} ${opts.map((o) => o.label).join(" ")}`)) ans = typedAnswer(q);
        else {
          const r = await answerQuestion({ ticket: taskText, brief, question: q.question, options: opts });
          ans = r.answer; used = r.used; personCost += r.cost; who = "owner";
          used.forEach((u) => elicited.add(u));
        }
        answers[q.question] = ans;
        px.write(JSON.stringify({ t: Date.now() - t0, stage: ctx.stage, who, header: q.header, question: q.question,
          options: opts.map((o) => o.label), answer: ans, used }) + "\n");
      }
      return { behavior: "allow", updatedInput: { ...input, answers } };
    },
  };

  const results = [];
  let sessionId = null;
  let ended = "done";
  // Temper can end a turn before the run is over (an agent in the background, a stop it asks for). A
  // person would type to go on, so the harness resumes the session with the same command, at most 5 times.
  // A vague task: when a session ends with a message that waits for the person (questions asked as text), the
  // product owner answers it and the session goes on, at most 3 times.
  const MAX_TURNS = a.arm === "temper" ? 6 : brief ? 4 : 1;
  let replies = 0;
  try {
    let p = prompt;
    for (let turn = 0; turn < MAX_TURNS; turn++) {
      let lastText = "";
      for await (const m of query({ prompt: p, options: { ...options, ...(sessionId ? { resume: sessionId } : {}) } })) {
        tx.write(JSON.stringify(m) + "\n");
        if (m.session_id) sessionId = m.session_id;
        if (m.type === "result") results.push(m);
        if (m.type === "assistant" && !m.parent_tool_use_id) {
          const t = (m.message?.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
          if (t) lastText = t;
        }
      }
      if (brief && lastText && replies < 3) {
        const r = await replyToMessage({ ticket: taskText, brief, message: lastText });
        personCost += r.cost;
        if (r.answer.trim().toUpperCase() !== "DONE") {
          replies++;
          r.used.forEach((u) => elicited.add(u));
          px.write(JSON.stringify({ t: Date.now() - t0, who: "owner", question: lastText.slice(0, 2000), answer: r.answer, used: r.used, reply: true }) + "\n");
          p = r.answer;
          continue;
        }
      }
      if (a.arm !== "temper") break;
      const n = temperMoves(work);
      if (n.action === "none" || n.action === "unknown") break;
      p = temperCmd;
    }
  } catch (e) {
    ended = abort.signal.aborted ? "timeout" : `error: ${e?.message || e}`;
  } finally {
    clearTimeout(timer);
  }

  const sum = (k) => results.reduce((s, r) => s + (Number(r[k]) || 0), 0);
  // A resumed session's result carries the cost of the whole session so far (SDK 0.3.x), not of its own query: adding the
  // results up counted a resumed run twice or more. When every model's cost only grows from one result to the next, the
  // last result is the run's cost; otherwise (an SDK that reports each query alone) the results add up.
  const usageOf = (r) => Object.fromEntries(Object.entries(r.modelUsage || {}).map(([k, v]) => [k, Number(v?.costUSD) || 0]));
  const cumulative = results.length > 1 && results.every((r, i) => i === 0 || Object.entries(usageOf(results[i - 1])).every(([k, c]) => (usageOf(r)[k] ?? -1) >= c));
  const models = {};
  if (cumulative) Object.assign(models, usageOf(results.at(-1)));
  else for (const r of results) for (const [k, c] of Object.entries(usageOf(r))) models[k] = (models[k] || 0) + c;
  const totalCost = cumulative ? Number(results.at(-1).total_cost_usd) || 0 : sum("total_cost_usd");
  const run = {
    task: a.task, arm: a.arm, rep: Number(a.rep), base, ...(a["task-dir"] ? { task_dir: taskDir } : {}),
    model_requested: a.model || "default",
    models_cost_usd: models,
    cost_usd: Number(totalCost.toFixed(4)),
    cost_results: cumulative ? "last (cumulative)" : "sum",
    wall_s: Math.round((Date.now() - t0) / 1000),
    api_s: Math.round(sum("duration_api_ms") / 1000),
    turns: sum("num_turns"),
    sessions: results.length,
    questions,
    ...(brief ? { facts_total: (brief.match(/^\d+\./gm) || []).length, facts_elicited: [...elicited].sort((x, y) => x - y),
      owner_replies: replies, person_cost_usd: Number(personCost.toFixed(4)) } : {}),
    ended,
    last_subtype: results.at(-1)?.subtype ?? null,
    temper_action_at_end: a.arm === "temper" ? temperMoves(work).action : null,
  };
  fs.writeFileSync(path.join(out, "run.json"), JSON.stringify(run, null, 2) + "\n");
  // Claude Code's own log of the session and of each agent: its usage per request holds the true output tokens (the SDK
  // stream above records only the count at the first block). bench/loop.py prices the main session from it.
  copySessionLog(sessionId, path.join(out, "session"));
  tx.end(); px.end();
  console.log(JSON.stringify(run));
}

main().catch((e) => { console.error(e); process.exit(1); });
