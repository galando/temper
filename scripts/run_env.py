"""run_env.py: how the CLI runs a command of a grouped Build (a task's test, a scenario's Test: command, a group's Validate
command, the integration suite).

  run_env.test_env(cwd)      the environment: this one, without the variables whose names say they hold a credential,
                             and with the folder the command runs in first on PYTHONPATH
  run_env.run_cmd(wt, timeout, cmd)   run cmd in wt (one string runs through bash -c), killing it at the timeout

A credential is no input of a test: a key, a token, a secret, a password or passphrase, credentials, an auth socket or
helper are left out; every other variable passes as it is, and git's GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n
pass together. PYTHONPATH puts the folder first so a package importable from
both the project root (an editable install) and the task's worktree resolves to the worktree's copy; other languages
ignore it.

  run_env.programs(cmd)      the first word of each step of a shell line
  run_env.env_fault(out, rc, cmd)   why a failed run is the environment's: one of three sure signs, else ""

  run_env.load_setup(config=None)   the setup block of .claude/temper.config ($TEMPER_SETUP_CONFIG, which the CLI sets, else
                             $TEMPER_CONFIG, else ./.claude/temper.config):
                             {} without one, else {'run', 'env', 'services', 'tools', 'dropped'}

The setup block (setup: run: <one shell line>, env:, services:, tools:) is the project's environment contract: run_cmd
runs the line in the same shell before the command (so its exports reach it), prints `temper-setup: OK`, and adds env.
A failing line prints `temper-setup: FAIL (exit N)` and exits 125 without running the command. A variable of env whose
name says it holds a credential is never set; it is listed in `dropped`. Without a block, nothing changes.
Standard library only.
"""
import os
import re
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config_yaml  # noqa: E402

CREDENTIAL_NAME = re.compile(r'PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|APIKEY|ASKPASS|(?:^|_)(?:KEYS?|TOKENS?|SECRETS?|AUTH|PAT)(?:_|$)')
CREDENTIAL_NAMES = {'GPG_AGENT_INFO', 'GNUPGHOME', 'KRB5CCNAME'}
# git's own configuration through the environment: GIT_CONFIG_COUNT and its GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n pairs.
# They pass whole or not at all: "_KEY_" reads as a credential above, and a count whose keys are gone makes every git call
# fail with "unable to parse command-line config" (9.8.4: Claude Code cloud sessions configure git this way).
# When one of its keys carries a credential (an extra header, a helper, a password or token), the family is left out whole.
GIT_CONFIG_FAMILY = re.compile(r'^GIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+)$')
GIT_CONFIG_SECRET_KEY = re.compile(r'extraheader|helper|password|passwd|token|secret|askpass', re.I)


def test_env(cwd=None):
    family = {k: v for k, v in os.environ.items() if GIT_CONFIG_FAMILY.match(k)}
    if any(GIT_CONFIG_SECRET_KEY.search(v) for k, v in family.items() if k.startswith('GIT_CONFIG_KEY_')):
        family = {}
    env = {k: v for k, v in os.environ.items()
           if not GIT_CONFIG_FAMILY.match(k) and k != 'TEMPER_SETUP_CONFIG' and not CREDENTIAL_NAME.search(k.upper()) and k.upper() not in CREDENTIAL_NAMES}
    env.update(family)
    if cwd:
        old = env.get('PYTHONPATH')
        env['PYTHONPATH'] = os.path.abspath(cwd) + (os.pathsep + old if old else '')
    return env


# 9.8.5 (Q6): text a JVM or a runtime prints at its start, which says nothing about the run (a row's detail once was
# `ng.disabledSchemes= WARNING: A terminally deprecated method in sun.misc.Unsafe has been called`)
BANNER = re.compile(r"^(?:NOTE: )?Picked up (?:JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS):|^WARNING: (?:A terminally deprecated method|"
                    r"sun\.misc\.Unsafe|Please consider reporting this|A restricted method|Use --enable-native-access|"
                    r"Restricted methods will be blocked|.*will be removed in a future release|An illegal reflective access|"
                    r"Illegal reflective access|All illegal access operations)")


def strip_banner(text):
    return "\n".join(l for l in text.split("\n") if not BANNER.search(l.strip()))


def is_credential(name):
    return bool(CREDENTIAL_NAME.search(name.upper())) or name.upper() in CREDENTIAL_NAMES


def _yaml_text(v):
    return ('true' if v else 'false') if isinstance(v, bool) else str(v)


FAIL_LINE = re.compile(r'\bFAIL(?:ED|URE|S)?\b|\bERROR\b|^not ok\b|^E\s+\S|Error:')
# 9.8.5 (S4): a log line a passing test printed (`20:01:44.264 [main] ERROR com.x.Y -- ...`) says nothing about the run
LOG_LINE = re.compile(r'^\d{1,2}:\d{2}:\d{2}(?:[.,]\d+)?\s+\[[^\]]*\]\s+(?:ERROR|WARN)\b')
# the build tool's own summary of what failed, before any other line: Maven's goal, a JaCoCo rule, a failed test's name
SUMMARY = (re.compile(r'temper-setup: FAIL'), re.compile(r'Failed to execute goal'), re.compile(r'Rule violated'),
           re.compile(r'^\[ERROR\]\s+(?:Tests run:.*FAILURE|[\w.$]+\.\w+:\d+\b)'), re.compile(r'<<< (?:FAILURE|ERROR)!'))

def fail_lines(out, keep=8, rc=None):
    """What a failing run says failed, most telling first: a time-out (exit 124); the build tool's summary (the last Maven
    `Failed to execute goal` line, `Rule violated` lines, the names of failed tests); then the lines that say FAIL, FAILED,
    ERROR, not ok or an exception, first ones first, without the log lines a passing test printed. With none of these, the
    LAST three lines of the output, never the first (9.8.4, 9.8.5)."""
    lines = [' '.join(l.split()) for l in out.decode('utf-8', 'replace').splitlines()]
    lines = [l[:240] for l in lines if l]
    head = ['the command did not finish within its time limit (exit 124)'] if rc == 124 else []
    for pat in SUMMARY:
        found = [l for l in lines if pat.search(l)]
        head += found[-1:] if pat.pattern == 'Failed to execute goal' else found[:4]
    hits = [l for l in lines if FAIL_LINE.search(l) and not LOG_LINE.search(l)]
    picked = list(dict.fromkeys(head + hits))
    return picked[:keep] if picked else lines[-3:]


STEP_OPS = {';', ';;', '&&', '||', '|', '|&'}


def steps(cmd):
    """The words of each step of a shell line, assignments left out. An operator inside quotes splits no step; a lone
    `&` (a redirection such as 2>&1, or a background job) splits nothing, as before. Unbalanced quotes: the plain split."""
    import shlex
    try:
        lex = shlex.shlex(cmd or '', posix=True, punctuation_chars=';&|')
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        toks = None
    if toks is None:
        segs = [seg.split() for seg in re.split(r'&&|\|\||;|\|', cmd or '')]
    else:
        segs, cur = [], []
        for t in toks:
            if t in STEP_OPS:
                segs.append(cur)
                cur = []
            else:
                cur.append(t)
        segs.append(cur)
    return [[t for t in seg if not re.match(r'^\w+=', t)] for seg in segs]


def programs(cmd):
    """The first word of each step of a shell line (assignments left out): the programs it starts (9.8.5, WP21)."""
    return {seg[0] for seg in steps(cmd) if seg}


def env_fault(out, rc, cmd, setup=None):
    """The reason a failed run is the environment's, or "": only a sure sign (WP21). The setup line failed (exit 125
    with its marker); exit 127 with `X: command not found` for a program the command starts; a service of the setup
    block that does not answer right after the failed run. No text of the output counts beyond those, and a time out
    is the code's."""
    text = out.decode('utf-8', 'replace') if isinstance(out, bytes) else str(out or '')
    if rc in (0, None, 124):
        return ''
    if 'temper-setup: FAIL' in text:
        m = re.search(r'temper-setup: FAIL \(exit \d+\)', text)
        return 'the setup block failed (%s)' % (m.group(0) if m else 'temper-setup: FAIL')
    if rc == 127:
        for name in re.findall(r'([^\s:]+): command not found', text):
            if name in programs(cmd):
                return '%s: command not found' % name
    if setup is None:
        setup = load_setup()
    services = (setup or {}).get('services') or {}
    if services:
        import doctor
        down = ['%s at %s' % (n, a) for n, a in services.items() if not doctor.answers(a)]
        if down:
            return 'the service %s does not answer after the run' % ', '.join(down)
    return ''


def load_setup(config=None):
    path = (config or os.environ.get('TEMPER_SETUP_CONFIG') or os.environ.get('TEMPER_CONFIG')
            or os.path.join('.claude', 'temper.config'))
    blk = config_yaml.load(path).get('setup')
    if not isinstance(blk, dict) or not blk:
        return {}
    env, dropped = {}, []
    raw = (config_yaml.load(path, as_text=True).get('setup') or {}).get('env')   # U18: 3.10 stays 3.10, never the float 3.1
    for k, v in (raw if isinstance(raw, dict) else {}).items():
        if is_credential(k):
            dropped.append(k)
        else:
            env[k] = _yaml_text(v)
    services = blk.get('services') if isinstance(blk.get('services'), dict) else {}
    tools = blk.get('tools') if isinstance(blk.get('tools'), list) else []
    run = blk.get('run', '')
    return {'run': _yaml_text(run) if run not in ('', None) else '', 'env': env,
            'services': {k: _yaml_text(v) for k, v in services.items()}, 'tools': [str(t) for t in tools],
            'dropped': dropped}


# U18: what is shown also hides a name with PW, PWD or PASS as a whole part (MY_PW, DB_PWD, DB_PASS; the shell's own PWD
# is a folder), and the password of a URL's user info in any value (scheme://user:SECRET@host keeps the user and the
# host; the password runs to the last @ before the host, so one that holds an @ is hidden whole). A secret key inside a
# value, after `;`, `&` or `?` (a connection string, a JDBC URL, a second assignment of the run line), and a value of a
# well known key shape under any name are hidden too (NEW-FLOW-5, R0-R1-4). A display rule only: test_env and
# load_setup leave out by CREDENTIAL_NAME alone, so a command receives what it received before. No masker is complete:
# a flag that holds a password (`-psecret`) and a key of no known shape under a plain name are still shown.
SHOWN_SECRET = re.compile(r'(?:^|_)(?:PWD?|PASS)(?:_|$)')
URL_PASSWORD = re.compile(r'\b([A-Za-z][A-Za-z0-9+.-]*://[^\s/:@]*:)[^\s/]+@')
INNER_KEY = re.compile(r'([;&?])([A-Za-z_]\w*)=([^;&\s]*)')
KEY_VALUE = re.compile(r'\b(?:(?:sk|pk|rk)[-_][A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|AKIA[0-9A-Z]{16}'
                       r'|xox[abprs]-[A-Za-z0-9-]{10,})')


def shown_secret(name):
    return is_credential(name) or (name.upper() != 'PWD' and bool(SHOWN_SECRET.search(name.upper())))


def mask(text):
    """The run line (or a line of the block) as shown to an agent or a person: a NAME=value (or a line NAME: value) whose
    NAME is a credential, or has PW, PWD or PASS as a part, reads NAME=<left out>, also inside a value after `;`, `&` or
    `?`; a URL's password and a value of a well known key shape read <left out>."""
    text = re.sub(r'^(\s*([A-Za-z_]\w*): ).+$', lambda m: m.group(1) + '<left out>' if shown_secret(m.group(2)) else m.group(0),
                  text or '', flags=re.M)
    def inner(value):   # inside a value Pwd is a password, never the shell's folder
        return INNER_KEY.sub(lambda m: m.group(1) + m.group(2) + '=<left out>'
                             if shown_secret(m.group(2)) or m.group(2).upper() == 'PWD' else m.group(0), value)
    text = re.sub(r'\b([A-Za-z_]\w*)=(\S+)',
                  lambda m: m.group(1) + '=' + ('<left out>' if shown_secret(m.group(1)) else inner(m.group(2))), text)
    text = URL_PASSWORD.sub(lambda m: m.group(1) + '<left out>@', text)
    return KEY_VALUE.sub('<left out>', text)


def shown_var(name, value):
    """A variable of the setup block as shown: NAME=value, masked as mask masks it (the whole value of a secret name)."""
    return name + '=' + ('<left out>' if shown_secret(name) else mask(str(value)))


# The run line runs in the same bash as the command. The EXIT trap turns any end of the line that is not a success (an
# `exit 3` in it, or a non-zero last status) into `temper-setup: FAIL (exit N)` and exit 125, so the command never runs.
SETUP_SCRIPT = ('__temper_ok=0; trap \'__rc=$?; [ "$__temper_ok" = 1 ] || { echo "temper-setup: FAIL (exit $__rc)"; exit 125; }\' EXIT\n'
                '%s\n'
                '__rc=$?; [ "$__rc" = 0 ] || exit "$__rc"\n'
                '__temper_ok=1; trap - EXIT; echo "temper-setup: OK"\n')


def setup_args(cmd, setup):
    """(args, extra env) for cmd under the setup block."""
    if not setup:
        return (['bash', '-c', cmd[0]] if len(cmd) == 1 else cmd), {}
    extra = dict(setup.get('env') or {})
    pre = SETUP_SCRIPT % setup['run'] if setup.get('run') else ''
    if len(cmd) == 1:
        return ['bash', '-c', pre + cmd[0]], extra
    return ['bash', '-c', pre + 'exec "$@"', 'temper-setup'] + list(cmd), extra


# ---- the reuse store (9.8.5, S5; WP22) -------------------------------------------------------------------------------
# The same command on the same tree runs once. One digest says what "the same tree" is (tree_key: the work tree as it
# is, without .temper/, .claude/ and the byproducts of a run); the key adds the command text, the setup block, the folder
# inside the repository, the first version line of each program the command starts and what the caller adds. The store
# is temper-results.json in the git common folder (one file for every worktree of the clone), changed under a lock file
# beside it. An entry: {"pass": {"ts", "tail", "seconds", "extra"}, "fail": {"ts", "rc", "tail", "fail_lines", "answer",
# "class", "limit", "again"}, "flaky", "forced", "last"}. A failure is kept beside the pass and is never a pass; the same
# failed check on the same key returns the kept failure with its date, but for an environment or a not measured failure
# (run again at most twice), a time out under a larger limit, and --fresh (TEMPER_FRESH=1, the person's, counted).
# The byproduct list sits under the reserved key "byproducts"; only the runner writes it.
RESULTS = 'temper-results.json'
KEEP = 200
BYPRODUCTS = 'byproducts'
OWN = ('.temper', '.claude')
BUILTINS = {'cd', 'echo', 'true', 'false', 'export', 'test', '[', 'exit', 'set', 'source', '.', 'eval', 'unset', 'printf',
            'exec', 'env', 'time', 'command', ':', 'trap', 'wait', 'sleep', 'read', 'shift', 'local', 'return'}
NO_TESTS = re.compile(r'NO TESTS RAN|no tests ran|collected 0 items|^Ran 0 tests', re.M)
SOURCE_EXT = ('.py', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs', '.go', '.java', '.kt', '.rb', '.rs', '.cs', '.php',
              '.swift', '.scala', '.sh')
TEST_DIR_NAMES = ('tests', 'test', 'unit', 'spec', 'acceptance')
_VERSIONS = {}   # program: its first version line, read once per CLI call (trap 4)


def is_test_path(p):
    """A test source file: a test file name (test_x.py, x_test.go, x.test.ts, x.spec.js, XTest.java), or a source file in a
    tests folder. Never a compiled or cached file."""
    if '__pycache__' in p or not p.endswith(SOURCE_EXT):
        return False
    b = os.path.basename(p)
    return bool(re.match(r'^test_.*\.py$|^.*_test\.(py|go)$|^conftest\.py$|^.*\.(test|spec)\.[cm]?[jt]sx?$|^.*Tests?\.(java|kt|cs)$|'
                         r'^.*_spec\.rb$', b)) or any(part in TEST_DIR_NAMES for part in p.split('/')[:-1])


def _git(wt, *args, **kw):
    p = subprocess.run(['git', '-C', wt] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, env=kw.get('env'))
    return p.stdout.decode('utf-8', 'replace').strip() if p.returncode == 0 else ''


def _abs(wt, p):
    return p if not p or os.path.isabs(p) else os.path.join(wt, p)


def _store(wt):
    d = _git(wt, 'rev-parse', '--git-common-dir')
    return os.path.join(_abs(wt, d), RESULTS) if d else ''


class _Flock:
    """An exclusive lock of a file, held for a with block (no lock where fcntl is missing)."""

    def __init__(self, path):
        self.path, self.fd = path, None

    def __enter__(self):
        try:
            import fcntl
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
        except (ImportError, OSError):
            return self
        for _ in range(20):
            try:
                fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
            except OSError:
                return self
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                a, b = os.fstat(fd), os.stat(self.path)
                if (a.st_ino, a.st_dev) == (b.st_ino, b.st_dev):
                    self.fd = fd
                    return self
            except OSError:
                pass
            # the file was unlinked (_drop_locks) between the open and the lock: lock the one at the path now
            os.close(fd)
        return self

    def __exit__(self, *exc):
        if self.fd is not None:
            os.close(self.fd)


def store_read(path):
    import json
    try:
        d = json.load(open(path))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _newest(e):
    if not isinstance(e, dict):
        return ''
    return max([str(e.get('ts') or '')] + [str((e.get(k) or {}).get('ts') or '') for k in ('pass', 'fail')
                                           if isinstance(e.get(k), dict)])


def store_change(path, fn):
    """Read, change (fn changes the dict in place) and replace the store under its lock; the oldest entries past KEEP
    go."""
    import json
    if not path:
        return {}
    with _Flock(path + '.lock'):
        d = store_read(path)
        fn(d)
        keys = [k for k, v in d.items() if isinstance(v, dict)]
        if len(keys) > KEEP:
            for k in sorted(keys, key=lambda k: _newest(d[k]))[:len(keys) - KEEP]:
                d.pop(k, None)
        _drop_locks(path, d)
        try:
            tmp = '%s.tmp.%d' % (path, os.getpid())
            with open(tmp, 'w') as f:
                json.dump(d, f)
            os.replace(tmp, path)
        except OSError:
            pass
        return d


def _drop_locks(path, d):
    """The lock file of a key the store no longer holds goes, unless a run holds it now: the folder stays small."""
    folder = os.path.join(os.path.dirname(path), 'temper-locks')
    try:
        import fcntl
        names = [n for n in os.listdir(folder) if n.endswith('.lock') and not isinstance(d.get(n[:-5]), dict)]
    except (ImportError, OSError):
        return
    for n in names:
        try:
            fd = os.open(os.path.join(folder, n), os.O_RDWR)
        except OSError:
            continue
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.unlink(os.path.join(folder, n))
        except OSError:
            pass
        finally:
            os.close(fd)


def _tops(wt):
    """The top folder of every worktree of the clone."""
    return [x[9:] for x in _git(wt, 'worktree', 'list', '--porcelain').splitlines() if x.startswith('worktree ')]


def untracked(wt):
    """The untracked paths git does not ignore, from the top of the repository (a folder wholly untracked as `dir/`)."""
    p = subprocess.run(['git', '-C', wt, 'ls-files', '-o', '--exclude-standard', '--directory', '--full-name', '-z', '--',
                        ':(top)'], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return {x for x in p.stdout.decode('utf-8', 'surrogateescape').split('\0') if x} if p.returncode == 0 else set()


def declared(root):
    """The files the person approved (approved_files of the run state) and the files tasks.md declares, from the
    project folder `root`, as written there."""
    import json
    out = set()
    try:
        st = json.load(open(os.path.join(root, '.temper', 'build-state.json')))
        st = st if isinstance(st, dict) else {}
    except (OSError, ValueError):
        st = {}
    out |= {str(x) for x in st.get('approved_files') or [] if x}
    sp = str(st.get('spec_path') or '')
    tasks = os.path.join(root, sp, 'tasks.md') if sp else ''
    if tasks and os.path.isfile(tasks):
        try:
            import tasks_md
            out |= {f for t in tasks_md.parse(tasks)['tasks'] for f in t.get('files') or []}
        except Exception:
            pass
    return out


def _bad_byproduct(p, prefix, tracked, decl):
    """Never a byproduct (trap 1): a tracked file or one under a listed folder, a declared file, a source or test file,
    the run's own folders."""
    d = p if p.endswith('/') else None
    rel = p[len(prefix):] if prefix and p.startswith(prefix) else p
    if rel.split('/')[0] in OWN or p.split('/')[0] in OWN:
        return True
    if p.rstrip('/').endswith(SOURCE_EXT) or is_test_path(p):
        return True
    if d:
        return any(t.startswith(d) for t in tracked) or any((prefix + f).startswith(d) for f in decl)
    return p in tracked or rel in decl or p in {prefix + f for f in decl}


def byproducts_of(wt, store=None, root=None, extra=()):
    """The byproduct list as it applies to the work tree wt: an entry git tracks, one a task declares, a source or test
    file is dropped at each use, whatever the store holds."""
    lst = (store or {}).get(BYPRODUCTS)
    lst = [str(x) for x in lst if isinstance(x, str) and x] if isinstance(lst, list) else []
    lst = list(dict.fromkeys(lst + [x for x in extra if x]))
    if not lst:
        return []
    prefix = _git(wt, 'rev-parse', '--show-prefix')
    p = subprocess.run(['git', '-C', wt, 'ls-files', '--full-name', '-z', '--'] + [':(top,literal)%s' % x for x in lst],
                       stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    tracked = {x for x in p.stdout.decode('utf-8', 'surrogateescape').split('\0') if x}
    decl = declared(root or os.getcwd()) | declared(wt)
    return [x for x in lst if not _bad_byproduct(x, prefix, tracked, decl)]


def tree_key(wt, byproducts=None, root=None):
    """The digest of the work tree as it is: the git tree of its tracked files with their content now and of every
    untracked file git does not ignore, without .temper/, .claude/ and the byproducts (.temper/ and .claude/ count as
    HEAD holds them, so a clean tree gives HEAD^{tree}). A copied index and a scratch object folder, so neither the real index nor the project's object
    store is touched (trap 2). '' outside a git repository."""
    import shutil
    import tempfile
    top = _git(wt, 'rev-parse', '--show-toplevel')
    if not top:
        return ''
    prefix = _git(wt, 'rev-parse', '--show-prefix')
    index = _abs(wt, _git(wt, 'rev-parse', '--git-path', 'index'))
    objects = _abs(wt, _git(wt, 'rev-parse', '--git-path', 'objects'))
    if byproducts is None:
        byproducts = byproducts_of(wt, store_read(_store(wt)), root)
    tmp = tempfile.mkdtemp(prefix='temper-tree-')
    try:
        os.makedirs(os.path.join(tmp, 'objects'))
        if os.path.isfile(index):
            # with its time: git reads an entry again when the index is no older than it (racy git), so a same size
            # edit in the second the entry was written is seen; a copy dated now would let the stat data call it clean.
            # Content and time from one open file: git replaces the index by a rename, which may land between two reads
            with open(index, 'rb') as src, open(os.path.join(tmp, 'index'), 'wb') as dst:
                st = os.fstat(src.fileno())
                shutil.copyfileobj(src, dst)
            os.utime(os.path.join(tmp, 'index'), ns=(st.st_atime_ns, st.st_mtime_ns))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, 'index'), GIT_OBJECT_DIRECTORY=os.path.join(tmp, 'objects'),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects)
        # the run's own folders count as HEAD holds them: a spec file staged for the commit changes no digest
        subprocess.run(['git', '-C', wt, 'reset', '-q', 'HEAD', '--'] + [':(top,literal)%s%s' % (prefix, o) for o in OWN],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        spec = [':(top)'] + [':(exclude,top,literal)%s%s' % (prefix, o) for o in OWN] + \
               [':(exclude,top,literal)%s' % b.rstrip('/') for b in byproducts]
        # exit 1 when an excluded folder is one git ignores (".temper is ignored"); the other paths are added all the same
        subprocess.run(['git', '-C', wt, 'add', '-A', '--'] + spec, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, env=env)
        return _git(wt, 'write-tree', env=env)
    except OSError:
        return ''
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def versions(cmd, setup=None, wt=None):
    """{program: its first version line} of each program the command starts (a path into the tree is part of the
    digest) and of each tool of the setup block: one shell call for those not read yet in this process. A program of
    the repository itself, named by its full path (a script in the work tree or in the git folder), is the project's
    own: it is never started with --version, which would run it (WP23)."""
    text = cmd[0] if len(cmd) == 1 else (cmd[0] if cmd else '')
    own = [x.rstrip('/') + '/' for x in (_git(wt, 'rev-parse', '--show-toplevel'), _git(wt, 'rev-parse', '--git-common-dir'))
           if x] if wt else []
    own = [os.path.realpath(x if os.path.isabs(x) else os.path.join(os.path.abspath(wt), x)) + '/' for x in own]
    progs = sorted({p for p in programs(text) if p not in BUILTINS and ('/' not in p or p.startswith('/'))
                    and not (p.startswith('/') and any(os.path.realpath(p).startswith(x) for x in own))} | set((setup or {}).get('tools') or []))
    todo = [p for p in progs if p not in _VERSIONS]
    if todo:
        import shlex
        lines = ['echo "@@temper %d"; %s %s 2>&1 </dev/null' % (i, shlex.quote(p), '-version' if os.path.basename(p) == 'java'
                                                                   else '--version') for i, p in enumerate(todo)]
        env = test_env()
        env.update((setup or {}).get('env') or {})
        try:
            r = subprocess.run(['bash', '-c', '\n'.join(lines)], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, env=env, timeout=20)
            out = r.stdout.decode('utf-8', 'replace')
        except (OSError, subprocess.TimeoutExpired):
            out = ''
        for i, p in enumerate(todo):
            part = out.split('@@temper %d\n' % i, 1)[1] if ('@@temper %d\n' % i) in out else ''
            part = part.split('@@temper ', 1)[0]
            first = [l.strip() for l in strip_banner(part).splitlines() if l.strip()]
            _VERSIONS[p] = first[0][:200] if first else ''
    return {p: _VERSIONS.get(p, '') for p in progs}


def result_key(wt, cmd, setup, extra=None, tree=None):
    """(key, tree) of a command run in wt: the digest, the command, the setup block, the folder inside the repository,
    the version lines and what the caller adds (the acceptance command: the lock's file digests). The time limit is no
    part of it. (None, '') outside a git repository."""
    import hashlib
    import json
    tree = tree if tree is not None else tree_key(wt)
    if not tree:
        return None, ''
    folder = _git(wt, 'rev-parse', '--show-prefix')
    raw = json.dumps([tree, list(cmd), setup or {}, folder, versions(cmd, setup, wt), extra], sort_keys=True, default=str)
    return hashlib.sha256(raw.encode('utf-8')).hexdigest(), tree


def _now():
    import time
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def fail_class(out, rc, cmd, setup):
    """`environment` (the setup line, a program not found, a service down, a project's SETUP marker), `not measured`
    (the runner found no test), else `command`."""
    text = out.decode('utf-8', 'replace') if isinstance(out, bytes) else str(out or '')
    if rc in (125, 127) or re.search(r'^[\w.-]+: SETUP: ', text, re.M) or env_fault(text, rc, ' '.join(cmd), setup):
        return 'environment'
    if rc in (4, 5) and NO_TESTS.search(text):
        return 'not measured'
    return 'command'


def _kept(e, timeout):
    """What a kept entry gives this call: ('pass' | 'fail', its record), ('again', n) for a failure run once more, or
    None to run."""
    if not isinstance(e, dict):
        return None
    p, f = e.get('pass') if isinstance(e.get('pass'), dict) else None, e.get('fail') if isinstance(e.get('fail'), dict) else None
    last = e.get('last') or ('fail' if f and (not p or str(f.get('ts')) > str(p.get('ts'))) else 'pass')
    if f and (last == 'fail' or not p):
        try:
            more = f.get('rc') == 124 and float(timeout) > float(f.get('limit') or 0)
        except (TypeError, ValueError):
            more = False
        if more:
            return None
        if f.get('class') in ('environment', 'not measured') and int(f.get('again') or 0) < 2:
            return 'again', int(f.get('again') or 0) + 1
        return 'fail', f
    return ('pass', p) if p else None


def _named(line, decl):
    for f in decl:
        st = os.path.splitext(os.path.basename(f))[0]
        if f in line or (len(st) >= 4 and re.search(r'\b%s\b' % re.escape(st), line)):
            return True
    return False


def _recheck_base(root, cmd, out, rc, setup):
    """The base of a failed run worth one more run at once (step 9): the same command passed on the base tree (the
    baseline, or a plan command), or failed there and this run shows a fail line the base did not, and no fail line names
    a declared file. ('pass' | 'red', masked base lines), or None."""
    if rc in (0, 124, 125, 126, 127) or fail_class(out, rc, cmd, setup) != 'command':
        return None
    try:
        import baseline
        base = baseline.base_result(root, ' '.join(cmd) if len(cmd) == 1 else cmd[0])
        lines = baseline.picked(out, rc)
    except Exception:
        return None
    if base is None:
        return None
    if base[0] == 'red' and (not base[1] or all(baseline.mask(x) in base[1] for x in lines)):
        return None
    if any(_named(x, declared(root)) for x in lines):
        return None
    return base[0], base[1], [x for x in lines if baseline.mask(x) not in base[1]]


def as_owner(wt, cmd, root=None):
    """WP23 mechanism 2, one owner: a command whose text is the owner's test text (check_run.det_for of the project
    folder `root`, as integrate reads it) runs in the owner's run text, its coverage measured as integrate measures it,
    so a group's Validate on the merged tree and integrate share one key. (command, info) for run_cached; the command as
    given, with no info, when it is not the owner's test text or the owner has no other run text. The folder the run
    text writes its coverage into (.temper/check, as check_run.run makes it in the project folder) is made in wt."""
    import json
    root = root or os.getcwd()
    text = ' '.join(cmd).strip()
    try:
        import check_run
        cfg = config_yaml.load(os.path.join(root, '.claude', 'temper.config'))
        det = check_run.det_for(root, *(str(config_yaml.get(cfg, k, '') or '').strip()
                                         for k in ('check.commands.test', 'check.commands.coverage')))
        run = ((det.get('coverage') or {}).get('run') or '') if det.get('test', '').strip() == text else ''
        if not run or run == text:
            return cmd, {}
        try:
            base = json.load(open(os.path.join(root, '.temper', 'build-state.json'))).get('base_sha') or ''
        except (OSError, ValueError, AttributeError):
            base = ''
        base = base or _git(root, 'rev-parse', 'HEAD')   # as `check build-checks` takes it
        os.makedirs(os.path.join(wt, '.temper', 'check'), exist_ok=True)   # go test -coverprofile makes no folder
        return [run], {'measure': check_run.measure_of(wt, det, base), 'need_extra': True}
    except Exception:   # the owner unknown: the command runs as the plan wrote it
        return cmd, {}


def kept(wt, cmd, setup=None, root=None):
    """What the store holds of cmd on the tree of wt as it is now, without running it (WP23 trap 9, the planted bugs read
    the suite's time here): ('pass' | 'fail', its record) as the runner would give it, or None when it holds nothing."""
    if setup is None:
        setup = load_setup()
    root = root or os.getcwd()
    path = _store(wt)
    store = store_read(path) if path else {}
    key = result_key(wt, cmd, setup, None, tree_key(wt, byproducts_of(wt, store, root), root))[0] if path else None
    e = store.get(key) if key else None
    if not isinstance(e, dict):
        return None
    p, f = (e.get(x) if isinstance(e.get(x), dict) else None for x in ('pass', 'fail'))
    if f and (e.get('last') == 'fail' or not p):
        return 'fail', f
    return ('pass', p) if p else None


def kept_again(wt, rows, since=''):
    """WP22 step 8: whether the store already knows that a check of `rows` (a ledger) failed again on the same key since
    `since`: 'reused' when the newest row of that check, written then, came back from the kept failure (nothing ran, so
    the tree, the command and the setup did not change), 'again' when the store ran an environment or not measured
    failure again there and it failed; else False. The questions read this before they compare failure texts and before
    the count fix_empty."""
    last = {}
    for x in rows or []:
        if isinstance(x, dict) and str(x.get('ts') or '') >= since:
            last[(x.get('claim'), x.get('group'), x.get('scenario'), x.get('cmd'))] = x
    want = [x for x in last.values() if x.get('key') and x.get('exit_code') not in (0, None)]
    store = store_read(_store(wt)) if want else {}
    for x in want:
        e = store.get(x['key'])
        f = e.get('fail') if isinstance(e, dict) else None
        if isinstance(f, dict) and e.get('last', 'fail') == 'fail' and (x.get('reused') or int(f.get('again') or 0) >= 1):
            return 'reused' if x.get('reused') else 'again'
    return False


def row_fields(info):
    """The fields a row of a runner call carries: tree, key, seconds and reused (the date, or null); flaky and forced
    when they hold."""
    i = info if isinstance(info, dict) else {}
    out = {'tree': i.get('tree') or None, 'key': i.get('key'), 'seconds': i.get('seconds'), 'reused': i.get('reused') or None}
    if i.get('flaky'):
        out['flaky'] = i['flaky']
    if i.get('forced'):
        out['forced'] = True
    return out


def run_cached(wt, timeout, cmd, setup=None, info=None, extra=None, fresh=None, root=None):
    """(output, exit, the date of a kept result or '') of cmd in wt (trap 6: three values). A kept pass of the same key
    is returned and not run; so is a kept failure (but its exceptions). One run in flight per key: a second caller waits
    on the key's lock file and reads the entry. A failed run whose command has a pass on the base runs once more at once
    (_recheck_base): fail then pass is flaky, the pass counts. A dict `info` gets tree, key, seconds, reused, flaky,
    forced and extra; its `measure`, when given, is called with the output of a pass and gives `extra`, kept with the
    pass (with `need_extra`, a kept pass without one runs again)."""
    import time
    if setup is None:
        setup = load_setup()
    if fresh is None:
        fresh = os.environ.get('TEMPER_FRESH') == '1'
    info = info if isinstance(info, dict) else {}
    root = root or os.getcwd()
    path = _store(wt)
    store = store_read(path) if path else {}
    key, tree = result_key(wt, cmd, setup, extra, tree_key(wt, byproducts_of(wt, store, root), root) if path else '')
    info.update(tree=tree or None, key=key, reused=None, flaky=None, forced=bool(fresh) or None, extra=None, fail_lines=None)
    again = 0

    def hit(e):
        k = _kept(e, timeout)
        if k is None or k[0] == 'again' or (k[0] == 'pass' and info.get('need_extra') and k[1].get('extra') is None):
            return k[1] if k and k[0] == 'again' else None
        rec = k[1]
        info.update(reused=str(rec.get('ts') or ''), seconds=rec.get('seconds'), extra=rec.get('extra'),
                    fail_lines=rec.get('fail_lines'))
        if k[0] == 'pass':
            if isinstance(e.get('flaky'), dict):   # step 9: a reused flaky pass is still flaky, for the commit card
                info['flaky'] = e['flaky']
            note = '[temper: the same command passed on this same tree at %s; reused, not run again]\n' % rec.get('ts', '?')
            return (note + str(rec.get('tail', ''))).encode('utf-8'), 0, str(rec.get('ts', ''))
        note = ('[temper: the same command failed on this same tree at %s (exit %s); not run again: change the code, the '
                'command or the setup block, or run it anyway]\n' % (rec.get('ts', '?'), rec.get('rc')))
        return (note + str(rec.get('tail', ''))).encode('utf-8'), int(rec.get('rc') or 1), str(rec.get('ts', ''))
    if key and not fresh:
        got = hit(store.get(key))
        if isinstance(got, tuple):
            return got
    lock = os.path.join(os.path.dirname(path), 'temper-locks', '%s.lock' % key) if key else ''
    import contextlib
    with _Flock(lock) if lock else contextlib.nullcontext():
        if key and not fresh:
            got = hit(store_read(path).get(key))
            if isinstance(got, tuple):
                return got
            again = got if isinstance(got, int) else 0
        before = untracked(wt) if key else set()
        t0 = time.time()
        out, rc = run_cmd(wt, timeout, cmd, setup)
        base = _recheck_base(root, cmd, out, rc, setup) if rc != 0 else None
        if base is not None:   # once more at once, on the same tree and limit; no agent comes between
            first = (base[2] or fail_lines(out, rc=rc))[:8]
            out2, rc2 = run_cmd(wt, timeout, cmd, setup)
            try:
                import baseline
                gone = rc2 == 0 or (base[0] == 'red' and baseline.picked(out2, rc2) and
                                    all(baseline.mask(x) in base[1] for x in baseline.picked(out2, rc2)))
            except Exception:
                gone = rc2 == 0
            if gone:
                info['flaky'] = {'ts': _now(), 'rc': rc, 'lines': first,
                                 'text': 'failed once (%s) and passed when run again at once' % '; '.join(first)[:300]}
            out, rc = out2, rc2
        info['seconds'] = round(time.time() - t0, 1)
        if rc == 0 and callable(info.get('measure')):
            info['extra'] = info['measure'](out)
        if rc != 0:
            info['fail_lines'] = fail_lines(out, None, rc)   # every one: a skip or a gate compares them with the base
        if not key:
            return out, rc, ''
        new = sorted(untracked(wt) - before)
        if new:
            new = byproducts_of(wt, None, root, new)
        ts = _now()
        tops = _tops(wt) if new or store.get(BYPRODUCTS) else []

        def put(d):
            e = d.get(key) if isinstance(d.get(key), dict) else {}
            tail = out[-2048:].decode('utf-8', 'replace')
            if rc == 0:
                e['pass'] = {'ts': ts, 'tail': tail, 'seconds': info['seconds'], 'extra': info.get('extra')}
                e['last'] = 'pass'
            else:
                e['fail'] = {'ts': ts, 'rc': rc, 'tail': tail, 'fail_lines': info['fail_lines'], 'answer': None,
                             'class': fail_class(out, rc, cmd, setup), 'limit': timeout, 'again': again}
                e['last'] = 'fail'
            if info.get('flaky'):
                e['flaky'] = info['flaky']
            elif rc == 0:   # the stamp is of the pass it describes: a pass made cleanly on the key ends it
                e.pop('flaky', None)
            if fresh:
                e['forced'] = ts
            d[key] = e
            if new or (tops and d.get(BYPRODUCTS)):   # a byproduct no worktree holds any more leaves the list
                d[BYPRODUCTS] = sorted(x for x in set(x for x in d.get(BYPRODUCTS) or [] if isinstance(x, str)) | set(new)
                                       if not tops or any(os.path.lexists(os.path.join(t, x)) for t in tops))
        store_change(path, put)
    return out, rc, ''


def main(argv):
    """python3 run_env.py tree DIR: the digest of DIR as it is (a verdict's tree); python3 run_env.py checked GATES DIR:
    `FAIL <why>` when the project changed after the Check verdict was computed (the two trees), else nothing."""
    import json
    if len(argv) == 3 and argv[1] == 'tree':
        print(tree_key(argv[2], root=argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == 'checked':
        try:
            g = json.load(open(argv[2])).get('check') or {}
        except (OSError, ValueError, AttributeError):
            g = {}
        was = str(g.get('tree') or '') if isinstance(g, dict) else ''
        try:   # only before the change is committed: a CI fix of the Pipeline stage is a change after Check by design
            stage = json.load(open(os.path.join(argv[3], '.temper', 'build-state.json'))).get('next_stage')
        except (OSError, ValueError, AttributeError):
            stage = None
        was = was if stage in ('check', 'commit') else ''
        now = tree_key(argv[3], root=argv[3]) if was else ''
        if was and now and now != was:
            print('FAIL the project changed after the Check verdict: Check judged the tree %s, the project is now the tree '
                  '%s; run Check again' % (was[:12], now[:12]))
            return 0
        # WP24 (ADR 0021): the Review verdict is of the committed tree, or of a tree that differs from it only by repair
        # commits the CLI recorded, whose checks ran again and whose recheck completed (scripts/repair_ops.py)
        try:
            gates = json.load(open(argv[2]))
            st = json.load(open(os.path.join(argv[3], '.temper', 'build-state.json')))
        except (OSError, ValueError, AttributeError):
            gates, st = {}, {}
        why = review_stale(gates, st, argv[3], now) if stage in ('check', 'commit') else ''
        if why:
            print('FAIL ' + why)
        return 0
    return 2


def review_stale(gates, state, root, now=''):
    """Why the Review verdict is not of the project as it is (in every run: a run with no repair has no chain, so any
    difference counts), or '': its tree is the tree now, or differs from it only by closed repairs whose recheck
    completed. The commit gate's row checked tree reads it, and so does a small change at Check or Commit
    (adhoc_ops.close_window), which then runs Review of its files again."""
    gr = gates.get('review') if isinstance(gates, dict) else None
    rv = str(gr.get('tree') or '') if isinstance(gr, dict) else ''
    now = (now or tree_key(root, root=root)) if rv else ''
    if rv and now and rv != now:
        import repair_ops
        if not repair_ops.closed_chain(state if isinstance(state, dict) else {}, rv, now):
            return ('the Review verdict judged the tree %s, the project is now the tree %s, and the difference is not only '
                    'closed repairs whose recheck completed; run Review again' % (rv[:12], now[:12]))
    return ''


def run_cmd(wt, timeout, cmd, setup=None):
    """Returns (output bytes, exit). 124 is a timeout, 127 a command that could not start, 125 a failed setup line."""
    if setup is None:
        setup = load_setup()
    args, extra = setup_args(cmd, setup)
    env = test_env(wt)
    env.update(extra)
    try:
        p = subprocess.Popen(args, cwd=wt, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
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


if __name__ == "__main__":
    sys.exit(main(sys.argv))
