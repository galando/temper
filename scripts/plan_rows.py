"""plan_rows.py: the grouped plan gate's rows of the temper CLI (tasks.md in groups), one JSON requirement per line.

  python3 -I plan_rows.py <max-blast-radius> <group context max bytes> <task block max bytes> <parsed plan JSON> <project>

Called by _grouped_plan_reqs in scripts/temper; it lived inside the CLI until 9.8.0, which moved it here to keep the CLI
under the plugin directory's 256 KiB limit for a file. Standard library only.
"""
import json, os, re, shlex, sys
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
# 9.8.4: a group must be able to pass its own Validate. Its worktree holds its own work and the groups it depends on, so a
# test file its Validate runs (named in the command as a path or a dotted Python module, inside a folder it names, or named by
# a script it runs from that script's folder) that a task of any other group edits is not there yet: the group fails its check every time (a measured run ran
# the selftest cases a later group updated, five times). Only a file that exists now counts; a new file is no conflict.
def run_paths(cmd, depth=0):
    try: words = shlex.split(cmd)
    except ValueError: words = cmd.split()
    out = []
    for w in words:
        if ' ' in w.strip() and depth < 2:           # bash -c '...': the inner command's words
            out += run_paths(w, depth + 1); continue
        w = w.split('=', 1)[1] if re.match(r'^[A-Za-z_]\w*=', w) else w
        w = w.split('::', 1)[0]
        if not w or w.startswith('-') or any(c in w for c in '$*?[{`|;&<>'): continue
        if re.fullmatch(r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)+', w) and not os.path.exists(os.path.join(sys.argv[5], w)):
            # a Python module named the dotted way (python3 -m unittest pkg.test_x): its file, or its package folder
            m = w.replace('.', '/')
            out.append(m + '.py' if os.path.isfile(os.path.join(sys.argv[5], m + '.py')) else m)
        elif '/' in w or os.path.splitext(w)[1]:
            out.append(w[2:] if w.startswith('./') else w)
    return list(dict.fromkeys(out))
def runs(path, f):
    """True when running `path` (a word of a Validate command) runs file f."""
    p = path.rstrip('/')
    if f == p: return True
    full = os.path.join(sys.argv[5], p)
    if os.path.isdir(full): return f.startswith(p + '/')
    if os.path.isfile(full) and os.path.dirname(f).startswith(os.path.dirname(p)):
        try: text = open(full, encoding='utf-8', errors='replace').read(512 * 1024)
        except OSError: return False
        return re.search(r'(^|[^\w.-])' + re.escape(os.path.basename(f)) + r'($|[^\w.-])', text, re.M) is not None
    return False
vo = []
for g in groups:
    paths = run_paths(g.get('validate') or '')
    if not paths: continue
    before = gclosure(g['id']) | {g['id']}
    own = {f for n in g['tasks'] for f in by_n[n]['files']}
    for t in tasks:
        if t['group'] in before or not t['group']: continue
        for f in t['files']:
            if f in own or not os.path.isfile(os.path.join(sys.argv[5], f)): continue
            if any(runs(p, f) for p in paths):
                vo.append("%s's Validate runs %s, which Task %d of %s edits: %s cannot pass its own check before %s; move the task into %s or "
                          "take the file out of %s's Validate" % (g['id'], f, t['n'], t['group'], g['id'], t['group'], g['id'], g['id']))
row('group validate order', vo, "no group's Validate runs a file a task of another group edits")
# 9.8.4: more than two tasks of one group on the same production file is one task cut in pieces: each piece passes its own
# gate on its own slice while the file as a whole is never checked until the group's Validate (a measured run had twelve
# tasks on a few files). Two tasks on one file, ordered by Depends, stay allowed; a shared test file does not count.
def is_test(f):
    parts = f.lower().split('/')
    base = parts[-1]
    return (any(p in ('test', 'tests', 'spec', 'specs', '__tests__', 'selftest', 'testing') for p in parts[:-1])
            or base.startswith(('test_', 'test-')) or re.search(r'[._-](test|tests|spec)\.[\w]+$', base) is not None)
shared = []
for g in groups:
    owners = {}
    for n in g['tasks']:
        for f in by_n[n]['files']:
            if not is_test(f): owners.setdefault(f, []).append(n)
    for f, ns in sorted(owners.items()):
        if len(ns) > 2:
            names = ['Task %d' % n for n in ns]
            shared.append('%s: %s and %s all declare %s; merge them into one task' % (g['id'], ', '.join(names[:-1]), names[-1], f))
row('shared production files', shared, 'no production file is declared by more than two tasks of one group')
row('integration command', [] if m['integration'] else ['no **Integration:** line'], 'integration command declared')
