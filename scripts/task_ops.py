"""task_ops.py: the Build task operations of the temper CLI, one mode per call.

  python3 -I task_ops.py <mode> [args...]

The CLI's _task_py calls it with standard input closed, the project's folder from the top of its repository in
TEMPER_PREFIX and the groups file in TEMPER_GROUPS_FILE. Modes: ctx, why and show (a task's brief and context),
snap, testrun, grouprun and integrun (run a declared command and record its row), integplan and ifcheck (the
integration facts and the Interfaces check), gatecheck, foreigncheck, unknown and reopencheck (what a group's branch
holds), restore (undo a task's changes) and verdict (a task's gate). It lived inside scripts/temper until 9.7.1, which
moved it here to keep every file of the plugin under the directory's 256 KiB limit.

Standard library only.
"""
import hashlib, json, os, re, shlex, signal, subprocess, sys, time

# The project's folder from the top of its repository ("" at the top). git status and git diff name a path from the
# top of the worktree; the plan names it from the project folder, so each is read from there (a path outside the
# project reads as ../..., which no task declares).
PREFIX = os.environ.get('TEMPER_PREFIX', '')

def R(p):
    if not PREFIX:
        return p
    if p.startswith(PREFIX):
        return p[len(PREFIX):]
    return os.path.relpath(p, PREFIX.rstrip('/'))

def top_of(wt):
    r = subprocess.run(['git', '-C', wt, 'rev-parse', '--show-toplevel'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode('utf-8', 'surrogateescape').strip() or wt

def norm(p):
    p = p.strip()
    return p[2:] if p.startswith('./') else p

def fail(msg):
    print('FAIL: ' + msg, file=sys.stderr)
    sys.exit(1)

_LOCK_DEADLINE = []

def lock_deadline():
    """H1: one wall-clock budget for every retry of the whole process (a few seconds), shared by all git commands of an
    undo or restore: the caller may pass its own deadline (epoch seconds) so the budget spans several processes."""
    if not _LOCK_DEADLINE:
        try:
            _LOCK_DEADLINE.append(float(os.environ.get('TEMPER_GIT_LOCK_DEADLINE') or 0) or time.time() + 5)
        except ValueError:
            _LOCK_DEADLINE.append(time.time() + 5)
    return _LOCK_DEADLINE[0]

def lock_failed(r):
    return r is not None and r.returncode != 0 and b'.lock' in r.stderr

def run_retry(cmd, delay=0.1):
    """Run a git command; a failure that names a .lock file (index.lock, HEAD.lock: another git process holds it,
    briefly) is retried until the shared budget is spent, any other failure is returned at once. Every command runs
    at least once."""
    dl = lock_deadline()
    while True:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode == 0 or b'.lock' not in r.stderr or time.time() + delay > dl:
            return r
        time.sleep(delay)

def snap(wt):
    """sha256 of every dirty or untracked path in the worktree ('DELETED' for a path that is gone), each path named from
    the project folder (R)."""
    r = subprocess.run(['git', '--literal-pathspecs', '-C', wt, 'status', '--porcelain=v1', '-z', '-uall'],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    ents = r.stdout.decode('utf-8', 'surrogateescape').split('\0')
    top = top_of(wt)
    out, i = {}, 0
    while i < len(ents):
        e = ents[i]; i += 1
        if len(e) < 4:
            continue
        xy, path = e[:2], e[3:]
        if xy[0] in 'RC' or xy[1] in 'RC':
            old = ents[i] if i < len(ents) else ''
            i += 1
            if old:
                out[R(old)] = 'DELETED'
        fp = os.path.join(top, path)
        try:
            out[R(path)] = hashlib.sha256(open(fp, 'rb').read()).hexdigest() if os.path.isfile(fp) else 'DELETED'
        except OSError:
            out[R(path)] = 'DELETED'
    return out

def untracked(wt):
    """The untracked paths of the worktree (porcelain '??'), for the byproducts a CLI test run leaves behind."""
    r = subprocess.run(['git', '--literal-pathspecs', '-C', wt, 'status', '--porcelain=v1', '-z', '-uall'],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return {R(e[3:]) for e in r.stdout.decode('utf-8', 'surrogateescape').split('\0') if e.startswith('?? ')}

def load_run(gfile):
    try:
        d = json.load(open(gfile))
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def run_cmd(wt, timeout, cmd):
    """Run cmd (one string runs through bash -c) in wt with a kill timeout; returns (output bytes, exit)."""
    args = ['bash', '-c', cmd[0]] if len(cmd) == 1 else cmd
    try:
        p = subprocess.Popen(args, cwd=wt, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            out, _ = p.communicate(timeout=float(timeout))
            rc = p.returncode if p.returncode >= 0 else 128 - p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            out, _ = p.communicate()
            rc = 124
    except OSError as e:
        out, rc = ('%s\n' % e).encode(), 127
    return out, rc

def show(out, rc, keep=12):
    """Print a suite's output for the orchestrator: a passing run only its last lines (the runner's summary), since the
    whole output of a long suite fills the main conversation for nothing; a failing run all of it, for the failure."""
    lines = out.decode('utf-8', 'replace').splitlines(True)
    if rc == 0 and len(lines) > keep:
        sys.stdout.write('[the first %d lines of the passing output are not shown]\n' % (len(lines) - keep))
        lines = lines[-keep:]
    sys.stdout.write(''.join(lines))
    sys.stdout.flush()

def red_why(r):
    """Why a failing RED run is not evidence ('' when it is): the command never ran the tests."""
    rc, cmd = r.get('exit_code'), r.get('cmd') or ''
    if rc in (126, 127): return 'the command could not run'
    if rc == 124: return 'it timed out'
    if isinstance(rc, int) and rc >= 128: return 'it was killed by a signal'
    if re.search(r'(^|[\s/\'"])pytest\b', cmd) and rc != 1:
        return 'pytest exits 1 when a test fails; %s is a collection, import or usage error' % rc
    return ''

def red_ok(r):
    """A RED run counts when it failed on the tests themselves, not before they ran."""
    return r.get('phase') == 'red' and r.get('exit_code') not in (0, None) and not red_why(r)

def ctx(plan, run, n):
    t = next((x for x in plan['tasks'] if x['n'] == n), None)
    if t is None:
        fail('tasks.md has no Task %d' % n)
    g = next((x for x in plan['groups'] if x['id'] == t['group']), None)
    if g is None:
        fail('Task %d is outside any group' % n)
    rg = (run.get('groups') or {}).get(g['id']) or {}
    rt = (run.get('tasks') or {}).get(str(n)) or {}
    status = rt.get('status', 'pending')
    attempts = rt.get('attempts') or []
    return {'n': n, 'title': t['title'], 'group': g['id'], 'files': t['files'], 'block': t['block'],
            'test': t['test'], 'context': g['context'], 'status': status,
            # one worktree per task: a task works in its own worktree (made by task start from the group branch, removed
            # when its gate passes or fails), never in the group worktree, which only takes merges and the group Validate
            'worktree': rt.get('worktree') or rg.get('worktree', ''), 'gworktree': rg.get('worktree', ''),
            'gbranch': rg.get('branch', ''), 'tbranch': rt.get('branch', ''),
            'attempt': rt.get('attempt', 1) if status == 'running' else len(attempts) + 1,
            'attempts': attempts, 'start_sha': rt.get('start_sha', ''), 'started_at': rt.get('started_at', ''),
            'snapshot': rt.get('snapshot') or {}, 'slug': run.get('slug', ''),
            'gstatus': rg.get('status', ''), 'gparked': rg.get('parked_reason', '')}

PATTERN_MAX_BYTES = 2048
TEST_NAME = re.compile(r'(^|/)(test_[^/]+|[^/]+_test\.[^/.]+|[^/]+\.(test|spec)\.[^/.]+|test[^/]*\.[^/.]+)$')

def pattern_test(wt, test_cmd, files, planned=()):
    """(path, first lines) of the existing test file nearest to the task's own test, or None: same extension, a test by
    its name, tracked in the task's worktree and not empty, declared by no task of the plan (another task may be
    rewriting it); the declared test itself when it exists already (the task extends it). Nearest is the longest
    shared folder prefix, then the name."""
    try:
        parts = shlex.split(test_cmd or '')
    except ValueError:
        parts = []
    own = ''
    for a in parts[1:]:
        if a.startswith('-') or any(ch in a for ch in '$*?[{`'):
            continue
        if '/' in a or os.path.splitext(a)[1]:
            own = norm(a)
            break
    if not own:
        own = next((norm(f) for f in files if TEST_NAME.search(norm(f))), '')
    if not own:
        return None
    ext = os.path.splitext(own)[1]
    declared = {norm(f) for f in files} | {norm(f) for f in planned}
    def has_text(x):
        try:
            return open(os.path.join(wt, x), 'rb').read(4096).strip() != b''
        except OSError:
            return False
    r = subprocess.run(['git', '-C', wt, 'ls-files', '-z'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    tracked = [x for x in r.stdout.decode('utf-8', 'surrogateescape').split('\0') if x]
    if own in tracked and has_text(own):
        pick = own
    else:
        cands = [x for x in tracked if x not in declared and os.path.splitext(x)[1] == ext and TEST_NAME.search(x) and has_text(x)]
        if not cands:
            return None
        def shared(x):
            a, b = os.path.dirname(x).split('/'), os.path.dirname(own).split('/')
            k = 0
            while k < min(len(a), len(b)) and a[k] == b[k]:
                k += 1
            return k
        pick = sorted(cands, key=lambda x: (-shared(x), x))[0]
    try:
        raw = open(os.path.join(wt, pick), 'rb').read(PATTERN_MAX_BYTES + 1)
    except OSError:
        return None
    text = raw[:PATTERN_MAX_BYTES].decode('utf-8', 'ignore')
    if len(raw) > PATTERN_MAX_BYTES:
        text = text[:text.rfind('\n') + 1] + '[the rest of the file is cut]'
    return pick, text.rstrip('\n')

def matches(path, pats):
    return any(path == norm(p) for p in pats)   # H4: exact paths only; the plan gate refuses glob characters

def known_shas(run, g):
    # D-08: the shas the CLI itself recorded (a task's commit, cli_commits) and the ones a human accepted for group g with
    # `group reopen --accept-foreign` (an override). A subject that merely looks like the CLI's proves nothing.
    known = {(v or {}).get('commit') for v in (run.get('tasks') or {}).values()} | set(run.get('cli_commits') or [])
    try:
        for o in json.load(open('.temper/overrides.json')):
            st = str(o.get('stage', '')).split(':', 2)
            if len(st) == 3 and st[0] == 'foreign-commit' and st[1] == g:
                known.add(st[2])
    except Exception:
        pass
    return known

def unknown_commits(cwd, run, g, ref):
    # M5: the commits of group g's base..ref that are neither recorded by the CLI nor accepted, newest first. A group
    # without a recorded base, or a git error, reports none (the checks that follow stay as they were).
    base = ((run.get('groups') or {}).get(g) or {}).get('base_sha')
    if not base:
        return []
    rl = subprocess.run(['git', '-C', cwd, 'rev-list', '--topo-order', '%s..%s' % (base, ref)],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if rl.returncode != 0:
        return []
    kn = known_shas(run, g)
    return [x for x in rl.stdout.decode('utf-8', 'replace').split() if x not in kn]

mode = sys.argv[1]

if mode == 'ctx':
    print(json.dumps(ctx(json.loads(sys.argv[2]), load_run(sys.argv[3]), int(sys.argv[4]))))

elif mode == 'why':
    plan, run, n, max_par = json.loads(sys.argv[2]), load_run(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    c = ctx(plan, run, n)
    t = next(x for x in plan['tasks'] if x['n'] == n)
    rg, rt = run.get('groups') or {}, run.get('tasks') or {}
    def st(m): return (rt.get(str(m)) or {}).get('status', 'pending')
    g = next(x for x in plan['groups'] if x['id'] == c['group'])
    gwait = [d for d in g['depends'] if ((rg.get(d) or {}).get('gate') or {}).get('verdict') != 'PASS']
    unmet = [d for d in t['depends'] if st(d) != 'passed']
    running = [x for x in plan['tasks'] if st(x['n']) == 'running']
    clash = [x['n'] for x in running if {norm(f) for f in x['files']} & {norm(f) for f in t['files']}]
    if (rg.get(c['group']) or {}).get('status') == 'parked': print('group %s is parked' % c['group'])
    elif gwait: print('group %s depends on %s' % (c['group'], ', '.join(gwait)))
    elif unmet: print('depends on %s' % ', '.join('Task %d' % d for d in unmet))
    elif clash: print('files overlap Task %d' % clash[0])
    elif len(running) >= max_par: print('max-parallel %d reached' % max_par)
    else: print('')

elif mode == 'snap':
    print(json.dumps(snap(sys.argv[2])))

elif mode == 'show':
    plan, run, n, project = json.loads(sys.argv[2]), load_run(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    c = ctx(plan, run, n)
    if not c['worktree']:
        fail('group %s is not started (temper group start %s)' % (c['group'], c['group']))
    head = 'TASK %d (group %s, attempt %d): %s\nWORKTREE: %s\nPROJECT:  %s\nDECLARED FILES: %s\n' % (
        n, c['group'], c['attempt'], c['title'], os.path.join(project, c['worktree'], PREFIX).rstrip('/'), project, ', '.join(c['files']))
    body = head + '--- TASK ---\n' + c['block'] + '\n--- GROUP CONTEXT ---\n' + c['context'] + '\n'
    # an existing test of the project, so the agent copies its style, imports and fixtures instead of guessing them
    pat = pattern_test(os.path.join(project, c['worktree'], PREFIX).rstrip('/'), c['test'], c['files'], [f for t in plan['tasks'] for f in t['files']])
    if pat:
        body += '--- PATTERN TEST (%s: follow its style, imports and fixtures) ---\n%s\n' % pat
    # F1: the human's feedback from a group gate's Change (group reopen --feedback ID) reaches the task agent
    fb_ids = [str(r['feedback']) for r in (((run.get('tasks') or {}).get(str(n)) or {}).get('reopened') or [])
              if r.get('feedback') and not r.get('resolved')]
    if fb_ids:
        try:
            rows = json.load(open(sys.argv[7]))
        except Exception:
            rows = []
        for i in fb_ids:
            text = [r.get('claim') or '' for r in rows if r.get('phase') == 'feedback'
                    and re.match(r'feedback #%s\b' % re.escape(i), r.get('claim') or '')]
            body += '--- FEEDBACK #%s (apply it) ---\n%s\n' % (i, text[-1] if text else '(no text recorded)')
    if c['attempts']:
        last = c['attempts'][-1]
        prev = '--- PREVIOUS ATTEMPT ---\n%s: %s\n%s\n' % (last.get('outcome', 'FAIL'), last.get('reason', ''),
                                                           last.get('output', ''))
        room = int(sys.argv[6]) - len(body.encode('utf-8'))
        pb = prev.encode('utf-8')
        if len(pb) > room:
            note = b'\n[truncated]\n'
            pb = pb[:max(room - len(note), 0)].decode('utf-8', 'ignore').encode('utf-8') + note if room > len(note) else b''
        body += pb.decode('utf-8', 'ignore')
    sys.stdout.write(body)

elif mode == 'testrun':
    wt, timeout, rowfile, n, group, attempt, phase = sys.argv[2:9]
    cmd = sys.argv[10:]   # argv[9] is the '--' separator
    before = untracked(wt)
    out, rc = run_cmd(wt, timeout, cmd)
    # F5: untracked paths that first appear during this CLI run (__pycache__, coverage files, logs) are the test
    # command's byproducts; the task verdict does not count them as undeclared changes
    byproducts = sorted(untracked(wt) - before)
    sys.stdout.write(out.decode('utf-8', 'replace'))
    sys.stdout.flush()
    row = {'claim': 'Task %s unit test %s' % (n, phase), 'cmd': ' '.join(shlex.quote(x) for x in cmd), 'exit_code': rc,
           'artifact': None, 'sha256': None, 'value': None, 'severity': None, 'phase': phase, 'scenario': None,
           'criterion': None, 'label': 'PROVEN' if rc == 0 else 'HEURISTIC', 'task': int(n), 'group': group,
           'attempt': int(attempt), 'executed_by': 'cli', 'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
           'output': out[-4096:].decode('utf-8', 'replace'), 'byproducts': byproducts[:1000]}
    json.dump(row, open(rowfile, 'w'))
    sys.exit(rc)

elif mode == 'grouprun':
    # the group's own Validate command, run by the CLI in the group worktree; the row is tagged with the
    # group and carries phase 'group', so it never counts as a task RED or GREEN run
    wt, timeout, rowfile, group = sys.argv[2:6]
    cmd = sys.argv[7:]    # argv[6] is the '--' separator
    out, rc = run_cmd(wt, timeout, cmd)
    show(out, rc)
    row = {'claim': 'Group %s validate' % group, 'cmd': ' '.join(shlex.quote(x) for x in cmd), 'exit_code': rc,
           'artifact': None, 'sha256': None, 'value': None, 'severity': None, 'phase': 'group', 'scenario': None,
           'criterion': None, 'label': 'PROVEN' if rc == 0 else 'HEURISTIC', 'group': group,
           'executed_by': 'cli', 'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
           'output': out[-4096:].decode('utf-8', 'replace')}
    json.dump(row, open(rowfile, 'w'))
    sys.exit(rc)

elif mode == 'integrun':
    # the full suite, run by the CLI in the project folder after the merges; phase 'integration' keeps it
    # out of the task RED/GREEN counts
    wt, timeout, rowfile = sys.argv[2:5]
    cmd = sys.argv[6:]    # argv[5] is the '--' separator
    out, rc = run_cmd(wt, timeout, cmd)
    show(out, rc)
    row = {'claim': 'Integration suite', 'cmd': ' '.join(shlex.quote(x) for x in cmd), 'exit_code': rc,
           'artifact': None, 'sha256': None, 'value': None, 'severity': None, 'phase': 'integration', 'scenario': None,
           'criterion': None, 'label': 'PROVEN' if rc == 0 else 'HEURISTIC', 'executed_by': 'cli',
           'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'output': out[-4096:].decode('utf-8', 'replace')}
    json.dump(row, open(rowfile, 'w'))
    sys.exit(rc)

elif mode == 'integplan':
    # integplan <plan> <groups.json>: the integration facts as one JSON line: the suite command, the groups whose
    # gate has not passed, the merge order (Depends first, then group number) and the Interfaces entries
    plan, run = json.loads(sys.argv[2]), load_run(sys.argv[3])
    rg = run.get('groups') or {}
    ids = [g['id'] for g in plan['groups']]
    deps = {g['id']: [d for d in g['depends'] if d in ids] for g in plan['groups']}
    order, done = [], set()
    while len(order) < len(ids):
        ready = sorted((i for i in ids if i not in done and all(d in done for d in deps[i])), key=lambda x: int(x[1:]))
        if not ready:
            ready = sorted((i for i in ids if i not in done), key=lambda x: int(x[1:]))
        order.append(ready[0]); done.add(ready[0])
    print(json.dumps({'integration': plan.get('integration') or '',
                      'notpassed': [i for i in order if ((rg.get(i) or {}).get('gate') or {}).get('verdict') != 'PASS'],
                      'order': order,
                      'worktrees': {i: (rg.get(i) or {}).get('worktree', '') for i in order},
                      'interfaces': [x for g in plan['groups'] for x in g['interfaces']]}))

elif mode == 'ifcheck':
    # ifcheck <interfaces-json>: the first Interfaces entry whose literal is not in its file at HEAD
    for x in json.loads(sys.argv[2]):
        r = subprocess.run(['git', 'show', 'HEAD:' + x['path']], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if r.returncode != 0 or x['literal'] not in r.stdout.decode('utf-8', 'replace'):
            print('interface missing: %s in %s' % (x['literal'], x['path']))
            sys.exit(1)

elif mode == 'gatecheck':
    # gatecheck <plan> <groups.json> <G> <abs worktree>: line 1 the group's validate command, line 2 the tasks that have not
    # passed (comma separated), line 3 the passed tasks whose recorded commit is not an ancestor of the worktree HEAD
    # (D-08: "Task N (sha)"), line 4 the group's status
    plan, run, g = json.loads(sys.argv[2]), load_run(sys.argv[3]), sys.argv[4]
    grp = next((x for x in plan['groups'] if x['id'] == g), None)
    if grp is None:
        fail('tasks.md has no group %s' % g)
    rt = run.get('tasks') or {}
    notpassed = ['Task %d' % n for n in grp['tasks'] if (rt.get(str(n)) or {}).get('status', 'pending') != 'passed']
    off = []
    for n in grp['tasks']:
        t = rt.get(str(n)) or {}
        if t.get('status') == 'passed' and t.get('commit'):
            r = subprocess.run(['git', '-C', sys.argv[5], 'merge-base', '--is-ancestor', t['commit'], 'HEAD'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode != 0:
                off.append('Task %d (%s)' % (n, t['commit'][:7]))
    print(grp['validate'])
    print(', '.join(notpassed))
    print(', '.join(off))
    print(((run.get('groups') or {}).get(g) or {}).get('status', ''))

elif mode == 'foreigncheck':
    # foreigncheck <abs worktree> <parked-shas-json> <accept-csv> <groups.json> <G>: one line per fact, "ACCEPT <sha>" for a
    # sha the human named (a unique prefix of 4 or more characters of a parked sha or of a commit of the group's base..HEAD
    # that is neither recorded by the CLI nor accepted), "BAD <given>" for one that is neither, "ON <sha>" for a parked sha
    # that is still an ancestor of the worktree HEAD and was not accepted (D-08), and "UNK <sha>" for such an unrecorded,
    # unaccepted commit that is not parked (M5: a replayed commit has a new sha)
    wt, parked = sys.argv[2], json.loads(sys.argv[3])
    run, grp = load_run(sys.argv[5]), sys.argv[6]
    unknown = [u for u in unknown_commits(wt, run, grp, 'HEAD') if u not in parked]
    universe = list(parked) + unknown
    acc = set()
    for a in (x.strip().lower() for x in sys.argv[4].split(',') if x.strip()):
        hit = [p for p in universe if p.startswith(a)] if len(a) >= 4 else []
        if len(hit) == 1:
            acc.add(hit[0])
            print('ACCEPT ' + hit[0])
        else:
            print('BAD ' + a)
    for p in parked:
        if p not in acc and subprocess.run(['git', '-C', wt, 'merge-base', '--is-ancestor', p, 'HEAD'],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            print('ON ' + p)
    for u in unknown:
        if u not in acc:
            print('UNK ' + u)

elif mode == 'unknown':
    # unknown <project root> <groups.json> <G> <ref>: the unrecorded, unaccepted commits of G's base..ref, one per line
    for u in unknown_commits(sys.argv[2], load_run(sys.argv[3]), sys.argv[4], sys.argv[5]):
        print(u)

elif mode == 'reopencheck':
    # reopencheck <plan> <groups.json> <G> <N>...: prints one "N<TAB>declared files, comma separated<TAB>start_sha"
    # line per task, or fails naming the first task that cannot be reopened
    plan, run, g = json.loads(sys.argv[2]), load_run(sys.argv[3]), sys.argv[4]
    grp = next((x for x in plan['groups'] if x['id'] == g), None)
    if grp is None:
        fail('tasks.md has no group %s' % g)
    by_n = {x['n']: x for x in plan['tasks']}
    def ancestors(n, seen=None):  # every task n depends on, directly or not
        seen = set() if seen is None else seen
        for d in (by_n.get(n) or {}).get('depends', []):
            if d not in seen:
                seen.add(d)
                ancestors(d, seen)
        return seen
    wanted = []
    for a in sys.argv[5:]:
        n = int(a)
        t = by_n.get(n)
        if t is None:
            fail('tasks.md has no Task %d' % n)
        if n not in grp['tasks']:
            fail('Task %d is not in group %s' % (n, g))
        st = (run.get('tasks') or {}).get(str(n)) or {}
        if st.get('status', 'pending') == 'running':
            fail('Task %d is running; let it finish or fail first' % n)
        if n not in wanted:
            wanted.append(n)
    # M3: restoring Task N's files to its start_sha would revert a later task's edits to the same file while
    # that task stays passed. A later task (one that depends on N, directly or not) that already ran and shares
    # a file must be reopened with it.
    for n in wanted:
        for m in grp['tasks']:
            if m in wanted or n not in ancestors(m):
                continue
            ms = (run.get('tasks') or {}).get(str(m)) or {}
            shared = sorted(set(by_n[n]['files']) & set(by_n[m]['files']))
            if shared and ms.get('status', 'pending') in ('passed', 'running'):
                fail('Task %d (depends on Task %d) also edits %s; reopen it too (--task %d)' % (m, n, ', '.join(shared), m))
    # dependents first: a later task restores to a start_sha that already holds its ancestors' edits
    wanted.sort(key=lambda n: -len(ancestors(n)))
    for n in wanted:
        st = (run.get('tasks') or {}).get(str(n)) or {}
        print('%d\t%s\t%s' % (n, ','.join(by_n[n]['files']), st.get('start_sha', '')))

elif mode == 'restore':
    # restore <worktree> <sha> <paths-json | @file>: each path goes back to its content at sha (and out of the index),
    # or is removed when sha does not have it. Batched: one ls-tree, then checkout/reset in chunks, never one git
    # process per path. A path behind a symlinked directory is left alone (never written or removed through the link).
    # A git lock that outlasts the shared retry budget ends the restore at once (exit 3).
    import stat
    wt, sha, arg = sys.argv[2], sys.argv[3], sys.argv[4]
    paths = json.loads(open(arg[1:]).read() if arg.startswith('@') else arg)
    lt = subprocess.run(['git', '--literal-pathspecs', '-C', wt, 'ls-tree', '-r', '-z', '--name-only', sha],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    had = set(lt.stdout.split(b'\0'))
    wtb = os.fsencode(wt)
    def link_above(p):
        cp = wtb
        for comp in os.fsencode(p).split(b'/')[:-1]:
            cp = os.path.join(cp, comp)
            try:
                st = os.lstat(cp)
            except OSError:
                return False
            if stat.S_ISLNK(st.st_mode):
                return True
            if not stat.S_ISDIR(st.st_mode):
                return False
        return False
    blocked = {p for p in paths if link_above(p)}
    tracked = [p for p in paths if os.fsencode(p) in had and p not in blocked]
    for p in paths:
        if os.fsencode(p) not in had and p not in blocked:
            try:
                os.remove(os.path.join(wt, p))
            except OSError:
                pass
    def chunked(cmd_head, chunk):
        return run_retry(['git', '--literal-pathspecs', '-C', wt] + cmd_head + ['--'] + chunk)
    for i in range(0, len(tracked), 200):
        chunk = tracked[i:i + 200]
        for head in (['checkout', sha], ['reset', '-q', 'HEAD']):
            r = chunked(head, chunk)
            if lock_failed(r):
                sys.exit(3)
            if r.returncode != 0:
                for p in chunk:   # one path in the chunk could not be restored: the rest still are
                    if lock_failed(chunked(head, [p])):
                        sys.exit(3)

elif mode == 'verdict':
    plan, run, ledger, n, wt = json.loads(sys.argv[2]), load_run(sys.argv[3]), sys.argv[4], int(sys.argv[5]), sys.argv[6]
    c = ctx(plan, run, n)
    try:
        rows = json.load(open(ledger))
    except Exception:
        rows = []
    # M1: only the rows made since this attempt started count; a reopened task numbers its attempts from 1 again, and
    # the rows of its earlier run must not stand in for a RED and a GREEN of this one
    mine = [r for r in rows if r.get('task') == n and r.get('attempt') == c['attempt'] and r.get('executed_by') == 'cli'
            and not (r.get('ts') and c['started_at'] and r['ts'] < c['started_at'])]
    # H1: the verdict reads the LAST run of the attempt: a red run, then a passing green after it, and the
    # attempt's final run must itself be that green (a failing re-run after a green is not forgiven).
    green = None
    for i, r in enumerate(mine):
        if r.get('phase') == 'green' and r.get('exit_code') == 0:
            green = i
    reason = ''
    if green is None:
        reason = 'no green run for this task and attempt'
    elif not any(red_ok(r) for r in mine[:green]):
        bad = [r for r in mine[:green] if r.get('phase') == 'red' and r.get('exit_code') not in (0, None)]
        reason = ('need a failing run before a passing run for this task and attempt' if not bad else
                  'the RED run did not run the tests (exit %s: %s); it must fail on an assertion' % (
                      bad[-1].get('exit_code'), red_why(bad[-1])))
    elif green != len(mine) - 1:
        reason = 'the final run of this attempt is not green'
    # the worktree's own run state (the commit hook writes .temper/gates.json there) is not the task's change
    def internal(p):
        return p.startswith('.temper/') or p.startswith('.claude/worktrees/')
    now = snap(wt)
    old = c['snapshot']
    changed = sorted(p for p in set(now) | set(old) if now.get(p, 'CLEAN') != old.get(p, 'CLEAN') and not internal(p))
    # H2: files changed by commits made in the worktree since the task's start also count
    foreign = []       # newest first, as git log prints them
    committed = []
    if c['start_sha']:
        rl = subprocess.run(['git', '-C', wt, 'log', '--topo-order', '--format=%H', '%s..HEAD' % c['start_sha']],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        # A1/D-08: only shas the CLI itself recorded (a task's commit, cli_commits) or a human accepted with
        # `group reopen --accept-foreign` (an override) are known; a subject that merely looks like the CLI's proves
        # nothing. The task's own worktree holds only this task's work, so any other commit in its range is the agent's.
        known = known_shas(run, c['group'])
        foreign = [x for x in rl.stdout.decode('utf-8', 'replace').split('\n') if x.strip() and x not in known]
        df = subprocess.run(['git', '-C', wt, 'diff', '--name-only', '--no-renames', '-z', c['start_sha'], 'HEAD'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        committed = sorted(R(p) for p in df.stdout.decode('utf-8', 'surrogateescape').split('\0') if p and not internal(R(p)))
    def commit_files(sha):
        dt = subprocess.run(['git', '-C', wt, 'diff-tree', '--no-commit-id', '--name-only', '-r', '-z', '--no-renames', '-m', '--root', sha],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return sorted({x for x in dt.stdout.decode('utf-8', 'surrogateescape').split('\0') if x})
    mine_changed = [p for p in changed if matches(p, c['files'])]
    # F5: a path a CLI test run of this attempt created, still untracked and in no commit, is a byproduct
    byproducts = {p for r in mine for p in (r.get('byproducts') or [])} - set(committed)
    # the worktree is this task's alone: every other changed path is an undeclared change of this task
    undeclared = sorted(p for p in set(changed) | set(committed) if not matches(p, c['files']) and p not in byproducts)
    problems = []
    def named(lst, cap=20):   # a verdict with thousands of paths names the first few
        return ', '.join(lst[:cap]) + (' (and %d more)' % (len(lst) - cap) if len(lst) > cap else '')
    if undeclared:
        problems.append('undeclared change: ' + named(undeclared))
    if foreign:   # D-08: each foreign sha with the files it changed
        problems.append('commit not made by the CLI: ' + '; '.join('%s (%s)' % (x[:7], named(commit_files(x), 10)) for x in foreign[:10])
                        + (' (and %d more)' % (len(foreign) - 10) if len(foreign) > 10 else ''))
    if problems and (foreign or not reason):
        reason = '; '.join(([reason] if reason and foreign else []) + problems)
    tail = ''
    if reason:
        last = [r for r in mine if r.get('output')]
        tail = '\n'.join((last[-1]['output'] if last else '').split('\n')[:20]).rstrip('\n')
    print(json.dumps({'verdict': 'FAIL' if reason else 'PASS', 'reason': reason, 'commit_paths': mine_changed,
                      'foreign_shas': foreign,
                      'output': tail, 'attempt': c['attempt'], 'title': c['title'], 'group': c['group'],
                      'slug': c['slug']}))
