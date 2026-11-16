#!/usr/bin/env python3
"""json_ops.py: the JSON helpers of the temper CLI: read a file, a dotted path of it, set one, append a row.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/json_ops.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def get_path(argv):
    import json, sys
    path, default = argv[2], argv[3]
    try:
        d = json.load(open(argv[1]))
    except Exception:
        print(default); sys.exit(0)
    cur = d
    for k in path.split('.'):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            print(default); sys.exit(0)
    if isinstance(cur, (dict, list)):
        print(json.dumps(cur))
    elif isinstance(cur, bool):
        print('true' if cur else 'false')  # bash compares lowercase — never emit Python's True/False
    else:
        print(cur if cur is not None else default)


def set_path(argv):
    import json, os, sys
    path, value, default = argv[2], argv[3], argv[4]
    try:
        d = json.load(open(argv[1]))
    except Exception:
        d = json.loads(default)
    # auto-typing: true/false/int/float pass through, else string
    if value in ('true', 'false'):
        v = (value == 'true')
    else:
        try:
            v = int(value)
        except ValueError:
            try:
                v = float(value)
            except ValueError:
                v = value
    cur = d
    keys = path.split('.')
    for k in keys[:-1]:
        cur = cur.setdefault(k, {})
    cur[keys[-1]] = v
    tmp = '%s.tmp.%d' % (argv[1], os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, argv[1])


WORDS = {n.replace("_", "-"): f for n, f in (
    ('get_path', get_path),
    ('set_path', set_path),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
