#!/usr/bin/env python3
"""spec_text.py: the spec texts of the temper CLI read and write: intent.md, plan.md, tasks.md.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/spec_text.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def unfenced_scenarios(argv):
    import re, sys
    bad = []
    fence = None   # info string of the currently open fence, else None
    for i, l in enumerate(open(argv[1]).read().splitlines(), 1):
        m = re.match(r'^\s*(`{3,}|~{3,})\s*(\S*)', l)
        if m:
            fence = (m.group(2) or '') if fence is None else None
            continue
        if fence != 'gherkin' and re.match(r'^\s*Scenario:', l):
            bad.append('%d: %s' % (i, l.strip()[:40]))
    print('\x1f'.join(bad))


def task_box(argv):
    import os, re, sys
    p, n, to = argv[1], argv[2], argv[3]
    frm = ' ' if to == 'x' else 'x'
    lines = open(p, encoding='utf-8').read().split('\n')
    inside = False
    for i, l in enumerate(lines):
        m = re.match(r'^###\s+Task\s+(\d+)\s*:', l)
        if m: inside = (m.group(1) == n)
        elif re.match(r'^#{1,2}\s', l): inside = False
        elif inside and re.match(r'^\s*- \[%s\]' % re.escape(frm), l):
            lines[i] = l.replace('- [%s]' % frm, '- [%s]' % to, 1)
            break
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines))
    os.replace(tmp, p)


def intent_carry(argv):
    import os, re, sys
    path, q = argv[1:3]
    norm = lambda t: re.sub(r'\W+', ' ', t).strip().lower()
    want = norm(q)[:60]
    lines = open(path, encoding='utf-8').read().split('\n')
    active, hit = False, None
    for i, l in enumerate(lines):
        h = re.match(r'^#{1,6}\s+(.*)$', l)
        if h:
            active = bool(re.match(r'open questions', h.group(1).strip(), re.I))
            continue
        m = re.match(r'^(\s*[-*]\s+(?:\[[ xX]\]\s+)?)Blocking:\s*(.+)$', l) if active else None
        if m and want and (norm(m.group(2)).startswith(want) or want.startswith(norm(m.group(2))[:60])):
            lines[i] = '%sDeferred: (carried forward at the Intent gate) %s' % (m.group(1), m.group(2).strip())
            hit = m.group(2).strip()
            break
    if hit is None:
        print('FAIL: no Blocking open question starts with: %s' % q[:80], file=sys.stderr)
        sys.exit(1)
    tmp = '%s.tmp.%d' % (path, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    os.replace(tmp, path)
    print('OK: carried forward: %s' % hit[:80])


def intent_status(argv):
    import os, re, sys
    path, sub, who, day = argv[1:5]
    text = open(path, encoding='utf-8').read()
    lines = text.split('\n')
    idx = next((i for i, l in enumerate(lines) if re.match(r'^\*\*Status:\*\*', l)), None)
    want = 'accepted' if sub == 'accept' else 'completed'
    cur = re.sub(r'^\*\*Status:\*\*\s*', '', lines[idx]).strip().lower() if idx is not None else ''
    if cur == want or (sub == 'accept' and cur == 'completed'):
        print('OK: intent.md is already %s' % cur)
        sys.exit(0)
    # An intent moves draft -> accepted -> completed: a draft nobody accepted at the Intent gate never turns completed, which
    # would read as finished work with no Accepted-by.
    if sub == 'complete' and cur != 'accepted':
        print('FAIL: intent.md is %s, not accepted; temper intent accept comes first (the person, at the Intent gate)' % (
            cur or 'without a Status'), file=sys.stderr)
        sys.exit(1)
    if idx is None:
        lines.insert(0, '**Status:** %s' % want)
        idx = 0
    else:
        lines[idx] = '**Status:** %s' % want
    key, value = ('Accepted-by', who) if sub == 'accept' else ('Completed', day)
    if not any(re.match(r'^\*\*%s:\*\*' % re.escape(key), l) for l in lines):
        lines.insert(idx + 1, '**%s:** %s' % (key, value))
    tmp = '%s.tmp.%d' % (path, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    os.replace(tmp, path)
    print('OK: intent.md is %s' % want)


def tier_lines(argv):
    import os, re, sys
    sp, mode, tier = argv[1], argv[2], argv[3].strip().lower()
    rx = re.compile(r'^(\s*(?:\*\*Complexity:\*\*|#{1,6}\s*Complexity:)[\s*]*)(trivial|simple|medium|complex)\b', re.I | re.M)
    if tier not in ('trivial', 'simple', 'medium', 'complex'):
        sys.exit(0)
    for name in ('intent.md', 'plan.md'):
        p = os.path.join(sp, name)
        try:
            text = open(p, encoding='utf-8', errors='surrogateescape').read()
        except OSError:
            continue
        said = [m.group(2).lower() for m in rx.finditer(text)]
        other = [s for s in said if s != tier]
        if not other:
            continue
        if mode == 'check':
            print('%s says %s' % (name, other[0]))
            continue
        new = rx.sub(lambda m: m.group(1) + tier, text)
        tmp = '%s.tmp.%d' % (p, os.getpid())
        with open(tmp, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(new)
        os.replace(tmp, p)
        print('OK: %s now says Complexity %s (it said %s)' % (name, tier, other[0]))


def uncovered_scenarios(argv):
    import json, re, sys
    intent_path, ev_path = argv[1:3]
    names = []
    for line in open(intent_path):
        m = re.match(r'^\s*Scenario:\s*(.+?)\s*$', line)
        if m:
            names.append(m.group(1))
    covered = set()
    try:
        entries = json.load(open(ev_path))
        covered = {e['scenario'] for e in entries if e.get('scenario') and e.get('exit_code') == 0}
    except Exception:
        pass
    missing = [n for n in names if n not in covered]
    print('\x1f'.join(missing))


def plan_hash_recorded(argv):
    import json, sys
    for p in argv[1:]:
        try:
            h = json.load(open(p)).get('plan_hash')
        except Exception:
            h = None
        if h:
            print(h)
            break


WORDS = {n.replace("_", "-"): f for n, f in (
    ('unfenced_scenarios', unfenced_scenarios),
    ('task_box', task_box),
    ('intent_carry', intent_carry),
    ('intent_status', intent_status),
    ('tier_lines', tier_lines),
    ('uncovered_scenarios', uncovered_scenarios),
    ('plan_hash_recorded', plan_hash_recorded),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
