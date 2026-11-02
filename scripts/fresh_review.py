"""fresh_review.py: the fresh review of a plan (9.7.6), read from the plan ledger. Nothing here decides a verdict by
judgment: it counts rows the reviewer recorded and compares digests.

  python3 fresh_review.py rows SPEC_DIR EVIDENCE.json COMPLEXITY MODE RISK [TWICE]   the plan gate's rows, one JSON per line
  python3 fresh_review.py status SPEC_DIR EVIDENCE.json COMPLEXITY MODE RISK [TWICE] the state flow.py reads, one JSON

A reviewer with no context (agents/plan-review.md) reads intent.md, plan.md and tasks.md as a newcomer would, through three
lenses, and records each in the plan ledger (`temper evidence add --stage plan --phase fresh`), every row with
`--artifact SPEC/tasks.md`, so the row carries the digest of the tasks.md it was found against:

  a finding     claim `[lens] scope: what is missing`, --severity high (a blocker), medium or low
  a lens done   claim `fresh review completed: <lens> <instance>`, --exit 0
  a paraphrase  claim `paraphrase: <what this proposes> | <how the system works, per the plan>`

Only rows recorded against the tasks.md as it is now count: an edited tasks.md makes the review stale, and it runs again.
A lens that recorded no completion row did not review; it is `not run`, never a lens with no findings.

MODE is plan.fresh-review: auto (medium and complex tiers), always, or off. RISK H runs two independent reviewers (A and
B) unless TWICE is false. Standard library only.
"""
import hashlib
import json
import os
import re
import sys

LENSES = ("readiness", "zoom-out", "comprehension")
BLOCKING = ("critical", "high")
DONE = re.compile(r"^fresh review completed:\s*(\S+)\s+(\S+)\s*$")
FINDING = re.compile(r"^\[([\w-]+)\]\s*(.*)$", re.S)


def digest(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return ""


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            rows = json.load(fh)
    except (OSError, ValueError):
        return []
    return rows if isinstance(rows, list) else []


def applies(complexity, mode):
    mode = (mode or "auto").strip().lower()
    if mode in ("off", "false", "no"):
        return False
    if mode in ("always", "on", "true", "yes"):
        return True
    return (complexity or "").strip().lower() in ("medium", "complex")


def instances(risk, twice="true"):
    return ["A", "B"] if (risk or "").strip().upper() == "H" and str(twice).strip().lower() != "false" else ["A"]


def state_of(row):
    if row.get("resolved"):
        return "resolved"
    if row.get("accepted"):
        return "accepted"
    if row.get("contested"):
        return "contested"
    if row.get("escalated"):
        return "escalated"
    return "open"


def status(spec, ev_path, complexity, mode, risk, twice="true"):
    tasks = os.path.join(spec, "tasks.md")
    sha = digest(tasks)
    need = [(lens, i) for i in instances(risk, twice) for lens in LENSES]
    out = {"applies": applies(complexity, mode) and bool(sha), "sha": sha, "need": ["%s %s" % n for n in need],
           "done": [], "missing": [], "todo": [], "stale": False, "paraphrase": "", "findings": [], "contests": []}
    if not out["applies"]:
        return out
    done, older = set(), False
    for i, r in enumerate(load(ev_path), 1):
        if not isinstance(r, dict) or r.get("phase") != "fresh":
            continue
        claim = str(r.get("claim") or "")
        current = r.get("sha256") == sha
        m = DONE.match(claim)
        if m:
            if current and r.get("exit_code") == 0:
                done.add((m.group(1).lower(), m.group(2).upper()))
            elif not current:
                older = True
            continue
        if claim.lower().startswith("paraphrase:"):
            if current:
                out["paraphrase"] = claim.split(":", 1)[1].strip()
            continue
        if not r.get("severity"):
            continue
        f = FINDING.match(claim)
        item = {"id": i, "severity": str(r.get("severity")).lower(), "lens": f.group(1).lower() if f else "",
                "claim": claim, "state": state_of(r)}
        if r.get("contested"):
            item["cite"] = r["contested"].get("cite")
            item["why"] = r["contested"].get("reason")
        if r.get("escalated"):
            item["why"] = r["escalated"].get("reason")
        if current:
            out["findings"].append(item)
        elif item["state"] == "contested":
            out["contests"].append(item)   # a contest of an earlier tasks.md: the next reviewer reads its evidence first
    out["done"] = ["%s %s" % n for n in need if n in done]
    out["missing"] = ["%s %s" % n for n in need if n not in done]
    out["stale"] = bool(out["missing"]) and older and not done
    # what a reviewer still has to do: the lenses not run, or the comprehension lens again when no paraphrase was recorded
    out["todo"] = out["missing"] or ([] if out["paraphrase"] else ["comprehension %s" % instances(risk, twice)[0]])
    return out


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
    if not st["missing"]:
        out.append(row("fresh review ran", True, "%s ran on this tasks.md" % ", ".join(st["done"])))
    elif st["stale"]:
        out.append(row("fresh review ran", False, "tasks.md changed after the fresh review; it runs again on the new text"))
    else:
        out.append(row("fresh review ran", False, "not run: %s; a reviewer that recorded no completion row did not review" % ", ".join(st["missing"])))
    if st["paraphrase"]:
        out.append(row("fresh reader's paraphrase", True, st["paraphrase"][:200]))
    else:
        out.append(row("fresh reader's paraphrase", False, "no paraphrase recorded for this tasks.md"))
    b = blockers(st)
    if b:
        out.append(row("no open plan blockers", False, "%d open: %s" % (len(b), " | ".join(describe(f) for f in b))))
    else:
        n = len([f for f in st["findings"] if f["state"] not in ("resolved", "accepted")])
        out.append(row("no open plan blockers", True, "0 open blockers%s" % (", %d lesser finding(s) open" % n if n else "")))
    return out


def main(argv):
    if len(argv) in (7, 8) and argv[1] in ("rows", "status"):
        st = status(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7] if len(argv) == 8 else "true")
        if argv[1] == "status":
            print(json.dumps(st))
        else:
            for r in rows(st):
                print(json.dumps(r))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
