#!/usr/bin/env python3
"""What a run's agents spent, read from Claude Code's own transcripts, and its cost at API list prices.

The total the Agent tool returns (`subagent_tokens`) is the size of the agent's context at its last call, not what it
was billed for: an agent of 19 calls whose last context held 114K tokens was billed for 1.65M (mostly cache reads).
Each agent's transcript (`<config>/projects/<project>/<session>/subagents/agent-<id>.jsonl`) records every call's usage:
input, the 5 minute and 1 hour cache writes, cache reads, output, the model that served it, its speed and its
inference geography. This sums them and prices them; the session's own transcript (`<session>.jsonl`) gives the main
conversation's calls the same way. Input and cache tokens are exact. A subagent's transcript records each reply before
it streams, so its output count is the reply's start: the reply's text gives a floor instead (`output_estimated`), and
its thinking, billed as output, is not counted, so its cost can be low. The main conversation's records are final.

  usage_cost.py agent <agent id>             one JSON line: the agent's calls summed (exit 1 when no transcript)
  usage_cost.py session <transcript> <since>  one JSON line: the main conversation's calls from <since> (ISO UTC)

Claude Code's transcript layout is not a documented interface: anything this cannot read is reported as not found,
and the caller falls back to the numbers the Agent tool gave.
"""
import datetime
import json
import os
import re
import sys

PRICES_AS_OF = "2026-10-14"
PRICES_SOURCE = "https://platform.claude.com/docs/en/about-claude/pricing"
# $ per million tokens, as the pricing page's model table gives them on PRICES_AS_OF:
# base input, 5 minute cache write, 1 hour cache write, cache hit, output.
PRICES = {
    "claude-fable-5-1": (10, 12.5, 20, 0.25, 50),
    "claude-mythos-5-1": (10, 12.5, 20, 0.25, 50),
    "claude-fable-5": (10, 12.5, 20, 1, 50),
    "claude-mythos-5": (10, 12.5, 20, 1, 50),
    "claude-opus-5-5": (4, 5, 8, 0.2, 20),
    "claude-opus-5": (5, 6.25, 10, 0.5, 25),
    "claude-opus-4-8": (5, 6.25, 10, 0.5, 25),
    "claude-opus-4-7": (5, 6.25, 10, 0.5, 25),
    "claude-opus-4-6": (5, 6.25, 10, 0.5, 25),
    "claude-opus-4-5": (5, 6.25, 10, 0.5, 25),
    "claude-opus-4-1": (15, 18.75, 30, 1.5, 75),
    "claude-opus-4": (15, 18.75, 30, 1.5, 75),
    "claude-sonnet-5-5": (2, 2.5, 4, 0.1, 10),
    "claude-sonnet-5": (2, 2.5, 4, 0.2, 10),
    "claude-sonnet-4-6": (3, 3.75, 6, 0.3, 15),
    "claude-sonnet-4-5": (3, 3.75, 6, 0.3, 15),
    "claude-sonnet-4": (3, 3.75, 6, 0.3, 15),
    "claude-haiku-5-5": (0.1, 0.125, 0.2, 0.01, 0.5),
    "claude-haiku-4-5": (1, 1.25, 2, 0.1, 5),
    "claude-3-5-haiku": (0.8, 1, 1.6, 0.08, 4),
}
# Claude Haiku 5.5 prices a request by its prompt (input, cache reads and cache writes): over 100,000 tokens, these.
LONG = {"claude-haiku-5-5": (100000, (0.5, 0.625, 1, 0.05, 2.5))}
# Fast mode: the page gives input and output at twice the standard price; the cache prices are taken at twice too.
FAST = {"claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"}
US_ONLY = 1.1               # inference_geo "us": every category
WEB_SEARCH = 10 / 1000.0    # $ per search


def base_id(model):
    """The price table's id of a transcript's model name: no provider prefix, version tag, date or context suffix."""
    m = str(model or "").strip().lower()
    m = re.sub(r"^(?:[a-z]+\.)?anthropic\.", "", m)     # anthropic.claude-... and us.anthropic.claude-...
    m = re.sub(r"\[[^\]]*\]$", "", m)                     # claude-opus-5-5[1m]
    m = re.sub(r"@.*$", "", m)                            # claude-opus-4-5@20251101
    m = re.sub(r"-v\d+(?::\d+)?$", "", m)                 # ...-v1:0
    m = re.sub(r"-\d{8}$", "", m)                         # ...-20250514
    return m


def call_cost(model, u):
    """The list price of one call, or None when its model has no price here."""
    mid = base_id(model)
    p = PRICES.get(mid)
    if p is None:
        return None
    cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else {}
    w5 = cc.get("ephemeral_5m_input_tokens")
    w1 = cc.get("ephemeral_1h_input_tokens") or 0
    if not isinstance(w5, int):
        w5 = max((u.get("cache_creation_input_tokens") or 0) - w1, 0)
    inp, read, out = u.get("input_tokens") or 0, u.get("cache_read_input_tokens") or 0, u.get("output_tokens") or 0
    if mid in LONG and inp + read + w5 + w1 > LONG[mid][0]:
        p = LONG[mid][1]
    cost = (inp * p[0] + w5 * p[1] + w1 * p[2] + read * p[3] + out * p[4]) / 1e6
    if str(u.get("speed") or "") == "fast" and mid in FAST:
        cost *= 2
    if str(u.get("inference_geo") or "").lower() == "us":
        cost *= US_ONLY
    stu = u.get("server_tool_use") if isinstance(u.get("server_tool_use"), dict) else {}
    return cost + (stu.get("web_search_requests") or 0) * WEB_SEARCH


def calls(path, main=False, since=""):
    """Each API call of a transcript once: Claude Code writes a record per content block of a message, each with the
    message's usage so far, so the largest value of each field is the call's own."""
    seen, order = {}, []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            m = d.get("message") if isinstance(d, dict) else None
            if not isinstance(m, dict) or m.get("role") != "assistant" or not isinstance(m.get("usage"), dict):
                continue
            if main and d.get("isSidechain"):
                continue
            ts = str(d.get("timestamp") or "")
            if since and ts[:19] < since[:19]:
                continue
            if str(m.get("model") or "").startswith("<"):   # Claude Code's own synthetic messages are no API call
                continue
            key = m.get("id") or d.get("requestId") or d.get("uuid") or len(order)
            if key not in seen:
                seen[key] = {"model": m.get("model"), "usage": {}, "first": ts, "last": ts, "chars": 0, "final": False}
                order.append(key)
            c = seen[key]
            c["last"] = ts or c["last"]
            c["final"] = c["final"] or bool(m.get("stop_reason"))
            for b in m.get("content") or []:
                if isinstance(b, dict):
                    c["chars"] += len(b.get("text") or "") + len(b.get("thinking") or "") + (len(json.dumps(b["input"])) if "input" in b else 0)
            for k, v in m["usage"].items():
                if isinstance(v, int) and not isinstance(v, bool):
                    c["usage"][k] = max(c["usage"].get(k, 0), v)
                elif isinstance(v, dict):
                    sub = c["usage"].setdefault(k, {})
                    for kk, vv in v.items():
                        if isinstance(vv, int) and not isinstance(vv, bool):
                            sub[kk] = max(sub.get(kk, 0), vv)
                elif v is not None:
                    c["usage"][k] = v
    out = [seen[k] for k in order]
    for c in out:
        # A record written before its reply streamed (no stop_reason: a subagent's transcript) holds the output count
        # of the reply's start; the reply's text, at about 4 characters a token, is the floor of its output.
        if not c["final"]:
            floor = (c["chars"] + 3) // 4
            if floor > c["usage"].get("output_tokens", 0):
                c["usage"]["output_tokens"] = floor
                c["estimated"] = True
    return out


def summary(cs):
    s = {"calls": 0, "input": 0, "cache_write": 0, "cache_read": 0, "output": 0, "tokens": 0, "cost": 0.0,
         "unpriced": [], "models": {}, "first": None, "last": None,
         "output_estimated": any(not c.get("final") for c in cs)}
    for c in cs:
        u, model = c["usage"], base_id(c["model"]) or "unknown"
        part = {"input": u.get("input_tokens") or 0, "cache_write": u.get("cache_creation_input_tokens") or 0,
                "cache_read": u.get("cache_read_input_tokens") or 0, "output": u.get("output_tokens") or 0}
        cost = call_cost(c["model"], u)
        mm = s["models"].setdefault(model, {"calls": 0, "tokens": 0, "cost": 0.0})
        s["calls"] += 1
        mm["calls"] += 1
        for k, v in part.items():
            s[k] += v
            s["tokens"] += v
            mm["tokens"] += v
        if cost is None:
            if model not in s["unpriced"]:
                s["unpriced"].append(model)
        else:
            s["cost"] += cost
            mm["cost"] += cost
        if c["first"]:
            s["first"] = min(s["first"] or c["first"], c["first"])
        if c["last"]:
            s["last"] = max(s["last"] or c["last"], c["last"])
    s["cost"] = round(s["cost"], 6)
    for mm in s["models"].values():
        mm["cost"] = round(mm["cost"], 6)
    s["ms"] = span_ms(s["first"], s["last"])
    return s


def span_ms(a, b):
    """Milliseconds from the first call's timestamp to the last one's (ISO UTC, as Claude Code writes them)."""
    def at(t):
        m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d+))?", t or "")
        if not m:
            raise ValueError(t)
        return datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").timestamp() + float("0." + (m.group(2) or "0"))
    try:
        return max(int(round((at(b) - at(a)) * 1000)), 0)
    except ValueError:
        return None


def config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def find_agent(agent):
    """The transcript of the agent Claude Code named `agent` (the newest when several sessions hold one)."""
    if not re.match(r"^[A-Za-z0-9_-]{6,64}$", agent or ""):
        return None
    hits, name = [], "agent-%s.jsonl" % agent
    for proj in subdirs(os.path.join(config_dir(), "projects")):
        for sess in subdirs(proj):
            h = os.path.join(sess, "subagents", name)
            if os.path.isfile(h) and not os.path.islink(h):
                hits.append(h)
    return max(hits, key=os.path.getmtime) if hits else None


def subdirs(path):
    try:
        return [e.path for e in os.scandir(path) if e.is_dir(follow_symlinks=False)]
    except OSError:
        return []


def main(argv):
    if len(argv) >= 2 and argv[0] == "agent":
        path = find_agent(argv[1])
        if not path:
            return 1
        try:
            s = summary(calls(path))
        except OSError:
            return 1
        if not s["calls"]:
            return 1
        s.update({"agent": argv[1], "path": path, "session": os.path.dirname(os.path.dirname(path)) + ".jsonl",
                  "served": sorted(s["models"]), "prices_as_of": PRICES_AS_OF})
        print(json.dumps(s, sort_keys=True))
        return 0
    if len(argv) >= 3 and argv[0] == "session":
        try:
            s = summary(calls(argv[1], main=True, since=argv[2]))
        except OSError:
            return 1
        s.update({"path": argv[1], "prices_as_of": PRICES_AS_OF})
        print(json.dumps(s, sort_keys=True))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
