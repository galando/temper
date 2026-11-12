"""compare_models.py RESULTS_DIR: the arms of Temper's Build task agents (run.mjs --task-model haiku | sonnet, out folders named
<task>__temper-<model>__<rep>), run by run and per task: hidden tests, cost (and the task agents' own cost, priced from their
logs with loop.py's prices), time, task retries and escalations, fix passes and Review rounds. Writes RESULTS_DIR/compare.json."""
import json
import os
import re
import statistics
import sys
from datetime import datetime

R = sys.argv[1]
sys_path_bench = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, sys_path_bench)
import loop  # noqa: E402  (bench/loop.py: the prices the SDK's own cost uses)


def listed(folder, suffix=""):
    """The entries of a folder whose name ends with suffix, as full paths, sorted (none when the folder is missing)."""
    try:
        return sorted(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith(suffix))
    except OSError:
        return []


def metas(run):
    return listed(os.path.join(run, "session", "subagents"), ".meta.json")


def kind_cost(run, kind):
    """Dollars of the subagents of one kind, priced request by request from their own logs (each message id once)."""
    total, seen = 0.0, set()
    for meta in metas(run):
        try:
            if kind not in json.load(open(meta)).get("agentType", ""):
                continue
        except ValueError:
            continue
        for line in open(meta.replace(".meta.json", ".jsonl")):
            try:
                m = json.loads(line)
            except ValueError:
                continue
            msg = m.get("message") or {}
            if m.get("type") != "assistant" or not msg.get("usage") or msg.get("id") in seen:
                continue
            seen.add(msg.get("id"))
            total += loop.price(msg.get("model", ""), msg["usage"])
    return total


def ts(x):
    try:
        return datetime.fromisoformat(x.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def agents(run):
    """Each agent of the run, from its subagent log's metadata (the mod's driver launches them, not the main transcript):
    its type, model and the prompt of its first message."""
    out = []
    for meta in metas(run):
        try:
            mt = json.load(open(meta))
        except ValueError:
            continue
        prompt = ""
        try:
            first = json.loads(open(meta.replace(".meta.json", ".jsonl")).readline())
            c = (first.get("message") or {}).get("content")
            prompt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict))
        except Exception:
            pass
        out.append({"type": mt.get("agentType", ""), "model": mt.get("model", ""), "prompt": prompt})
    return out


def subagent_secs(run, kind):
    """Seconds the logs of the subagents of one kind ran (first to last timestamp of each log), summed."""
    total = 0.0
    for meta in metas(run):
        try:
            mt = json.load(open(meta))
        except ValueError:
            continue
        if kind not in json.dumps(mt):
            continue
        times = []
        for line in open(meta.replace(".meta.json", ".jsonl")):
            try:
                t = ts(json.loads(line).get("timestamp", ""))
            except ValueError:
                t = None
            if t:
                times.append(t)
        if times:
            total += max(times) - min(times)
    return total


rows = []
for d in listed(R):
    if "__temper-" not in os.path.basename(d) or not os.path.isdir(d) or not os.path.isfile(os.path.join(d, "grade.json")):
        continue
    task, arm, rep = re.match(r".*/(.+)__temper-(\w+)__(\d+)$", d).groups()
    g = json.load(open(os.path.join(d, "grade.json")))
    r = json.load(open(os.path.join(d, "run.json")))
    ag = agents(d)
    tasks_md = [os.path.join(x, "tasks.md") for x in listed(os.path.join(d, "work", ".temper", "specs"))
                if os.path.isfile(os.path.join(x, "tasks.md"))]
    ntasks = len(re.findall(r"^### Task \d+", open(tasks_md[0]).read(), re.M)) if tasks_md else 0
    bt = [a for a in ag if a["type"].endswith("build-task")]
    chained = sum(len(re.findall(r"\d+", (re.search(r"Tasks?: ([\d, ]+)", a["prompt"]) or [None, ""])[1])) or 1 for a in bt)
    rows.append({
        "task": task, "arm": arm, "rep": int(rep),
        "hidden": "%s/%s" % (g.get("hidden_pass"), g.get("hidden_total")), "all": bool(g.get("hidden_all")),
        "suite": bool(g.get("suite_ok")), "outside": len(g.get("outside_expected") or []),
        "cost": r.get("cost_usd") or 0, "by_model": r.get("models_cost_usd") or {}, "wall": r.get("wall_s") or 0,
        "questions": r.get("questions"), "ended": r.get("ended"),
        "tasks": ntasks, "task_launches": len(bt), "task_runs": chained, "task_models": sorted({a["model"] for a in bt}),
        "build_secs": round(subagent_secs(d, "build-task")), "task_cost": kind_cost(d, "build-task"),
        "fix_passes": sum(1 for a in ag if a["type"].endswith("temper-build")),
        "escalated": sum(1 for a in bt if "sonnet" in a["model"]) if arm == "haiku" else 0,
        "no_coverage": any("recorded coverage 'none'" in l for l in open(os.path.join(d, "person.jsonl"))),
        "reviews": sum(1 for a in ag if a["type"].endswith("temper-review")),
    })

print("| task | arm | rep | hidden | suite | outside | cost $ | task agents $ | wall s | Build task s | tasks | task launches | task runs | escalated | fix passes | reviews | questions | coverage missing |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for x in rows:
    tm = x["task_cost"]
    print("| %s | %s | %d | %s | %s | %d | %.2f | %.3f | %d | %d | %d | %d | %d | %d | %d | %d | %s | %s |" % (
        x["task"], x["arm"], x["rep"], x["hidden"], "ok" if x["suite"] else "BROKEN", x["outside"], x["cost"], tm, x["wall"],
        x["build_secs"], x["tasks"], x["task_launches"], x["task_runs"], x["escalated"], x["fix_passes"], x["reviews"], x["questions"],
        "yes" if x["no_coverage"] else ""))

print("\nPer task and arm (means):")
print("| task | arm | runs | all hidden | hidden pass rate | cost $ | task agents $ | wall s | Build task s | task runs per task | fix passes | reviews |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for task in sorted({x["task"] for x in rows}):
    for arm in ("haiku", "sonnet"):
        xs = [x for x in rows if x["task"] == task and x["arm"] == arm]
        if not xs:
            continue
        rate = statistics.mean(int(x["hidden"].split("/")[0]) / max(int(x["hidden"].split("/")[1]), 1) for x in xs)
        print("| %s | %s | %d | %d/%d | %.0f%% | %.2f | %.3f | %.0f | %.0f | %.2f | %.1f | %.1f |" % (
            task, arm, len(xs), sum(x["all"] for x in xs), len(xs), 100 * rate, statistics.mean(x["cost"] for x in xs),
            statistics.mean(x["task_cost"] for x in xs),
            statistics.mean(x["wall"] for x in xs), statistics.mean(x["build_secs"] for x in xs),
            statistics.mean(x["task_runs"] / max(x["tasks"], 1) for x in xs), statistics.mean(x["fix_passes"] for x in xs),
            statistics.mean(x["reviews"] for x in xs)))
json.dump(rows, open(os.path.join(R, "compare.json"), "w"), indent=2)
