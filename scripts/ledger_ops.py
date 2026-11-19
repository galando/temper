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


def evidence_entry(argv):
    import json, os, sys
    claim, cmd, exit_code, artifact, artifact_hash, value, severity, label, phase, scenario, criterion, confidence, kind, ts = argv[1:15]
    e = {'claim': claim, 'cmd': cmd or None,
         'exit_code': int(exit_code) if exit_code != '' else None,
         'artifact': artifact or None, 'sha256': artifact_hash or None,
         'value': (float(value) if value != '' else None),
         'severity': severity or None, 'phase': phase or None, 'scenario': scenario or None,
         'criterion': criterion or None, 'label': label, 'ts': ts}
    if confidence != '':
        e['confidence'] = float(confidence)
    if kind:
        e['kind'] = kind
    if argv[15:]:   # 9.8.5 (WP18): Review's completion row names the files read, from the project folder
        e['read'] = list(dict.fromkeys(os.path.normpath(os.path.relpath(r) if os.path.isabs(r) else r) for r in argv[15:] if r.strip()))
    print(json.dumps(e))


def evidence_list(argv):
    import json, sys
    for i, e in enumerate(json.load(open(argv[1])), 1):
        mark = 'OK ' if (e.get('exit_code') in (0, None)) else 'ERR'
        line = f"#{i} [{e.get('label')}] {mark} {e.get('claim')}" + (f" [void: {e['voided'].get('reason')}]" if isinstance(e.get('voided'), dict) else '')
        if e.get('severity'):
            line += f" (severity: {e.get('severity')})"
        if e.get('resolved'):
            line += f" [resolved: {e['resolved'].get('fixed_by')}]"
        if e.get('accepted'):
            line += f" [accepted: {e['accepted'].get('reason')}]"
        if e.get('cmd'):
            line += f" (cmd: {e.get('cmd')}, exit {e.get('exit_code')})"
        if e.get('scenario'):
            line += f" [scenario: {e.get('scenario')}]"
        print(line)


def run_entry(argv):
    import json, sys
    claim, cmd, exit_code, severity, label, phase, scenario, criterion, ts = argv[1:]
    e = {'claim': claim, 'cmd': cmd, 'exit_code': int(exit_code), 'artifact': None,
         'sha256': None, 'value': None, 'severity': severity or None,
         'phase': phase or None, 'scenario': scenario or None, 'criterion': criterion or None,
         'label': label, 'executed_by': 'cli', 'ts': ts}
    print(json.dumps(e))


def feedback_resolved_row(argv):
    import json, sys, time
    print(json.dumps({'claim': 'feedback #%s: applied — Task %s re-ran after group reopen and passed its task gate' % (argv[1], argv[2]),
                      'cmd': None, 'exit_code': 0, 'artifact': None, 'sha256': None, 'value': None, 'severity': None,
                      'phase': 'feedback-resolved', 'scenario': None, 'criterion': None, 'label': 'PROVEN', 'task': int(argv[2]),
                      'executed_by': 'cli', 'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}))


def confirm_row(argv):
    import json, sys, time
    print(json.dumps({'claim': 'Task %s confirmed by %s' % (argv[1], argv[2]), 'cmd': None, 'exit_code': 0, 'artifact': None,
                      'sha256': None, 'value': None, 'severity': None, 'phase': 'confirm', 'scenario': None, 'criterion': None,
                      'label': 'PROVEN', 'task': int(argv[1]), 'executed_by': 'person', 'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}))


def write_verdict(argv):
    import json, os, sys
    f, stage, verdict, reqs, ts = argv[1:6]
    d = json.load(open(f))
    d[stage] = {'verdict': verdict, 'requirements': json.loads(reqs), 'ts': ts}
    tmp = '%s.tmp.%d' % (f, os.getpid())
    with open(tmp, 'w') as fh:
        json.dump(d, fh, indent=2)
    os.replace(tmp, f)


def last_value(argv):
    import json, sys, re
    file, keyword = argv[1:3]
    entries = json.load(open(file))
    vals = [e.get('value') for e in entries
            if (not keyword or re.search(keyword, e.get('claim') or '', re.I)) and e.get('value') is not None]
    print(vals[-1] if vals else '')


def last_claim(argv):
    import json, re, sys
    try:
        rows = json.load(open(argv[1]))
    except Exception:
        rows = []
    hits = [str(r.get('claim')) for r in rows if isinstance(r, dict) and re.search(argv[2], str(r.get('claim') or ''))]
    print(hits[-1] if hits else '')


def last_row(argv):
    import json, re, sys
    try:
        rows = json.load(open(argv[1]))
    except Exception:
        rows = []
    hits = [r for r in rows if isinstance(r, dict) and re.search(argv[2], str(r.get('claim') or ''))]
    print('%s|%s' % (hits[-1].get('exit_code'), ' '.join(str(hits[-1].get('output') or '').split())[:300]) if hits else '')


def scenarios_covered(argv):
    import json, sys
    entries = json.load(open(argv[1]))
    covered = {e['scenario'] for e in entries if e.get('scenario') and e.get('exit_code') == 0}
    print(len(covered))


def latest_claim_exit(argv):
    import json, sys, re
    file, keyword = argv[1:3]
    entries = json.load(open(file))
    hits = [e for e in entries if re.search(keyword, e.get('claim') or '', re.I)]
    print(('%s|%s' % (hits[-1].get('exit_code'), hits[-1].get('claim') or '')) if hits else '')


def print_rows(argv):
    import json, sys
    for r in json.loads(argv[1]):
        if r['pass'] is True and argv[2] == '1':
            continue
        mark = 'v' if r['pass'] is True else '?' if r['pass'] is None else 'x'   # ? not measured (WP19)
        print(f"  [{mark}] {r['name']} — {r['detail']}")


WORDS = {n.replace("_", "-"): f for n, f in (
    ('evidence_resolve', evidence_resolve),
    ('evidence_accept', evidence_accept),
    ('feedback_answered', feedback_answered),
    ('last_green', last_green),
    ('evidence_entry', evidence_entry),
    ('evidence_list', evidence_list),
    ('run_entry', run_entry),
    ('feedback_resolved_row', feedback_resolved_row),
    ('confirm_row', confirm_row),
    ('write_verdict', write_verdict),
    ('last_value', last_value),
    ('last_claim', last_claim),
    ('last_row', last_row),
    ('scenarios_covered', scenarios_covered),
    ('latest_claim_exit', latest_claim_exit),
    ('print_rows', print_rows),
)}


def main():
    # Under a locale that cannot encode a dash, print an escape rather than lose the rows.
    sys.stdout.reconfigure(errors="backslashreplace")
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
