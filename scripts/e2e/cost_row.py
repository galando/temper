"""cost_row.py RESULT.json USAGE.json MODE RUN: one row of `live-smoke.sh cost`, from Claude Code's result (claude -p --output-format
json) and the run's .temper/usage.json (the reviewer's time: the plan stage's sonnet launches). Standard library only."""
import json
import sys

path, usage_path, mode, run = sys.argv[1:5]
try:
    lines = open(path).read().strip().splitlines()
    r = json.loads(lines[-1]) if lines else {}
except (OSError, ValueError):
    r = {}
u = r.get("usage") or {}
tokens_in = sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
try:
    rows = json.load(open(usage_path))
except (OSError, ValueError):
    rows = []
rows = rows if isinstance(rows, list) else []
rev = sum(int(x.get("ms") or 0) for x in rows if isinstance(x, dict) and x.get("stage") == "plan" and "sonnet" in str(x.get("model") or ""))
cost = r.get("total_cost_usd")
print("%-7s %-3s %9.0f %6s %12d %12d %10s %s" % (mode, run, (r.get("duration_ms") or 0) / 1000, r.get("num_turns", "?"), tokens_in,
      int(u.get("output_tokens") or 0), ("%.2f" % cost) if isinstance(cost, (int, float)) else "?", ("%.0f" % (rev / 1000)) if rev else "-"))
