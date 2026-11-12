"""fresh_review.py: the fresh review of a plan (9.7.6), read from the plan ledger and the run state. Nothing here judges a plan:
it counts rows a reviewer recorded and compares digests and times.

  python3 fresh_review.py rows SPEC_DIR EVIDENCE.json STATE.json MODE TWICE ROUNDS   the plan gate's rows, one JSON per line
  python3 fresh_review.py status SPEC_DIR EVIDENCE.json STATE.json MODE TWICE ROUNDS the state flow.py reads, one JSON
  python3 fresh_review.py mark request|start|again|loop STATE.json SPEC_DIR ROUNDS NOW EVIDENCE.json   the CLI's marks (temper plan
                                                                        fresh; loop: a step back to Intent, Plan or Design)

A reviewer with no context (agents/plan-review.md) reads intent.md, plan.md and tasks.md as a newcomer would, through three
lenses, and records what it finds in the plan ledger (`temper evidence add --stage plan --phase fresh`):

  a finding     claim `[lens] scope: what is missing`, --severity high (a blocker), medium or low
  a lens done   claim `fresh review completed: <lens> <instance>`, --exit 0; the readiness lens also gives --value N, the
                number of tasks it checked, which must be the number of tasks in tasks.md
  a paraphrase  claim `paraphrase: <what this plan proposes> | <how the system works, per the plan>`, each part 6 words or more

The CLI marks each launch (`temper plan fresh start`, run by the orchestrator just before it launches the reviewer, so after the
Plan agent returned): the digest of intent.md, plan.md and tasks.md, the time, and how many rows the plan ledger held. Only rows
appended after that count, so a row the Plan agent wrote itself never does (a ledger shorter than the mark was cleared: the
review has not run on it). An edit of any of the three files after the launch makes the review stale.
A lens with no completion row did not review: it is `not run`, never a lens with no findings.

MODE is plan.fresh-review: ask (the default: the plan question offers it, at every tier, and it applies once the person asks
for it), auto (medium and complex tiers), always, or off. A risk H plan gets two independent reviewers (A and B) unless TWICE
is false. ROUNDS (plan.fresh-review-rounds, default 3) caps the launches of one run; 9.8.4: a loop back (or a replan) after
which plan.md or tasks.md changed earns one more round (cap_of). Standard library only.
"""
import hashlib
import json
import os
import re
import sys

# 9.8.4: the first round runs four lenses, `tests` among them (which existing tests the change breaks, and which task updates
# them); every later round on the same review is a `recheck`: it checks only whether each earlier finding is fixed and reads
# only the task blocks that changed. Rounds that each read the whole plan again found 18, 14 and 4 new findings in a measured
# run, and never converged.
LENSES = ("readiness", "zoom-out", "comprehension", "tests")
LENSES_BEFORE = ("readiness", "zoom-out", "comprehension")   # a launch recorded by a version before 9.8.4
RECHECK = ("recheck",)
BLOCKING = ("critical", "high")
DONE = re.compile(r"^fresh review completed:\s*(\S+)\s+(\S+)\s*$")
FINDING = re.compile(r"^\[([\w-]+)\]\s*(.*)$", re.S)
TASK = re.compile(r"^###\s+Task\s+\d+", re.M)
FILES = ("intent.md", "plan.md", "tasks.md")
MIN_WORDS = 6


def digest(spec):
    """One digest over the three files a reviewer reads; '' when tasks.md is missing."""
    if not os.path.isfile(os.path.join(spec, "tasks.md")):
        return ""
    h = hashlib.sha256()
    for name in FILES:
        h.update(name.encode() + b"\0")
        try:
            with open(os.path.join(spec, name), "rb") as fh:
                h.update(fh.read())
        except OSError:
            h.update(b"(absent)")
        h.update(b"\0")
    return h.hexdigest()


def plan_digest(spec):
    """9.8.4: one digest over plan.md and tasks.md, the files a loop back must change to earn one more round."""
    h = hashlib.sha256()
    for name in ("plan.md", "tasks.md"):
        try:
            with open(os.path.join(spec, name), "rb") as fh:
                h.update(name.encode() + b"\0" + fh.read() + b"\0")
        except OSError:
            h.update(name.encode() + b"\0(absent)\0")
    return h.hexdigest()


def cap_of(fs, spec, cap):
    """9.8.4: the round limit of this run: plan.fresh-review-rounds, plus one round for each loop back (or replan) after which
    plan.md or tasks.md changed. A loop back records the digest of those files (`grant`); the round it earns is taken at the
    next launch (`extra`). Without it a loop back cleared the review while the spent rounds forbade a new one, and the gate
    failed on "not run yet" with Override as the only way on."""
    extra = int(fs.get("extra") or 0)
    grant = fs.get("grant")
    # the round is earned only at the limit; below it the next launch takes the grant with no round added (mark start)
    pending = isinstance(grant, str) and grant != plan_digest(spec) and int(fs.get("rounds") or 0) >= cap + extra
    return cap + extra + (1 if pending else 0), pending


def load(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return default
    return d if isinstance(d, type(default)) else default


def fresh_state(state):
    f = state.get("fresh")
    return f if isinstance(f, dict) else {}


def applies(mode, complexity, requested):
    mode = (mode or "ask").strip().lower()
    if mode in ("off", "false", "no"):
        return False
    if mode in ("always", "on", "true", "yes"):
        return True
    if mode == "auto":
        return (complexity or "").strip().lower() in ("medium", "complex")
    return bool(requested)     # ask: the person asked for it at the plan question


def instances(risk, twice="true"):
    return ["A", "B"] if (risk or "").strip().upper() == "H" and str(twice).strip().lower() != "false" else ["A"]


def state_of(row):
    """A finding's state: the one reading, findings.finding_state (the CLI's and flow.py's too)."""
    import findings
    return findings.finding_state(row)


def task_count(spec):
    try:
        with open(os.path.join(spec, "tasks.md"), encoding="utf-8") as fh:
            return len(TASK.findall(fh.read()))
    except OSError:
        return 0


def task_hashes(spec):
    """{task number: digest of its block} of tasks.md, so a later round knows which blocks changed."""
    try:
        with open(os.path.join(spec, "tasks.md"), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return {}
    out, cur, buf = {}, None, []
    for line in text.split("\n") + ["## end"]:
        m = re.match(r"^###\s+Task\s+(\d+)", line)
        if m or re.match(r"^##?\s", line):
            if cur is not None:
                out[cur] = hashlib.sha256("\n".join(buf).strip().encode()).hexdigest()
            cur, buf = (m.group(1) if m else None), []
        if cur is not None:
            buf.append(line)
    return out


def planned_recheck(fs, ledger, spec):
    """What the next round re-checks, or None for a full round: the open findings and the paraphrase of the round that ran
    last (its launch window, while the ledger still holds it) and the task blocks changed since it. A round whose reviewer
    recorded no completion row did not run, so the next one is full."""
    launch = fs.get("launch") if isinstance(fs.get("launch"), dict) else None
    if launch is None or len(ledger) < int(launch.get("rows") or 0):
        p = fs.get("pending_recheck")
        return p if isinstance(p, dict) else None
    found, para, ran = [], launch.get("paraphrase", "") if isinstance(launch.get("recheck"), dict) else "", False
    for i, r in enumerate(ledger, 1):
        if i <= int(launch.get("rows") or 0) or not isinstance(r, dict) or r.get("phase") != "fresh":
            continue
        claim = str(r.get("claim") or "")
        if DONE.match(claim) and r.get("exit_code") == 0:
            ran = True
        elif claim.lower().startswith("paraphrase:"):
            para = claim.split(":", 1)[1].strip()
        elif r.get("severity") and state_of(r) not in ("resolved", "accepted"):
            found.append({"id": i, "severity": str(r.get("severity")).lower(), "claim": claim})
    if not ran:
        return None
    if isinstance(launch.get("recheck"), dict):
        para = para or launch["recheck"].get("paraphrase", "")
    before, now = launch.get("tasks") or {}, task_hashes(spec)
    changed = sorted(int(n) for n in now if now[n] != before.get(n)) if before else sorted(int(n) for n in now)
    return {"findings": found, "changed": changed, "paraphrase": para}


def paraphrase_ok(text):
    parts = [p.strip() for p in text.split("|")]
    return len(parts) >= 2 and all(len(p.split()) >= MIN_WORDS for p in parts[:2])


def status(spec, ev_path, state_path, mode, twice="true", rounds_cap="3"):
    state = load(state_path, {})
    fs = fresh_state(state)
    try:
        cap = max(int(rounds_cap), 1)
    except ValueError:
        cap = 3
    complexity, risk = state.get("complexity") or "", state.get("risk") or ""
    m = (mode or "ask").strip().lower()
    now = digest(spec)
    launch = fs.get("launch") if isinstance(fs.get("launch"), dict) else None
    out = {"mode": m, "applies": applies(m, complexity, fs.get("requested")) and bool(now), "digest": now,
           "offer": m == "ask" and not fs.get("requested") and bool(now) and state.get("command", "temper") == "temper",
           "need": [], "done": [], "missing": [], "stale": False, "launched": launch is not None, "recheck": None,
           "rounds": int(fs.get("rounds") or 0), "cap": cap_of(fs, spec, cap)[0], "capped": int(fs.get("rounds") or 0) >= cap_of(fs, spec, cap)[0],
           "paraphrase": "", "paraphrase_short": False, "lazy": [], "findings": [], "contests": []}
    ledger = load(ev_path, []) if out["applies"] else []
    if launch is not None and len(ledger) < int(launch.get("rows") or 0):
        launch = None                      # the ledger was cleared since the launch (a loop back): it has not run on this one
        out["launched"] = False
    out["stale"] = launch is not None and launch.get("digest") != now
    # the lenses of the round on these files: the launch's own, or (before the next launch) the ones it will run
    if launch is not None and not out["stale"]:
        lenses = launch.get("lenses") or LENSES_BEFORE
        out["recheck"] = launch.get("recheck") if isinstance(launch.get("recheck"), dict) else None
    else:
        out["recheck"] = planned_recheck(fs, ledger, spec) if out["applies"] else None
        lenses = RECHECK if out["recheck"] else LENSES
    need = [(lens, i) for i in instances(risk, twice) for lens in lenses]
    out["need"] = ["%s %s" % n for n in need]
    if not out["applies"]:
        return out
    after = int(launch.get("rows") or 0) if launch and not out["stale"] else None
    done, tasks = set(), task_count(spec)
    for i, r in enumerate(ledger, 1):
        if not isinstance(r, dict) or r.get("phase") != "fresh":
            continue
        claim = str(r.get("claim") or "")
        current = after is not None and i > after
        mm = DONE.match(claim)
        if mm:
            if current and r.get("exit_code") == 0:
                lens, inst = mm.group(1).lower(), mm.group(2).upper()
                if lens == "readiness" and r.get("value") != tasks:
                    out["lazy"].append("readiness %s checked %s task(s), tasks.md has %d" % (
                        inst, "no count of" if r.get("value") is None else "%g" % r.get("value"), tasks))
                    continue
                want = len((out["recheck"] or {}).get("findings") or [])
                if lens == "recheck" and r.get("value") != want:
                    out["lazy"].append("recheck %s checked %s earlier finding(s), the round has %d" % (
                        inst, "no count of" if r.get("value") is None else "%g" % r.get("value"), want))
                    continue
                done.add((lens, inst))
            continue
        if claim.lower().startswith("paraphrase:"):
            if current:
                out["paraphrase"] = claim.split(":", 1)[1].strip()
            continue
        if not r.get("severity"):
            continue
        f = FINDING.match(claim)
        item = {"id": i, "severity": str(r.get("severity")).lower(), "lens": f.group(1).lower() if f else "",
                "claim": claim, "state": state_of(r), "cite": None, "quote": None, "why": None}
        if r.get("contested"):
            item.update(cite=r["contested"].get("cite"), quote=r["contested"].get("quote"), why=r["contested"].get("reason"))
        if r.get("escalated"):
            item["why"] = r["escalated"].get("reason")
        if current:
            out["findings"].append(item)
        elif item["state"] == "contested":
            out["contests"].append(item)   # a contest of an earlier round: the next reviewer reads its evidence first
    if not out["paraphrase"] and after is not None and out["recheck"]:
        out["paraphrase"] = out["recheck"].get("paraphrase") or ""   # a recheck keeps the paraphrase of the round it checks
    out["paraphrase_short"] = bool(out["paraphrase"]) and not paraphrase_ok(out["paraphrase"])
    out["done"] = ["%s %s" % n for n in need if n in done]
    out["missing"] = ["%s %s" % n for n in need if n not in done]
    return out


def need_launch(st):
    """The CLI launches the reviewer by itself only when it has not run on these files: never launched, or the files changed."""
    return st["applies"] and (not st["launched"] or st["stale"]) and not st["capped"]


def blockers(st):
    return [f for f in st["findings"] if f["severity"] in BLOCKING and f["state"] not in ("resolved", "accepted")]


def describe(f):
    tail = ""
    if f["state"] == "contested":
        tail = " (contested: %s)" % f.get("cite")
    elif f["state"] == "escalated":
        tail = " (escalated: only the person knows)"
    return "#%d %s%s" % (f["id"], f["claim"][:120], tail)


def row(name, ok, detail):
    return {"name": name, "pass": ok, "detail": detail}


def rows(st):
    if not st["applies"]:
        return []
    out = []
    lazy = "; " + "; ".join(st["lazy"]) if st["lazy"] else ""
    if st["stale"]:
        out.append(row("fresh review ran", False, "intent.md, plan.md or tasks.md changed after the fresh review; it runs again on the new text"))
    elif not st["launched"]:
        out.append(row("fresh review ran", False, "not run yet: the CLI launches it (temper plan fresh start)"))
    elif st["missing"]:
        out.append(row("fresh review ran", False, "not run: %s; a reviewer that recorded no completion row did not review%s" % (", ".join(st["missing"]), lazy)))
    else:
        out.append(row("fresh review ran", True, "%s ran on these files (round %d of %d)" % (", ".join(st["done"]), st["rounds"], st["cap"])))
    if st["paraphrase"] and not st["paraphrase_short"]:
        out.append(row("fresh reader's paraphrase", True, st["paraphrase"][:200]))
    elif st["paraphrase"]:
        out.append(row("fresh reader's paraphrase", False, "too short to compare with the intent (each part needs %d words or more): %s" % (MIN_WORDS, st["paraphrase"][:120])))
    else:
        out.append(row("fresh reader's paraphrase", False, "no paraphrase recorded for these files"))
    b = blockers(st)
    if b:
        out.append(row("no open plan blockers", False, "%d open: %s" % (len(b), " | ".join(describe(f) for f in b))))
    else:
        n = len([f for f in st["findings"] if f["state"] not in ("resolved", "accepted")])
        out.append(row("no open plan blockers", True, "0 open blockers%s" % (", %d lesser finding(s) open" % n if n else "")))
    return out


def mark(what, state_path, spec, rounds_cap, now, ev_path):
    """The CLI's marks, in the run state under `fresh`: the person asked for the review, a reviewer is launched (the digest of
    the three files and the time; one round more), or a reviewer that did not finish runs again."""
    state = load(state_path, {})
    if not state:
        print("FAIL: no active run (temper state init first)", file=sys.stderr)
        return 1
    fs = fresh_state(state)
    try:
        cap = max(int(rounds_cap), 1)
    except ValueError:
        cap = 3
    if what == "request":
        fs["requested"] = True
        msg = "the fresh review is requested; it runs before the plan question"
    elif what == "start":
        d = digest(spec)
        if not d:
            print("FAIL: no tasks.md in %s to review" % spec, file=sys.stderr)
            return 1
        limit, pending = cap_of(fs, spec, cap)
        if int(fs.get("rounds") or 0) >= limit:
            print("FAIL: the fresh review ran %d round(s), the limit (plan.fresh-review-rounds%s); the person decides at the plan question" % (
                limit, ", and one more after each loop back that changes plan.md or tasks.md" if fs.get("grant") or fs.get("extra") else ""), file=sys.stderr)
            return 1
        if pending:
            fs["extra"] = int(fs.get("extra") or 0) + 1   # the round a loop back earned is taken now
        fs.pop("grant", None)                             # a grant serves the next launch only
        ledger = load(ev_path, [])
        rc = planned_recheck(fs, ledger, spec)
        fs["launch"] = {"digest": d, "ts": now, "rows": len(ledger), "tasks": task_hashes(spec), "lenses": list(RECHECK if rc else LENSES)}
        if rc:
            fs["launch"]["recheck"] = rc
        fs.pop("pending_recheck", None)
        fs["rounds"] = int(fs.get("rounds") or 0) + 1
        msg = "fresh review round %d of %d launched on these files" % (fs["rounds"], cap)
    elif what == "again":
        la = fs.pop("launch", None)
        if isinstance(la, dict) and isinstance(la.get("recheck"), dict):
            fs["pending_recheck"] = la["recheck"]   # the recheck that did not finish runs again as a recheck
        msg = "the fresh review runs again"
    elif what == "loop":
        # 9.8.4: a loop back (or a replan) earns one more round once plan.md or tasks.md changes; a second loop back before
        # that round is taken earns no second one
        fs["grant"] = plan_digest(spec)
        msg = "a loop back: the fresh review may run one more round once plan.md or tasks.md changes"
    else:
        print("FAIL: usage: temper plan fresh request|start|again", file=sys.stderr)
        return 1
    state["fresh"] = fs
    tmp = "%s.tmp.%d" % (state_path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(state, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, state_path)
    print("OK: %s" % msg)
    return 0


def main(argv):
    if len(argv) == 8 and argv[1] in ("rows", "status"):
        st = status(*argv[2:8])
        if argv[1] == "status":
            print(json.dumps(st))
        else:
            for r in rows(st):
                print(json.dumps(r))
        return 0
    if len(argv) == 8 and argv[1] == "mark":
        return mark(*argv[2:8])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
