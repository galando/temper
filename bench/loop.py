#!/usr/bin/env python3
"""loop.py RUN_DIR...: the main session of each run, turn by turn, from its transcript.

The main session is every assistant message with no parent_tool_use_id (Temper's agents carry one). For each run it
prints, and writes to RUN_DIR/loop.json:

  turns        model requests the main session made (one per assistant message id)
  context      tokens each request read (input, cache read and cache write), mean and total
  output       tokens it wrote
  cost         priced from the request's own usage (PRICES below), main session alone, and every request of the run
  by_tool      the turns, grouped by the tool the request called (a request that calls none: "text")
  growth       characters the main conversation gained, by source: each tool's results, the session's own text and
               tool inputs; what every later turn reads again
  agents       each agent launch: its type, model, prompt length and result length
  refused      the main session's calls the mod refused, with the first words of why

`--summary DIR...` prints one markdown row per run instead (hidden tests from grade.json, wall time from run.json).

It reads Claude Code's own logs of the session, which run.mjs copies to RUN_DIR/session (main.jsonl, and subagents/ with
one log per agent): each request's usage there holds its true output tokens. Without them it falls back to
transcript.jsonl, whose assistant messages carry only the output count of their first block, so output is understated
there.

Prices are per million tokens, from the Claude API's model table (2026-10). A 5 minute cache write is 1.25 times the
input price, a 1 hour write 2 times; a cache read is $0.20, $0.10 and $0.01. A Haiku request whose prompt is over
100,000 tokens is billed at 5 times every rate. `--check` compares the priced total with the SDK's own
costUSD per model (the last result of a resumed session holds the whole session's). Standard library only.
"""
import json
import os
import sys
from collections import defaultdict

PRICES = {  # input, output, cache read: the rates Claude Code's own cost (the SDK's costUSD) uses, checked to the cent
    "opus": (4.00, 20.00, 0.20),
    "sonnet": (2.00, 10.00, 0.10),
    "haiku": (0.10, 0.50, 0.01),
}


def family(model):
    for k in PRICES:
        if k in (model or ""):
            return k
    return None


LONG = 100_000   # a Haiku request whose prompt is longer is billed at 5 times every rate (checked against the SDK)


def rates(model, u):
    f = family(model)
    if f is None:
        return None
    pin, pout, pcr = PRICES[f]
    k = 5 if f == "haiku" and ctx_tokens(u) > LONG else 1
    return pin * k, pout * k, pcr * k


def price(model, u):
    r = rates(model, u)
    if r is None:
        return 0.0
    pin, pout, pcr = r
    cc = u.get("cache_creation") or {}
    w5 = int(cc.get("ephemeral_5m_input_tokens") or 0)
    w1 = int(cc.get("ephemeral_1h_input_tokens") or 0)
    rest = max(0, int(u.get("cache_creation_input_tokens") or 0) - w5 - w1)
    return (int(u.get("input_tokens") or 0) * pin + int(u.get("output_tokens") or 0) * pout
            + int(u.get("cache_read_input_tokens") or 0) * pcr + (w5 + rest) * pin * 1.25 + w1 * pin * 2) / 1e6


def split(model, u):
    """The cost of one request in three parts: reading the cache (and fresh input), writing it, and output."""
    r = rates(model, u)
    if r is None:
        return 0.0, 0.0, 0.0
    pin, pout, pcr = r
    cc = u.get("cache_creation") or {}
    w5 = int(cc.get("ephemeral_5m_input_tokens") or 0)
    w1 = int(cc.get("ephemeral_1h_input_tokens") or 0)
    rest = max(0, int(u.get("cache_creation_input_tokens") or 0) - w5 - w1)
    read = (int(u.get("input_tokens") or 0) * pin + int(u.get("cache_read_input_tokens") or 0) * pcr) / 1e6
    write = ((w5 + rest) * pin * 1.25 + w1 * pin * 2) / 1e6
    return read, write, int(u.get("output_tokens") or 0) * pout / 1e6


def ctx_tokens(u):
    return int(u.get("input_tokens") or 0) + int(u.get("cache_read_input_tokens") or 0) + int(u.get("cache_creation_input_tokens") or 0)


def size(content):
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        return sum(size(c.get("text", "")) if isinstance(c, dict) else 0 for c in content)
    return len(json.dumps(content))


def label(name, inp):
    if name == "Bash":
        cmd = (inp or {}).get("command", "")
        first = cmd.strip().splitlines()[0] if cmd.strip() else ""
        if "scripts/temper go" in first or first.endswith("temper go"):
            return "Bash: temper go"
        if "scripts/temper" in first:
            return "Bash: temper " + first.split("scripts/temper", 1)[1].split()[0] if first.split("scripts/temper", 1)[1].split() else "Bash: temper"
        return "Bash: other"
    return name


def session_lines(run_dir):
    """(main log lines, [(agent meta, agent log lines)]) from RUN_DIR/session, else None."""
    main = os.path.join(run_dir, "session", "main.jsonl")
    if not os.path.exists(main):
        return None
    subs = []
    sd = os.path.join(run_dir, "session", "subagents")
    for f in sorted(os.listdir(sd)) if os.path.isdir(sd) else []:
        if f.endswith(".jsonl"):
            meta_p = os.path.join(sd, f[:-len(".jsonl")] + ".meta.json")
            meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
            subs.append((meta, open(os.path.join(sd, f), encoding="utf-8", errors="replace").read().splitlines()))
    return open(main, encoding="utf-8", errors="replace").read().splitlines(), subs


def analyse(run_dir, check=False):
    path = os.path.join(run_dir, "transcript.jsonl")
    logs = session_lines(run_dir)
    if not os.path.exists(path) and logs is None:
        return None
    if logs is not None:
        lines = logs[0]
        for meta, sub_lines in logs[1]:
            for line in sub_lines:
                try:
                    m = json.loads(line)
                except ValueError:
                    continue
                if m.get("type") == "assistant":
                    m["parent_tool_use_id"] = meta.get("toolUseId") or "agent"
                    lines.append(json.dumps(m))
        lines += [l for l in open(path, encoding="utf-8", errors="replace") if '"type":"result"' in l] if os.path.exists(path) else []
    else:
        lines = open(path, encoding="utf-8", errors="replace")
    main, sub = {}, {}
    order = []
    tools = {}            # tool_use_id -> (name, input, main?)
    growth = defaultdict(int)
    agents = []
    refused = []           # the main session's calls the mod refused (9.9.0: its session guard and the stage rules)
    sdk = defaultdict(float)
    for line in lines:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        t = m.get("type")
        if t == "result":
            for model, u in (m.get("modelUsage") or {}).items():   # cumulative over a resumed session: keep the largest
                sdk[family(model) or model] = max(sdk[family(model) or model], float(u.get("costUSD") or 0))
            continue
        if t not in ("assistant", "user"):
            continue
        msg = m.get("message") or {}
        is_main = not m.get("parent_tool_use_id") and not m.get("isSidechain")
        if t == "assistant":
            mid = msg.get("id") or id(m)
            book = main if is_main else sub
            if mid not in book:
                order.append(mid) if is_main else None
                book[mid] = {"model": msg.get("model"), "usage": msg.get("usage") or {}, "tools": [], "text": 0}
            elif int((msg.get("usage") or {}).get("output_tokens") or 0) > int(book[mid]["usage"].get("output_tokens") or 0):
                book[mid]["usage"] = msg.get("usage")
            for c in msg.get("content") or []:
                if c.get("type") == "tool_use":
                    tools[c["id"]] = (c["name"], c.get("input") or {}, is_main)
                    if is_main:
                        book[mid]["tools"].append(label(c["name"], c.get("input")))
                        growth["session: tool inputs"] += len(json.dumps(c.get("input") or {}))
                        if c["name"] in ("Agent", "Task"):
                            agents.append({"id": c["id"], "type": (c.get("input") or {}).get("subagent_type"),
                                           "model": (c.get("input") or {}).get("model"),
                                           "prompt_chars": len((c.get("input") or {}).get("prompt", "")), "result_chars": 0})
                elif c.get("type") == "text" and is_main:
                    book[mid]["text"] += len(c.get("text", ""))
                    growth["session: text"] += len(c.get("text", ""))
        elif is_main:
            content = msg.get("content")
            if isinstance(content, str):
                growth["prompt"] += len(content)
                continue
            for c in content or []:
                if c.get("type") == "tool_result":
                    name, inp, _ = tools.get(c.get("tool_use_id"), ("?", {}, True))
                    n = size(c.get("content"))
                    text = c.get("content") if isinstance(c.get("content"), str) else json.dumps(c.get("content"))
                    if "Temper: " in text and c.get("is_error"):
                        refused.append({"tool": name, "why": text[text.find("Temper: "):][:160]})
                    growth["result: " + label(name, inp)] += n
                    for a in agents:
                        if a["id"] == c.get("tool_use_id"):
                            a["result_chars"] = n
                elif c.get("type") == "text":
                    growth["prompt"] += len(c.get("text", ""))
    turns = [main[k] for k in order]
    by_tool = defaultdict(lambda: {"turns": 0, "cost": 0.0})
    for x in turns:
        key = ", ".join(sorted(set(x["tools"]))) or "text"
        by_tool[key]["turns"] += 1
        by_tool[key]["cost"] += price(x["model"], x["usage"])
    ctx = [ctx_tokens(x["usage"]) for x in turns]
    priced_sub = defaultdict(float)
    for x in sub.values():
        priced_sub[family(x["model"]) or "?"] += price(x["model"], x["usage"])
    priced_main = sum(price(x["model"], x["usage"]) for x in turns)
    out = {
        "run": os.path.basename(run_dir.rstrip("/")),
        "source": "session logs" if logs is not None else "transcript (output understated)",
        "main_model": sorted({x["model"] for x in turns if x["model"]}),
        "turns": len(turns),
        "context_mean": round(sum(ctx) / len(ctx)) if ctx else 0,
        "context_max": max(ctx) if ctx else 0,
        "context_total": sum(ctx),
        "first_context": ctx[0] if ctx else 0,
        "cache_write_total": sum(int(x["usage"].get("cache_creation_input_tokens") or 0) for x in turns),
        "output_total": sum(int(x["usage"].get("output_tokens") or 0) for x in turns),
        "cost_main": round(priced_main, 4),
        "cost_main_split": dict(zip(("read", "write", "output"), (round(sum(split(x["model"], x["usage"])[i] for x in turns), 4) for i in range(3)))),
        "cost_agents_by_model": {k: round(v, 4) for k, v in sorted(priced_sub.items())},
        "cost_priced_total": round(priced_main + sum(priced_sub.values()), 4),
        "cost_sdk_by_model": {k: round(v, 4) for k, v in sorted(sdk.items())},
        "by_tool": {k: {"turns": v["turns"], "cost": round(v["cost"], 4)} for k, v in sorted(by_tool.items(), key=lambda kv: -kv[1]["turns"])},
        "growth_chars": dict(sorted(growth.items(), key=lambda kv: -kv[1])),
        "agents": [{k: v for k, v in a.items() if k != "id"} for a in agents],
        "refused": refused,
        "per_turn": [{"ctx": c, "out": int(x["usage"].get("output_tokens") or 0), "tools": x["tools"]} for c, x in zip(ctx, turns)],
    }
    return out


def summary(dirs):
    """One markdown row per run: the task, arm and rep from run.json, hidden tests from grade.json, and the loop numbers."""
    print("| Run | Hidden | Cost | Main | Main read/write/out | Turns | Context mean/max | Refused | Wall |")
    print("|---|---|---|---|---|---|---|---|---|")
    for d in dirs:
        r = analyse(d)
        if r is None:
            continue
        run = json.load(open(os.path.join(d, "run.json"))) if os.path.exists(os.path.join(d, "run.json")) else {}
        g = json.load(open(os.path.join(d, "grade.json"))) if os.path.exists(os.path.join(d, "grade.json")) else {}
        sp = r["cost_main_split"]
        print("| %s | %s | $%.2f | $%.2f | $%.2f/$%.2f/$%.2f | %d | %dk/%dk | %d | %s s |" % (
            r["run"], "%s/%s" % (g.get("hidden_pass", "?"), g.get("hidden_total", "?")), r["cost_priced_total"], r["cost_main"],
            sp["read"], sp["write"], sp["output"], r["turns"], r["context_mean"] // 1000, r["context_max"] // 1000,
            len(r["refused"]), run.get("wall_s", "?")))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if "--summary" in sys.argv:
        return summary(args)
    for d in args:
        r = analyse(d, check)
        if r is None:
            continue
        with open(os.path.join(d, "loop.json"), "w") as f:
            json.dump(r, f, indent=2)
            f.write("\n")
        print("%s: %d turns on %s, context mean %d (first %d, max %d), main $%.2f, run priced $%.2f" % (
            r["run"], r["turns"], "/".join(r["main_model"]), r["context_mean"], r["first_context"], r["context_max"],
            r["cost_main"], r["cost_priced_total"]))
        print("  main: read $%.2f, write $%.2f, output $%.2f; agents %s" % (r["cost_main_split"]["read"], r["cost_main_split"]["write"],
              r["cost_main_split"]["output"], r["cost_agents_by_model"]))
        if check:
            print("  sdk %s (%s)" % (r["cost_sdk_by_model"], r["source"]))
        if "--detail" in sys.argv:
            print("  by tool: " + "; ".join("%s %d ($%.2f)" % (k, v["turns"], v["cost"]) for k, v in r["by_tool"].items()))
            print("  growth (chars): " + "; ".join("%s %d" % (k, v) for k, v in r["growth_chars"].items()))
            for a in r["agents"]:
                print("  agent %s on %s: prompt %d, result %d chars" % (a["type"], a["model"], a["prompt_chars"], a["result_chars"]))


if __name__ == "__main__":
    main()
