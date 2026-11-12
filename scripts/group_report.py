"""group_report.py json GROUPS_FILE REVIEW_LEDGER | group_report.py text REPORT_JSON: the grouped Build measurement report
(9.7.0, AC-12). `json` reads groups.json and the review ledger and prints the report as JSON (`state archive` embeds it in
gate-ledger.json); `text` prints that JSON for a person (`temper group report`). Called by _group_report_json and
cmd_group_report in scripts/temper; it lived inside the CLI until 9.8.4, which moved it here to keep the CLI under the
plugin directory's 256 KiB limit for a file. Standard library only.
"""
import calendar, json, sys, time


def report_json(groups_file, review_file):
    def load(p, default):
        try:
            return json.load(open(p))
        except Exception:
            return default
    run = load(groups_file, {})
    rev = load(review_file, [])
    def secs(s):
        try:
            return calendar.timegm(time.strptime(s, '%Y-%m-%dT%H:%M:%SZ'))
        except Exception:
            return None
    spent, attempts, esc = {}, {}, 0
    for n, t in sorted((run.get('tasks') or {}).items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
        rows = list(t.get('attempts_prior') or []) + list(t.get('attempts') or [])
        attempts[n] = rows
        for r in rows:
            if isinstance(r.get('ms'), int):
                spent[r.get('model') or 'unknown'] = spent.get(r.get('model') or 'unknown', 0) + r['ms']
            if isinstance(r.get('n'), int) and r['n'] >= 3:
                esc += 1
    groups = run.get('groups') or {}
    wall, starts, ends = {}, [], []
    for g, v in sorted(groups.items()):
        a, b = secs(v.get('started_at') or ''), secs(v.get('finished_at') or '')
        if a is not None:
            starts.append(a)
        if a is not None and b is not None and (v.get('gate') or {}).get('verdict') == 'PASS':
            wall[g] = (b - a) * 1000
            ends.append(b)
    total = (max(ends) - min(starts)) * 1000 if starts and ends else 0
    openf = sum(1 for e in rev if isinstance(e, dict) and e.get('severity') and not e.get('resolved') and not e.get('accepted'))
    task_groups = {n: (t or {}).get('group') for n, t in (run.get('tasks') or {}).items() if (t or {}).get('group')}
    print(json.dumps({'ms_by_model': spent, 'attempts': attempts, 'escalations': esc, 'task_groups': task_groups,
                      'parked': sorted(g for g, v in groups.items() if v.get('status') == 'parked'),
                      'wall_ms_by_group': wall, 'build_wall_ms': total, 'review_findings_open': openf},
                     sort_keys=True))


def report_text(j):
    r = json.loads(j)
    def dur(ms):
        s = int(ms or 0) // 1000
        return '%d min %d s' % (s // 60, s % 60) if s >= 60 else '%d s' % s
    tasks = sorted(r['attempts'].items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0)
    groups = r.get('task_groups') or {}
    total = sum(r['ms_by_model'].values())
    print('Grouped Build report')
    print('  Tasks: %d, in %d group(s). Build time: %s.' % (len(tasks), len(r['wall_ms_by_group']) or len(set(groups.values())), dur(r['build_wall_ms'])))
    print('  Time the task agents ran: %s%s' % (dur(total), (' (' + ', '.join('%s %s' % (m, dur(n)) for m, n in sorted(r['ms_by_model'].items())) + ')') if r['ms_by_model'] else ''))
    for g, ms in sorted(r['wall_ms_by_group'].items()):
        print('  Group %s: passed its group gate after %s.' % (g, dur(ms)))
    print('  Groups stopped for you (parked): %s' % (', '.join(r['parked']) or 'none'))
    print('  Tasks that moved to the stronger model after two failed attempts: %d' % r['escalations'])
    print('  Open review findings: %d' % r['review_findings_open'])
    for n, rows in tasks:
        if not rows:
            print('  Task %s: not run yet' % n)
            continue
        last = rows[-1]
        head = 'passed' if last.get('outcome') == 'PASS' else 'failed'
        print('  Task %s: %s after %d attempt(s)' % (n, head, len(rows)))
        for i, a in enumerate(rows, 1):
            what = 'passed' if a.get('outcome') == 'PASS' else 'failed'
            model = a.get('model') or 'no model given to task gate'
            extra = []
            if isinstance(a.get('ms'), int):
                extra.append(dur(a['ms']))
            line = '    attempt %d: %s (%s%s)' % (i, what, model, ''.join(', ' + x for x in extra))
            reason = (a.get('reason') or '').strip().split('\n')[0]
            if what == 'failed' and reason:
                line += ': ' + (reason if len(reason) <= 160 else reason[:157] + '...')
            print(line)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'json':
        report_json(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == 'text':
        report_text(sys.argv[2])
    else:
        print('usage: group_report.py json GROUPS_FILE REVIEW_LEDGER | text REPORT_JSON', file=sys.stderr)
        sys.exit(2)
