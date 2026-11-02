"""cost_row.py RESULT.json USAGE.json MODE RUN WALL_S: one row of `live-smoke.sh cost`. RESULT.json is what `claude -p --output-format
json` printed. A headless session can end a turn while an agent runs in the background and take the run up in a second turn,
so it can hold more than one result; the cost and the API time in the last one are the session's totals. WALL_S is the time
the shell measured. The reviewer's time comes from the run's .temper/usage.json (the plan stage's sonnet launches). Standard
library only."""
import json
import sys

path, usage_path, mode, run, wall = sys.argv[1:6]
results = []
try:
    for line in open(path):
        line = line.strip()
        if line.startswith("{"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") == "result":
                results.append(d)
except OSError:
    pass
last = results[-1] if results else {}
try:
    rows = json.load(open(usage_path))
except (OSError, ValueError):
    rows = []
rows = rows if isinstance(rows, list) else []
ms = lambda pick: sum(int(x.get("ms") or 0) for x in rows if isinstance(x, dict) and x.get("stage") == "plan" and pick(str(x.get("model") or "")))
cost = last.get("total_cost_usd")
print("%-7s %-3s %8s %8.0f %8.0f %8.0f %9s" % (mode, run, wall, (last.get("duration_api_ms") or 0) / 1000, ms(lambda m: "sonnet" not in m) / 1000,
      ms(lambda m: "sonnet" in m) / 1000, ("%.2f" % cost) if isinstance(cost, (int, float)) else "?"))
