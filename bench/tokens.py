#!/usr/bin/env python3
"""tokens.py RUN_DIR...: the tokens each run used, from its transcript's result messages (Claude Code's own counts, per
model). Writes RUN_DIR/tokens.json and prints one line per run. Works for runs made before this script: the transcript
holds the counts. Standard library only.

  input        fresh input tokens (not from the cache)
  cache_read   input tokens read from the prompt cache (cheap, but each one is context the model reads)
  cache_write  input tokens written to the cache
  output       output tokens (thinking included)
  total        all four: how much text went through the models
"""
import json
import os
import sys

KEYS = (("input", "inputTokens"), ("cache_read", "cacheReadInputTokens"), ("cache_write", "cacheCreationInputTokens"),
        ("output", "outputTokens"))


def count(run_dir):
    by_model = {}
    path = os.path.join(run_dir, "transcript.jsonl")
    if not os.path.exists(path):
        return None
    for line in open(path, encoding="utf-8", errors="replace"):
        if '"type":"result"' not in line and '"type": "result"' not in line:
            continue
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("type") != "result":
            continue
        for model, u in (m.get("modelUsage") or {}).items():
            agg = by_model.setdefault(model, {k: 0 for k, _ in KEYS})
            for k, src in KEYS:
                agg[k] += int(u.get(src) or 0)
    total = {k: sum(v[k] for v in by_model.values()) for k, _ in KEYS}
    total["total"] = sum(total.values())
    return {"by_model": by_model, "total": total}


def main():
    for d in sys.argv[1:]:
        t = count(d)
        if t is None:
            continue
        with open(os.path.join(d, "tokens.json"), "w") as f:
            json.dump(t, f, indent=2)
            f.write("\n")
        print("%s total=%d output=%d cache_read=%d" % (os.path.basename(d.rstrip("/")), t["total"]["total"], t["total"]["output"], t["total"]["cache_read"]))


if __name__ == "__main__":
    main()
