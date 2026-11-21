"""loop_step.py LOOPS_FILE FROM TO REASON TS [LEDGER STATE]: one step back of `temper state loop`.

It keeps what the stage left open (Review's findings, Check's failed runs with their output). It counts nothing and
refuses nothing: a step back from a failed gate spent its repeat of the run's budget in the CLI's dispatcher before this
ran (scripts/budget.py, ADR 0019 decision 1), and max_iterations is the limit of that key, so the view keeps its n/m.
A pair's loop stays in active_loops for the whole run. Moved out of scripts/temper so it stays under the plugin
directory's 256 KiB file limit. Standard library only; importing it runs nothing.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from findings import finding_state  # noqa: E402


def limit(frm):
    """The limit of the key gate:FRM (budget.py); 2 when the record cannot be read."""
    try:
        import budget
        return budget.room("gate:%s" % frm, budget.Facts())["limit"]
    except Exception:
        return 2


def group_failures(loops_file):
    """9.8.4: the groups whose check failed, first in what a step back from Build carries: the gate's reason, how many times
    it failed, and the first FAIL lines of its Validate output (groups.json, beside the loops file, before the step back
    archives it)."""
    try:
        d = json.load(open(os.path.join(os.path.dirname(os.path.abspath(loops_file)), 'groups.json')))
    except Exception:
        return []
    out = []
    for gid, g in sorted((d.get('groups') or {}).items()):
        gate = (g or {}).get('gate') or {}
        if gate.get('verdict') != 'FAIL':
            continue
        fails = int(g.get('fails') or 1)
        lines = [' '.join(str(x).split())[:200] for x in gate.get('fail_lines') or []][:5]
        out.append('group %s check failed%s: %s%s' % (gid, ' %d times' % fails if fails > 1 else '',
                                                      ' '.join(str(gate.get('reason', '')).split())[:400],
                                                      ('; what failed: ' + ' | '.join(lines)) if lines else ''))
    return out


def step(f, frm, to, reason, ts, ledger="", state=""):
    """One step back; returns (exit code, the line to print)."""
    max_per_type = limit(frm)
    d = json.load(open(f))
    active = d.get('active_loops', [])
    loop = next((l for l in active if l['from_stage'] == frm and l['to_stage'] == to), None)
    if loop is None:
        loop = {'id': f'loop-{len(active) + len(d.get("history", [])) + 1}', 'from_stage': frm,
                'to_stage': to, 'reason': reason, 'iteration': 0, 'max_iterations': max_per_type,
                'started': ts}
        active.append(loop)
    loop['max_iterations'] = max_per_type   # the limit of the key as it is now (a grant raises it)
    loop['iteration'] += 1
    loop['reason'] = reason or loop['reason']
    loop['at'] = ts      # each step writes when it ran: readers order by at, so the latest reason is the one a fix pass reads
    try:                 # an older Run Build again no longer speaks for the stage
        st = json.load(open(state))
        if st.pop('redo', None) is not None:
            json.dump(st, open(state, 'w'), indent=2)
    except Exception:
        pass
    # What the stage left open goes with the loop, since the loop clears that stage's ledger: Review's open findings, Check's
    # failed runs. The fix pass reads them (temper next names them in its prompt).
    try:
        rows = json.load(open(ledger)) if ledger else []
    except Exception:
        rows = []

    def open_row(e):
        if not isinstance(e, dict) or finding_state(e) in ('resolved', 'accepted'):
            return False
        if frm == 'review':
            return bool(e.get('severity'))
        # 9.8.4: Plan's open fresh review findings go with a step back from Plan (they were lost with the cleared ledger)
        if frm == 'plan' and e.get('severity'):
            return True
        # a task's RED run fails by design: it is no finding (a measured loop listed twenty of them and no group failure)
        if frm == 'build' and e.get('phase') in ('red', 'group'):
            return False
        return isinstance(e.get('exit_code'), int) and e.get('exit_code') != 0

    def out_of(e):
        # 9.8.0: a failed Check run goes back with the tail of its output (the failing test and its assertion), so the fix pass
        # sees what failed, not only the name of the run. A failed coverage row goes with its verdict (WP19).
        if frm != 'check':
            return ''
        out = ' '.join(str(e.get('output') or '').split())
        return (': ' + out[-600:]) if out else ''
    # WP23: the failure records of the stage the loop leaves, by id (scripts/failure.py): the text below is a copy of them
    try:
        recs = json.load(open(os.path.join(os.path.dirname(os.path.abspath(f)), 'evidence', 'failures.json')))
        ids = [x['id'] for x in recs if isinstance(x, dict) and x.get('resolved') is None and x.get('stage') == frm and x.get('id')]
    except Exception:
        ids = []
    if ids:
        loop['records'] = ids[-20:]
    else:
        loop.pop('records', None)
    left = group_failures(f) if frm == 'build' else []
    left += [('[%s] ' % e['severity'] if e.get('severity') else '') + str(e.get('claim', ''))[:300] + out_of(e) for e in rows
             if open_row(e)]
    if left:
        loop['findings'] = left[:20]
    else:
        loop.pop('findings', None)
    d['active_loops'] = active
    json.dump(d, open(f, 'w'), indent=2)
    return 0, 'OK: loop %s->%s iteration %d/%d' % (frm, to, loop['iteration'], max_per_type)


def main(argv):
    rc, line = step(*argv[1:6], *argv[6:8])
    print(line)
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv))
