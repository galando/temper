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
    FIELD = re.compile(r'^\*\*(Depends|Validate|Interfaces|Integration|Context|Files?|Test|Cases):\*\*\s*(.*)$')
    # a case of a task's **Cases:** list: a bullet that is not the task's checkbox
    CASE = re.compile(r'^\s*[-*]\s+(?!\[[ xX]\])\S')
    groups, tasks = [], []
    integration = None
    cur_g = cur_t = None
    ctx_open = False
    cases_open = False
    files_open = False
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
            groups.append(cur_g); cur_t = None; ctx_open = False; cases_open = False; files_open = False
            continue
        if tm:
            cur_t = {'n': int(tm.group(1)), 'title': tm.group(2), 'group': cur_g['id'] if cur_g else None,
                     'files': [], 'depends': [], 'test': '', 'manual': False, 'confirm': '', 'cases': 0, 'block_bytes': 0, 'block': ''}
            tasks.append(cur_t); ctx_open = False; cases_open = False; files_open = False
            if cur_g: cur_g['tasks'].append(cur_t['n'])
            continue
        if re.match(r'^#{1,2}\s', line):
            cur_t = None; ctx_open = False; cases_open = False; files_open = False
            continue
        fm = FIELD.match(line)
        if fm:
            key, val = fm.group(1), fm.group(2)
            if key == 'Integration':
                integration = cmd_of(val); ctx_open = False; continue
            if cur_t is not None:
                # a **File:** line per file, or several on one line: every path counts, once
                files_open = key in ('File', 'Files')
                if files_open: cur_t['files'] += [f for f in path_tokens(val) if f not in cur_t['files']]
                elif key == 'Depends': cur_t['depends'] = [int(x) for x in re.findall(r'Task\s+(\d+)', val)]
                elif key == 'Test':
                    # **Test:** manual — what the person confirms: no RED or GREEN, the person confirms by hand
                    mm = re.match(r'^\s*manual\b\s*[—–:\-]*\s*(.*)$', val, re.I)
                    cur_t['manual'] = bool(mm)
                    cur_t['confirm'] = mm.group(1).strip() if mm else ''
                    cur_t['test'] = 'manual' if mm else cmd_of(val)
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
            if files_open and re.match(r'^\s*[-*]\s+(?!\[[ xX]\])\S', line):
                bare = re.sub(r'^\s*[-*]\s+', '', line).strip().strip('`')
                got = path_tokens(line) or ([bare[2:] if bare.startswith('./') else bare] if re.fullmatch(r'[\w.@\-/*?]+', bare) and ('/' in bare or '.' in bare) else [])
                cur_t['files'] += [f for f in got if f not in cur_t['files']]
            elif files_open and line.strip() and not re.match(r'^\s*[-*]\s+\[[ xX]\]', line):
                files_open = False
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


# ---- the states of a Build task, one definition each -------------------------------------------------------------------
# The CLI moves a task's status in groups.json (pending, running, passed, failed, covered). What the readers derive from it
# is defined here once: which tasks the schedule may launch and why one waits (the schedule, `temper task start`'s reason,
# the flow's chains), when a task is done (the flow's group check and the gate's "all tasks complete" row) and the state
# the view, the report and the panel show.
STARTABLE = ('pending', 'failed')   # never started, or a failed attempt to retry (a failed one goes alone, on its attempt's model)


def status_of(run, n):
    return (((run or {}).get('tasks') or {}).get(str(n)) or {}).get('status', 'pending')


def task_done(task, run):
    """A task is done when the run recorded it passed. A task the run holds no record of, in a group it never started, is
    judged by its box in tasks.md (a run not built task by task, such as one finished before groups.json): there the box
    is the only record. Once the run started its group, a box ticked by hand is not a pass (the CLI ticks it on one)."""
    run = run if isinstance(run, dict) else {}
    if str(task['n']) in (run.get('tasks') or {}) or task.get('group') in (run.get('groups') or {}):
        return status_of(run, task['n']) == 'passed'
    return re.search(r'^\s*- \[[xX]\]', task.get('block') or '', re.M) is not None


def display_state(info, group_info, phases):
    """The one state a task shows (view.json's build grid, the report, the panel): waiting, running, red, green, covered
    (its tests passed before any change: the person decides), pass, fail, or parked (failed in a parked group)."""
    st = (info or {}).get('status', 'pending')
    if st == 'passed':
        return 'pass'
    if st == 'failed':
        return 'parked' if (group_info or {}).get('status') == 'parked' else 'fail'
    if st == 'covered':
        return 'covered'
    if st == 'running':
        return 'green' if 'green' in phases else ('red' if 'red' in phases else 'running')
    return 'waiting'


def _why_waiting(plan, run, t, busy, slots_left, max_par, declared):
    """Why a startable task t cannot launch now, or None: `busy` holds the tasks running or already in the ready set."""
    rg = run.get('groups') or {}
    gdep = {g['id']: g['depends'] for g in plan['groups']}
    by_n = {x['n']: x for x in plan['tasks']}
    def gpass(g): return ((rg.get(g) or {}).get('gate') or {}).get('verdict') == 'PASS'
    n, g = t['n'], t['group']
    unmet = [d for d in t['depends'] if not (task_done(by_n[d], run) if d in by_n else status_of(run, d) == 'passed')]
    gwait = [d for d in gdep.get(g, []) if not gpass(d)]
    if (rg.get(g) or {}).get('status') == 'parked': return 'group %s is parked' % g
    if not (rg.get(g) or {}).get('worktree'): return 'group %s not started' % g
    if gwait: return 'group %s depends on %s' % (g, ', '.join(gwait))
    if unmet: return 'depends on %s' % ', '.join('Task %d' % d for d in unmet)
    clash = [m for m in busy if declared.get(m, set()) & declared[n]]
    if clash: return 'files overlap Task %d' % clash[0]
    if slots_left <= 0: return 'max-parallel %d reached' % max_par
    return None


def _norm(p):
    p = p.strip()
    return p[2:] if p.startswith('./') else p


def why_not_ready(plan, run, n, max_par):
    """Why Task n is not in the ready set, as the schedule decides it ('' when it is, or is not startable)."""
    why_of = {}
    schedule(plan, run, max_par, '', '', '', why_of)
    return why_of.get(n, '')


def schedule(plan, run, max_par, task_model, esc_model, project, why_of=None):
    """The ready set of a grouped run, one dict per launchable task, then a done or waiting line. A dict passed as why_of
    gets the reason each startable task waits, by task number."""
    if not isinstance(run, dict):
        run = {}
    rg, rt = run.get('groups') or {}, run.get('tasks') or {}
    norm = _norm
    tasks = sorted(plan['tasks'], key=lambda t: ([g['id'] for g in plan['groups']].index(t['group']) if t['group'] in [g['id'] for g in plan['groups']] else 999, t['n']))
    declared = {t['n']: {norm(f) for f in t['files']} for t in tasks}
    def status(n): return status_of(run, n)
    def agent_alias(m):  # the Agent tool's model parameter takes aliases, not full ids
        for a in ('haiku', 'sonnet', 'opus'):
            if m.startswith('claude-' + a + '-'): return a
        return m
    def gstatus(g): return (rg.get(g) or {}).get('status', 'pending')
    def gpass(g): return ((rg.get(g) or {}).get('gate') or {}).get('verdict') == 'PASS'
    running = [t['n'] for t in tasks if status(t['n']) == 'running']
    slots = max_par - len(running)
    ready, waiting = [], []
    why_of = {} if why_of is None else why_of
    for t in tasks:
        n, g = t['n'], t['group']
        if status(n) not in STARTABLE:
            continue
        why = _why_waiting(plan, run, t, list(running) + [r['task'] for r in ready], slots - len(ready), max_par, declared)
        if why:
            waiting.append('Task %d (%s)' % (n, why))
            why_of[n] = why
            continue
        attempt = len((rt.get(str(n)) or {}).get('attempts') or []) + 1
        mdl = task_model if attempt <= 2 else esc_model
        # the task's own worktree (temper task start makes it beside the group's: temper-{slug}-T{N} for temper-{slug}-{G})
        gwt = rg[g]['worktree']
        twt = gwt[:-len(g)] + 'T%d' % n if gwt.endswith('-' + g) else gwt
        ready.append({'task': n, 'group': g, 'title': t['title'], 'worktree': twt,
                      'project': project, 'model': mdl, 'agent_model': agent_alias(mdl),
                      'attempt': attempt, 'manual': bool(t.get('manual'))})
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
