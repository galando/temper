// The product owner of a vague task: a model that knows the task's private brief (brief.md, numbered facts) and
// answers a developer's questions from it, the same way in every arm. It answers only what is asked, so an arm
// learns a fact only by asking about it; a broad question ("any other rules?") gets every fact that answers it.
// Each answer reports which facts it revealed ("used"), so a run's elicitation is measured apart from its tests.
// It runs with no tools and no settings, one turn per answer, on BENCH_PERSON_MODEL (default Sonnet).
import { query } from "@anthropic-ai/claude-agent-sdk";
import os from "node:os";

const MODEL = process.env.BENCH_PERSON_MODEL || "claude-sonnet-5-5";

const SYSTEM = `You play the product owner who wrote a ticket. A developer is working on it and may ask you questions.
You know the numbered facts in your private brief.

Rules:
- Answer truthfully from the brief.
- Answer only what the question asks. Do not volunteer brief facts the question does not ask about.
- When a question asks broadly for the requirements, rules, constraints or edge cases of the work, share every brief
  fact that answers it.
- When the brief says nothing about what is asked, say you have no preference and the developer should use their
  judgment.
- Never mention the brief or its numbers; speak as the product owner, briefly.
- Reply with JSON only, nothing else: {"answer": "...", "used": [the numbers of the brief facts your answer reveals]}`;

function parse(text) {
  const m = `${text || ""}`.match(/\{[\s\S]*\}/);
  if (m) {
    try {
      const j = JSON.parse(m[0]);
      return { answer: `${j.answer ?? ""}`, used: Array.isArray(j.used) ? j.used.map(Number).filter(Number.isFinite) : [] };
    } catch {}
  }
  return { answer: `${text || ""}`.trim(), used: [] };
}

async function ask(prompt) {
  let text = "", cost = 0;
  for await (const m of query({ prompt, options: { model: MODEL, tools: [], settingSources: [], maxTurns: 1,
    systemPrompt: SYSTEM, cwd: os.tmpdir(), env: { ...process.env } } })) {
    if (m.type === "result") {
      text = m.result || text;
      cost += Number(m.total_cost_usd) || 0;
    }
  }
  return { ...parse(text), cost };
}

// A question from AskUserQuestion, with its options. The answer is an option's label exactly when one fits.
export async function answerQuestion({ ticket, brief, question, options }) {
  const opts = (options || []).map((o) => `- ${o.label}${o.description ? `: ${o.description}` : ""}`).join("\n");
  return ask(`The ticket:\n${ticket}\n\nYour private brief:\n${brief}\n\nThe developer asks:\n${question}\n\n` +
    (opts ? `They offer these options:\n${opts}\nIf one option fits your answer, put its label, exactly, as the answer. ` +
      `Otherwise write a short answer of your own.` : `Write a short answer.`));
}

// The developer's last message when a session ended. If it waits for an answer, the reply goes back to it.
export async function replyToMessage({ ticket, brief, message }) {
  return ask(`The ticket:\n${ticket}\n\nYour private brief:\n${brief}\n\nThe developer's last message:\n${message}\n\n` +
    `If this message asks you questions or waits for your decision before going on, answer them. If it does not wait ` +
    `for you (a summary of finished work, or assumptions stated without asking), reply with {"answer": "DONE", "used": []}.`);
}
