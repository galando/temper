#!/usr/bin/env python3
"""scorecard.py: the scorecard of bench rounds (9.8.5, WP05), from what run.mjs and grade.py leave in each run folder.

  python3 bench/scorecard.py [RESULTS_DIR...]                       scorecard.json in each folder, and the table printed
  python3 bench/scorecard.py RESULTS_DIR... --gate FILE [--arm NAME] [--before NAME] [--plain NAME]

A block is one arm of one results folder, named `<folder>/<arm>` (the folder's own name, the arm of run.json), so the
round before (on the base `10e965a`) and the round after, both run as the arm `temper`, stay apart, and the model test
of WP32 is a third block in a folder of its own. Each block gives, by task kind (bug, clear, vague) and in all: the
runs, the cost and the wall time (mean, median, minimum and maximum), the dialogs (the distinct dialog indices of
person.jsonl, else run.json's `questions`), the hand backs (a run with the mod whose main session took turns), the
hidden tests, the rules met on a vague task, the launches, seconds and dollars by agent type (bench/agentlog.py, the
type matched whole), the Reviews a run, the steps back to Plan the person chose (an answer whose move is `back` and
whose option goes back to Plan, the `to` of its person.jsonl line) and the blocked tasks (the distinct tasks an agent
marked with `temper task blocked N` and the CLI took). Two figures of the plan's quality (WP32, added by the owner):
`amendments`, the entries of the run's amendments record (`.temper/evidence/amendments.json`, WP25), also apart as
`amendments_by_rule` (kind `amend`) and `amendments_by_person` (kind `patch`), and `first_review_high`, the findings
of level high or critical the first Review launch recorded in the Review ledger (`.temper/evidence/review.json`), up to
its first `review completed` row. `state clear` deletes both files when a run ends, so run.mjs keeps every entry it saw
in the run's folder, under `records/`; the scorecard reads those, and what the work tree still holds. A run with no
such record (plain Claude Code, or a CLI that writes none, as the round before on `10e965a`) gives null, never 0.

Cost has one source: the SDK's own result messages, as run.json holds them (`cost_usd`). bench/loop.py prices the same
requests from Claude Code's logs and its `--check` compares the two; the scorecard reads run.json only.

--gate holds one block against the pass lines of part H of docs/plans/one-go/done.md and writes FILE (the release's is
docs/evidence/scorecard-9.8.5.json): `bug`, `clear` and `vague` (cost and time against the plain block, no clean run
handed back; 2 dialogs, and on a vague task one more for every four Blocking answers), `hidden` (a pass rate not below
the round before), `rules_met` (at least 95% on the vague tasks), `reviews` (the share of runs with two or more Reviews
at most half of the round before) and `steps_back` (the steps back to Plan and the blocked tasks, each not above the
round before: row D96). --arm names the block (default: the `temper` block of the last folder given, the round after);
--before the round before (default: the `temper` block of the first folder, when there are two or more); --plain the
plain Claude Code block (default: the `vanilla` block of the gated arm's folder, else of any folder). A line with no
data is `"pass": null`. Exit 1 when a line with data fails. Standard library only; no model call.
"""
import json
import math
import os
import re
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import agentlog  # noqa: E402  (the logs of the agents, the type matched whole)

KINDS = {"bug": ("cent-mismatch", "tenant-leak"), "clear": ("partial-payments", "ts-seat-holds"),
         "vague": ("vague-refunds", "vague-late-fees")}
LINES = {"bug": (1.5, 2.5), "clear": (2.0, 4.5), "vague": (3.0, 4.5)}   # cost and time, times the plain block
DIALOGS = 2
RULES_MET = 0.95


def read(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def jsonl(path):
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return out


def kind_of(task):
    return next((k for k, ts in KINDS.items() if task in ts), "other")


def main_turns(run):
    """Requests of the main session (assistant messages with no parent tool use), each message id once."""
    rows = jsonl(os.path.join(run, "session", "main.jsonl")) or jsonl(os.path.join(run, "transcript.jsonl"))
    seen = set()
    for m in rows:
        if m.get("type") == "assistant" and not m.get("parent_tool_use_id"):
            seen.add((m.get("message") or {}).get("id") or len(seen))
    return len(seen)


def blocked_tasks(run):
    """The distinct tasks the agents marked with `temper task blocked N` that the CLI took (its result no error)."""
    calls, done = {}, set()
    for meta in agentlog.metas(run):
        for m in agentlog.log_lines(meta):
            for c in (m.get("message") or {}).get("content") or []:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "tool_use" and c.get("name") == "Bash":
                    hit = re.search(r"\btask blocked (\d+)\b", str((c.get("input") or {}).get("command") or ""))
                    if hit:
                        calls[c.get("id")] = int(hit.group(1))
                elif c.get("type") == "tool_result" and c.get("tool_use_id") in calls and not c.get("is_error"):
                    text = c.get("content")
                    text = text if isinstance(text, str) else " ".join(
                        str(x.get("text", "")) for x in text or [] if isinstance(x, dict))
                    if "FAIL:" not in text:
                        done.add(calls[c["tool_use_id"]])
    return len(done)


def records(run, name):
    """The entries of a run record (a list in a JSON file), from the copy run.mjs kept and from the work tree, each
    once and in the order first seen; None when no such file exists. The amendments record also has the lists an
    approval moved to .temper/archive (state_ops._amendments_close)."""
    files = [os.path.join(run, "records", name), os.path.join(run, "work", ".temper", "evidence", name)]
    if name == "amendments.json":
        arch = os.path.join(run, "work", ".temper", "archive")
        files += sorted(os.path.join(arch, f) for f in (os.listdir(arch) if os.path.isdir(arch) else [])
                        if f.startswith("amendments-") and f.endswith(".json"))
    out, seen, found = [], set(), False
    for f in files:
        rows = read(f)
        if not isinstance(rows, list):
            continue
        found = True
        for r in rows:
            if not isinstance(r, dict):
                continue
            k = json.dumps([r.get(x) for x in ("n", "ts", "kind", "what", "claim", "severity", "cmd", "phase")])
            if k not in seen:
                seen.add(k)
                out.append(r)
    return out if found else None


def amendments(run):
    """(all, by rule, by the person) of the amendments record, or (None, None, None) when the run has none."""
    rows = records(run, "amendments.json")
    if rows is None:
        return None, None, None
    return (len(rows), sum(1 for r in rows if r.get("kind") == "amend"),
            sum(1 for r in rows if r.get("kind") == "patch"))


def first_review_high(run):
    """The findings of level high or critical before the first `review completed` row of the Review ledger; None when
    the run recorded no Review row."""
    rows = records(run, "review.json")
    if not rows:
        return None
    n = 0
    for r in rows:
        if r.get("claim") == "review completed":
            break
        if str(r.get("severity") or "").lower() in ("high", "critical"):
            n += 1
    return n


def one(run):
    r = read(os.path.join(run, "run.json"), {}) or {}
    g = read(os.path.join(run, "grade.json"), {}) or {}
    person = [p for p in jsonl(os.path.join(run, "person.jsonl")) if isinstance(p, dict)]
    idx = {p.get("dialog") for p in person if p.get("dialog") is not None and not p.get("reply")}
    by_q = {}
    for p in person:
        if p.get("qid"):
            by_q[p["qid"]] = by_q.get(p["qid"], 0) + 1
    ag = agentlog.agents(run)
    types = sorted({a["type"] for a in ag})
    turns = main_turns(run)
    am = amendments(run)
    return {
        "task": r.get("task"), "kind": kind_of(r.get("task")), "arm": r.get("arm"), "rep": r.get("rep"),
        "cost": r.get("cost_usd") or 0.0, "wall": r.get("wall_s") or 0,
        "dialogs": len(idx) if idx else (r.get("questions") or 0), "by_question": by_q,
        "blocking": by_q.get("intent.blocking", 0),
        "clean": r.get("ended") == "done", "mod": bool(r.get("mod")), "main_turns": turns,
        "handed_back": bool(r.get("mod")) and turns > 0,
        "hidden": (g.get("hidden_pass") or 0, g.get("hidden_total") or 0),
        "rules": (len(g.get("facts_met") or []), len(g.get("facts_tested") or [])) if "facts_tested" in g else None,
        "launches": {t: sum(1 for a in ag if a["type"] == t) for t in types},
        "agent_secs": {t: round(agentlog.subagent_secs(run, t)) for t in types},
        "agent_cost": {t: round(agentlog.kind_cost(run, t), 4) for t in types},
        "reviews": sum(1 for a in ag if a["type"] == "temper:temper-review"),
        "steps_back": sum(1 for p in person if p.get("move") == "back" and p.get("to") == "plan"),
        "blocked": blocked_tasks(run),
        "amendments": am[0], "amendments_by_rule": am[1], "amendments_by_person": am[2],
        "first_review_high": first_review_high(run),
        "plugin_commit": r.get("plugin_commit"), "plugin_version": r.get("plugin_version"),
    }


def spread(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return None
    return {"mean": round(st.mean(xs), 4), "median": round(st.median(xs), 4), "min": min(xs), "max": max(xs), "n": len(xs)}


def cell(runs):
    hp = sum(x["hidden"][0] for x in runs)
    ht = sum(x["hidden"][1] for x in runs)
    rules = [x["rules"] for x in runs if x["rules"]]
    launches = {}
    for x in runs:
        for t, n in x["launches"].items():
            launches[t] = launches.get(t, 0) + n
    return {
        "runs": len(runs), "cost": spread([x["cost"] for x in runs]), "wall": spread([x["wall"] for x in runs]),
        "dialogs": spread([x["dialogs"] for x in runs]),
        # D90 and D91 promise 2 dialogs; only D92, a vague task, one more for every four Blocking answers
        "dialogs_over": sum(1 for x in runs
                            if x["dialogs"] > DIALOGS + (math.ceil(x["blocking"] / 4) if x["kind"] == "vague" else 0)),
        "clean_handed_back": sum(1 for x in runs if x["clean"] and x["handed_back"]),
        "hidden_rate": round(hp / ht, 4) if ht else None,
        "rules_met": round(sum(a for a, _ in rules) / max(sum(b for _, b in rules), 1), 4) if rules else None,
        "launches": dict(sorted(launches.items())),
        "two_reviews_share": round(sum(1 for x in runs if x["reviews"] >= 2) / len(runs), 4) if runs else None,
        "steps_back": spread([x["steps_back"] for x in runs]),
        "blocked": spread([x["blocked"] for x in runs]),
        # WP32: the plan's quality; a run with no record is left out of the spread (null when none has one)
        "amendments": spread([x["amendments"] for x in runs]),
        "amendments_by_rule": spread([x["amendments_by_rule"] for x in runs]),
        "amendments_by_person": spread([x["amendments_by_person"] for x in runs]),
        "first_review_high": spread([x["first_review_high"] for x in runs]),
    }


def block(runs):
    out = {"all": cell(runs), "commits": sorted({x["plugin_commit"] for x in runs if x["plugin_commit"]})}
    for k in list(KINDS) + ["other"]:
        rs = [x for x in runs if x["kind"] == k]
        if rs:
            out[k] = cell(rs)
    return out


def scorecard(folders):
    blocks, per_folder = {}, {}
    for folder in folders:
        runs = [one(os.path.join(folder, d)) for d in sorted(os.listdir(folder))
                if os.path.isfile(os.path.join(folder, d, "run.json"))]
        name = os.path.basename(os.path.normpath(folder))
        mine = {}
        for arm in sorted({x["arm"] for x in runs if x["arm"]}):
            mine["%s/%s" % (name, arm)] = block([x for x in runs if x["arm"] == arm])
        per_folder[folder] = mine
        blocks.update(mine)
    return blocks, per_folder


def mean_n(s):
    """`mean (n)` of a spread, or `not measured` when no run has the record."""
    return "not measured" if not s else "%s (%d)" % (s["mean"], s["n"])


def mean_of(b, kind, key):
    c = (b or {}).get(kind) or {}
    return (c.get(key) or {}).get("mean")


def gate(blocks, arm, before, plain):
    a, b, p = blocks.get(arm), blocks.get(before) if before else None, blocks.get(plain) if plain else None
    out = {}
    for kind, (cost_line, time_line) in LINES.items():
        c = (a or {}).get(kind)
        if not c:
            out[kind] = {"pass": None, "why": "no %s runs in %s" % (kind, arm)}
            continue
        pc, pw = mean_of(p, kind, "cost"), mean_of(p, kind, "wall")
        cost = round(c["cost"]["mean"] / pc, 3) if pc else None
        time = round(c["wall"]["mean"] / pw, 3) if pw else None
        ok = [cost is not None and cost <= cost_line, time is not None and time <= time_line,
              c["dialogs_over"] == 0, c["clean_handed_back"] == 0]
        out[kind] = {"cost_ratio": cost, "cost_line": cost_line, "time_ratio": time, "time_line": time_line,
                     "dialogs": c["dialogs"], "runs_over_dialogs": c["dialogs_over"],
                     "clean_handed_back": c["clean_handed_back"],
                     "pass": all(ok) if cost is not None and time is not None else None}
    hid, hid_b = ((a or {}).get("all") or {}).get("hidden_rate"), ((b or {}).get("all") or {}).get("hidden_rate")
    out["hidden"] = {"rate": hid, "before": hid_b, "pass": (hid >= hid_b) if hid is not None and hid_b is not None else None}
    rm = ((a or {}).get("vague") or {}).get("rules_met")
    out["rules_met"] = {"rate": rm, "line": RULES_MET, "pass": (rm >= RULES_MET) if rm is not None else None}
    sh, sh_b = ((a or {}).get("all") or {}).get("two_reviews_share"), ((b or {}).get("all") or {}).get("two_reviews_share")
    out["reviews"] = {"share": sh, "before": sh_b, "pass": (sh <= sh_b / 2) if sh is not None and sh_b is not None else None}
    sb, sb_b = mean_of(a, "all", "steps_back"), mean_of(b, "all", "steps_back")
    bl, bl_b = mean_of(a, "all", "blocked"), mean_of(b, "all", "blocked")
    out["steps_back"] = {"mean": sb, "before": sb_b, "blocked": bl, "blocked_before": bl_b,
                         "pass": (sb <= sb_b and bl <= bl_b) if None not in (sb, sb_b, bl, bl_b) else None}
    return out


def pick(blocks, folders, want, arm, default_folder):
    if want:
        return want
    names = ["%s/%s" % (os.path.basename(os.path.normpath(f)), arm) for f in default_folder]
    return next((n for n in names if n in blocks), None)


def main(argv):
    folders, opts, i = [], {}, 0
    while i < len(argv):
        if argv[i] in ("--gate", "--arm", "--before", "--plain") and i + 1 < len(argv):
            opts[argv[i][2:]] = argv[i + 1]
            i += 2
            continue
        if argv[i].startswith("--"):
            print("scorecard.py: unknown flag %s (see the header of this file)" % argv[i], file=sys.stderr)
            return 2
        folders.append(argv[i])
        i += 1
    if not folders:
        folders = [os.environ.get("TEMPER_BENCH_RESULTS") or os.path.expanduser("~/temper-bench-results")]
    folders = [os.path.abspath(f) for f in folders]
    blocks, per_folder = scorecard(folders)
    for folder, mine in per_folder.items():
        with open(os.path.join(folder, "scorecard.json"), "w", encoding="utf-8") as f:
            json.dump({"version": 1, "blocks": mine}, f, indent=1, sort_keys=True)
            f.write("\n")
    print("| block | runs | cost mean (median, min to max) | wall s mean (median, min to max) | dialogs median | hidden "
          "| rules met | amendments mean (runs) | first Review High mean (runs) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name, b in sorted(blocks.items()):
        c = b["all"]
        print("| %s | %d | %.2f (%.2f, %.2f to %.2f) | %.0f (%.0f, %.0f to %.0f) | %s | %s | %s | %s | %s |" % (
            name, c["runs"], c["cost"]["mean"], c["cost"]["median"], c["cost"]["min"], c["cost"]["max"],
            c["wall"]["mean"], c["wall"]["median"], c["wall"]["min"], c["wall"]["max"], c["dialogs"]["median"],
            c["hidden_rate"], c["rules_met"], mean_n(c["amendments"]), mean_n(c["first_review_high"])))
    if "gate" not in opts:
        return 0
    arm = pick(blocks, folders, opts.get("arm"), "temper", folders[-1:])
    before = pick(blocks, folders, opts.get("before"), "temper", folders[:1] if len(folders) > 1 else [])
    plain = pick(blocks, folders, opts.get("plain"), "vanilla", folders[-1:] + folders)
    if arm not in blocks:
        print("scorecard.py: no block %s (the blocks: %s)" % (arm, ", ".join(sorted(blocks))), file=sys.stderr)
        return 2
    lines = gate(blocks, arm, before, plain)
    doc = {"version": 1, "arm": arm, "before": before, "plain": plain, "lines": lines, "blocks": blocks,
           "pass": all(v["pass"] is not False for v in lines.values())}
    with open(opts["gate"], "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    for k, v in lines.items():
        print("%-10s %s" % (k, {True: "pass", False: "MISS", None: "no data"}[v["pass"]]))
    return 0 if doc["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
