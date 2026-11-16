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


WORDS = {n.replace("_", "-"): f for n, f in (
    ('groups_mutate', groups_mutate),
    ('group_deps', group_deps),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
