#!/usr/bin/env python3
"""groups_ops.py: the grouped Build of the temper CLI: groups.json and its changes.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/groups_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import json
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
    try:
        MUTATIONS[body](d, a, task_status)
    except ValueError as e:
        print('FAIL: %s' % e, file=sys.stderr)
        sys.exit(1)
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
        print(i.get('verdict', ''), i.get('head', ''), int(merged(i)))
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


# The changes of groups.json a caller names (_groups_mutate <name> [args...]): each changes d, the whole
# document, from a, the extra arguments; a task's status changes only through task_status.


def group_start(d, a, task_status):
    d['version'] = 1
    d.setdefault('plan_hash', a[7])
    d['slug'] = a[0]
    d['feature_branch'] = a[1]
    d.setdefault('groups', {})
    d.setdefault('tasks', {})
    e = d['groups'].setdefault(a[2], {})
    e['status'] = 'running' if e.get('status') in (None, 'pending') else e['status']
    e['worktree'] = a[3]
    e['branch'] = a[4]
    e['base_sha'] = a[5] if a[8] == '0' else e.get('base_sha') or a[5]   # a new branch (not this run's own) starts here
    e.setdefault('started_at', a[6])
    e.setdefault('finished_at', None)


def group_gate(d, a, task_status):
    g = d.setdefault('groups', {}).setdefault(a[0], {})
    g['gate'] = {'verdict': a[1], 'ts': a[4]}
    if a[1] == 'PASS':
        g['status'] = 'passed'
        g['finished_at'] = a[4]
    else:
        g['gate']['reason'] = a[2]
        if a[3]: g['gate']['timeout_s'] = int(a[3])
        if a[5]: g['gate'].update(ran=True, fail_lines=json.loads(a[5]))   # 9.8.4: the check ran; what failed in it
        g['fails'] = int(g.get('fails') or 0) + 1                          # and how many times the group's check failed
        if g.get('status') != 'parked':
            g['status'] = 'running'
        g['finished_at'] = None


def cli_commit(d, a, task_status):
    d.setdefault('cli_commits', []).append(a[0])


def task_reopen(d, a, task_status):
    t = d.setdefault('tasks', {}).setdefault(a[0], {})
    t.setdefault('attempts_prior', []).extend(t.get('attempts') or [])
    t['attempts'] = []; t.pop('blocked', None)
    task_status(t, 'pending')
    t['attempt'] = 1
    for k in ('commit', 'passed_at', 'snapshot', 'start_sha', 'started_at'):
        t.pop(k, None)
    t.setdefault('reopened', []).append({'ts': a[1], 'feedback': a[2] or None})
    g = d.setdefault('groups', {}).setdefault(a[3], {})
    g.pop('parked_foreign', None)   # D-08: off the branch or accepted (checked above); no other group's list is touched
    g.pop('gate', None); g.pop('fix', None)
    g.pop('finished_at', None)
    g.pop('confirmed', None)        # the person's Continue was for the group as it passed; it is asked again once it passes again
    d.pop('integration', None)      # and the merge of the groups no longer holds this group's work: integrate runs again
    if g.get('status') in ('parked', 'passed'):
        g['status'] = 'running'
        g.pop('parked_reason', None)


def group_confirm(d, a, task_status):
    g = d.setdefault('groups', {}).setdefault(a[0], {})
    g['confirmed'] = a[1]


def task_start(d, a, task_status):
    t = d.setdefault('tasks', {}).setdefault(a[0], {})
    if t.get('status') == 'running':
        print('FAIL: Task %s is already running' % a[0], file=sys.stderr)
        sys.exit(1)
    t.setdefault('attempts', [])
    t['group'] = a[1]
    task_status(t, 'running')
    t['attempt'] = len(t['attempts']) + 1
    t['start_sha'] = a[2]
    t['snapshot'] = json.loads(a[3])
    t['started_at'] = a[4]
    t['worktree'] = a[5]
    t['branch'] = a[6]
    t['model'] = a[7] if t['attempt'] <= 2 else a[8]
    t['start_hashes'] = json.loads(a[9] or '{}')   # 9.8.5 (Q4): the code files as this attempt found them


def task_wt_forget(d, a, task_status):
    t = d.setdefault('tasks', {}).setdefault(a[0], {})
    t.pop('worktree', None)
    t.pop('branch', None)


def task_covered(d, a, task_status):
    task_status(d['tasks'][a[0]], 'covered'); d['tasks'][a[0]]['covered'] = {'cmd': a[1], 'tail': a[2], 'ts': a[3]}


def task_env_fault(d, a, task_status):
    d['tasks'][a[0]]['env_fault'] = {'reason': a[1], 'ts': a[2]}


def task_awaiting(d, a, task_status):
    d['tasks'][a[0]]['awaiting'] = 'confirm'


def task_fail(d, a, task_status):
    t = d['tasks'][a[0]]
    def num(x): return int(x) if x.isdigit() else None
    t.setdefault('attempts', []).append({'n': int(a[1]), 'model': a[2] or None, 'outcome': 'FAIL', 'reason': a[3],
        'ms': num(a[4]), 'ts': a[5], 'output': a[6]})
    task_status(t, 'failed')
    if int(a[1]) >= 3 or a[8]:
        g = d.setdefault('groups', {}).setdefault(a[7], {})
        g.setdefault('parked_foreign', []).extend(x for x in json.loads(a[9] or '[]') if x not in g.get('parked_foreign', []))
        # a group already parked keeps the reason it was parked for and gains this one
        new = a[8] or 'Task %s failed %s attempts' % (a[0], a[1])
        old = g.get('parked_reason') if g.get('status') == 'parked' else ''
        g['parked_reason'] = old + ' -- also: ' + new if old and new not in old else (old or new)
        g['status'] = 'parked'


def task_park(d, a, task_status):
    t = d['tasks'][a[0]]
    t.setdefault('attempts', []).append({'n': int(a[1]), 'model': a[2] or None, 'outcome': 'FAIL', 'reason': a[3], 'ts': a[4]})
    task_status(t, 'failed')
    g = d.setdefault('groups', {}).setdefault(a[5], {})
    g['status'] = 'parked'
    g['parked_reason'] = a[3]
    if a[6]:   # the commit the CLI just made on the task branch is its own, so a reopen does not take it for an agent's
        d.setdefault('cli_commits', []).append(a[6])


def task_pass(d, a, task_status):
    t = d['tasks'][a[0]]
    def num(x): return int(x) if x.isdigit() else None
    t.setdefault('attempts', []).append({'n': int(a[1]), 'model': a[2] or None, 'outcome': 'PASS', 'reason': '',
        'ms': num(a[3]), 'ts': a[4]})
    task_status(t, 'passed')
    t['passed_at'] = a[4]
    t['commit'] = a[7] or None
    for x in (a[5], a[6]):
        if x:
            d.setdefault('cli_commits', []).append(x)


def feedback_resolved(d, a, task_status):
    for r in (d['tasks'][a[0]].get('reopened') or []):
        if r.get('feedback'): r['resolved'] = True


def merged(i):
    """M1: the groups are merged into the feature branch: a PASS wrote it, a later verdict keeps it, and a PASS of a run
    saved before the key existed counts as merged."""
    return bool(i.get('merged', i.get('verdict') == 'PASS'))


def integration(d, a, task_status):
    old = d.get('integration') or {}
    d['integration'] = {'verdict': a[0], 'reason': a[1], 'group': a[2] or None,
                        'files': [f for f in a[3].split(',') if f], 'ts': a[4], 'head': a[6]}
    if a[0] == 'PASS' or merged(old):
        d['integration']['merged'] = True
    if a[5]:
        d['integration']['foreign'] = json.loads(a[5])   # {group: [sha, newest first]}: the person takes them out or keeps them


def task_confirmed(d, a, task_status):
    d['tasks'][a[0]]['confirmed_by'] = a[1]; d['tasks'][a[0]].pop('awaiting', None)


MUTATIONS = {n.replace("_", "-"): f for n, f in (
    ('group_start', group_start),
    ('group_gate', group_gate),
    ('cli_commit', cli_commit),
    ('task_reopen', task_reopen),
    ('group_confirm', group_confirm),
    ('task_start', task_start),
    ('task_wt_forget', task_wt_forget),
    ('task_covered', task_covered),
    ('task_env_fault', task_env_fault),
    ('task_awaiting', task_awaiting),
    ('task_fail', task_fail),
    ('task_park', task_park),
    ('task_pass', task_pass),
    ('feedback_resolved', feedback_resolved),
    ('integration', integration),
    ('task_confirmed', task_confirmed),
)}


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
