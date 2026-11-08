"""loop_step.py LOOPS_FILE FROM TO REASON CONFIG TS [LEDGER STATE MUTATION_THRESHOLD]: one step back of `temper state loop`.

It counts the step against the pair's budget and keeps what the stage left open (Review's findings, Check's failed runs
with their output). CONFIG is a JSON object of the config values the budget reads (loops.max-per-type, fix.max-loops; a key
that is not set is left out). Moved out of scripts/temper so it stays under the plugin directory's 256 KiB file limit.
Standard library only; importing it runs nothing.

The budget of a step back is one rule, `budget(frm, to, cfg)`, so the CLI that counts the steps and the flow that offers
them never disagree. A pair's loop stays in active_loops for the whole run: the budget is per run (a step back from Build
to Plan happens once per run, reference/orchestrator-patterns.md), so a loop never moves to history before the run ends.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from findings import finding_state  # noqa: E402


def budget(frm, to, cfg):
    """How many steps back the run may take from FRM to TO. cfg(key, default) -> str reads the config. Build to Plan is
    once per run; Check to Build or Fix takes fix.max-loops when it is set; every other pair takes loops.max-per-type
    (default 2). A value that is not a whole number counts as the default 2."""
    if frm == "build" and to == "plan":
        return 1
    mx = cfg("loops.max-per-type", "2")
    if frm == "check" and to in ("build", "fix"):
        mx = cfg("fix.max-loops", mx)
    try:
        return int(mx)
    except (TypeError, ValueError):
        return 2


def step(f, frm, to, reason, cfg, ts, ledger="", state="", mutation_threshold="70"):
    """One step back; returns (exit code, the line to print)."""
    max_per_type = budget(frm, to, cfg)
    d = json.load(open(f))
    active = d.get('active_loops', [])
    loop = next((l for l in active if l['from_stage'] == frm and l['to_stage'] == to), None)
    if loop is None:
        loop = {'id': f'loop-{len(active) + len(d.get("history", [])) + 1}', 'from_stage': frm,
                'to_stage': to, 'reason': reason, 'iteration': 0, 'max_iterations': max_per_type,
                'started': ts}
        active.append(loop)
    loop['max_iterations'] = max_per_type   # the budget as it is now (the config may have changed since the first step)
    if loop['iteration'] >= max_per_type:
        d['active_loops'] = active
        json.dump(d, open(f, 'w'), indent=2)
        return 1, 'BLOCKED: max iterations (%d) reached for %s->%s' % (max_per_type, frm, to)
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
        return isinstance(e.get('exit_code'), int) and e.get('exit_code') != 0

    def out_of(e):
        # 9.8.0: a failed Check run goes back with the tail of its output (the failing test and its assertion), so the fix pass
        # sees what failed, not only the name of the run. The mutation score row goes with its surviving mutants.
        if frm != 'check':
            return ''
        out = ' '.join(str(e.get('output') or '').split())
        return (': ' + out[-600:]) if out else ''

    def low_mutation(e):
        try:
            return frm == 'check' and str(e.get('claim')) == 'mutation score' and float(e.get('value')) < float(mutation_threshold)
        except (TypeError, ValueError):
            return False
    left = [('[%s] ' % e['severity'] if e.get('severity') else '') + str(e.get('claim', ''))[:300] + out_of(e) for e in rows
            if open_row(e) or low_mutation(e)]
    if left:
        loop['findings'] = left[:20]
    else:
        loop.pop('findings', None)
    d['active_loops'] = active
    json.dump(d, open(f, 'w'), indent=2)
    return 0, 'OK: loop %s->%s iteration %d/%d' % (frm, to, loop['iteration'], max_per_type)


def main(argv):
    f, frm, to, reason, config, ts = argv[1:7]
    try:
        values = json.loads(config)
    except ValueError:
        values = {}
    if not isinstance(values, dict):
        values = {}

    def cfg(key, default=""):
        v = values.get(key)
        return default if v is None or v == "" else str(v)
    rc, line = step(f, frm, to, reason, cfg, ts, *argv[7:10])
    print(line)
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv))
