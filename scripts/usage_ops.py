"""usage_ops.py: the usage ledger of a run (.temper/usage.json), for scripts/temper.

  python3 usage_ops.py json USAGE.json                          the summary the report reads: rows and time by stage, by model
                                                                and in all, one JSON line (nothing when no row was recorded)
  python3 usage_ops.py fill USAGE.json STAGE MS [TASK] [MODEL]  9.8.4 (`temper usage add ... --fill`): the time of an agent the
                                                                tool ran in the background, from its completion notice, put into
                                                                the newest row of that stage (and task, and model) recorded with
                                                                no time; exit 1, changing nothing, when there is none

An agent run in the background returns its report before its completion notice, so its `after` calls recorded its time as
none and the report showed "-" for Design and Build. The caller holds the run's lock for fill. Standard library only.
"""
import json, os, sys


def summary(path):
    try:
        rows = json.load(open(path))
    except Exception:
        rows = []
    rows = [r for r in rows if isinstance(r, dict)] if isinstance(rows, list) else []
    if not rows:
        return 0
    def add(acc, r):
        acc['rows'] += 1
        if isinstance(r.get('ms'), int):
            acc['ms'] = (acc['ms'] or 0) + r['ms']
    fresh = lambda: {'rows': 0, 'ms': None}
    by_stage, by_model, total = {}, {}, fresh()
    for r in rows:
        st = by_stage.setdefault(r.get('stage') or 'unknown', fresh())
        add(st, r)
        # the models a stage's rows name (what the orchestrator launched it on)
        if r.get('model') and r.get('model') not in st.setdefault('models', []):
            st['models'].append(r.get('model'))
        add(by_model.setdefault(r.get('model') or 'unknown', fresh()), r)
        add(total, r)
    print(json.dumps({'by_stage': by_stage, 'by_model': by_model, 'total': total}, sort_keys=True))


def fill(path, stage, ms, task="", model=""):
    try:
        rows = json.load(open(path))
    except Exception:
        return 1
    if not isinstance(rows, list):
        return 1
    for r in reversed(rows):
        if (isinstance(r, dict) and r.get("stage") == stage and r.get("ms") is None and str(r.get("task") or "") == str(task or "")
                and (not model or not r.get("model") or r.get("model") == model)):
            r["ms"] = int(ms)
            tmp = "%s.tmp.%d" % (path, os.getpid())
            with open(tmp, "w") as fh:
                json.dump(rows, fh, indent=2)
                fh.write("\n")
            os.replace(tmp, path)
            return 0
    return 1


def main(argv):
    if len(argv) == 3 and argv[1] == "json":
        return summary(argv[2]) or 0
    if 5 <= len(argv) <= 7 and argv[1] == "fill" and argv[4].isdigit():
        return fill(*argv[2:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
