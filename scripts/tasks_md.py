"""tasks_md.py: the grouped tasks.md of a run, read the one way the CLI and flow.py both read it.

  python3 tasks_md.py parse <tasks.md>
      prints {groups, tasks, integration} as JSON: groups [{id, title, depends, validate, interfaces,
      context, context_bytes, tasks}], tasks [{n, title, group, files, depends, test, cases,
      block_bytes, block}]. File tokens are the backticked paths of the **File:** lines.
  python3 tasks_md.py schedule <groups.json> <max-parallel> <task model> <escalation model> <project> <tasks.md>
      prints the ready set (`temper schedule`): one JSON line per launchable task, then a done or a
      waiting line when no task is ready.

Standard library only.
"""
import json
import re
import sys


def parse(path):
    """tasks.md -> {groups, tasks, integration}, the shape every grouped command reads."""
    try:
        lines = open(path, encoding='utf-8').read().split('\n')
    except Exception:
        lines = []
    FIELD = re.compile(r'^\*\*(Depends|Validate|Interfaces|Integration|Context|File|Test|Cases):\*\*\s*(.*)$')
    # a case of a task's **Cases:** list: a bullet that is not the task's checkbox
    CASE = re.compile(r'^\s*[-*]\s+(?!\[[ xX]\])\S')
    groups, tasks = [], []
    integration = None
    cur_g = cur_t = None
    ctx_open = False
    cases_open = False
    def path_tokens(text):
        out = []
        for m in re.finditer(r'`([^`]+)`', text):
            t = m.group(1).strip()
            if re.fullmatch(r'[\w.@\-/*?]+', t) and ('/' in t or '.' in t) and t.lower() != 'none':
                out.append(t[2:] if t.startswith('./') else t)
        return list(dict.fromkeys(out))
    def cmd_of(text):
        m = re.search(r'`([^`]+)`', text)
        return m.group(1).strip() if m else text.strip()
    for line in lines:
        gm = re.match(r'^##\s+Group\s+(G\d+)\s*:\s*(.*?)\s*$', line)
        tm = re.match(r'^###\s+Task\s+(\d+)\s*:\s*(.*?)\s*$', line)
        if gm:
            cur_g = {'id': gm.group(1), 'title': gm.group(2), 'depends': [], 'validate': '',
                     'interfaces': [], 'context': '', 'context_bytes': 0, 'tasks': []}
            groups.append(cur_g); cur_t = None; ctx_open = False; cases_open = False
            continue
        if tm:
            cur_t = {'n': int(tm.group(1)), 'title': tm.group(2), 'group': cur_g['id'] if cur_g else None,
                     'files': [], 'depends': [], 'test': '', 'cases': 0, 'block_bytes': 0, 'block': ''}
            tasks.append(cur_t); ctx_open = False; cases_open = False
            if cur_g: cur_g['tasks'].append(cur_t['n'])
            continue
        if re.match(r'^#{1,2}\s', line):
            cur_t = None; ctx_open = False; cases_open = False
            continue
        fm = FIELD.match(line)
        if fm:
            key, val = fm.group(1), fm.group(2)
            if key == 'Integration':
                integration = cmd_of(val); ctx_open = False; continue
            if cur_t is not None:
                if key == 'File': cur_t['files'] = path_tokens(val)
                elif key == 'Depends': cur_t['depends'] = [int(x) for x in re.findall(r'Task\s+(\d+)', val)]
                elif key == 'Test': cur_t['test'] = cmd_of(val)
                # the concrete cases Plan wrote for the task's test, one bullet each (an inline value counts as one)
                cases_open = key == 'Cases'
                if cases_open and val.strip(): cur_t['cases'] += 1
                cur_t['block'] += line + '\n'; continue
            if cur_g is not None:
                ctx_open = False
                if key == 'Depends': cur_g['depends'] = re.findall(r'G\d+', val)
                elif key == 'Validate': cur_g['validate'] = cmd_of(val)
                elif key == 'Interfaces':
                    cur_g['interfaces'] += [{'path': a, 'literal': b} for a, b in
                                            re.findall(r'`([^`]+)`\s*[—\-]+\s*`([^`]+)`', val)]
                elif key == 'Context':
                    ctx_open = True
                    if val.strip(): cur_g['context'] += val + '\n'
                continue
        if cur_t is not None:
            if cases_open and CASE.match(line): cur_t['cases'] += 1
            cur_t['block'] += line + '\n'
        elif cur_g is not None and ctx_open:
            cur_g['context'] += line + '\n'
    for g in groups:
        g['context'] = g['context'].strip()
        g['context_bytes'] = len(g['context'].encode('utf-8'))
    for t in tasks:
        t['block'] = ('### Task %d: %s\n%s' % (t['n'], t['title'], t['block'])).strip('\n')
        t['block_bytes'] = len(t['block'].encode('utf-8'))

    return {'groups': groups, 'tasks': tasks, 'integration': integration}


def schedule(plan, run, max_par, task_model, esc_model, project):
    """The ready set of a grouped run, one dict per launchable task, then a done or waiting line."""
    if not isinstance(run, dict):
        run = {}
    rg, rt = run.get('groups') or {}, run.get('tasks') or {}
    def norm(p):
        p = p.strip()
        return p[2:] if p.startswith('./') else p
    tasks = sorted(plan['tasks'], key=lambda t: ([g['id'] for g in plan['groups']].index(t['group']) if t['group'] in [g['id'] for g in plan['groups']] else 999, t['n']))
    gdep = {g['id']: g['depends'] for g in plan['groups']}
    declared = {t['n']: {norm(f) for f in t['files']} for t in tasks}
    def status(n): return (rt.get(str(n)) or {}).get('status', 'pending')
    def agent_alias(m):  # the Agent tool's model parameter takes aliases, not full ids
        for a in ('haiku', 'sonnet', 'opus'):
            if m.startswith('claude-' + a + '-'): return a
        return m
    def gstatus(g): return (rg.get(g) or {}).get('status', 'pending')
    def gpass(g): return ((rg.get(g) or {}).get('gate') or {}).get('verdict') == 'PASS'
    running = [t['n'] for t in tasks if status(t['n']) == 'running']
    slots = max_par - len(running)
    ready, waiting = [], []
    for t in tasks:
        n, g = t['n'], t['group']
        if status(n) not in ('pending', 'failed'):
            continue
        why = None
        unmet = [d for d in t['depends'] if status(d) != 'passed']
        gwait = [d for d in gdep.get(g, []) if not gpass(d)]
        if gstatus(g) == 'parked': why = 'group %s is parked' % g
        elif not (rg.get(g) or {}).get('worktree'): why = 'group %s not started' % g
        elif gwait: why = 'group %s depends on %s' % (g, ', '.join(gwait))
        elif unmet: why = 'depends on %s' % ', '.join('Task %d' % d for d in unmet)
        else:
            clash = [m for m in list(running) + [r['task'] for r in ready]
                     if declared[m] & declared[n]]
            if clash: why = 'files overlap Task %d' % clash[0]
            elif slots <= len(ready): why = 'max-parallel %d reached' % max_par
        if why:
            waiting.append('Task %d (%s)' % (n, why))
            continue
        attempt = len((rt.get(str(n)) or {}).get('attempts') or []) + 1
        mdl = task_model if attempt <= 2 else esc_model
        # the task's own worktree (temper task start makes it beside the group's: temper-{slug}-T{N} for temper-{slug}-{G})
        gwt = rg[g]['worktree']
        twt = gwt[:-len(g)] + 'T%d' % n if gwt.endswith('-' + g) else gwt
        ready.append({'task': n, 'group': g, 'title': t['title'], 'worktree': twt,
                      'project': project, 'model': mdl, 'agent_model': agent_alias(mdl),
                      'attempt': attempt})
    out = list(ready)
    if not ready:
        ids = [g['id'] for g in plan['groups']]
        if ids and all(gpass(g) for g in ids):
            out.append({'done': True, 'next': 'temper integrate'})
        else:
            # A running task has no ready line. Its agent has not returned: the gate waits for that agent's result, so this
            # line names no gate command (a gate run now finds no green run and spends one of the task's attempts).
            def ran_on(n): return task_model if ((rt.get(str(n)) or {}).get('attempt') or 1) <= 2 else esc_model
            waiting += ['Task %d (running on %s: wait for its agent to return)' % (n, ran_on(n)) for n in running]
            out.append({'waiting': waiting, 'parked': [g for g in ids if gstatus(g) == 'parked'],
                        'done': False})
    return out


def load_run(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "parse":
        print(json.dumps(parse(sys.argv[2])))
    elif len(sys.argv) >= 8 and sys.argv[1] == "schedule":
        for line in schedule(parse(sys.argv[7]), load_run(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]):
            print(json.dumps(line))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
