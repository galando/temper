#!/usr/bin/env python3
"""ledger_ops.py: the evidence ledger of the temper CLI: add, list, resolve, accept, run, and the rows gates read from it.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/ledger_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def evidence_resolve(argv):
    import json, os, sys
    f, id_s, fixed_by, ts = argv[1:5]
    entries = json.load(open(f))
    try:
        idx = int(id_s)
    except ValueError:
        sys.exit("FAIL: --id must be the 1-based number shown by 'temper evidence list'")
    if idx < 1 or idx > len(entries):
        sys.exit("FAIL: no finding #%s in this stage (it has %d entries)" % (id_s, len(entries)))
    e = entries[idx - 1]
    if not e.get('severity'):
        sys.exit("FAIL: finding #%s carries no severity, so it never counted against a gate" % id_s)
    if e.get('resolved'):
        sys.exit("FAIL: finding #%s is already resolved (%s)" % (id_s, e['resolved'].get('fixed_by')))
    if e.get('accepted'):
        sys.exit("FAIL: finding #%s is already accepted (%s)" % (id_s, e['accepted'].get('reason')))
    e['resolved'] = {'fixed_by': fixed_by, 'ts': ts}
    tmp = '%s.tmp.%d' % (f, os.getpid())
    with open(tmp, 'w') as fh:
        json.dump(entries, fh, indent=2)
    os.replace(tmp, f)
    print("OK: %s finding #%s resolved — %s" % (e.get('severity'), id_s, fixed_by))


def evidence_accept(argv):
    import json, os, sys
    f, id_s, reason, by, ts = argv[1:6]
    entries = json.load(open(f))
    try:
        idx = int(id_s)
    except ValueError:
        sys.exit("FAIL: --id must be the 1-based number shown by 'temper evidence list'")
    if idx < 1 or idx > len(entries):
        sys.exit("FAIL: no finding #%s in this stage (it has %d entries)" % (id_s, len(entries)))
    e = entries[idx - 1]
    if not e.get('severity'):
        sys.exit("FAIL: finding #%s carries no severity, so it never counted against a gate" % id_s)
    if e.get('resolved'):
        sys.exit("FAIL: finding #%s is already resolved (%s)" % (id_s, e['resolved'].get('fixed_by')))
    if e.get('accepted'):
        sys.exit("FAIL: finding #%s is already accepted (%s)" % (id_s, e['accepted'].get('reason')))
    e['accepted'] = {'reason': reason, 'author': by, 'ts': ts}
    tmp = '%s.tmp.%d' % (f, os.getpid())
    with open(tmp, 'w') as fh:
        json.dump(entries, fh, indent=2)
    os.replace(tmp, f)
    print("OK: %s finding #%s accepted by %s — %s" % (e.get('severity'), id_s, by, reason))


def feedback_answered(argv):
    import json, re, sys, os
    try:
        rows = json.load(open(argv[1]))
    except Exception:
        rows = []
    fb = {m.group(1) for r in rows if r.get('phase') == 'feedback'
          for m in [re.search(r'feedback #(\d+)', r.get('claim') or '')] if m}
    res = {m.group(1): r for r in rows if r.get('phase') == 'feedback-resolved'
           for m in [re.search(r'feedback #(\d+)', r.get('claim') or '')] if m}
    if not fb:
        print('SKIP')
    else:
        unanswered = []
        for n in sorted(fb, key=int):
            r = res.get(n)
            if r is None:
                unanswered.append('feedback #%s' % n)
            else:
                c = r.get('claim') or ''
                m = re.search(r'declined\s*[—-]\s*(.*)', c)
                if 'declined' in c and (not m or not m.group(1).strip()):
                    unanswered.append('feedback #%s (declined with no reason)' % n)
        print(' | '.join(unanswered) if unanswered else 'OK')


def last_green(argv):
    import json, sys
    try:
        rows = json.load(open(argv[1]))
    except Exception:
        rows = []
    hits = [r for r in rows if r.get('phase') == 'green' and 'test' in (r.get('claim') or '').lower()]
    if hits:
        print('%s|%s' % (hits[-1].get('exit_code'), hits[-1].get('claim') or ''))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('evidence_resolve', evidence_resolve),
    ('evidence_accept', evidence_accept),
    ('feedback_answered', feedback_answered),
    ('last_green', last_green),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
