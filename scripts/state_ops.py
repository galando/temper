#!/usr/bin/env python3
"""state_ops.py: the run state of the temper CLI: init, advance, the stage it is at, redo, the ledger it archives.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/state_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def migrate_legacy(argv):
    import json, os, sys, tempfile
    p = argv[1]
    try:
        d = json.load(open(p))
    except Exception:
        sys.exit(0)                     # malformed state == absent; never crash (spine contract)
    changed = False
    if not isinstance(d, dict):
        sys.exit(0)
    if d.get("next_stage") == "eval":       d["next_stage"] = "commit";        changed = True
    if d.get("stage") == "eval_complete":   d["stage"] = "check_complete";     changed = True
    # ADR 0012: a run state written before the run id; its step count starts here
    if "run_id" not in d:
        import uuid
        d["run_id"] = uuid.uuid4().hex[:16];  changed = True
    if not isinstance(d.get("step"), int):
        d["step"] = 0;                        changed = True
    if not changed:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)                  # atomic: a truncated migration would LOSE state


def state_next(argv):
    import json, os, sys
    p, nxt, ts = argv[1:4]
    seq = argv[4:]
    try:
        d = json.load(open(p))
        if not isinstance(d, dict):
            d = {}
    except Exception:
        d = {}
    same = d.get('next_stage') == nxt
    if not same:
        cur = d.get('next_stage')
        if nxt in seq and cur in seq and seq.index(nxt) < seq.index(cur):
            # Going back: the bookkeeping stage (the last stage left, which guards/verify-tests-ran.sh reads) is the one
            # before the stage the run is at again, so a run sent back from Check no longer reads check_complete.
            i = seq.index(nxt)
            d['stage'] = (seq[i - 1] + '_complete') if i else 'started'
            d.pop('end_report', None)   # a run sent back from Commit shows its report again when it gets there
        d['next_stage'] = nxt
        d.pop('parked', None)   # a park ends when the run moves on
        # a small change belongs to the stage it was made at: a window open there, or the steps it still owed, end with it
        d.pop('adhoc', None)
        d.pop('adhoc_done', None)
        try:
            d['step'] = int(d.get('step') or 0) + 1
        except (TypeError, ValueError):
            d['step'] = 1
    d['updated'] = ts
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, p)
    print('same' if same else 'moved')


def redo_from(argv):
    import json, os, sys
    gates_p, over_p, redone_p, to, ts = argv[1:6]
    seq = argv[6:]
    if to not in seq:
        sys.exit(0)
    redo = set(seq[seq.index(to):])

    def load(p, default):
        try:
            d = json.load(open(p))
            return d if isinstance(d, type(default)) else default
        except Exception:
            return default

    def save(p, d):
        tmp = '%s.tmp.%d' % (p, os.getpid())
        with open(tmp, 'w') as f:
            json.dump(d, f, indent=2)
            f.write('\n')
        os.replace(tmp, p)

    gates = load(gates_p, {})
    if any(k in gates for k in redo):
        save(gates_p, {k: v for k, v in gates.items() if k not in redo})
    over = load(over_p, [])
    keep = [o for o in over if not (isinstance(o, dict) and o.get('stage') in redo)]
    gone = [o for o in over if isinstance(o, dict) and o.get('stage') in redo]
    if gone:
        old = load(redone_p, [])
        save(redone_p, old + [dict(o, redone_at=ts, redone_from=to) for o in gone])
        save(over_p, keep)


def archive_ledger(argv):
    import json, sys
    gates_f, overrides_f, out_f, ts, grouped, usage = argv[1:7]
    pairs = argv[7:]
    def load(p, default):
        try:
            return json.load(open(p))
        except Exception:
            return default
    gates = load(gates_f, {})
    overrides = load(overrides_f, [])
    evidence = {}
    for stage, ledger in sorted(zip(pairs[0::2], pairs[1::2])):
        rows = load(ledger, [])
        if rows:
            evidence[stage] = {'rows': len(rows),
                               'labels': {l: sum(1 for e in rows if e.get('label') == l)
                                          for l in sorted({e.get('label') for e in rows if e.get('label')})}}
    doc = {'gates': gates, 'overrides': overrides, 'evidence': evidence, 'archived': ts}
    if grouped:
        doc['grouped'] = json.loads(grouped)
    if usage:
        doc['usage'] = json.loads(usage)
    # The same record but for its times (state clear after the commit archives again): the committed file stays as it is,
    # so the commit does not leave the spec folder changed.
    def bare(o):
        if isinstance(o, dict):
            return {k: bare(v) for k, v in o.items() if k not in ('archived', 'ts')}
        if isinstance(o, list):
            return [bare(v) for v in o]
        return o
    if bare(load(out_f, None)) != bare(doc):
        with open(out_f, 'w') as fh:
            json.dump(doc, fh, indent=2)
            fh.write('\n')


def state_redo(argv):
    import json, os, sys
    p, stage, reason, ts, enter = argv[1:6]
    d = json.load(open(p))
    if enter:
        d['enter'] = stage
    d['redo'] = {'stage': stage, 'reason': reason, 'ts': ts}
    # the stage runs again from the start: a small change made at it, and the steps it still owed, end here
    d.pop('adhoc', None)
    d.pop('adhoc_done', None)
    if stage == 'commit':
        d.pop('end_report', None)   # the commit gate runs again, and the report is shown again after it
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2); f.write('\n')
    os.replace(tmp, p)


def review_code(argv):
    import hashlib, json, os, subprocess, sys
    mode, state = argv[1:3]
    def git(*a):
        r = subprocess.run(['git', '-c', 'core.quotePath=false', '-c', 'status.renames=false'] + list(a), capture_output=True)
        return r.stdout.decode('utf-8', 'replace') if r.returncode == 0 else ''
    top = git('rev-parse', '--show-toplevel').strip()
    pre = git('rev-parse', '--show-prefix').strip()
    def mine(path):
        rel = path[len(pre):] if pre and path.startswith(pre) else path
        return None if rel.startswith(('.temper/', '.claude/')) or (pre and not path.startswith(pre)) else rel
    def snap():
        files = {}
        for f in git('status', '--porcelain=v1', '-z', '-uno', '--', '.').split('\0'):
            if len(f) < 4:
                continue
            rel = mine(f[3:])
            if rel is None:
                continue
            try:
                files[rel] = hashlib.sha256(open(os.path.join(top, f[3:]), 'rb').read()).hexdigest()
            except OSError:
                files[rel] = 'DELETED'
        return {'head': git('rev-parse', 'HEAD').strip(), 'files': files}
    try:
        d = json.load(open(state))
    except Exception:
        sys.exit(0)
    if mode == 'save':
        d['review_snapshot'] = snap()
        tmp = '%s.tmp.%d' % (state, os.getpid())
        with open(tmp, 'w') as f:
            json.dump(d, f, indent=2); f.write('\n')
        os.replace(tmp, state)
        sys.exit(0)
    old = d.get('review_snapshot')
    if not isinstance(old, dict):
        print('NONE'); sys.exit(0)
    cur = snap()
    a, b = old.get('files') or {}, cur['files']
    changed = {k for k in b if b[k] != a.get(k)} | {k for k in a if k not in b}
    if old.get('head') and cur['head'] and old.get('head') != cur['head']:
        changed |= {r for r in (mine(x) for x in git('diff', '--name-only', '--no-renames', old['head'], cur['head'], '--', '.').split('\n') if x) if r}
    print(', '.join(sorted(changed)[:5]))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('migrate_legacy', migrate_legacy),
    ('state_next', state_next),
    ('redo_from', redo_from),
    ('archive_ledger', archive_ledger),
    ('state_redo', state_redo),
    ('review_code', review_code),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
