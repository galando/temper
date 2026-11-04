#!/usr/bin/env node
// One benchmark run: one task, one arm, one repetition.
//
//   node scripts/bench/run.mjs --task login-lockout --arm temper --rep 1 [--model M] [--timeout-min 60] [--out DIR]
//
// Arms (the task text is the same, word for word, in every arm):
//   vanilla  Claude Code with the task as the prompt. No plugin, no extra words.
//   careful  The strong baseline: the task plus the instructions a careful developer would type
//            (explore, plan, tests first, run the suite). No plugin.
//   temper   `/temper:temper <task>` with this repository loaded as a plugin.
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
// It is never part of CI: it costs real model calls. Requires `npm install` in scripts/bench once.
import { query } from "@anthropic-ai/claude-agent-sdk";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";
import { answer } from "./person.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN = path.resolve(HERE, "..", "..");
const TEMPER = path.join(PLUGIN, "scripts", "temper");
// Results live outside the plugin folder: Temper's CLI refuses to run a project inside its own plugin.
export const RESULTS = process.env.TEMPER_BENCH_RESULTS || path.join(os.homedir(), "temper-bench-results");

const CAREFUL = `

Work the way a careful senior developer would: first read the relevant code and write a short plan, \
then write failing tests for the required behaviour, then implement, then run the whole test suite and \
fix anything that fails. Wire the change into the application so it is actually used, and do not add \
anything the task does not ask for.`;

function args() {
  const a = { rep: "1", "timeout-min": "60", out: "" };
  const v = process.argv.slice(2);
  for (let i = 0; i < v.length; i++) if (v[i].startsWith("--")) a[v[i].slice(2)] = v[++i];
  if (!a.task || !["vanilla", "careful", "temper"].includes(a.arm)) {
    console.error("usage: run.mjs --task ID --arm vanilla|careful|temper [--rep N] [--model M] [--timeout-min N] [--out DIR]");
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

async function main() {
  const a = args();
  const taskDir = path.join(HERE, "tasks", a.task);
  const taskText = fs.readFileSync(path.join(taskDir, "task.md"), "utf8").trim();
  const out = path.resolve(a.out || path.join(RESULTS, `${a.task}__${a.arm}__${a.rep}`));
  fs.mkdirSync(out, { recursive: true });
  const work = path.join(out, "work");
  const base = seed(taskDir, work);
  const tx = fs.createWriteStream(path.join(out, "transcript.jsonl"));
  const px = fs.createWriteStream(path.join(out, "person.jsonl"));

  const prompt = a.arm === "temper" ? `/temper:temper ${taskText}` : a.arm === "careful" ? taskText + CAREFUL : taskText;
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
      const { updatedInput, log } = answer(input, ctx.moves);
      for (const l of log) px.write(JSON.stringify({ t: Date.now() - t0, stage: ctx.stage, ...l }) + "\n");
      return { behavior: "allow", updatedInput };
    },
  };

  const results = [];
  let sessionId = null;
  let ended = "done";
  // Temper can end a turn before the run is over (an agent in the background, a stop it asks for). A
  // person would type to go on, so the harness resumes the session with the same command, at most 5 times.
  const MAX_TURNS = a.arm === "temper" ? 6 : 1;
  try {
    for (let turn = 0; turn < MAX_TURNS; turn++) {
      const p = turn === 0 ? prompt : "/temper:temper";
      for await (const m of query({ prompt: p, options: { ...options, ...(sessionId ? { resume: sessionId } : {}) } })) {
        tx.write(JSON.stringify(m) + "\n");
        if (m.session_id) sessionId = m.session_id;
        if (m.type === "result") results.push(m);
      }
      if (a.arm !== "temper") break;
      const n = temperMoves(work);
      if (n.action === "none" || n.action === "unknown") break;
    }
  } catch (e) {
    ended = abort.signal.aborted ? "timeout" : `error: ${e?.message || e}`;
  } finally {
    clearTimeout(timer);
  }

  const sum = (k) => results.reduce((s, r) => s + (Number(r[k]) || 0), 0);
  const models = {};
  for (const r of results) for (const [k, v] of Object.entries(r.modelUsage || {})) models[k] = (models[k] || 0) + (Number(v?.costUSD) || 0);
  const run = {
    task: a.task, arm: a.arm, rep: Number(a.rep), base,
    model_requested: a.model || "default",
    models_cost_usd: models,
    cost_usd: Number(sum("total_cost_usd").toFixed(4)),
    wall_s: Math.round((Date.now() - t0) / 1000),
    api_s: Math.round(sum("duration_api_ms") / 1000),
    turns: sum("num_turns"),
    sessions: results.length,
    questions,
    ended,
    last_subtype: results.at(-1)?.subtype ?? null,
    temper_action_at_end: a.arm === "temper" ? temperMoves(work).action : null,
  };
  fs.writeFileSync(path.join(out, "run.json"), JSON.stringify(run, null, 2) + "\n");
  tx.end(); px.end();
  console.log(JSON.stringify(run));
}

main().catch((e) => { console.error(e); process.exit(1); });
