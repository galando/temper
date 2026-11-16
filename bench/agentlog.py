"""agentlog.py: the agents of a bench run, read from the copy of Claude Code's own logs in RUN/session (run.mjs writes it).

  metas(run)                    the .meta.json files of the run's subagents (each names agentType and model)
  agents(run)                   each agent: its type, model, the prompt of its first message and its last text
  kind_cost(run, kind)          dollars of the agents of one type, priced request by request (each message id once)
  subagent_secs(run, kind)      seconds the logs of the agents of one type ran, first to last time stamp, added up
  subagent_span(run, kind)      the same as one union of intervals (agents that ran at once count once); kind None: all

Moved out of compare_models.py (9.8.5, WP05), which runs at import. The agent type is matched whole: "temper:temper-build"
is not "temper:temper-build-task". Standard library only, with bench/loop.py's prices.
"""
import json
import os
from datetime import datetime

import loop  # bench/loop.py: the prices the SDK's own cost uses


def listed(folder, suffix=""):
    """The entries of a folder whose name ends with suffix, as full paths, sorted (none when the folder is missing)."""
    try:
        return sorted(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith(suffix))
    except OSError:
        return []


def metas(run):
    return listed(os.path.join(run, "session", "subagents"), ".meta.json")


def meta_of(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def log_lines(meta):
    try:
        with open(meta.replace(".meta.json", ".jsonl")) as f:
            for line in f:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def of_kind(meta, kind):
    return kind is None or meta_of(meta).get("agentType", "") == kind


def kind_cost(run, kind):
    """Dollars of the subagents of one type, priced request by request from their own logs (each message id once)."""
    total, seen = 0.0, set()
    for meta in metas(run):
        if not of_kind(meta, kind):
            continue
        for m in log_lines(meta):
            msg = m.get("message") or {}
            if m.get("type") != "assistant" or not msg.get("usage") or msg.get("id") in seen:
                continue
            seen.add(msg.get("id"))
            total += loop.price(msg.get("model", ""), msg["usage"])
    return total


def ts(x):
    try:
        return datetime.fromisoformat(str(x).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def agents(run):
    """Each agent of the run, from its subagent log's metadata (the mod's driver launches them, not the main transcript):
    its type, model, the prompt of its first message and its last text."""
    out = []
    for meta in metas(run):
        mt = meta_of(meta)
        prompt, last = "", ""
        for i, m in enumerate(log_lines(meta)):
            if i == 0:
                c = (m.get("message") or {}).get("content")
                prompt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict))
            if m.get("type") == "assistant":
                t = " ".join(x.get("text", "") for x in (m.get("message") or {}).get("content") or []
                             if isinstance(x, dict) and x.get("type") == "text").strip()
                last = t or last
        out.append({"type": mt.get("agentType", ""), "model": mt.get("model", ""), "prompt": prompt, "last": last})
    return out


def intervals(run, kind):
    out = []
    for meta in metas(run):
        if not of_kind(meta, kind):
            continue
        times = [t for t in (ts(m.get("timestamp", "")) for m in log_lines(meta)) if t]
        if times:
            out.append((min(times), max(times)))
    return out


def subagent_secs(run, kind):
    """Seconds the logs of the subagents of one type ran (first to last timestamp of each log), summed."""
    return sum(b - a for a, b in intervals(run, kind))


def subagent_span(run, kind=None):
    """Seconds covered by the union of the intervals of the subagents of one type (of all, with None)."""
    total, end = 0.0, None
    for a, b in sorted(intervals(run, kind)):
        if end is None or a > end:
            total += b - a
            end = b
        elif b > end:
            total += b - end
            end = b
    return total
