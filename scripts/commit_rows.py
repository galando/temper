#!/usr/bin/env python3
"""commit_rows.py: the rows of the commit gate of the temper CLI: overrides, blast radius, the touch patterns.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/commit_rows.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import re
import sys


def override_covers(argv):
    import json, sys
    def load(p, default):
        try:
            d = json.load(open(p))
            return d if isinstance(d, type(default)) else default
        except Exception:
            return default
    over, gates, stage = load(argv[1], []), load(argv[2], {}), argv[3]
    v = gates.get(stage)
    vts = str(v.get('ts') or '') if isinstance(v, dict) else ''
    sys.exit(0 if any(isinstance(o, dict) and o.get('stage') == stage and (not vts or not o.get('ts') or str(o.get('ts')) >= vts)
                      for o in over) else 1)


# the test files the commit gate allows beside the plan's, and a repair may commit (WP24: the pattern of the base, unchanged)
TEST_RE = re.compile(r'(^|/)(tests?|unit|spec|__tests__)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[cm]?[jt]sx?$|Tests?\.(java|kt|cs)$|_spec\.rb$')


def blast_radius(argv):
    import json, os, re, sys
    plan = json.loads(argv[1]); spec = argv[2].rstrip('/')
    declared = {f for t in plan.get('tasks', []) for f in t.get('files', [])}
    try:
        rows = json.load(open(argv[3]))
    except Exception:
        rows = []
    allowed = set()
    for r in rows if isinstance(rows, list) else []:
        m = re.match(r'^drift (\S+): (Add to plan|Allow once)\b', str(r.get('claim') or ''), re.I)
        if m:
            allowed.add(m.group(1))
    test = TEST_RE
    def ok(p):
        if spec and (p == spec or p.startswith(spec + '/')): return True
        if p.startswith('.temper/') or p.startswith('.claude/worktrees/'): return True   # run state the CLI owns
        return p in declared or p in allowed or bool(test.search(p))
    changed = [l.strip() for l in sys.stdin if l.strip()]
    bad = [c for c in changed if not ok(c)]
    if bad: print('FAIL changed outside declared files: ' + ', '.join(bad[:5]) + (' (and %d more)' % (len(bad) - 5) if len(bad) > 5 else ''))
    else: print('PASS %d changed, all declared' % len(changed))


def fix_plan(argv):
    # BLACKBOX-1: a fix run's declared set as blast_radius reads a plan: the files rca.md names (the file of AT, the
    # Blast radius and the Read first items, as card.py's fix_files reads them) plus the recorded regression test.
    # The rca.md fields are read here the way panel.py's rca_fields does: this module stays isolated (case 32).
    import json, re
    try:
        text = open(argv[1], encoding="utf-8").read()
    except OSError:
        text = ""
    plain = lambda t: re.sub(r"[*`]", "", t).strip()

    def items(name):
        lines = text.splitlines()
        for i, l in enumerate(lines):
            m = re.match(r"^(#{1,6})\s+(.*?)\s*$", l)
            if m and m.group(2).lower().startswith(name.lower()):
                lvl = len(m.group(1))
                end = next((j for j in range(i + 1, len(lines))
                            if (lambda h: h and len(h.group(1)) <= lvl)(re.match(r"^(#{1,6})\s", lines[j]))), len(lines))
                return [plain(re.sub(r"^\s*[-*]\s+", "", x)) for x in lines[i + 1:end]
                        if re.match(r"^\s*[-*]\s+\S", x)]
        return []
    m_at = re.search(r"^\**AT:?\**:?\s*(.+)$", text, re.M | re.I)
    names = []
    for x in [(plain(m_at.group(1)).split(":")[0].strip() if m_at else "")] + items("Blast radius") + items("Read first"):
        x = x.split()[0].strip("`") if x.strip() else ""
        if x and x not in names:
            names.append(x)
    rt = str(argv[2] if len(argv) > 2 else "").strip()
    if rt and rt not in names:
        names.append(rt)
    print(json.dumps({"tasks": [{"files": names}]}))


def declared_list(argv):
    import json,sys; print('\n'.join(sorted({f for t in json.loads(argv[1]).get('tasks', []) for f in t.get('files', [])})))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('override_covers', override_covers),
    ('blast_radius', blast_radius),
    ('fix_plan', fix_plan),
    ('declared_list', declared_list),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
