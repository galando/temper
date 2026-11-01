"""risk.py: the rating of a plan, computed from its blast radius (F11). One call, the same answer for the same input.

  python3 risk.py compute SPEC_DIR SECURITY_MAP.json [--raise L|M|H --reason TEXT] [--prior L|M|H]

Prints `RISK: M (5 production files; HIGH file src/x.py)` and, on a second line, a JSON object with the fields the CLI
keeps in the run state (risk, risk_reasons, risk_raise, risk_raise_reason). Exit 1 with a message for a raise with no
reason, or one that would lower the rating. Standard library only.

The rule: production files are the files the tasks declare that are neither tests nor docs. Up to 3 is L, up to 10 is M,
more is H. A CRITICAL entry in the security map makes it H. A HIGH entry, or a [CROSS-REPO] row in plan.md's Blast Radius
section, moves it up one tier (at most H), once.
"""
import json
import os
import re
import sys

import tasks_md

TIERS = ["L", "M", "H"]
TEST_DIR = re.compile(r"(^|/)(tests?|__tests__|specs?)/")
DOC_DIR = re.compile(r"(^|/)docs?/")
TEST_NAME = re.compile(r"(\.(test|spec)\.|^test_|_test\.)")
DOC_NAME = re.compile(r"^(readme|changelog)", re.I)


def is_production(path):
    p = path.strip().lstrip("./")
    base = os.path.basename(p)
    if TEST_DIR.search(p) or DOC_DIR.search(p) or TEST_NAME.search(base) or DOC_NAME.match(base):
        return False
    return True


def declared_files(spec):
    files = []
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    for t in plan["tasks"]:
        for f in t["files"]:
            if f not in files:
                files.append(f)
    return files


def security_levels(path):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if isinstance(data, dict):
        data = data.get("entries", list(data.values()))
    out = []
    for e in data if isinstance(data, list) else []:
        if isinstance(e, dict) and e.get("sensitivity"):
            out.append((str(e["sensitivity"]).upper(), str(e.get("file") or "")))
    return out


def cross_repo(spec):
    try:
        text = open(os.path.join(spec, "plan.md"), encoding="utf-8").read()
    except OSError:
        return False
    m = re.search(r"^##\s+Blast Radius\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
    return bool(m and "[CROSS-REPO]" in m.group(1))


def tier_up(level):
    return TIERS[min(TIERS.index(level) + 1, 2)]


def compute(spec, security_map, raise_to="", reason="", prior=""):
    prod = [f for f in declared_files(spec) if is_production(f)]
    n = len(prod)
    level = "L" if n <= 3 else ("M" if n <= 10 else "H")
    why = ["%d production file%s" % (n, "" if n == 1 else "s")]
    sec = security_levels(security_map)
    crit = [f for lv, f in sec if lv == "CRITICAL"]
    high = [f for lv, f in sec if lv == "HIGH"]
    cross = cross_repo(spec)
    if crit:
        level = "H"
        why.append("CRITICAL file %s" % (crit[0] or "in the security map"))
    elif high or cross:
        level = tier_up(level)
        if high:
            why.append("HIGH file %s" % (high[0] or "in the security map"))
        if cross:
            why.append("CROSS-REPO row in the Blast Radius")
    held = prior if prior in TIERS else ""
    if raise_to:
        if raise_to not in TIERS:
            raise ValueError("--raise takes L, M or H")
        if not reason.strip():
            raise ValueError("a raise needs a reason (--reason '<why>')")
        if TIERS.index(raise_to) < TIERS.index(level):
            raise ValueError("a raise never lowers the rating: the blast radius gives %s, and %s is lower" % (level, raise_to))
        if not held or TIERS.index(raise_to) > TIERS.index(held):
            held = raise_to
    state = {"risk": level, "risk_reasons": "; ".join(why)}
    if held and TIERS.index(held) > TIERS.index(level):
        state["risk"] = held
        state["risk_reasons"] += "; raised by the person to %s" % held
    if held:
        state["risk_raise"] = held
    if raise_to and reason.strip():
        state["risk_raise_reason"] = reason.strip()
    return state


def main(argv):
    if len(argv) < 4 or argv[1] != "compute":
        print(__doc__, file=sys.stderr)
        return 2
    opt = lambda name: argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else ""
    try:
        state = compute(argv[2], argv[3], opt("--raise"), opt("--reason"), opt("--prior"))
    except ValueError as e:
        print("FAIL: %s" % e, file=sys.stderr)
        return 1
    print("RISK: %s (%s)" % (state["risk"], state["risk_reasons"]))
    print(json.dumps(state))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
