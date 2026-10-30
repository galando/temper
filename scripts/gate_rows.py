"""gate_rows.py: gate rows that scripts/temper asks for by name, one mode per call (each prints JSON rows, one per line).

  python3 gate_rows.py intent-blocking INTENT.md   the row for a Blocking question left open in a draft intent
  python3 gate_rows.py plan-rows SPEC_DIR PROJECT  the rows added to the plan gate (scenario test commands)
  python3 gate_rows.py build-rows SPEC_DIR EVIDENCE.json  the rows added to the build gate (criteria validated)

They live here so scripts/temper stays under the directory's 256 KiB limit. Standard library only.
"""
import json
import os
import re
import sys

import acceptance
import tasks_md
import maven_loop
import plan_ops


def row(name, ok, detail):
    return {"name": name, "pass": ok, "detail": detail}


def intent_blocking(path):
    """A draft intent fails while a `- Blocking:` line is under its Open Questions: the person answers it first (it goes
    into Decisions). A Deferred question and an accepted or completed intent pass."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return row("blocking question open", True, "intent.md unreadable; the other rows report it")
    m = re.search(r"^\*\*Status:\*\*\s*(draft|accepted|completed)\s*$", text, re.I | re.M)
    status = m.group(1).lower() if m else None
    if status != "draft":
        return row("blocking question open", True, "skipped: the intent is %s; this check applies to drafts only" % (status or "of no known status"))
    open_q, active = [], False
    for line in text.splitlines():
        h = re.match(r"^#{1,6}\s+(.*)$", line)
        if h:
            active = bool(re.match(r"open questions", h.group(1).strip(), re.I))
            continue
        b = re.match(r"^\s*[-*]\s+Blocking:\s*(.+)$", line) if active else None
        if b:
            open_q.append(b.group(1).strip())
    if open_q:
        return row("blocking question open", False, "%d Blocking question(s) open: %s%s; answer them before the plan" % (
            len(open_q), open_q[0][:80], "" if len(open_q) == 1 else " and %d more" % (len(open_q) - 1)))
    return row("blocking question open", True, "no Blocking question is open")


FILE_TOKEN = re.compile(r"[\w./@-]+\.\w+")


def test_file_of(cmd):
    """The test file a Test: command names (`pytest unit/test_x.py::test_a -q` -> unit/test_x.py), or ''."""
    for tok in re.split(r"\s+", cmd):
        tok = tok.strip("'\"`").split("::")[0]
        if "/" in tok and FILE_TOKEN.fullmatch(tok) and not tok.startswith("-"):
            return tok[2:] if tok.startswith("./") else tok
    return ""


def plan_scenario_commands(spec, project):
    """Every scenario of intent.md carries a Test: line, a scoped command that proves it on the merged tree. FAIL names each
    scenario with none (joined with |), and each Test: file that no task declares and the project lacks. SKIP (a pass)
    when the intent holds no scenario."""
    name = "scenario test commands"
    try:
        lines = open(os.path.join(spec, "intent.md"), encoding="utf-8").read().splitlines()
    except OSError:
        return row(name, True, "skipped: no intent.md")
    blocks = acceptance.scenario_blocks(lines)
    if not blocks:
        return row(name, True, "skipped: no scenarios")
    declared = set()
    for t in tasks_md.parse(os.path.join(spec, "tasks.md"))["tasks"]:
        declared.update(t["files"])
    missing = [b["name"] for b in blocks if not b["cmd"].strip()]
    nofile = []
    for b in blocks:
        f = test_file_of(b["cmd"]) if b["cmd"].strip() else ""
        if f and f not in declared and not os.path.exists(os.path.join(project, f)):
            nofile.append("%s (%s)" % (b["name"], f))
    if missing or nofile:
        parts = []
        if missing:
            parts.append("no Test: line: " + " | ".join(missing))
        if nofile:
            parts.append("Test: file no task declares and the project lacks: " + " | ".join(nofile))
        return row(name, False, "; ".join(parts))
    return row(name, True, "%d scenario(s), each with a Test: command" % len(blocks))


def plan_maven_verify(spec):
    """A Maven group (a task or the group's Validate runs mvn, mvnd or mvnw, or a task declares a pom.xml) validates with
    `mvn verify` and JaCoCo on, once, at the group gate. The row names each Maven group that breaks the rule."""
    name = "maven group verify"
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    bad, maven = [], 0
    for g in plan["groups"]:
        tasks = [t for t in plan["tasks"] if t["group"] == g["id"]]
        if not (maven_loop.is_maven(g["validate"]) or any(maven_loop.is_maven(t["test"]) for t in tasks)
                or any(f.endswith("pom.xml") for t in tasks for f in t["files"])):
            continue
        maven += 1
        v = g["validate"]
        if not (maven_loop.is_maven(v) and re.search(r"\bverify\b", v) and "jacoco" in v.lower()):
            bad.append(g["id"])
    if not maven:
        return row(name, True, "skipped: no Maven group")
    if bad:
        return row(name, False, "%s: a Maven group validates with `mvn verify` and JaCoCo on (for example `mvn verify -Pjacoco`), once, at the group gate" % ", ".join(bad))
    return row(name, True, "%d Maven group(s) validate with mvn verify and JaCoCo" % maven)


def build_criteria(spec, evidence):
    out, failed = acceptance.build_report(os.path.join(spec, "intent.md"), evidence)
    bad = [x for x in out if " FAIL" in x]
    if bad:
        return row("criteria validated", False, " ".join(bad)[:600])
    return row("criteria validated", True, "%d criteria: %s" % (len(out), ", ".join(
        "%s %s" % (x.split()[0], x.split()[1].rstrip(":")) for x in out))[:300])


def pipeline_gate(spec):
    """The Pipeline gate, printed as the CLI's gates print: a JSON array of rows, then 1 or 0. The agent writes
    pipeline-context.json; a missing file, or a status that is neither green nor red, is a result that is not final."""
    try:
        ctx = json.load(open(os.path.join(spec, "pipeline-context.json"), encoding="utf-8"))
    except (OSError, ValueError):
        ctx = None
    status = ctx.get("status") if isinstance(ctx, dict) else None
    rows = [row("pipeline result", status in ("green", "red"),
                "the checks gave a final result: %s" % status if status in ("green", "red")
                else "the Pipeline result is missing or not final (no pipeline-context.json with a green or red status)")]
    if status in ("green", "red"):
        failed = [j.get("name", "?") for j in (ctx.get("failed_jobs") or []) if isinstance(j, dict)]
        rows.append(row("jobs passed", status == "green",
                        "every job passed" if status == "green" else "%d job(s) failed: %s" % (len(failed), ", ".join(failed[:5]) or "see pipeline-context.json")))
    return "%s %d" % (json.dumps(rows), 1 if all(r["pass"] for r in rows) else 0)


def main(argv):
    if len(argv) == 3 and argv[1] == "pipeline-gate":
        print(pipeline_gate(argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == "scenario-known":
        names = [b["name"] for b in acceptance.scenario_blocks(open(argv[2], encoding="utf-8").read().splitlines())]
        return 0 if argv[3] in names else 1
    if len(argv) in (4, 5) and argv[1] == "plan-rows":
        print(json.dumps(plan_scenario_commands(argv[2], argv[3])))
        print(json.dumps(plan_maven_verify(argv[2])))
        if os.path.isfile(os.path.join(argv[2], "plan.md")):   # a run with no plan.md (the trivial path) has no map to review
            print(json.dumps(plan_ops.gate_row(argv[2], argv[4] if len(argv) == 5 else "auto")))
        return 0
    if len(argv) == 4 and argv[1] == "build-rows":
        if os.path.isfile(os.path.join(argv[2], "intent.md")):
            print(json.dumps(build_criteria(argv[2], argv[3])))
        return 0
    if len(argv) == 3 and argv[1] == "intent-blocking":
        print(json.dumps(intent_blocking(argv[2])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
