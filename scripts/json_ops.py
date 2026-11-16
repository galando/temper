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


def read_valid(argv):
    import json, sys
    try:
        json.load(open(argv[1]))
        print(open(argv[1]).read())
    except Exception:
        print(argv[2])


def append_row(argv):
    import json, os, sys
    try:
        d = json.load(open(argv[1]))
        if not isinstance(d, list):
            d = []
    except Exception:
        d = []
    d.append(json.loads(argv[2]))
    tmp = '%s.tmp.%d' % (argv[1], os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, argv[1])


def same_file(argv):
    import os, sys; sys.exit(0 if os.path.realpath(argv[1]) == os.path.realpath(argv[2]) else 1)


def req(argv):
    import json, sys
    print(json.dumps({'name': argv[1], 'pass': argv[2] == '1', 'detail': argv[3]}))


def jget(argv):
    import json, sys
    v = json.load(sys.stdin).get(argv[1], '')
    s = json.dumps(v) if isinstance(v, (list, dict)) else ('' if v is None else str(v))
    sys.stdout.buffer.write((s + '\n').encode('utf-8', 'surrogateescape'))


WORDS = {n.replace("_", "-"): f for n, f in (
    ('get_path', get_path),
    ('set_path', set_path),
    ('read_valid', read_valid),
    ('append_row', append_row),
    ('same_file', same_file),
    ('req', req),
    ('jget', jget),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
