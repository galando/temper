#!/usr/bin/env python3
"""acceptance.py — explicit validation links between criteria, scenarios, and evidence.

Usage: acceptance.py <stage> <intent.md> <evidence.json>
       acceptance.py status <intent.md> <evidence-dir>

`status` prints {criteria: [{id, priority, status: passed|open, evidence}], ts} as
JSON for `.temper/status.json`: a criterion is passed when its latest `criterion` row
is a supported pass, or when it is Covered by scenarios that ALL have a supported
passing latest row. Rows from each stage's ledger file in the evidence dir (one file per
name on the fixed EVIDENCE_STAGES list, the same list scripts/temper allows) are merged
by ts.

Prints `every criterion has explicit validation links` on success, or the errors
joined with `; ` and exits non-zero. python3 stdlib only.

At stage `plan` the artifact must be internally consistent: stable AC-NN ids,
Validate links, Covers references. At stage `check` additionally every scenario
and non-scenario criterion must have a SUPPORTED PASSING evidence row (the
latest row for that scenario/criterion wins — a newer failure is never hidden by
an older pass).

A supported pass = exit_code == 0 AND (an artifact whose CURRENT sha256 still
matches the recorded sha256, OR a non-empty cmd).
"""
import hashlib
import json
import re
import sys

OK_LINE = "every criterion has explicit validation links"
VALIDATE_TYPES = ("scenario", "code", "manual", "metric")
AC_RE = re.compile(r"^AC-\d{2,}$")
COVERS_RE = re.compile(r"^\s*Covers:\s*(.+?)\s*$", re.I)
VALIDATE_RE = re.compile(r"^\s*Validate:\s*(\w+)\s*[—-]\s*(.*)$", re.I)
BULLET_RE = re.compile(r"^(\s*)-\s+")
# The stage names a ledger file can carry (scripts/temper EVIDENCE_STAGES). `status`
# reads one file per name, in this order, and no other file in the evidence dir.
EVIDENCE_STAGES = ("build", "check", "commit", "design", "fix", "intent", "plan", "rca", "review")


def blank_placeholders(text):
    """Blank every {...} span so `Why: {…}` doesn't count as content."""
    return re.sub(r"\{[^{}]*\}", "", text)


def strip_checkbox(line):
    """`- [ ] AC-01 ...` -> `AC-01 ...`; plain `- AC-01 ...` unchanged."""
    t = BULLET_RE.sub("", line.rstrip())
    t = re.sub(r"^\[[ xX]\]\s*", "", t)
    return t.strip()


def heading_level(line):
    m = re.match(r"^(#{1,6})\s", line)
    return len(m.group(1)) if m else 0


def section_lines(lines, name):
    """Lines under a heading matching `name` (case-insensitive, any level),
    closing at the next heading of the same or higher level. Fenced code blocks
    are passed through untouched (the caller decides whether to use them)."""
    out, active, level = [], False, 0
    for line in lines:
        h = heading_level(line)
        if h:
            if active and h <= level:
                break
            if not active and re.match(r"^#{1,6}\s+" + re.escape(name) + r"\s*$", line, re.I):
                active, level = True, h
                continue
        if active:
            out.append(line)
    return out


def scenario_lines(lines):
    """(name, line_number) for every `Scenario:` line, fenced or not —
    every scenario reader is line-based."""
    out = []
    for i, line in enumerate(lines, 1):
        m = re.match(r"^\s*Scenario:\s*(.+?)\s*$", line)
        if m:
            out.append((m.group(1), i))
    return out


def covers_ids_in_lines(lines):
    """Every AC id mentioned on a `Covers:` line within these lines."""
    ids = []
    for line in lines:
        m = COVERS_RE.match(line)
        if m:
            for tok in m.group(1).split(","):
                tok = tok.strip()
                if tok:
                    ids.append(tok)
    return ids


def parse_criteria(lines):
    """Success Criteria bullets -> list of dicts:
    {id, optional, deferred, has_validate, vtype, vdetails, why, first_line, lineno}.
    Placeholder bullets (content starting with `{`) are skipped by every counter."""
    crits, cur = [], None
    in_fence = False
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            in_fence = not in_fence
            continue
        if in_fence:
            if cur is not None:
                cur["block"].append(line)
            continue
        if BULLET_RE.match(line):
            if cur is not None:
                crits.append(cur)
            content = strip_checkbox(line)
            cur = {"first_line": content, "lineno": i, "block": [line]}
            if content.startswith("{"):
                cur["placeholder"] = True
        elif cur is not None:
            cur["block"].append(line)
    if cur is not None:
        crits.append(cur)
    for c in crits:
        if c.get("placeholder"):
            continue
        m = re.match(r"^(AC-\d+)\s*\[(required|optional)\]:", c["first_line"])
        c["id"] = m.group(1) if m else None
        c["priority"] = m.group(2) if m else None
        c["optional"] = (m.group(2) == "optional") if m else None
        c["deferred"] = any(re.match(r"^\s*Deferred:", l) for l in c["block"])
        vm = None
        for l in c["block"]:
            vm = VALIDATE_RE.match(l)
            if vm:
                break
        c["has_validate"] = bool(vm)
        c["vtype"] = vm.group(1).lower() if vm else None
        c["vdetails"] = blank_placeholders(vm.group(2)).strip() if vm else ""
        wm = re.search(r"Why:\s*(.*)", "\n".join(c["block"]))
        c["why"] = blank_placeholders(wm.group(1)).strip() if wm else ""
    return crits


def load_evidence(path):
    try:
        rows = json.load(open(path))
    except Exception:
        return []
    return rows if isinstance(rows, list) else []


def supported_pass(row):
    if row.get("exit_code") != 0:
        return False
    artifact, sha = row.get("artifact"), row.get("sha256")
    if artifact and sha:
        try:
            cur = hashlib.sha256(open(artifact, "rb").read()).hexdigest()
            return cur == sha
        except OSError:
            return False
    return bool(row.get("cmd"))


def latest_by_key(rows, key):
    """Latest row per key value (a later row always shadows an earlier one)."""
    out = {}
    for r in rows:
        k = r.get(key)
        if k:
            out[k] = r
    return out


def status_report(intent_path, ev_dir):
    """Per-criterion status for the live view (`temper status --json`)."""
    import datetime
    import os
    lines = open(intent_path).read().splitlines()
    real = [c for c in parse_criteria(section_lines(lines, "Success Criteria"))
            if not c.get("placeholder") and c.get("id")]
    rows = []
    for stage in EVIDENCE_STAGES:
        for i, r in enumerate(load_evidence(os.path.join(ev_dir, stage + ".json")), 1):
            if isinstance(r, dict):
                rows.append((r.get("ts") or "", stage, i, r))
    rows.sort(key=lambda t: t[0])   # stable: equal ts keeps file order

    def latest(key, value):
        hit = None
        for _, stage, i, r in rows:
            if r.get(key) == value:
                hit = (stage, i, r)
        return hit

    # scenario name -> the AC ids its Covers: line names (the line sits in its block)
    covers, current = {}, None
    for line in lines:
        m = re.match(r"^\s*Scenario:\s*(.+?)\s*$", line)
        if m:
            current = m.group(1)
            covers.setdefault(current, [])
            continue
        cm = COVERS_RE.match(line)
        if cm and current:
            covers[current] += [t.strip() for t in cm.group(1).split(",") if t.strip()]

    out = []
    for c in real:
        evidence, status = [], "open"
        hit = latest("criterion", c["id"])
        if hit and supported_pass(hit[2]):
            status = "passed"
            evidence.append("%s#%d %s" % (hit[0], hit[1], hit[2].get("claim") or ""))
        else:
            names = [n for n, ids in covers.items() if c["id"] in ids]
            hits = [latest("scenario", n) for n in names]
            if names and all(h and supported_pass(h[2]) for h in hits):
                status = "passed"
                evidence = ["%s#%d scenario %s" % (h[0], h[1], n) for n, h in zip(names, hits)]
        out.append({"id": c["id"], "priority": c["priority"], "status": status,
                    "evidence": [e.strip() for e in evidence]})
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {"criteria": out, "ts": ts}


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "status":
        if len(sys.argv) != 4:
            print("usage: acceptance.py status <intent.md> <evidence-dir>", file=sys.stderr)
            return 2
        try:
            print(json.dumps(status_report(sys.argv[2], sys.argv[3]), indent=2))
        except OSError as e:
            print(f"cannot read intent: {e}", file=sys.stderr)
            return 2
        return 0
    if len(sys.argv) != 4:
        print("usage: acceptance.py <stage> <intent.md> <evidence.json>", file=sys.stderr)
        return 2
    stage, intent_path, ev_path = sys.argv[1:4]
    errors = []
    try:
        lines = open(intent_path).read().splitlines()
    except OSError as e:
        print(f"cannot read intent: {e}", file=sys.stderr)
        return 2

    crits = [c for c in parse_criteria(section_lines(lines, "Success Criteria"))]
    real = [c for c in crits if not c.get("placeholder")]

    if not real:
        errors.append("no acceptance criteria found under Success Criteria")

    ids, seen, dups = [], set(), []
    for c in real:
        cid = c.get("id")
        if not cid:
            snippet = c["first_line"][:40]
            errors.append(f"criterion without AC-NN id: {snippet}")
        elif not AC_RE.match(cid):
            errors.append(f"criterion id '{cid}' is not AC-NN")
        elif cid in seen:
            dups.append(cid)
        else:
            seen.add(cid)
        if cid:
            ids.append(cid)
    if dups:
        errors.append("duplicate criterion id(s): " + ", ".join(dups))

    scen = scenario_lines(lines)
    scen_names, scen_dups = [], []
    name_seen = set()
    for name, _ in scen:
        if name in name_seen:
            scen_dups.append(name)
        else:
            name_seen.add(name)
            scen_names.append(name)
    if scen_dups:
        errors.append("duplicate scenario name(s): " + ", ".join(scen_dups))

    # Covers references — anywhere in the file (scenario blocks).
    covered = set()
    for cid in covers_ids_in_lines(lines):
        if cid not in seen:
            errors.append(f"Covers: references unknown criterion {cid}")
        else:
            covered.add(cid)

    for c in real:
        label = c.get("id") or c["first_line"][:40]
        if not c["has_validate"]:
            errors.append(f"{label}: no Validate: line")
        elif c["vtype"] not in VALIDATE_TYPES:
            errors.append(f"{label}: Validate type '{c['vtype']}' not in "
                          + "/".join(VALIDATE_TYPES))
        elif not c["vdetails"]:
            errors.append(f"{label}: Validate details are empty or a placeholder")
        if not c["why"]:
            pass  # `Why:` is enforced by gate intent, not here
        if c.get("deferred") and c.get("optional") is False:
            errors.append(f"{label}: required criteria can never be deferred")
        if c["has_validate"] and c["vtype"] == "scenario" and c.get("id") \
                and c["id"] not in covered:
            errors.append(f"{label}: Validate: scenario but no scenario Covers: it")

    if stage == "check":
        rows = load_evidence(ev_path)
        latest_scen = latest_by_key(rows, "scenario")
        for name in scen_names:
            row = latest_scen.get(name)
            if not row or not supported_pass(row):
                errors.append(f"scenario '{name}' has no supported passing evidence row")
        latest_crit = latest_by_key(rows, "criterion")
        for c in real:
            if c.get("id") and c["has_validate"] and c["vtype"] in ("code", "manual", "metric"):
                row = latest_crit.get(c["id"])
                if not row or not supported_pass(row):
                    errors.append(f"{c['id']} has no supported passing evidence row")

    if errors:
        print("; ".join(errors))
        return 1
    print(OK_LINE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
