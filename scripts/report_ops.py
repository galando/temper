#!/usr/bin/env python3
"""report_ops.py: the report and status of the temper CLI, and the usage rows they read.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/report_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def status_text(argv):
    import json, sys
    for c in json.loads(argv[1])['criteria']:
        ev = '; '.join(c['evidence']) if c['evidence'] else 'no evidence'
        print('  [%s] %s (%s) — %s' % ('v' if c['status'] == 'passed' else ' ', c['id'], c['priority'], ev))
    print('Models')
    for l in argv[2].splitlines():
        if '=' in l and ' (' in l:
            name, rest = l.split('=', 1)
            model, src = rest.rsplit(' (', 1)
            print('  %-16s %-18s %s' % (name, model, src.rstrip(')')))


def report_table(argv):
    import json, sys
    d = json.load(open(argv[1]))
    try:
        overrides = json.load(open(argv[2]))
    except Exception:
        overrides = []
    accepted = [o for o in overrides if str(o.get('stage', '')).startswith('foreign-commit:')]
    overridden = {o['stage'] for o in overrides if o not in accepted}
    print('Stage    Verdict  Evidence')
    print('-------  -------  --------')
    for stage in ['intent', 'plan', 'design', 'build', 'review', 'check', 'commit']:
        g = d.get(stage)
        if not g:
            continue
        tag = g['verdict'] + (' (overridden)' if stage in overridden and g['verdict'] == 'FAIL' else '')
        print(f"{stage:<8} {tag}")
        for r in g.get('requirements', []):
            mark = 'v' if r['pass'] else 'x'
            print(f"           [{mark}] {r['name']} — {r['detail']}")
    if overridden:
        print()
        print(f'{len(overridden)} gate(s) overridden by a human — see .temper/overrides.json')
    if accepted:
        print()
        print('Agent commits kept by a human (group reopen --accept-foreign):')
        for o in accepted:
            _, grp, sha = (str(o['stage']).split(':', 2) + ['', ''])[:3]
            print('  %s in group %s, by %s: %s' % (sha[:7], grp, o.get('by', '?'), o.get('reason', '')))


def report_usage(argv):
    import json, sys
    u = json.loads(argv[1])
    def n(v): return '-' if v is None else str(v)
    seq = ['intent', 'rca', 'plan', 'design', 'build', 'task', 'fix', 'review', 'check']
    in_run = lambda kv: (seq.index(kv[0]) if kv[0] in seq else len(seq), kv[0])
    print()
    print('Usage (the time Claude Code gave for each agent)')
    w = max([10] + [len(k) for k in list(u['by_stage']) + list(u['by_model'])])   # a full model id is wider than a stage
    print('  %-*s %6s %12s  %s' % (w, 'stage', 'rows', 'ms', 'model'))
    for k, v in sorted(u['by_stage'].items(), key=in_run):
        print('  %-*s %6d %12s  %s' % (w, k, v['rows'], n(v['ms']), ', '.join(v.get('models') or []) or '-'))
    print('  %-*s %6s %12s' % (w, 'model', 'rows', 'ms'))
    for k, v in u['by_model'].items():
        print('  %-*s %6d %12s' % (w, k, v['rows'], n(v['ms'])))
    t = u['total']
    print('  %-*s %6d %12s' % (w, 'total', t['rows'], n(t['ms'])))


def status_json(argv):
    import json, sys
    d = json.loads(argv[1])
    d['models'] = [{'stage': l.split('=', 1)[0], 'model': l.split('=', 1)[1].rsplit(' (', 1)[0], 'source': l.rsplit(' (', 1)[1].rstrip(')')}
                   for l in argv[2].splitlines() if '=' in l and ' (' in l]
    print(json.dumps(d))


def report_json(argv):
    import json, sys
    d = json.load(open(argv[1]))
    d['usage'] = json.loads(argv[2])
    print(json.dumps(d, indent=2))


def usage_row(argv):
    import json, sys
    a = argv[1:]
    def num(x): return int(x) if x.isdigit() else None
    print(json.dumps({'stage': a[0], 'model': a[1] or None, 'ms': num(a[2]),
                      'task': num(a[3]), 'group': a[4] or None, 'ts': a[5]}))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('status_text', status_text),
    ('report_table', report_table),
    ('report_usage', report_usage),
    ('status_json', status_json),
    ('report_json', report_json),
    ('usage_row', usage_row),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
