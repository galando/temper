"""earlier_build.py SPEC_PATH PARSED_PLAN_JSON: the commit of the spec folder's newest committed gate-ledger.json that records a
Build PASS of its own (not skipped). Exit 0 (the commit) when no file of the plan changed since; exit 2 (the commit, a tab, and
what changed) when one did; exit 1 (why) when no such ledger is committed. Called by _earlier_build in scripts/temper (a door
into Review or Check); it lived inside the CLI until 9.8.4, which moved it here to keep the CLI under the plugin directory's
256 KiB limit for a file. Standard library only.
"""
import json, subprocess, sys
spec = sys.argv[1].rstrip('/')
def git(*a):
    r = subprocess.run(['git', '--literal-pathspecs', '-c', 'core.quotePath=false'] + list(a), capture_output=True, text=True)
    return r.returncode, r.stdout
led = spec + '/gate-ledger.json'
rc, shas = git('log', '-n', '20', '--format=%H', '--', led)
shas = shas.split() if rc == 0 else []
if not shas:
    print('the spec folder holds no committed gate-ledger.json of an earlier run'); sys.exit(1)
def built(sha):
    # the ledger as that commit holds it records a Build PASS of its own (not a skip)
    rc, text = git('show', '%s:./%s' % (sha, led))
    try:
        d = json.loads(text) if rc == 0 else {}
    except ValueError:
        return False
    b = (d.get('gates') or {}).get('build') or {} if isinstance(d, dict) else {}
    return b.get('verdict') == 'PASS' and not any(isinstance(o, dict) and o.get('stage') == 'build' for o in d.get('overrides') or [])
# the newest ledger that does: a later door run that skipped Build (or a run left without one) hides no earlier Build PASS
sha = next((x for x in shas if built(x)), None)
if not sha:
    print('no committed gate-ledger.json of the spec folder records a Build PASS of its own'); sys.exit(1)
try:
    files = sorted({f for t in json.loads(sys.argv[2]).get('tasks', []) for f in t.get('files', [])})
except ValueError:
    files = []
if not files:
    print('tasks.md declares no files'); sys.exit(1)
rc, out = git('diff', '--name-only', sha, '--', *files)
if rc or out.strip():
    print('%s\tthe ledger committed in %s records Build PASS, but a file of the plan changed since: %s' % (
        sha, sha[:7], ', '.join(out.split()[:3]) or 'git diff failed'))
    sys.exit(2)
print(sha)
