# Case file 83: review 3 of the adversarial review of 9.8.5, rules 5 and 6. Sourced by test-temper.sh; its helpers (fresh,
# gpass, _at, vw) are used here. Each assertion is a reproduction: it failed on the code under review, and the commit
# that added it fixed it.
_repo83() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_g83() { # _g83 <python over g, the Check verdict of gates.json, that sets r>: prints r
  python3 - "$1" <<'PY'
import json, sys
try:
    g = json.load(open('.temper/gates.json')).get('check') or {}
except (OSError, ValueError):
    g = {}
row = lambda n: next((x for x in g.get('requirements') or [] if str(x.get('name', '')).startswith(n)), {})
r = None
exec(sys.argv[1])
print(r)
PY
}

# --- rule 5: the suite the CLI ran failed on this tree; a CLI run of a command an agent chose stands in for it ---
fresh; _repo83; printf 'check:\n  commands:\n    test: "echo FAIL: test_a; exit 1"\n' >> .claude/temper.config
gpass intent plan build review; _at check
"$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_t83_tree="$(_g83 "r = g.get('tree')")"
"$TEMPER" evidence run --stage check --claim 'tests: the suite (run by the CLI)' -- true >/dev/null 2>&1
"$TEMPER" gate check >/dev/null 2>&1
assert_eq "review 3: tests pass is not passed by a run of true when the CLI's run of the configured suite failed on the tree the verdict names" \
  "verdict=FAIL|tests=False|same tree=True" \
  "verdict=$(_g83 "r = g.get('verdict')")|tests=$(_g83 "r = row('tests pass').get('pass')")|same tree=$([[ "$(_g83 "r = g.get('tree')")" == "$_t83_tree" ]] && echo True || echo False)"
