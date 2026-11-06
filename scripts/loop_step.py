"""loop_step.py LOOPS_FILE FROM TO REASON MAX TS [LEDGER STATE MUTATION_THRESHOLD]: one step back of `temper state loop`.

It counts the step against the pair's budget and keeps what the stage left open (Review's findings, Check's failed runs
with their output). Moved out of scripts/temper so it stays under the plugin directory's 256 KiB file limit.
Standard library only.
"""
import json, sys
f, frm, to, reason, max_per_type, ts = sys.argv[1:7]
max_per_type = int(max_per_type)
d = json.load(open(f))
active = d.get('active_loops', [])
loop = next((l for l in active if l['from_stage'] == frm and l['to_stage'] == to), None)
if loop is None:
    loop = {'id': f'loop-{len(active) + len(d.get("history", [])) + 1}', 'from_stage': frm,
             'to_stage': to, 'reason': reason, 'iteration': 0, 'max_iterations': max_per_type,
             'started': ts}
    active.append(loop)
if loop['iteration'] >= max_per_type:
    print('BLOCKED: max iterations (%d) reached for %s->%s' % (max_per_type, frm, to))
    d['active_loops'] = active
    json.dump(d, open(f, 'w'), indent=2)
    sys.exit(1)
loop['iteration'] += 1
loop['reason'] = reason or loop['reason']
loop['at'] = ts      # each step writes when it ran: readers order by at, so the latest reason is the one a fix pass reads
try:                 # an older Run Build again no longer speaks for the stage
    st = json.load(open(sys.argv[8]))
    if st.pop('redo', None) is not None:
        json.dump(st, open(sys.argv[8], 'w'), indent=2)
except Exception:
    pass
# What the stage left open goes with the loop, since the loop clears that stage's ledger: Review's open findings, Check's
# failed runs. The fix pass reads them (temper next names them in its prompt).
try:
    rows = json.load(open(sys.argv[7])) if len(sys.argv) > 7 and sys.argv[7] else []
except Exception:
    rows = []
def open_row(e):
    if not isinstance(e, dict) or e.get('resolved') or e.get('accepted'):
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
        return frm == 'check' and str(e.get('claim')) == 'mutation score' and float(e.get('value')) < float(sys.argv[9])
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
print('OK: loop %s->%s iteration %d/%d' % (frm, to, loop['iteration'], max_per_type))
