#!/usr/bin/env bash
# make-helpers-5.sh: prints case-helpers-5.sh, the helper functions and constants of temper-cases-5.sh, so that
# temper-cases-6.sh runs on its own and the parallel runner runs 5 and 6 side by side (9.8.5).
#   bash scripts/selftest/make-helpers-5.sh > scripts/selftest/case-helpers-5.sh
# A case of temper-cases-31.sh fails when the committed file differs from what this prints.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 -I - "$HERE/temper-cases-5.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split('\n')
consts = ('ST_WT', 'T1W', 'SG_RUN', 'OT', 'OF', 'TB', 'TPL')
out, i = [], 0
while i < len(src):
    l = src[i]
    if re.match(r'^(%s)=' % '|'.join(consts), l) and '$(' not in l:
        out.append(l)
    elif re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{', l):
        if l.rstrip().endswith('}') and l.count('{') <= l.count('}'):
            out.append(l)
        else:
            out.append(l)
            i += 1
            while i < len(src) and src[i] != '}':
                out.append(src[i])
                i += 1
            out.append('}')
    i += 1
print("# case-helpers-5.sh: the helper functions and constants of temper-cases-5.sh, so temper-cases-6.sh runs on its own")
print("# (9.8.5). Made by make-helpers-5.sh; do not edit by hand. temper-cases-6.sh sources it when the helpers are not defined.")
print('\n'.join(out))
PY
