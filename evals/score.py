#!/usr/bin/env python3
"""Scores one measurement run of a Temper fixture (evals/README.md).

  score.py hidden <fixture> <tree>
      Runs the fixture's hidden test against a copy of <tree>. Exit 0 when it passes (the
      defect is not there), 1 when it fails. The copy is thrown away; <tree> is never written.

  score.py run <fixture> <project> [--transcript FILE]... [--result FILE]... [--label TEXT]
               [--append RESULTS.md]
      Reads the run in <project> (.temper/evidence/review.json, .temper/gates.json,
      .temper/usage.json), the session transcripts (Claude Code's JSONL, for the gates asked
      and the moves made) and the `claude -p --output-format json` results (for unattended
      runs), and prints one JSON object. With --append, it also adds one row to RESULTS.md.

Standard library only. Nothing here decides a gate: it reads what the run left.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

EVALS = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(EVALS, "fixtures")

# A CLI call that moves the run or decides for the person: these need the person's answer
# first, unless the run is armed and the move is one the armed run makes by itself.
MOVE = re.compile(
    r"scripts/temper\s+(?:state\s+(?:advance|loop)\b|override\b|evidence\s+accept\b|group\s+reopen\b[^\n]*--accept-foreign)"
)
ARM = re.compile(r"scripts/temper\s+state\s+set\s+run_mode\s+autonomous\b")
SKIP_COPY = {".git", ".temper", ".claude", "__pycache__"}


def load_fixture(name):
    path = os.path.join(FIXTURES, name, "fixture.json")
    if not os.path.isfile(path):
        sys.exit("FAIL: no fixture named %r" % name)
    with open(path) as f:
        return json.load(f)


def hidden_passes(name, tree):
    """Copies tree, adds the hidden test, runs it. True when it passes."""
    fx = load_fixture(name)
    src = os.path.join(FIXTURES, name, fx["hidden"])
    work = tempfile.mkdtemp(prefix="temper-hidden-")
    try:
        dest = os.path.join(work, "tree")
        shutil.copytree(tree, dest, ignore=lambda d, names: [n for n in names if n in SKIP_COPY])
        shutil.copy(src, os.path.join(dest, "test_hidden_fixture.py"))
        proc = subprocess.run(
            [sys.executable, "-m", "unittest", "-q", "test_hidden_fixture"],
            cwd=dest,
            capture_output=True,
            text=True,
            timeout=120,
            env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
        )
        return proc.returncode == 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def matches_all(text, patterns):
    return bool(patterns) and all(re.search(p, text, re.I) for p in patterns)


def review_score(project, fx):
    rows = read_json(os.path.join(project, ".temper", "evidence", "review.json"), [])
    findings = [r for r in rows if isinstance(r, dict) and r.get("severity") and r.get("claim") != "review completed"]
    hits = [r for r in findings if matches_all(str(r.get("claim", "")), fx.get("review_anchors", []))]
    best = None
    order = ["critical", "high", "medium", "low"]
    for r in hits:
        sev = str(r.get("severity", "")).lower()
        if best is None or (sev in order and order.index(sev) < order.index(best)):
            best = sev
    return {
        "findings": len(findings),
        "flagged": bool(hits),
        "severity": best,
        "resolved": any(r.get("resolved") or r.get("resolved_by") or r.get("fixed_by") for r in hits),
        "claims": [str(r.get("claim", ""))[:200] for r in hits][:3],
    }


def check_score(project, fx):
    gates = read_json(os.path.join(project, ".temper", "gates.json"), {})
    check = gates.get("check") if isinstance(gates, dict) else None
    verdict = check.get("verdict") if isinstance(check, dict) else None
    reqs = check.get("requirements", []) if isinstance(check, dict) else []
    failed = [r for r in reqs if isinstance(r, dict) and not r.get("pass")]
    anchor = fx.get("check_anchor") or ""
    # A Check that never ran leaves every scenario untraced: it names the defect only when it
    # recorded a green test run of its own.
    ran = any(isinstance(r, dict) and r.get("name") == "tests pass" and r.get("pass") for r in reqs)
    named = [r for r in failed if ran and anchor and re.search(anchor, str(r.get("detail", "")), re.I)]
    return {
        "verdict": verdict,
        "ran": ran,
        "flagged": bool(named),
        "failed_rows": [str(r.get("name") or r.get("label") or "?") for r in failed],
    }


def transcript_score(paths):
    """Gates asked, moves made and whether each move followed a gate answer; cost and time."""
    asked, moves, unanswered, armed = 0, 0, [], False
    answered_since_move = False
    pending = {}
    cost = None
    first_ts = last_ts = None
    for path in paths:
        with open(path) as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                ts = e.get("timestamp")
                if ts:
                    first_ts = first_ts or ts
                    last_ts = ts
                if e.get("type") == "cost-state":
                    cost = e
                msg = e.get("message") if isinstance(e.get("message"), dict) else {}
                content = msg.get("content") if isinstance(msg.get("content"), list) else []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use":
                        name, data = block.get("name"), block.get("input") or {}
                        if name == "AskUserQuestion":
                            headers = [str(q.get("header", "")) for q in data.get("questions", []) if isinstance(q, dict)]
                            if any(h.strip().lower() == "temper gate" for h in headers):
                                pending[block.get("id")] = "gate"
                                asked += 1
                        elif name == "Bash":
                            command = str(data.get("command", ""))
                            if ARM.search(command):
                                armed = True
                            if MOVE.search(command):
                                pending[block.get("id")] = ("move", command)
                    elif block.get("type") == "tool_result":
                        what = pending.pop(block.get("tool_use_id"), None)
                        if what == "gate" and not block.get("is_error"):
                            answered_since_move = True
                        elif isinstance(what, tuple) and not block.get("is_error"):
                            moves += 1
                            if not answered_since_move and not armed:
                                unanswered.append(what[1].strip()[:160])
                            answered_since_move = False
    out = {"gates_asked": asked, "moves": moves, "moves_without_answer": len(unanswered), "unanswered": unanswered[:5], "armed": armed}
    if cost:
        out["cost_usd"] = cost.get("totalCostUSD")
        out["minutes"] = round((cost.get("totalDuration") or 0) / 60000.0, 1)
        out["api_minutes"] = round((cost.get("totalAPIDuration") or 0) / 60000.0, 1)
        out["tokens"] = model_tokens(cost.get("modelUsage") or {})
    elif first_ts and last_ts:
        a = datetime.datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
        b = datetime.datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
        out["minutes"] = round((b - a).total_seconds() / 60.0, 1)
    return out


def model_tokens(model_usage):
    total = {"input": 0, "cache_write": 0, "cache_read": 0, "output": 0}
    by_model = {}
    for model, u in model_usage.items():
        if not isinstance(u, dict):
            continue
        row = {
            "input": int(u.get("inputTokens") or 0),
            "cache_write": int(u.get("cacheCreationInputTokens") or 0),
            "cache_read": int(u.get("cacheReadInputTokens") or 0),
            "output": int(u.get("outputTokens") or 0),
        }
        by_model[model] = row
        for k in total:
            total[k] += row[k]
    total["by_model"] = by_model
    return total


def result_score(paths):
    """The `claude -p --output-format json` results of an unattended run, summed."""
    cost, ms, api_ms, turns = 0.0, 0, 0, 0
    usage = {}
    for path in paths:
        r = read_json(path, {})
        cost += float(r.get("total_cost_usd") or 0)
        ms += int(r.get("duration_ms") or 0)
        api_ms += int(r.get("duration_api_ms") or 0)
        turns += int(r.get("num_turns") or 0)
        for model, u in (r.get("modelUsage") or {}).items():
            acc = usage.setdefault(model, {})
            for k, v in u.items():
                if isinstance(v, (int, float)):
                    acc[k] = acc.get(k, 0) + v
    return {"cost_usd": round(cost, 4), "minutes": round(ms / 60000.0, 1), "api_minutes": round(api_ms / 60000.0, 1), "turns": turns, "tokens": model_tokens(usage)}


def git_head(path):
    try:
        return subprocess.run(["git", "-C", path, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def fmt_tokens(t):
    if not t:
        return "not recorded"
    return "%d in, %d cache write, %d cache read, %d out" % (t["input"], t["cache_write"], t["cache_read"], t["output"])


def yes(v):
    return "yes" if v else "no"


def row_for(s):
    gates = s.get("session", {})
    asked = "%s asked, %s moves, %s without an answer" % (gates.get("gates_asked", "n/a"), gates.get("moves", "n/a"), gates.get("moves_without_answer", "n/a")) if gates else "not measured"
    usage = s.get("session") or s.get("unattended") or {}
    cost = usage.get("cost_usd")
    return "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        s["date"],
        s["plugin_commit"] or "?",
        s["fixture"],
        s["label"] or "",
        yes(s["fixed_at_end"]),
        yes(s["review"]["flagged"]) + (" (%s)" % s["review"]["severity"] if s["review"]["severity"] else ""),
        "%s, %s" % (s["check"]["verdict"] or "no verdict", "names it" if s["check"]["flagged"] else "does not name it"),
        asked,
        fmt_tokens(usage.get("tokens")),
        "%.2f" % cost if isinstance(cost, (int, float)) else "n/a",
        usage.get("minutes", "n/a"),
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    h = sub.add_parser("hidden")
    h.add_argument("fixture")
    h.add_argument("tree")
    r = sub.add_parser("run")
    r.add_argument("fixture")
    r.add_argument("project")
    r.add_argument("--transcript", action="append", default=[])
    r.add_argument("--result", action="append", default=[])
    r.add_argument("--label", default="")
    r.add_argument("--append")
    a = ap.parse_args()

    if a.cmd == "hidden":
        ok = hidden_passes(a.fixture, a.tree)
        print("PASS: the hidden test passes" if ok else "FAIL: the hidden test fails")
        return 0 if ok else 1

    fx = load_fixture(a.fixture)
    s = {
        "date": datetime.date.today().isoformat(),
        "plugin_commit": git_head(os.path.dirname(EVALS)),
        "fixture": a.fixture,
        "kind": fx["kind"],
        "label": a.label,
        "fixed_at_end": hidden_passes(a.fixture, a.project),
        "review": review_score(a.project, fx),
        "check": check_score(a.project, fx),
        "usage_json": read_json(os.path.join(a.project, ".temper", "usage.json"), []),
    }
    if a.transcript:
        s["session"] = transcript_score(a.transcript)
    if a.result:
        s["unattended"] = result_score(a.result)
    print(json.dumps(s, indent=2))
    if a.append:
        with open(a.append, "a") as f:
            f.write(row_for(s) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
