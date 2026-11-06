"""plan_rows.py: the grouped plan gate's rows of the temper CLI (tasks.md in groups), one JSON requirement per line.

  python3 -I plan_rows.py <max-blast-radius> <group context max bytes> <task block max bytes> <parsed plan JSON> <project>

Called by _grouped_plan_reqs in scripts/temper; it lived inside the CLI until 9.8.0, which moved it here to keep the CLI
under the plugin directory's 256 KiB limit for a file. Standard library only.
"""
import json, os, shlex, sys
max_blast, ctx_max, blk_max = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
m = json.loads(sys.argv[4])
groups, tasks = m['groups'], m['tasks']
def row(name, bad, ok_detail):
    print(json.dumps({'name': name, 'pass': not bad, 'detail': '; '.join(bad) if bad else ok_detail}))
by_n = {}
bad = []
if not groups: bad.append('no "## Group G<n>: title" heading')
for t in tasks:
    if t['n'] in by_n: bad.append('duplicate Task %d' % t['n'])
    by_n.setdefault(t['n'], t)
    if not t['group']: bad.append('Task %d is outside any group' % t['n'])
row('grouped plan', bad, '%d groups: %s' % (len(groups), ', '.join('%s (%d tasks)' % (g['id'], len(g['tasks'])) for g in groups)))
row('declared files', ['Task %d: no declared files' % t['n'] for t in tasks if not t['files']],
    'every task declares its files')
row('exact file paths', ['Task %d: **File:** %s is a glob; declare exact paths' % (t['n'], f)
                         for t in tasks for f in t['files'] if any(c in f for c in '*?[')],
    'every **File:** is an exact path')
def test_path(cmd):  # the first path-like argument of a test command, else ''
    try: parts = shlex.split(cmd)
    except ValueError: return ''
    for a in parts[1:]:
        if a.startswith('-') or any(c in a for c in '$*?[{`'): continue
        if '/' in a or os.path.splitext(a)[1] in ('.sh', '.py', '.js', '.ts', '.bats', '.rb'): return a
    return ''
def undeclared_test(t):
    p = test_path(t['test'])
    if not p: return None
    q = p[2:] if p.startswith('./') else p
    if q in {f.strip()[2:] if f.strip().startswith('./') else f.strip() for f in t['files']}: return None
    if os.path.exists(os.path.join(sys.argv[5], q)): return None
    return 'Task %d: test path %s is not declared in **File:** and does not exist yet' % (t['n'], q)
row('task test command', ['Task %d: no test command' % t['n'] for t in tasks if not t['test']]
    + [m for m in map(undeclared_test, tasks) if m],
    'every task declares its own scoped test command')
row('task test cases', ['Task %d: %d case(s) under **Cases:** (need 2 or more: the normal result and an edge or error case)' % (t['n'], t['cases'])
                        for t in tasks if t['cases'] < 2],
    'every task lists the concrete cases its test must check')
row('group context', ['%s: no group context' % g['id'] for g in groups if not g['context']],
    'every group has a context block')
row('context budget', ['%s: context %d bytes > %d' % (g['id'], g['context_bytes'], ctx_max)
                       for g in groups if g['context_bytes'] > ctx_max], 'every context within %d bytes' % ctx_max)
row('task block budget', ['Task %d: block %d bytes > %d' % (t['n'], t['block_bytes'], blk_max)
                          for t in tasks if t['block_bytes'] > blk_max], 'every task block within %d bytes' % blk_max)
gids = {g['id'] for g in groups}
dep_bad = []
for t in tasks:
    for d in t['depends']:
        if d not in by_n: dep_bad.append('Task %d depends on unknown Task %d' % (t['n'], d))
for g in groups:
    for d in g['depends']:
        if d not in gids: dep_bad.append('%s depends on unknown %s' % (g['id'], d))
def find_cycle(nodes, edges, label):
    state = {}
    def visit(n, path):
        state[n] = 1
        for d in edges.get(n, []):
            if d not in nodes: continue
            if state.get(d) == 1:
                return ' -> '.join(label(x) for x in path[path.index(d):] + [d])
            if d not in state:
                r = visit(d, path + [d])
                if r: return r
        state[n] = 2
        return None
    for n in nodes:
        if n not in state:
            r = visit(n, [n])
            if r: return r
    return None
c = find_cycle(list(by_n), {n: t['depends'] for n, t in by_n.items()}, lambda x: 'Task %d' % x)
if c: dep_bad.append('Depends cycle: ' + c)
gdeps = {g['id']: g['depends'] for g in groups}
c = find_cycle(list(gids), gdeps, str)
if c: dep_bad.append('Depends cycle: ' + c)
# F3: a group's worktree starts from the feature branch plus the groups it depends on, so a task that depends on a
# task of another group needs its own group to depend (transitively) on that group, or it runs without that work
def gclosure(g):
    seen, stack = set(), list(gdeps.get(g, []))
    while stack:
        x = stack.pop()
        if x in seen: continue
        seen.add(x); stack.extend(gdeps.get(x, []))
    return seen
for n, t in sorted(by_n.items()):
    for d in t['depends']:
        dg = (by_n.get(d) or {}).get('group')
        if dg and t['group'] and dg != t['group'] and dg not in gclosure(t['group']):
            dep_bad.append('Task %d (%s) depends on Task %d (%s) but %s does not depend on %s' % (n, t['group'], d, dg, t['group'], dg))
row('dependencies', dep_bad, 'no cycles, no unknown dependencies')
# A precedes B when A is a transitive task ancestor of B, or B's group transitively depends on A's group.
def closure(start, edges, ok):
    seen, stack = set(), list(edges.get(start, []))
    while stack:
        x = stack.pop()
        if x in seen or not ok(x): continue
        seen.add(x); stack.extend(edges.get(x, []))
    return seen
tdeps = {n: t['depends'] for n, t in by_n.items()}
ordered = set()
for n, t in by_n.items():
    for a in closure(n, tdeps, lambda x: x in by_n): ordered.add((a, n))
    if t['group']:
        for ag in closure(t['group'], gdeps, lambda x: x in gids):
            for o in tasks:
                if o['group'] == ag: ordered.add((o['n'], n))
ov = []
ts = sorted(by_n)
for i, a in enumerate(ts):
    for b in ts[i + 1:]:
        if (a, b) in ordered or (b, a) in ordered: continue
        for f in by_n[a]['files']:
            if f in by_n[b]['files']:
                ov.append('file ownership overlap: %s in Task %d and Task %d' % (f, a, b))
row('file ownership', ov, 'tasks that can run together declare disjoint files')
big = []
for g in groups:
    files = {f for n in g['tasks'] for f in by_n[n]['files']}
    if len(files) > max_blast:
        big.append('%s declares %d files > autonomy.max-blast-radius=%d: split the group' % (g['id'], len(files), max_blast))
row('group blast radius', big, 'every group within autonomy.max-blast-radius=%d' % max_blast)
row('integration command', [] if m['integration'] else ['no **Integration:** line'], 'integration command declared')
