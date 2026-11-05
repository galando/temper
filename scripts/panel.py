"""panel.py: the panel of a stage, drawn by the CLI from the files the stage wrote (9.8.0, round 5).

  python3 panel.py plan SPEC_DIR PROJECT     the Plan panel, then the plan's diagram
  python3 panel.py design SPEC_DIR           the Design panel
  python3 panel.py rca RCA_MD                the RCA panel (rca.md as the RCA agent writes it)
  python3 panel.py task SPEC_DIR PROJECT N... each Build task's panel, from tasks.md, groups.json and the build ledger

Before, each Opus agent drew its own 76 column box (a Python script to pad the rows, then the box again as its last
message): 2,000 to 3,000 output tokens and 30 to 40 seconds a stage, for text the CLI can draw from the files. The CLI
counts what it can count (criteria, scenarios, files to create or modify, the risk) instead of taking the agent's
count. A file that is missing gives a shorter panel, never an error: the panel only shows.

Standard library only.
"""
import json
import os
import re
import subprocess
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import acceptance  # noqa: E402
import scenario_ops  # noqa: E402
import tasks_md  # noqa: E402

WIDTH = 76
INNER = WIDTH - 4


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""


def rows(text):
    """A row of the panel, wrapped to the border; a continuation row is indented two spaces."""
    text = re.sub(r"[\r\n\t]+", " ", text).strip()
    lines = textwrap.wrap(text, INNER, subsequent_indent="  ", break_long_words=True, break_on_hyphens=False) or [""]
    return ["| %s |" % l.ljust(INNER) for l in lines]


def box(title, facts, sections):
    """One closed panel: the title, the fact rows, then each titled section with rows (an empty section is left out)."""
    rule = "+" + "-" * (WIDTH - 2) + "+"
    out = [rule] + rows(title) + [rule]
    for f in facts:
        out += rows(f)
    for name, items in sections:
        if not items:
            continue
        head = "+--- %s (%d) ---+" % (name, len(items))
        out.append(head + "-" * max(0, WIDTH - len(head) - 1) + "+" if len(head) < WIDTH else head[:WIDTH - 1] + "+")
        for it in items:
            out += rows(it)
    out.append(rule)
    return out


def section(text, name, level=None):
    """The lines under the heading whose text starts with `name` (any level, or the level given), to the next heading of
    the same level or higher."""
    lines = text.splitlines()
    for i, l in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*?)\s*$", l)
        if m and m.group(2).lower().startswith(name.lower()) and (level is None or len(m.group(1)) == level):
            lvl = len(m.group(1))
            end = next((j for j in range(i + 1, len(lines)) if (lambda h: h and len(h.group(1)) <= lvl)(re.match(r"^(#{1,6})\s", lines[j]))), len(lines))
            return lines[i + 1:end]
    return []


def plain(t):
    return re.sub(r"[*`]", "", t).strip()


def first_sentence(lines):
    text = " ".join(plain(re.sub(r"^\s*(?:[-*]|\d+[.)])\s+", "", l)) for l in lines
                    if l.strip() and not l.lstrip().startswith(("#", "|", "<!--", "```")))
    m = re.match(r"(.+?[.!?])(\s|$)", text)
    return (m.group(1) if m else text)[:200]


def h1(text, prefix):
    m = re.search(r"^#\s+(?:%s:\s*)?(.+?)\s*$" % prefix, text, re.M)
    return m.group(1).strip() if m else ""


def plan(spec, project):
    intent = read(os.path.join(spec, "intent.md"))
    plan_md = read(os.path.join(spec, "plan.md"))
    ilines = intent.splitlines()
    crits = [c for c in acceptance.parse_criteria(section(intent, "Success Criteria")) if not c.get("placeholder") and c.get("id")]
    # Scenarios with the group heading above each (Happy Path, Error Paths, Edge Cases).
    scen, group = [], ""
    blocks = acceptance.scenario_blocks(ilines)
    names = iter(blocks)
    for l in ilines:
        g = re.match(r"^#{3,6}\s+(.*?)\s*$", l)
        if g:
            group = plain(g.group(1))
        if re.match(r"^\s*Scenario:\s*\S", l):
            b = next(names, None)
            if b is not None:
                scen.append("[%s] %s%s" % (group or "scenario", b["name"], (", Covers: " + ", ".join(b["covers"])) if b["covers"] else ""))
    files = []
    for t in tasks_md.parse(os.path.join(spec, "tasks.md")).get("tasks", []):
        files += [f for f in t.get("files", []) if not any(ch in f for ch in "*?")]
    files = list(dict.fromkeys(files))
    modify = [f for f in files if os.path.exists(os.path.join(project, f))]
    state = {}
    try:
        state = json.load(open(os.path.join(project, ".temper", "build-state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        pass
    search = first_sentence(section(plan_md, "Cross-Repo Search"))
    search = "local" if not search or re.match(r"(?i)(not available|none|local)\b", search) else short(search, 40)
    decisions = [plain(re.sub(r"^#{3,6}\s+(?:Decision\s+\d+:\s*)?", "", l)) for l in section(plan_md, "Approach Decisions")
                 if re.match(r"^#{3,6}\s+\S", l)]
    title = h1(plan_md, "Plan") or h1(intent, "Intent") or os.path.basename(spec.rstrip("/"))
    hot = []
    try:
        hot = json.load(open(os.path.join(project, ".temper", "security-map.json"), encoding="utf-8"))
    except (OSError, ValueError):
        pass
    level = [str(e.get("sensitivity", "")).upper() for e in hot if isinstance(e, dict)] if isinstance(hot, list) else []
    facts = [
        "INTENT: %s -> %d criteria (%d scenarios cover them)" % (first_sentence(section(intent, "Problem")) or "see intent.md", len(crits), len(blocks)),
        "ARCHITECTURE: create %d files, modify %d files   RISK: %s" % (len(files) - len(modify), len(modify), state.get("risk") or "?"),
        "COMPLEXITY: %s   SEARCH: %s" % (state.get("complexity") or "?", search),
    ]
    if "CRITICAL" in level or "HIGH" in level:
        facts.append("SECURITY: %d CRITICAL, %d HIGH hot paths" % (level.count("CRITICAL"), level.count("HIGH")))
    out = box("PLAN: %s" % title, facts, [("SCENARIOS", scen), ("DECISIONS", decisions)])
    return out + ascii_diagram(section(plan_md, "Diagram"))


def short(text, n):
    return text if len(text) <= n else text[:n].rsplit(" ", 1)[0]


def ascii_diagram(lines):
    """The terminal drawing of plan.md's Diagram section: its ```text blocks (the template's ASCII rendering), never the
    mermaid block, which a terminal cannot draw."""
    out, block, lang = [], None, ""
    for l in lines:
        m = re.match(r"^\s*```\s*([\w-]*)", l)
        if m and block is None:
            block, lang = [], m.group(1).lower()
        elif m:
            if lang in ("text", "", "ascii", "txt"):
                out += block
            block = None
        elif block is not None:
            block.append(l)
    return out


def table_rows(lines):
    """The rows of the first markdown table in these lines, as lists of cells, header and rule left out."""
    out = []
    for l in lines:
        if not l.strip().startswith("|"):
            if out:
                break
            continue
        cells = [plain(c) for c in l.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{3,}:?", c) for c in cells if c):
            continue
        out.append(cells)
    return out[1:] if out else []


def design(spec):
    text = read(os.path.join(spec, "design.md"))
    import flow  # the one reading of Areas of Concern the Design gate makes
    lines = text.splitlines()
    concerns = []
    for c in flow.concern_blocks(lines):
        res = next((plain(l)[len("resolved:"):].strip() for l in lines[c["start"]:c["end"]] if plain(l).lower().startswith("resolved:")), "")
        concerns.append(c["title"] + (" (resolved: %s)" % res if res else " (open)"))
    decisions = []
    log = section(text, "Decision Log")
    for cells in table_rows(log):
        if len(cells) >= 4:
            decisions.append("%s: %s, because %s" % (cells[0], cells[2], cells[3]))
        elif cells:
            decisions.append(": ".join(c for c in cells if c))
    if not decisions:
        decisions = [plain(re.sub(r"^\s*(?:#{3,6}|[-*])\s+", "", l)) for l in log if re.match(r"^\s*(?:#{3,6}|[-*])\s+\S", l)]
    contracts = [l for l in section(text, "API Contracts") if re.match(r"^#{3,6}\s+\S", l)]
    tables = [l for l in section(text, "Database Changes") if re.match(r"^#{3,6}\s+\S", l)]
    facts = ["API CONTRACTS: %d   DATABASE CHANGES: %d   CONCERNS OPEN: %d" % (
        len(contracts), len(tables), sum(1 for c in concerns if c.endswith("(open)")))]
    return box("DESIGN: %s" % (h1(text, "Design") or os.path.basename(spec.rstrip("/"))), facts,
               [("AREAS OF CONCERN", concerns), ("DECISIONS", decisions)])


RCA_FIELDS = ("CAUSE", "AT", "CONFIDENCE", "SINCE", "CHAIN", "FIX", "TEST")


def rca(path):
    text = read(path)
    if not text.strip():
        return ["(no rca.md at %s)" % path]
    vals = {}
    for k in RCA_FIELDS:
        m = re.search(r"^\**%s:?\**:?\s*(.+)$" % k, text, re.M | re.I)
        vals[k] = plain(m.group(1)) if m else ""
    # A file still in the panel format of 9.8.0's first release prints as it is.
    if not any(vals.values()) and text.lstrip().startswith("+"):
        return text.rstrip("\n").splitlines()
    facts = ["CAUSE: %s" % (vals["CAUSE"] or "?"),
             "AT: %s   CONFIDENCE: %s   SINCE: %s" % (vals["AT"] or "?", vals["CONFIDENCE"] or "?", vals["SINCE"] or "unknown")]
    if vals["CHAIN"]:
        facts.append("CHAIN: %s" % vals["CHAIN"])
    facts += ["FIX: %s" % (vals["FIX"] or "?"), "TEST: %s" % (vals["TEST"] or "?")]

    def items(name):
        return [plain(re.sub(r"^\s*[-*]\s+", "", l)) for l in section(text, name) if re.match(r"^\s*[-*]\s+\S", l)]
    title = h1(text, "RCA") or "the bug"
    return box("RCA: %s" % title, facts, [("BLAST RADIUS", items("Blast radius")), ("READ FIRST", items("Read first"))])


def load_json(path, default):
    try:
        return json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return default


def task(spec, project, ns):
    """Each Build task's panel, from what the CLI recorded: the attempt, the RED and GREEN runs of the CLI (`task test`),
    the gate's verdict and reason, the files of the task's commit and the scenarios it owes. Before, each Build task agent
    drew this box itself: a Python script to pad it, then the box (about a minute of a Haiku agent, and a command that
    could hang until the Bash timeout)."""
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    run = load_json(os.path.join(project, ".temper", "groups.json"), {})
    rows = load_json(os.path.join(project, ".temper", "evidence", "build.json"), [])
    rows = rows if isinstance(rows, list) else []
    intent = os.path.join(spec, "intent.md")
    out = []
    for n in ns:
        t = next((x for x in plan.get("tasks", []) if x.get("n") == n), None)
        if t is None:
            out.append("(no Task %d in tasks.md)" % n)
            continue
        rt = ((run.get("tasks") if isinstance(run, dict) else None) or {}).get(str(n)) or {}
        atts = rt.get("attempts") or []
        last = atts[-1] if atts and isinstance(atts[-1], dict) else {}
        status = rt.get("status", "pending")
        attempt = rt.get("attempt") if status == "running" else (last.get("n") or rt.get("attempt") or 1)
        mine = [r for r in rows if isinstance(r, dict) and r.get("task") == n and r.get("attempt") == attempt
                and r.get("executed_by") == "cli"]
        red = next((r.get("exit_code") for r in mine if r.get("phase") == "red"), None)
        green = next((r.get("exit_code") for r in reversed(mine) if r.get("phase") == "green"), None)
        verdict = {"passed": "PASS", "covered": "COVERED (an earlier task built it)", "running": "not judged yet"}.get(
            status, last.get("outcome") or status.upper())
        changed = []
        if rt.get("commit"):
            r = subprocess.run(["git", "-C", project, "show", "--name-only", "--format=", rt["commit"]],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            changed = [x for x in r.stdout.decode("utf-8", "replace").split("\n") if x.strip()][:20]
        try:
            owed = [name for name, _ in scenario_ops.owed(plan, intent, n)]
        except Exception:  # the panel only shows: a scenario it cannot read is left out
            owed = []
        facts = ["Attempt: %s   Test: red exit %s, green exit %s   Gate: %s" % (
            attempt, "none" if red is None else red, "none" if green is None else green, verdict)]
        why = [last.get("reason")] if last.get("outcome") == "FAIL" and last.get("reason") and status != "passed" else []
        out += box("TASK %d: %s" % (n, plain(t.get("title") or "")), facts,
                   [("CHANGED" if changed else "DECLARED", changed or list(t.get("files") or [])),
                    ("SCENARIOS", owed), ("WHY IT FAILED", why)])
    return out


def main(argv):
    if len(argv) >= 4 and argv[1] == "plan":
        out = plan(argv[2], argv[3])
    elif len(argv) >= 3 and argv[1] == "design":
        out = design(argv[2])
    elif len(argv) >= 3 and argv[1] == "rca":
        out = rca(argv[2])
    elif len(argv) >= 5 and argv[1] == "task" and all(a.isdigit() for a in argv[4:]):
        out = task(argv[2], argv[3], [int(a) for a in argv[4:]])
    else:
        print("usage: panel.py plan SPEC_DIR PROJECT | design SPEC_DIR | rca RCA_MD | task SPEC_DIR PROJECT N...", file=sys.stderr)
        return 1
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
