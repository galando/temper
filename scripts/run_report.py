#!/usr/bin/env python3
"""run_report.py: the end of run report, as one page to share, made from .temper/view.json.

Usage:
  run_report.py render [--view .temper/view.json] [--root DIR] [--target file|artifact] [-o OUT]

The page shows what the run did: the stages with their verdicts, the person's skips and the
loops with their reasons; the plan's files by Build group; each Build task with its state,
model and retries; the Review findings; the Check markers with their failing lines; the
acceptance criteria with their evidence; time and tokens. It reads only view.json, the file
the temper CLI writes after every change (docs/flow.md), so it shows what the mod shows.

The default output is report.html in the run's spec folder ("-o -" prints it; any other -o is
a file name ending in .html). `--target artifact` emits the fragment shape the Artifact tool
expects, as plan_review.py does. Every value is escaped, so run text such as "</style>"
cannot break the page. Nothing is written inside this plugin's own folder (the rule of
plan_review.py). python3 stdlib only. No network.
"""
import argparse
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plan_review import output_refusal, to_artifact_fragment  # noqa: E402
from usage_cost import PRICES_AS_OF  # noqa: E402

TASK = {"waiting": ("○", "waiting", "muted"), "running": ("◐", "running", "info"), "red": ("●", "RED", "bad"),
        "green": ("●", "GREEN", "good"), "pass": ("✓", "PASS", "good"), "fail": ("✗", "FAIL", "bad"),
        "parked": ("⏸", "parked", "warn")}
MARK = {"passed": ("✓", "good"), "failed": ("✗", "bad"), "skipped": ("↷", "warn"), "here": ("●", "info"), "todo": ("○", "muted")}
MARKER = {"pass": ("✓", "good"), "fail": ("✗", "bad"), "info": ("•", "info"), "none": ("○", "muted")}

CSS = """
:root{--bg:#ffffff;--fg:#1d1d1f;--muted:#6b6b70;--line:#e3e3e8;--card:#f7f7f9;--good:#1f7a3a;--bad:#b42318;--warn:#9a6700;--info:#1c4fbf}
@media (prefers-color-scheme: dark){:root{--bg:#141416;--fg:#ececf0;--muted:#9a9aa3;--line:#2b2b31;--card:#1c1c20;--good:#5cc77d;--bad:#ff7b72;--warn:#e3b341;--info:#79a8ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:960px;margin:0 auto;padding:24px 16px 48px}h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 8px}
.sub{color:var(--muted)}.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px;margin:8px 0}
.chips{display:flex;flex-wrap:wrap;gap:6px}.chip{border:1px solid var(--line);border-radius:999px;padding:2px 10px}
.good{color:var(--good)}.bad{color:var(--bad)}.warn{color:var(--warn)}.info{color:var(--info)}.muted{color:var(--muted)}
table{border-collapse:collapse;width:100%}table+table{margin-top:12px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:600}code{font:13px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace}
ul{margin:4px 0;padding-left:20px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:8px}
@media (max-width:600px){th,td{padding:4px}}
"""


def e(value):
    return html.escape("" if value is None else str(value), quote=True)


def duration(view):
    t = view.get("time") or {}
    try:
        from datetime import datetime
        a = datetime.fromisoformat(str(t.get("started")).replace("Z", "+00:00"))
        b = datetime.fromisoformat(str(t.get("updated")).replace("Z", "+00:00"))
        mins = int((b - a).total_seconds() // 60)
        return "%d h %d min" % (mins // 60, mins % 60) if mins >= 60 else "%d min" % mins
    except Exception:
        return None


def num(x):
    return x if isinstance(x, int) and not isinstance(x, bool) else 0


def spent(ms):
    secs = num(ms) // 1000
    return "%d s" % secs if secs < 60 else ("%d min" % (secs // 60) if secs < 3600 else "%d h %d min" % (secs // 3600, secs % 3600 // 60))


def tokens(n):
    n = num(n)
    return "%.1fM" % (n / 1e6) if n >= 1e6 else ("%dk" % (n // 1000) if n >= 1000 else str(n))


def usd(v):
    return "%s" % ("$%.2f" % v if v >= 0.995 else "$%.4f" % v) if isinstance(v, (int, float)) and not isinstance(v, bool) else "-"


def section(title, body):
    return "<section><h2>%s</h2>%s</section>" % (e(title), body)


def render(view, main=None):
    run = view.get("run") or {}
    stages = view.get("stages") or []
    here = next((s for s in stages if s.get("mark") == "here"), None)
    done = here is not None and here.get("id") == "commit" and here.get("verdict") == "PASS"
    result = "Done" if done else "In progress (%s)" % (here or {}).get("label", run.get("stage", "?"))
    usage = view.get("usage") or {}
    head = ["<h1>%s</h1>" % e(run.get("title") or run.get("slug") or "Temper run"),
            "<div class='sub'>%s</div>" % " · ".join(e(x) for x in [
                "Spec " + str(run.get("slug") or ""), "Branch " + str(run.get("branch") or "none"), result,
                duration(view) and "Time " + duration(view), usage.get("tokens") and tokens(usage.get("tokens")) + " tokens"] if x)]
    out = ["".join(head)]

    chips = "".join("<span class='chip %s'>%s %s</span>" % (MARK.get(s.get("mark"), ("", ""))[1], MARK.get(s.get("mark"), ("?", ""))[0], e(s.get("label")))
                    for s in stages)
    rows = []
    for s in stages:
        if s.get("skipped"):
            rows.append("<li class='warn'>%s skipped: %s</li>" % (e(s.get("label")), e((s.get("skipped") or {}).get("reason"))))
        for f in s.get("failed") or []:
            rows.append("<li class='bad'>%s failed: %s %s</li>" % (e(s.get("label")), e(f.get("name")), e(f.get("detail"))))
    label = {s.get("id"): s.get("label") for s in stages}
    for loop in view.get("loops") or []:
        rows.append("<li class='info'>↺ %s to %s (%s of %s): %s</li>" % (e(label.get(loop.get("from"), loop.get("from"))), e(label.get(loop.get("to"), loop.get("to"))), e(loop.get("iteration")),
                                                                     e(loop.get("max")), e(loop.get("reason") or "no reason given")))
    out.append(section("Stages", "<div class='chips'>%s</div>%s" % (chips, "<ul>%s</ul>" % "".join(rows) if rows else "")))

    plan = view.get("plan") or {}
    if plan.get("groups") or plan.get("files"):
        cards = "".join("<div class='card'><b>%s</b> %s<ul>%s</ul></div>" % (e(g.get("id")), e(g.get("title")), "".join("<li><code>%s</code></li>" % e(f) for f in g.get("files") or []))
                        for g in plan.get("groups") or [])
        grouped = {f for g in plan.get("groups") or [] for f in g.get("files") or []}
        rest = [f for f in plan.get("files") or [] if f not in grouped]
        if rest:
            cards += "<div class='card'><b>Other files</b><ul>%s</ul></div>" % "".join("<li><code>%s</code></li>" % e(f) for f in rest)
        note = "approved by you at the plan gate" if plan.get("approved") else "as the plan lists them"
        out.append(section("Plan files", "<div class='sub'>%s</div><div class='grid'>%s</div>" % (e(note), cards)))

    build = view.get("build") or {}
    if build.get("groups"):
        trs = []
        for g in build["groups"]:
            for t in g.get("tasks") or []:
                glyph, word, cls = TASK.get(t.get("state"), ("?", t.get("state"), ""))
                retries = max(num(t.get("attempts")) - 1, 0)
                trs.append("<tr><td>%s</td><td>%s %s</td><td class='%s'>%s %s</td><td>%s</td><td>%s</td></tr>" % (
                    e(g.get("id")), e(t.get("n")), e(t.get("title")), cls, glyph, e(word), e(t.get("model") or ""), retries))
        integration = build.get("integration")
        out.append(section("Build", "<table><tr><th>Group</th><th>Task</th><th>State</th><th>Model</th><th>Retries</th></tr>%s</table>%s" % (
            "".join(trs), "<p>Integration: %s</p>" % e(integration) if integration else "")))

    findings = view.get("findings") or []
    if findings:
        def claim(f):
            text = str(f.get("claim") or "")
            return text.split(None, 1)[1] if f.get("file") and len(text.split(None, 1)) > 1 else text

        def conf(f):
            c = f.get("confidence")
            return "%.2f" % c if isinstance(c, (int, float)) and not isinstance(c, bool) else ""

        trs = "".join("<tr><td class='%s'>%s</td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td></tr>" % (
            "bad" if f.get("severity") in ("critical", "high") else "warn", e(f.get("severity")), e(conf(f)),
            e("%s:%s" % (f.get("file"), f.get("line")) if f.get("file") else ""), e(claim(f)), e(f.get("state")))
            for f in findings)
        out.append(section("Review findings", "<table><tr><th>Severity</th><th>Confidence</th><th>Where</th><th>Finding</th><th>State</th></tr>%s</table>" % trs))

    markers = [m for m in view.get("check_markers") or [] if m.get("state") != "none"]
    if markers:
        cards = "".join("<div class='card'><b class='%s'>%s %s</b> %s%s</div>" % (
            MARKER.get(m.get("state"), ("", ""))[1], MARKER.get(m.get("state"), ("?", ""))[0], e(m.get("name")),
            e(m.get("detail")), "<ul>%s</ul>" % "".join("<li><code>%s</code></li>" % e(x) for x in m.get("lines") or []) if m.get("lines") else "")
            for m in view.get("check_markers") or [])
        out.append(section("Check", "<div class='grid'>%s</div>" % cards))

    criteria = view.get("criteria") or []
    if criteria:
        lis = "".join("<li class='%s'>%s <b>%s</b> %s%s</li>" % (
            "good" if c.get("status") == "passed" else "muted", "✓" if c.get("status") == "passed" else "○", e(c.get("id")), e(c.get("text")),
            "<ul>%s</ul>" % "".join("<li class='muted'>%s</li>" % e(x) for x in c.get("evidence") or []) if c.get("evidence") else "")
            for c in criteria)
        passed = sum(1 for c in criteria if c.get("status") == "passed")
        out.append(section("Acceptance criteria: %d of %d met" % (passed, len(criteria)), "<ul>%s</ul>" % lis))

    order = {s.get("id"): i for i, s in enumerate(stages)}
    plus = []

    def cost(v, short):   # a cost with + leaves out what has no cost here
        if v is None:
            return "-"
        if short:
            plus.append(1)
        return usd(v) + ("+" if short else "")
    tables = []
    for key, head in (("by_stage", "Stage"), ("by_model", "Model")):
        rows = usage.get(key) or {}
        if rows:
            # The stage table names the model each stage was launched on (what Temper asked for).
            model = (lambda v: "<td>%s</td>" % e(", ".join(str(m) for m in v.get("models") or []) or "-")) if key == "by_stage" else (lambda v: "")
            trs = "".join("<tr><td>%s</td>%s<td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
                e(k), model(v), e(v.get("runs")), e(tokens(v.get("tokens"))), e(spent(v.get("ms"))),
                e(cost(v.get("cost"), v.get("partial") or v.get("unpriced"))))
                          for k, v in sorted(rows.items(), key=lambda kv: (order.get(kv[0], len(order)), kv[0])) if isinstance(v, dict))
            cols = "<th>Model</th>" if key == "by_stage" else ""
            tables.append("<table><tr><th>%s</th>%s<th>Launches</th><th>Tokens</th><th>Time</th><th>Cost</th></tr>%s</table>" % (head, cols, trs))
    if tables:
        notes = []
        no_price = list(usage.get("no_price") or [])
        if isinstance(main, dict) and main.get("calls"):
            # the main conversation's calls on a model with a price here; none of them priced is no cost
            mc = main.get("cost") if main["calls"] > main.get("unpriced_calls", main["calls"] if main.get("unpriced") else 0) else None
            no_price += [x for x in main.get("unpriced") or [] if x not in no_price]
            whole = None
            if usage.get("cost") is not None or mc is not None:
                short = bool(usage.get("unpriced") or usage.get("partial") or main.get("unpriced")) or usage.get("cost") is None
                whole = cost((usage.get("cost") or 0) + (mc or 0), short)
            notes.append("Main conversation since the run started: %s tokens in %d call(s), %s.%s" % (
                tokens(main.get("tokens")), main["calls"], cost(mc, bool(main.get("unpriced"))),
                " The run, agents and main conversation: %s." % whole if whole is not None else ""))
        if usage.get("unpriced"):
            notes.append("%d launch(es) have no cost: no transcript was found (the tokens are then the total Claude Code gave, "
                         "the context at the end), or none of their calls ran on a model with a price here." % usage["unpriced"])
        if plus:
            notes.append("A cost with + leaves out what has no cost here: a launch with none, or calls on a model with no price here.")
        if no_price:
            notes.append("No price here for the model(s) %s (scripts/usage_cost.py holds the prices)." % ", ".join(no_price))
        if usage.get("output_estimated"):
            notes.append("An agent transcript records each reply before it streams: its output is taken from the reply text, and "
                         "its thinking, billed as output, is not counted, so the cost of the agents can be low.")
        notes.append("Tokens as billed, from each agent transcript; cost at the API list prices of %s. A Claude plan is not "
                     "billed per token." % ((main or {}).get("prices_as_of") or PRICES_AS_OF))
        tables.append("".join("<p class='muted'>%s</p>" % e(x) for x in notes))
        out.append(section("Time, tokens and cost", "".join(tables)))

    title = "Temper report: %s" % (run.get("title") or run.get("slug") or "run")
    return ("<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
            "<title>%s</title><style>%s</style></head><body><main>%s</main></body></html>\n" % (e(title), CSS, "".join(out)))


def main(argv=None):
    p = argparse.ArgumentParser(prog="run_report.py", description="The end of run report from .temper/view.json.")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--view", default=os.path.join(".temper", "view.json"))
    r.add_argument("--root", default=".", help="the project folder the run's spec path is relative to")
    r.add_argument("--target", choices=["file", "artifact"], default="file")
    r.add_argument("-o", dest="out", default=None)
    r.add_argument("--main", default="", help="the main conversation's usage, one JSON line (temper report gives it)")
    args = p.parse_args(argv)
    try:
        with open(args.view, encoding="utf-8") as f:
            view = json.load(f)
    except (OSError, ValueError) as err:
        print("FAIL: cannot read %s: %s" % (args.view, err), file=sys.stderr)
        return 1
    if view.get("version") != 1 or not view.get("run"):
        print("FAIL: %s holds no run of view version 1" % args.view, file=sys.stderr)
        return 1
    try:
        main = json.loads(args.main) if args.main else None
    except ValueError:
        main = None
    doc = render(view, main)
    if args.target == "artifact":
        doc = to_artifact_fragment(doc)
    out = args.out or os.path.join(args.root, view["run"].get("spec") or ".temper", "report.html")
    if out == "-":
        sys.stdout.write(doc)
        return 0
    why = output_refusal(out, ".html")
    if why:
        print("FAIL: " + why, file=sys.stderr)
        return 2
    try:
        if args.out is None:
            os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(doc)
    except OSError as err:
        print("FAIL: cannot write %s: %s" % (out, err), file=sys.stderr)
        return 1
    print("OK: wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
