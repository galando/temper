#!/usr/bin/env python3
"""state_ops.py: the run state of the temper CLI: init, advance, the stage it is at, redo, the ledger it archives.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/state_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


SAVED_BY = "9.8.5"   # the version that wrote the run state (state init); a state with none was saved by an older Temper


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
    # WP11: a run armed by 9.8.4 or by an earlier 9.8.5 was approved for Build alone: it asks at every stage
    if d.get("run_mode") == "autonomous" and not d.get("unattended_from"):
        d["run_mode"] = "interactive";        changed = True
    # WP11 (row D60): a run saved by an older Temper (no saved_by). Saved after its Review, its completion row names no
    # file Review read (WP18), so its Review verdict is no verdict of this version: the verdict goes, and Review runs once
    # more. The stamp is written once, so this happens once.
    if d.get("saved_by") != SAVED_BY:
        if "saved_by" not in d and d.get("next_stage") == "review":
            top = os.path.dirname(p) or "."
            gp, lp = os.path.join(top, "gates.json"), os.path.join(top, "evidence", "review.json")
            try:
                gates = json.load(open(gp))
            except Exception:
                gates = {}
            try:
                rows = json.load(open(lp))
            except Exception:
                rows = []
            named = any(isinstance(r, dict) and r.get("read") for r in rows if isinstance(rows, list))
            if isinstance(gates, dict) and "review" in gates and not named:
                gates.pop("review", None)
                fd, tmp = tempfile.mkstemp(dir=top)
                with os.fdopen(fd, "w") as f:
                    json.dump(gates, f, indent=2); f.write("\n")
                os.replace(tmp, gp)
        if "saved_by" not in d:
            _bind_saved(p, d)
        d["saved_by"] = SAVED_BY;            changed = True
    if not changed:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)                  # atomic: a truncated migration would LOSE state


def _bind_saved(p, d):
    """WP32: a run saved by 9.8.4 or by the base, taken up once. Its plan_hash is the digest those versions computed;
    where the plan holds what this version binds besides (a second Integration line), the saved digest of the plan as
    it is now moves to this version's digest, so the approval still binds the plan it approved and only a later change
    fails the gates."""
    import json, os, tempfile
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import approval
    import tasks_md
    h, spec = d.get("plan_hash"), d.get("spec_path")
    if not h or not isinstance(spec, str) or not spec:
        return
    root = os.path.dirname(os.path.dirname(os.path.abspath(p)))
    tasks = os.path.join(spec if os.path.isabs(spec) else os.path.join(root, spec), "tasks.md")
    if not os.path.isfile(tasks):
        return
    m = tasks_md.parse(tasks)
    new = approval.plan_digest(m)
    if not new or new == h or approval.plan_digest(m, legacy=True) != h:
        return
    d["plan_hash"] = new
    gp = os.path.join(os.path.dirname(p) or ".", "groups.json")
    try:
        g = json.load(open(gp))
    except Exception:
        return
    if isinstance(g, dict) and g.get("plan_hash") == h:
        g["plan_hash"] = new
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(gp) or ".")
        with os.fdopen(fd, "w") as f:
            json.dump(g, f, indent=2); f.write("\n")
        os.replace(tmp, gp)


def may_start(argv):
    """WP11 (ADR 0019 decision 3): whether `state set run_mode autonomous` may start the unattended run. Only at the
    approval: the run is at Plan or Design, that stage's gate is PASS and not skipped (or at RCA in a fix run, WP17),
    and run.default allows it. Prints the reason and exits 1 when it may not."""
    import json, sys
    def load(p, default):
        try:
            d = json.load(open(p))
            return d if isinstance(d, type(default)) else default
        except Exception:
            return default
    state, gates, over = load(argv[1], {}), load(argv[2], {}), load(argv[3], [])
    default, enabled = argv[4].strip().lower(), argv[5].strip().lower()
    stage = state.get("next_stage") or ""
    g = gates.get(stage) if isinstance(gates.get(stage), dict) else {}
    if state.get("command") == "fix" and stage == "rca":
        g = {"verdict": "PASS"}   # WP17: the root cause question is a fix run's approval; RCA has no gate
    if default == "never-unattended":
        why = "run.default is never-unattended: this project's runs ask at every stage"
    elif stage not in ("plan", "design", "rca"):
        why = "the run goes on by itself only from the approval (the person's option at Plan or Design); the run is at %s" % (
            stage or "no stage")
    elif g.get("verdict") != "PASS" or any(isinstance(o, dict) and o.get("stage") == stage for o in over):
        why = "the run goes on by itself only from an approval whose check passed; the %s check did not pass" % stage
    else:
        return
    print(why)
    sys.exit(1)


def park_end(argv):
    """WP11: the person's answer ends the stop of the stage (`temper park --end`): the mark `parked` goes."""
    import json, os
    p = argv[1]
    try:
        d = json.load(open(p))
    except Exception:
        return
    if not isinstance(d, dict) or "parked" not in d:
        return
    d.pop("parked", None)
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, p)


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
        d.pop('repair', None)   # WP24: a repair belongs to the stage it opened at, and so does what it asks
        d.pop('repair_stop', None)
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
    import os
    failures = load(os.path.join(os.path.dirname(os.path.abspath(gates_f)), 'evidence', 'failures.json'), [])
    if failures:   # WP23: the failure records of the run (scripts/failure.py)
        doc['failures'] = failures
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
    p, stage, reason, ts = argv[1:5]
    d = json.load(open(p))
    d['redo'] = {'stage': stage, 'reason': reason, 'ts': ts}
    # the stage runs again from the start: a small change made at it, and the steps it still owed, end here
    d.pop('adhoc', None)
    d.pop('adhoc_done', None)
    d.pop('repair', None)
    d.pop('repair_stop', None)
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


def state_init(argv):
    import json, os, sys, uuid
    d = {
        'stage': 'started',
        'spec': argv[1],
        'spec_path': f'.temper/specs/{argv[1]}',
        'branch': argv[2],
        'command': argv[3],
        'next_stage': 'intent' if argv[3] == 'temper' else 'rca',
        'run_mode': 'interactive',
        'artifacts': ['intent.md', 'tasks.md'] if argv[3] == 'temper' else ['rca.md'],
        'updated': argv[4],
        # ADR 0012: the run and the step a decision of the person belongs to. step counts every change of next_stage.
        'run_id': uuid.uuid4().hex[:16],
        'step': 0,
        'started': argv[4],
        'saved_by': SAVED_BY,   # WP11: a state with none was saved by an older Temper (migrate_legacy)
    }
    # ADR 0013: the feature as the person gave it (the Intent brief's input)
    if argv[6]: d['feature'] = argv[6]
    json.dump(d, open(argv[5], 'w'), indent=2)
    # WP17: a new run spends the record of a trivial request (scripts/trivial.py): the commit hook no longer holds it
    try:
        os.remove(os.path.join(os.path.dirname(argv[5]), 'trivial.json'))
    except OSError:
        pass


def _amendments_close(p):
    """WP25: an approval starts the list of the plan since the approval again: the amendments and patches of the plan
    before it go to .temper/archive/ (the commit card lists .temper/evidence/amendments.json whole)."""
    import os, time
    src = os.path.join(os.path.dirname(os.path.abspath(p)), 'evidence', 'amendments.json')
    if os.path.isfile(src):
        dst = os.path.join(os.path.dirname(os.path.abspath(p)), 'archive')
        os.makedirs(dst, exist_ok=True)
        os.replace(src, os.path.join(dst, 'amendments-%s.json' % time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())))


def approve_plan(argv):
    import json, os, sys
    p = argv[1]
    _amendments_close(p)
    d = json.load(open(p))
    try:
        files = json.loads(argv[2])
    except ValueError:
        files = []
    d['approved_files'] = files if isinstance(files, list) else []
    if argv[3]:
        d['plan_hash'] = argv[3]
    else:
        d.pop('plan_hash', None)
    # WP12: the digest of intent.md as approved, or absent (scripts/approval.py bound), beside the plan's
    if len(argv) > 4 and argv[4]:
        d['intent_hash'] = argv[4]
    else:
        d.pop('intent_hash', None)
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, p)


def approve_design_tasks(argv):
    import json, os, sys
    p = argv[1]
    d = json.load(open(p))
    try:
        files = json.loads(argv[2])
    except ValueError:
        files = []
    if isinstance(files, list):
        d['approved_files'] = files
    d['plan_hash'] = argv[3]
    d['tasks_changed_by_design'] = True
    _amendments_close(p)
    tmp = '%s.tmp.%d' % (p, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, p)


def grouped_models(argv):
    import json, sys
    d = json.loads(argv[1]); d['task_model'] = argv[2]; d['escalation_model'] = argv[3]
    print(json.dumps(d))


def pending_done(argv):
    import json, os, sys
    try:
        if json.load(open(argv[1])).get('stage') == argv[2]:
            os.remove(argv[1])
    except Exception:
        pass


def override_entry(argv):
    import json, sys
    print(json.dumps({'stage': argv[1], 'reason': argv[2], 'by': argv[3], 'ts': argv[4]}))


def adhoc_review(argv):
    import json, sys
    sys.exit(0 if 'review' in (json.load(open(argv[1])).get('adhoc_done') or {}).get('steps', []) else 1)


WORDS = {n.replace("_", "-"): f for n, f in (
    ('migrate_legacy', migrate_legacy),
    ('may_start', may_start),
    ('park_end', park_end),
    ('state_next', state_next),
    ('redo_from', redo_from),
    ('archive_ledger', archive_ledger),
    ('state_redo', state_redo),
    ('review_code', review_code),
    ('state_init', state_init),
    ('approve_plan', approve_plan),
    ('approve_design_tasks', approve_design_tasks),
    ('grouped_models', grouped_models),
    ('pending_done', pending_done),
    ('override_entry', override_entry),
    ('adhoc_review', adhoc_review),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
