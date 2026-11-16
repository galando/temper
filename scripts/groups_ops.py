#!/usr/bin/env python3
"""groups_ops.py: the grouped Build of the temper CLI: groups.json and its changes.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/groups_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def groups_mutate(argv):
    import importlib.util, json, os, sys
    spec = importlib.util.spec_from_file_location('task_cover', argv[1])   # by its one full path, no folder on the import path
    task_cover = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(task_cover)
    task_status = task_cover.set_status
    f, body, a = argv[2], argv[3], argv[4:]
    try:
        d = json.load(open(f))
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    ns = dict(locals())   # the body runs as it did at the top of a program: one namespace, d read back after it
    try:
        exec(body, ns)
    except ValueError as e:
        print('FAIL: %s' % e, file=sys.stderr)
        sys.exit(1)
    d = ns['d']
    tmp = '%s.tmp.%d' % (f, os.getpid())
    with open(tmp, 'w') as fh:
        json.dump(d, fh, indent=2)
        fh.write('\n')
    os.replace(tmp, f)


def group_deps(argv):
    import json, sys
    plan = json.loads(argv[2])
    for grp in plan['groups']:
        if grp['id'] == argv[1]:
            print('ok ' + ' '.join(grp['depends']))
            sys.exit(0)
    print('unknown')


def groups_reset_rows(argv):
    import json, sys
    try:
        d = json.load(open(argv[1]))
    except Exception:
        d = {}
    for g, e in sorted((d.get('groups') or {}).items()):
        print('\t'.join([d.get('slug') or '', g, e.get('worktree') or '', e.get('branch') or '']))
    for n, e in sorted((d.get('tasks') or {}).items()):   # a task's own worktree, kept by a park or still running
        if e.get('worktree') or e.get('branch'):
            print('\t'.join([d.get('slug') or '', 'T' + n, e.get('worktree') or '', e.get('branch') or '']))


def kept_worktrees(argv):
    import json, sys
    try:
        ts = json.load(open(argv[1])).get('tasks') or {}
    except Exception:
        ts = {}
    for k in sorted(ts, key=lambda x: int(x) if x.isdigit() else 0):
        v = ts[k]
        if v.get('group') == argv[2] and v.get('status') != 'running' and v.get('worktree'):
            print(v['worktree'])


def dep_verdict(argv):
    import json, sys
    try:
        g = ((json.load(open(argv[1])).get('groups') or {}).get(argv[2]) or {})
        print((g.get('gate') or {}).get('verdict', '') + ('|confirmed' if g.get('confirmed') else ''))
    except Exception:
        print('')


def group_worktree(argv):
    import json, sys
    try:
        print(((json.load(open(argv[1])).get('groups') or {}).get(argv[2]) or {}).get('worktree', ''))
    except Exception:
        print('')


def parked_foreign(argv):
    import json, sys
    try:
        print(json.dumps(((json.load(open(argv[1])).get('groups') or {}).get(argv[2]) or {}).get('parked_foreign') or []))
    except Exception:
        print('[]')


def running_tasks(argv):
    import json, sys
    try:
        d = json.load(open(argv[1]))
    except Exception:
        d = {}
    print(' '.join(sorted((k for k, v in (d.get('tasks') or {}).items() if v.get('group') == argv[2] and v.get('status') == 'running'), key=int)))


def task_attempt(argv):
    import json, sys; print(((json.load(open(argv[1])).get('tasks') or {}).get(argv[2]) or {}).get('attempt') or 1)


def gate_verdict(argv):
    import json, sys
    try:
        print((((json.load(open(argv[1])).get('groups') or {}).get(argv[2]) or {}).get('gate') or {}).get('verdict', ''))
    except Exception:
        print('')


def task_ready(argv):
    import json, sys
    n = int(argv[1])
    print(1 if any(l.strip().startswith('{') and json.loads(l).get('task') == n for l in sys.stdin) else 0)


def open_feedback(argv):
    import json, sys
    try:
        t = (json.load(open(argv[1])).get('tasks') or {}).get(argv[2]) or {}
    except Exception:
        t = {}
    print(' '.join(str(r['feedback']) for r in (t.get('reopened') or []) if r.get('feedback') and not r.get('resolved')))


def integration_head(argv):
    import json, sys
    try:
        i = json.load(open(argv[1])).get('integration') or {}
        print(i.get('verdict', ''), i.get('head', ''))
    except Exception:
        print('')


def foreign_add(argv):
    import json, sys
    d = json.loads(argv[1]); d[argv[2]] = [x for x in argv[3].split() if x]
    print(json.dumps(d))


def integration_verdict(argv):
    import json, sys
    try:
        i = json.load(open(argv[1])).get('integration') or {}
    except Exception:
        i = {}
    print('%s|%s' % (i.get('verdict', ''), i.get('reason', '')))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('groups_mutate', groups_mutate),
    ('group_deps', group_deps),
    ('groups_reset_rows', groups_reset_rows),
    ('kept_worktrees', kept_worktrees),
    ('dep_verdict', dep_verdict),
    ('group_worktree', group_worktree),
    ('parked_foreign', parked_foreign),
    ('running_tasks', running_tasks),
    ('task_attempt', task_attempt),
    ('gate_verdict', gate_verdict),
    ('task_ready', task_ready),
    ('open_feedback', open_feedback),
    ('integration_head', integration_head),
    ('foreign_add', foreign_add),
    ('integration_verdict', integration_verdict),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
