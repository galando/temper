"""run_summary.py: one line a finished run leaves in the project (9.8.5, WP05).

  python3 run_summary.py append TEMPER_DIR NOW     `temper state clear` calls it before it deletes the run's files: one
                                                   JSON line goes to TEMPER_DIR/runs.jsonl, which keeps its last 200
  run_summary.record_ask(TEMPER_DIR, view)         flow_view.write_view records the question a view asks

The line: {"v": 1, "at", "run", "slug", "command", "version", "mode", "ended", "asks": {"n", "by_stage", "by_kind"},
"steps_back": [{"from", "to", "n"}], "launches": {"by_stage"}, "seconds", "agent_seconds", "skips"}. It is made from the
files `state clear` deletes: build-state.json (the run), feedback-loops.json (the steps back), usage.json (the agents
recorded with their stage and time), overrides.json (the skips), gates.json (`ended` is `committed` when the commit gate's
verdict is PASS, else `cleared`) and asked.json. A launch is a usage row of an agent stage. A row of a task gate is no
launch unless it has a time: the gate of a task an earlier conversation left running, which counts for Build.

asked.json holds the questions the CLI asked, once each: when the flow writes a view whose `ask` is set, the key
`<run id>:<step>:<question id>` is recorded with the stage and the kind, so `next` run twice at one step counts one. A set
of Blocking questions counts one for every four (a dialog holds four). Follow up dialogs (More options, a reason, a name)
are asked by the carrier and are not seen here: the count is the CLI's questions. Neither file decides a gate row;
runs.jsonl survives `state init` and `state clear`. Every failure here is silent: the summary never stops a run.
Standard library only.
"""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

KEEP = 200
ASKED = "asked.json"
RUNS = "runs.jsonl"
PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, doc):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".asked.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def record_ask(temper_dir, doc):
    """Record the question a view asks, once for its run, step and id (and a Blocking set, one for every four)."""
    run = doc.get("run") if isinstance(doc.get("run"), dict) else None
    if run is None or run.get("id") is None:
        return
    found = []
    ask = doc.get("ask") if isinstance(doc.get("ask"), dict) else None
    if ask is not None and ask.get("id"):
        found.append((str(ask["id"]), str(ask.get("kind") or ""), 1))
    blocking = doc.get("blocking_asks") if isinstance(doc.get("blocking_asks"), list) else []
    if blocking:
        found.append(("intent.blocking", "blocking", (len(blocking) + 3) // 4))
    if not found:
        return
    path = os.path.join(temper_dir, ASKED)
    asked = read(path, {})
    if not isinstance(asked, dict):
        asked = {}
    changed = False
    for qid, kind, n in found:
        key = "%s:%s:%s" % (run.get("id"), run.get("step"), qid)
        if key not in asked:
            asked[key] = {"stage": run.get("stage"), "kind": kind, "n": n}
            changed = True
    if changed:
        write_json(path, asked)


def stamp(text):
    try:
        return datetime.strptime(str(text), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def summary(temper_dir, now):
    state = read(os.path.join(temper_dir, "build-state.json"), {})
    if not isinstance(state, dict) or not state:
        return None
    run_id = state.get("run_id")
    asked = read(os.path.join(temper_dir, ASKED), {})
    asks = {"n": 0, "by_stage": {}, "by_kind": {}}
    for key, a in sorted((asked if isinstance(asked, dict) else {}).items()):
        if not isinstance(a, dict) or not key.startswith("%s:" % run_id):
            continue
        n = int(a.get("n") or 1)
        asks["n"] += n
        st, kd = str(a.get("stage") or "none"), str(a.get("kind") or "none")
        asks["by_stage"][st] = asks["by_stage"].get(st, 0) + n
        asks["by_kind"][kd] = asks["by_kind"].get(kd, 0) + n
    loops = read(os.path.join(temper_dir, "feedback-loops.json"), {})
    back = {}
    # the loops still open and those closed: a step back of the run is in one of the two lists
    for l in ((loops.get("active_loops") or []) + (loops.get("history") or [])) if isinstance(loops, dict) else []:
        if isinstance(l, dict):
            k = (str(l.get("from_stage") or ""), str(l.get("to_stage") or ""))
            it = l.get("iteration")   # loop_step.py keeps one record a pair: its iteration is the steps it made
            back[k] = back.get(k, 0) + (it if isinstance(it, int) and not isinstance(it, bool) else 1)
    usage = read(os.path.join(temper_dir, "usage.json"), [])
    by_stage, ms = {}, 0
    for r in usage if isinstance(usage, list) else []:
        # A `task` row is a task gate's record: the agent gates its own tasks and its launch has its `build` row. Only
        # the gate of a task left running by an earlier conversation (`task gate N --ms`) records a launch with no row.
        if isinstance(r, dict) and (r.get("stage") != "task" or isinstance(r.get("ms"), int)):
            st = "build" if r.get("stage") == "task" else str(r.get("stage") or "unknown")
            by_stage[st] = by_stage.get(st, 0) + 1
            ms += r.get("ms") if isinstance(r.get("ms"), int) else 0
    gates = read(os.path.join(temper_dir, "gates.json"), {})
    commit = gates.get("commit") if isinstance(gates, dict) else None
    overrides = read(os.path.join(temper_dir, "overrides.json"), [])
    plugin = read(os.path.join(PLUGIN, ".claude-plugin", "plugin.json"), {})
    t0, t1 = stamp(state.get("started") or state.get("created")), stamp(now)
    spec = str(state.get("spec_path") or "")
    return {
        "v": 1, "at": now, "run": run_id, "slug": state.get("spec") or os.path.basename(spec.rstrip("/")) or None,
        "command": state.get("command") or "temper", "version": plugin.get("version") if isinstance(plugin, dict) else None,
        "mode": state.get("run_mode") or "interactive",
        "ended": "committed" if isinstance(commit, dict) and commit.get("verdict") == "PASS" else "cleared",
        "asks": asks,
        "steps_back": [{"from": f, "to": t, "n": n} for (f, t), n in sorted(back.items())],
        "launches": {"by_stage": dict(sorted(by_stage.items()))},
        "seconds": int((t1 - t0).total_seconds()) if t0 and t1 else None,
        "agent_seconds": ms // 1000,
        "skips": len(overrides) if isinstance(overrides, list) else 0,
    }


def append(temper_dir, now):
    line = summary(temper_dir, now)
    if line is None:
        return 0
    path = os.path.join(temper_dir, RUNS)
    try:
        with open(path, encoding="utf-8") as f:
            kept = [l for l in f.read().splitlines() if l.strip()]
    except OSError:
        kept = []
    kept = (kept + [json.dumps(line, sort_keys=True)])[-KEEP:]
    fd, tmp = tempfile.mkstemp(dir=temper_dir, prefix=".runs.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(kept) + "\n")
    os.replace(tmp, path)
    return 0


def main(argv):
    if len(argv) == 3 and argv[0] == "append":
        try:
            return append(argv[1], argv[2])
        except Exception:   # the summary never stops `state clear`
            return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
