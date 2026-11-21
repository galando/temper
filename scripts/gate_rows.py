"""gate_rows.py: gate rows that scripts/temper asks for by name, one mode per call (each prints JSON rows, one per line).

  python3 gate_rows.py intent-blocking INTENT.md   the row for a Blocking question left open in a draft intent
  python3 gate_rows.py intent-rules INTENT.md      the row for the rules checklist (### Rules covered) of a draft intent
  python3 gate_rows.py plan-rows SPEC_DIR PROJECT  the rows added to the plan gate (scenario test commands, the request's
                                                   routes kept, tasks agree with decisions)
  python3 gate_rows.py build-rows SPEC_DIR EVIDENCE.json [KEY]  the rows added to the build gate (criteria validated;
                                                   WP23: the acceptance tests and coverage the checks when Build ends
                                                   recorded; in a fix run tests pass and the regression proof)
  python3 gate_rows.py check-rows LEDGER BASELINE [KEY]  the row coverage of the check gate (WP19): the coverage rule of
                                                   check_run.py on the ledger's latest coverage row, the baseline and
                                                   check.coverage-threshold when the project's config holds it; then the
                                                   acceptance tests and a fix's regression proof (WP23)

They live here so scripts/temper stays under the directory's 256 KiB limit. Standard library only.
"""
import json
import os
import re
import sys

import acceptance
import decisions
import intent_parse
import tasks_md
import maven_loop
import plan_ops
import runs


def row(name, ok, detail):
    """A gate row; ok None is the third state (WP19): not measured, which fails nothing and is never read as passed."""
    if ok is None:
        return {"name": name, "pass": None, "state": "not measured", "detail": "not measured: %s" % detail}
    return {"name": name, "pass": ok, "detail": detail}


def ledger_rows(ledger):
    try:
        return [x for x in json.load(open(ledger, encoding="utf-8")) if isinstance(x, dict)]
    except (OSError, ValueError, TypeError):
        return []


def check_rows(ledger, baseline, key):
    """The row coverage, judged again here with the config and the baseline as they are now: the ledger's latest coverage
    row (the CLI's, with what it measured, or a recorded value) is the measure."""
    import check_run
    rows = ledger_rows(ledger)
    hits = [x for x in rows if not x.get("scenario") and re.search("coverage", str(x.get("claim") or ""), re.I)
            and (x.get("value") is not None or x.get("state"))]
    last = hits[-1] if hits else {}
    measure = {"total": last.get("value"), "command": last.get("command", True), "exit": last.get("cov_exit"),
               "hint": last.get("hint") or "", "note": last.get("note") or ("" if last else "no coverage was recorded")}
    base, why = check_run.base_value(baseline)
    v = check_run.coverage_verdict(measure, base, last.get("changed"), key or None, why)
    return row("coverage", {"pass": True, "fail": False}.get(v["state"]), v["why"])


def one_line(x, n=300):
    return " ".join(str(x or "").split())[:n]


def acceptance_row(rows):
    """The row `acceptance tests written before Build`, from the ledger's latest acceptance row (the checks when Build
    ends write it at Build, Check at Check: one name, so the flow's matchers serve both stages); None with none."""
    hits = [x for x in rows if re.match(r"acceptance \(written before Build\)", str(x.get("claim") or ""))]
    if not hits:
        return None
    ran = [x for x in hits if runs.counts(x)]   # rule 5 (ADR 0024): a row an agent wrote, or a void one, counts nowhere
    if not ran:
        return row("acceptance tests written before Build", False, "no run of the acceptance tests the CLI made: a row "
                   "written with evidence add counts nowhere")
    last, claim = ran[-1], str(ran[-1].get("claim") or "")
    if last.get("exit_code") != 0:
        return row("acceptance tests written before Build", False, one_line(last.get("output")))
    ok = "they pass, unchanged since they were locked"
    if ", corrected after the lock: " in claim:
        ok = "they pass, as the person corrected them after the lock (%s)" % claim.split(", corrected after the lock: ", 1)[1]
    if claim.endswith("skipped"):
        ok = "skipped: %s" % one_line(last.get("output"))
    return row("acceptance tests written before Build", True, ok)


def regression_row(rows):
    """A fix's regression proof (WP23): only a row the CLI ran counts; a proof an agent or a person wrote fails the row.
    None when no proof row was written at all."""
    hits = [x for x in rows if x.get("claim") == "regression proof"]
    if not hits:
        return None
    cli = [x for x in hits if x.get("executed_by") == "cli" and not x.get("voided")]
    if not cli:
        return row("regression proof", False, "no regression proof the CLI ran: a proof row written with evidence add counts nowhere")
    return row("regression proof", cli[-1].get("exit_code") == 0, one_line(cli[-1].get("output")))


def fix_run():
    try:
        return json.load(open(os.path.join(".temper", "build-state.json"))).get("command") == "fix"
    except (OSError, ValueError, AttributeError):
        return False


def build_rows(spec, ledger, key):
    """The rows the Build gate adds (WP23): criteria validated; from the checks when Build ends, the acceptance tests and
    coverage with the names Check uses; in a fix run, the suite (`tests pass`) and the regression proof."""
    out = []
    if spec and os.path.isfile(os.path.join(spec, "intent.md")):
        out.append(build_criteria(spec, ledger))
    rows = ledger_rows(ledger)
    acc = acceptance_row(rows)
    if acc:
        out.append(acc)
    if any(x.get("claim") == "coverage" and x.get("state") for x in rows):
        out.append(check_rows(ledger, os.path.join(".temper", "evidence", "baseline.json"), key))
    if fix_run():
        suite = [x for x in rows if x.get("claim") == "Integration suite"]
        ran = [x for x in suite if runs.counts(x)]   # rule 5: only a run of the suite the CLI made (integrate) counts
        if suite and not ran:
            out.append(row("tests pass", False, "no run of the suite the CLI made: a row written with evidence add counts "
                           "nowhere"))
        elif ran:
            s = ran[-1]
            out.append({"name": "tests pass", "pass": None, "state": "skipped", "detail": "skipped: the base's failures, which "
                        "you went on from"} if s.get("state") == "skipped" else
                       row("tests pass", s.get("exit_code") == 0, "the suite (%s) exited %s" % (one_line(s.get("cmd"), 160),
                                                                                       s.get("exit_code"))))
        reg = regression_row(rows)
        if reg:
            out.append(reg)
    return out


def intent_blocking(path):
    """A draft intent fails while a `- Blocking:` line is under its Open Questions: the person answers it first (it goes
    into Decisions). A Deferred question and an accepted or completed intent pass."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return row("blocking question open", True, "intent.md unreadable; the other rows report it")
    status = intent_parse.status(text)
    if status != "draft":
        return row("blocking question open", True, "skipped: the intent is %s; this check applies to drafts only" % (status or "of no known status"))
    open_q = intent_parse.blocking(text)
    if open_q:
        return row("blocking question open", False, "%d Blocking question(s) open: %s%s; answer them before the plan" % (
            len(open_q), open_q[0][:80], "" if len(open_q) == 1 else " and %d more" % (len(open_q) - 1)))
    return row("blocking question open", True, "no Blocking question is open")


# 9.8.0: Exempt (what never gets the action) is an item of its own and comes with the first: a measured run spent its
# questions on narrow exceptions (once ever, fees on fees) and never asked which invoices are exempt, and missed one.
RULES = ("Who", "When", "How much", "Exempt", "States", "Where it shows", "Exceptions")
CORE_RULES = ("Who", "When", "How much", "Exempt")
# A reason that is only the request's silence ("no time window in the request", "not stated").
SILENCE = re.compile(r"\b(in|by|from) the (request|ticket)\b|\b(request|ticket) (does not|doesn't|did not|didn't) "
                     r"(say|name|state|mention|give|specify)|\bnot (stated|given|mentioned|named|specified)\b|\bunspecified\b", re.I)


def intent_rules(path):
    """9.8.0: a draft intent says, for each item of Intent's rules checklist (agents/intent.md), whether it asked the
    person, assumed an answer, or found it does not apply: a `### Rules covered` section with one line per item
    (`- Exceptions: asked (...)`). The row checks only that every item is there; what was asked is the person's to see at
    the gate. It stops an item from being left out, as when the exemptions were folded into another question."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return row("rules checklist covered", True, "intent.md unreadable; the other rows report it")
    status = intent_parse.status(text)
    if status != "draft":
        return row("rules checklist covered", True, "skipped: the intent is %s; this check applies to drafts only" % (status or "of no known status"))
    seen, why, active = {}, {}, False
    for line in text.splitlines():
        h = re.match(r"^#{1,6}\s+(.*)$", line)
        if h:
            active = bool(re.match(r"rules covered", h.group(1).strip(), re.I))
            continue
        b = re.match(r"^\s*[-*]\s+([A-Za-z ]+?):\s*(asked|assumed|not applicable)\b(.*)$", line, re.I) if active else None
        if b:
            seen[b.group(1).strip().lower()] = b.group(2).lower()
            why[b.group(1).strip().lower()] = b.group(3)
    missing = [r for r in RULES if r.lower() not in seen]
    if missing:
        return row("rules checklist covered", False, "### Rules covered has no asked, assumed or not applicable line for: %s" % ", ".join(missing))
    # 9.8.0 (round 5): two measured runs skipped the refund window. One wrote "When: not applicable (no time window in
    # the request)": the request's silence is the reason to ask, never to skip. The other assumed "no time limit" while
    # it asked about where refunds show: with six questions at most, Who, When, How much and Exempt come first.
    silent = [r for r in CORE_RULES if seen[r.lower()] != "asked" and SILENCE.search(why[r.lower()])]
    if silent:
        return row("rules checklist covered", False, "%s: not asked because the request does not say it; that is the reason to ask: "
                   "write a Blocking question for it (not applicable means the feature has no such rule at all)" % ", ".join(silent))
    later = [r for r in RULES if r not in CORE_RULES and seen[r.lower()] == "asked"]
    skipped = [r for r in CORE_RULES if seen[r.lower()] == "assumed"]
    if skipped and later:
        return row("rules checklist covered", False, "%s assumed while %s asked: Who, When, How much and Exempt come first; ask %s and "
                   "fold a later item into Assumptions" % (", ".join(skipped), ", ".join(later), " and ".join(skipped)))
    return row("rules checklist covered", True, "; ".join("%s %s" % (r, seen[r.lower()]) for r in RULES))


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


def pom_binds_jacoco(project, cmd):
    """9.8.5: the pom of the folder a Maven command runs in binds JaCoCo's check goal, so `mvn verify` runs it with no
    profile or flag (a project like the measured one names no jacoco on the command line)."""
    for part in maven_loop.maven_parts(cmd or ""):
        rel = os.path.join(part["dir"], "pom.xml") if part["dir"] else "pom.xml"
        try:
            pom = open(os.path.join(project or ".", rel), encoding="utf-8").read()
        except OSError:
            continue
        if "jacoco" in pom.lower() and re.search(r"<goal>\s*check\s*</goal>", pom):
            return True
    return False


def plan_maven_verify(spec, project=None):
    """A Maven group (a task or the group's Validate runs mvn, mvnd or mvnw, or a task declares a pom.xml) validates with
    `mvn verify` and JaCoCo on, once, at the group gate. The row names each Maven group that breaks the rule."""
    name = "maven group verify"
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    bad, maven = [], 0
    for g in plan["groups"]:
        tasks = [t for t in plan["tasks"] if t["group"] == g["id"]]
        if not (maven_loop.maven_parts(g["validate"]) or any(maven_loop.is_maven(t["test"]) for t in tasks)
                or any(f.endswith("pom.xml") for t in tasks for f in t["files"])):
            continue
        maven += 1
        v = g["validate"]
        on = "jacoco" in v.lower().replace("jacoco.skip=true", "") or ("jacoco.skip=true" not in v.lower() and pom_binds_jacoco(project, v))
        if not (maven_loop.maven_parts(v) and re.search(r"\bverify\b", v) and on):
            bad.append(g["id"])
    if not maven:
        return row(name, True, "skipped: no Maven group")
    if bad:
        return row(name, False, "%s: a Maven group validates with `mvn verify` and JaCoCo on (for example `mvn verify -Pjacoco`), once, at the group gate" % ", ".join(bad))
    return row(name, True, "%d Maven group(s) validate with mvn verify and JaCoCo" % maven)


def plan_maven_filtered(spec, project):
    """A `verify` filtered by -Dtest= or -Dit.test= under a JaCoCo BUNDLE rule fails the rule: say so before the run."""
    name = "maven filtered verify"
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    cmds = [("%s Validate" % g["id"], g["validate"]) for g in plan["groups"]]
    cmds += [("%s Task %s Test" % (t["group"], t["n"]), t["test"]) for t in plan["tasks"]]
    cmds.append(("Integration", plan.get("integration") or ""))
    try:
        lines = open(os.path.join(spec, "intent.md"), encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    cmds += [('Scenario "%s" Test' % b["name"], b["cmd"]) for b in acceptance.scenario_blocks(lines)]
    seen, bad = 0, []
    for label, cmd in cmds:
        for part in maven_loop.maven_parts(cmd or ""):
            seen += 1
            args = part["args"]
            if "verify" not in args or "-Djacoco.skip=true" in args or not any(a.startswith(("-Dtest=", "-Dit.test=")) for a in args):
                continue
            rel = os.path.join(part["dir"], "pom.xml") if part["dir"] else "pom.xml"
            try:
                pom = open(os.path.join(project, rel), encoding="utf-8").read()
            except OSError:
                continue
            if not (re.search(r"<goal>\s*check\s*</goal>", pom) and "jacoco" in pom.lower()):
                continue
            rules = re.findall(r"<rule>(.*?)</rule>", pom, re.S)
            if any("<element>" not in r or re.search(r"<element>\s*BUNDLE\s*</element>", r) for r in rules):
                bad.append("%s: %s has a JaCoCo BUNDLE rule, and a filtered verify covers only part of the bundle" % (label, rel))
    if not seen:
        return row(name, True, "skipped: no Maven command")
    if bad:
        # 9.8.5: a group's Validate must be `mvn verify` with JaCoCo on (the maven group verify row), so its fix is to drop
        # the filter; a filtered run belongs in a task's Test (an end to end replay followed the old advice into that row)
        validate = any(" Validate: " in b for b in bad)
        how = ("For a group's Validate, drop the filter: `mvn verify` runs the whole module with JaCoCo on, as the maven group "
               "verify row asks. A filtered run belongs in a task's Test: there, run `test` instead of `verify`, or add "
               "-Djacoco.skip=true" if validate else "Run `test` instead of `verify`, or add -Djacoco.skip=true")
        return row(name, False, "; ".join(bad) + ". " + how)
    return row(name, True, "no filtered verify under a JaCoCo bundle rule")


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
        if status == "red":
            rows.append(fix_paths_row(ctx.get("fix")))
    return "%s %d" % (json.dumps(rows), 0 if any(r["pass"] is False for r in rows) else 1)


def fix_paths_row(fix):
    """A red result's fix list names real files: each entry starts with `<path>:` where the path exists in the project, or with
    `no file:` when the log names no file (a path guessed from a step name is how a fix goes to the wrong place)."""
    entries = [str(x) for x in fix] if isinstance(fix, list) else []
    if not entries:
        return row("fix paths", False, "the fix list is empty: it names no file and no change")
    bad = []
    for i, e in enumerate(entries, 1):
        head = e.split(":", 1)[0].strip()
        if head == "no file" or (head and ":" in e and os.path.isfile(head) and ".." not in head.split("/") and not os.path.isabs(head)):
            continue
        bad.append("entry %d starts with %s" % (i, "'%s', which is not a file here" % head[:60] if head else "no path"))
    return row("fix paths", not bad, "every fix entry names a file that exists, or says `no file:`" if not bad else "; ".join(bad[:3]) + " (a fix entry starts with an existing `path:` or `no file:`)")


ROUTE = re.compile(r"\b(GET|POST|PUT|PATCH|DELETE)\s+(/[^\s`'\",;)]*)")


def route_shape(path):
    """A route's shape: each parameter segment (`{id}`, `{payment_id}`, `:id`, `<id>`) as `{}`, no trailing punctuation."""
    path = path.rstrip(".:")
    return "/".join("{}" if re.fullmatch(r"\{[^}]*\}|:[A-Za-z_]\w*|<[^>]*>", seg) else seg for seg in path.split("/"))


def intent_decisions(spec_dir):
    """The text of intent.md's `### Decisions` section (the person's answers), or ""."""
    try:
        lines = open(os.path.join(spec_dir, "intent.md"), encoding="utf-8").read().splitlines()
    except OSError:
        return ""
    out, inside = [], False
    for line in lines:
        if line.startswith("#"):
            inside = line.strip().lower() == "### decisions"
            continue
        if inside:
            out.append(line)
    return "\n".join(out)


def plan_request_routes(spec_dir, project):
    """9.8.0 (round 5): every HTTP route the request names (`POST /invoices/{id}/refunds`) is in the plan, method and shape
    unchanged (a parameter may be renamed). A run's Plan once built the request's refund route as another path, and
    Design, the acceptance tests and Build followed it; only the session noticed. The request is the run's feature text
    (`temper state init --feature`); a request that names no route passes, and so does a route the person changed in the
    intent's Decisions."""
    name = "request routes kept"
    try:
        state = json.load(open(os.path.join(project, ".temper", "build-state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    feature = state.get("feature") if isinstance(state, dict) else None
    want = [(m.group(1), route_shape(m.group(2))) for m in ROUTE.finditer(feature or "")]
    want = list(dict.fromkeys(want))
    if not want:
        return row(name, True, "the request names no route")
    text = ""
    for f in ("plan.md", "tasks.md"):
        try:
            text += open(os.path.join(spec_dir, f), encoding="utf-8").read() + "\n"
        except OSError:
            pass
    have = {(m.group(1), route_shape(m.group(2))) for m in ROUTE.finditer(text)}
    # The person may change a route at Intent: a route the request names that the plan does not is kept out when the
    # intent's Decisions name it (they decided about it) or name the plan's route of the same method (they chose it).
    decided = {(m.group(1), route_shape(m.group(2))) for m in ROUTE.finditer(intent_decisions(spec_dir))}
    missing = [w for w in want if w not in have and w not in decided
               and not any(h in decided for h in have if h[0] == w[0])]
    if not missing:
        return row(name, True, "%d route(s) of the request, each in the plan: %s" % (len(want), ", ".join("%s %s" % w for w in want)))
    detail = "; ".join("the request names %s %s, the plan does not%s" % (
        mth, path, (" (it names %s)" % ", ".join("%s %s" % h for h in sorted(have) if h[0] == mth)) if any(h[0] == mth for h in have) else "")
        for mth, path in missing)
    return row(name, False, detail + ". Keep each route the request names, method and path, in plan.md (a parameter may be renamed)")


def main(argv):
    if len(argv) == 3 and argv[1] == "pipeline-gate":
        print(pipeline_gate(argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == "scenario-known":
        names = [b["name"] for b in acceptance.scenario_blocks(open(argv[2], encoding="utf-8").read().splitlines())]
        return 0 if argv[3] in names else 1
    if len(argv) in (4, 5) and argv[1] == "plan-rows":
        print(json.dumps(plan_scenario_commands(argv[2], argv[3])))
        print(json.dumps(plan_maven_verify(argv[2], argv[3])))
        print(json.dumps(plan_request_routes(argv[2], argv[3])))
        if os.path.isfile(os.path.join(argv[2], "plan.md")):   # a run with no plan.md (the trivial path) has no map to review
            print(json.dumps(plan_ops.gate_row(argv[2], argv[4] if len(argv) == 5 else "auto")))
        print(json.dumps(decisions.row(argv[3], argv[2])))   # WP14: the answers reach tasks.md before the approval
        print(json.dumps(plan_maven_filtered(argv[2], argv[3])))
        return 0
    if len(argv) in (4, 5) and argv[1] == "build-rows":
        for r in build_rows(argv[2], argv[3], argv[4] if len(argv) == 5 else ""):
            print(json.dumps(r))
        return 0
    if len(argv) in (4, 5) and argv[1] == "check-rows":
        print(json.dumps(check_rows(argv[2], argv[3], argv[4] if len(argv) == 5 else "")))
        rows = ledger_rows(argv[2])
        for r in (acceptance_row(rows), regression_row(rows) if fix_run() else None):   # WP23: moved out of scripts/temper
            if r:
                print(json.dumps(r))
        return 0
    if len(argv) == 3 and argv[1] == "intent-rules":
        print(json.dumps(intent_rules(argv[2])))
        return 0
    if len(argv) == 3 and argv[1] == "intent-blocking":
        print(json.dumps(intent_blocking(argv[2])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
