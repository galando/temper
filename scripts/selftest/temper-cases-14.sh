# Release 9.7.6: the fresh review of the plan, checkable contests, a reviewer that did not run, and spec drift.
# Sourced by test-temper.sh after temper-cases-13.sh (helpers: nx, labels, gpass, setup, assert_eq, assert_exit).

_fr_plan() { # a medium plan at the Plan stage whose only failing rows are the fresh review's
  setup
  "$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1
  gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state set complexity medium >/dev/null 2>&1
  cat > .temper/specs/demo/plan.md <<'EOF'
## Context Map
- use: intent.md - the accepted scope
- reviewed: auto - every source is current and on topic

## Blast Radius
- no external consumers

## Cross-Repo Search
- not available: no cross-repo search tool connected
EOF
}
_fr_sha() { python3 -c "import hashlib; print(hashlib.sha256(open('.temper/specs/demo/tasks.md','rb').read()).hexdigest())"; }
_fr_done() { # _fr_done <lens> [instance]
  "$TEMPER" evidence add --stage plan --phase fresh --exit 0 --label PROVEN --claim "fresh review completed: $1 ${2:-A}" \
    --artifact .temper/specs/demo/tasks.md >/dev/null 2>&1
}
_fr_para() { "$TEMPER" evidence add --stage plan --phase fresh --claim "paraphrase: the demo runs twice | a demo is one shell step" \
  --artifact .temper/specs/demo/tasks.md >/dev/null 2>&1; }
_fr_find() { # _fr_find <severity> <claim>
  "$TEMPER" evidence add --stage plan --phase fresh --severity "$1" --claim "$2" --artifact .temper/specs/demo/tasks.md >/dev/null 2>&1
}
_fr_row() { # _fr_row <row name> -> pass|detail of that plan gate row
  "$TEMPER" gate plan >/dev/null 2>&1
  python3 - "$1" <<'PY'
import json, sys
for r in json.load(open('.temper/gates.json'))['plan']['requirements']:
    if r['name'] == sys.argv[1]:
        print('%s|%s' % (r['pass'], r['detail'])); break
else:
    print('absent')
PY
}

# --- 1. The tier decides whether the fresh review applies (plan.fresh-review: auto) ---
setup
assert_exit "fresh review: a simple plan passes the plan gate with no fresh review" 0 "$TEMPER" gate plan
assert_eq "fresh review: a simple plan has no fresh review row" "absent" "$(_fr_row 'fresh review ran')"
_fr_plan
assert_exit "fresh review: a medium plan fails the plan gate until the fresh review ran" 1 "$TEMPER" gate plan
assert_eq "fresh review: the row names every lens as not run" \
  "False|not run: readiness A, zoom-out A, comprehension A; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"
printf 'plan:\n  fresh-review: off\n' >> .claude/temper.config
assert_exit "fresh review: plan.fresh-review off turns it off for a medium plan" 0 "$TEMPER" gate plan
setup; printf 'plan:\n  fresh-review: always\n' >> .claude/temper.config
assert_exit "fresh review: plan.fresh-review always runs it for a simple plan" 1 "$TEMPER" gate plan

# --- 2. The CLI launches the reviewer, once, after the plan agent; the plan passes when every lens recorded its row ---
_fr_plan; "$TEMPER" gate plan >/dev/null 2>&1
assert_eq "fresh review: next launches one reviewer with no context, on the brief's model, with every lens" \
  "work|temper:temper-plan-review|sonnet|1|1" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], a['model'], str(int('Lenses: readiness, zoom-out, comprehension.' in a['prompt'])), str(int(a['before'][0].endswith('state set fresh_review $(_fr_sha)')))])")"
"$TEMPER" state set fresh_review "$(_fr_sha)" >/dev/null 2>&1
_fr_done readiness; _fr_done zoom-out
assert_eq "fresh review: a lens with no completion row is not run, never a lens with no findings" \
  "False|not run: comprehension A; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"
assert_eq "fresh review: a launched reviewer that did not finish is asked about, not launched again" \
  "ask|Run the fresh review again (Recommended)" "$(nx "d['action'] + '|' + d['ask']['question']['options'][0]['label']")"
assert_eq "fresh review: Run the fresh review again clears the launch mark" "1" \
  "$(nx "int(d['ask']['options'][0]['calls'][-1].endswith('state set fresh_review none'))")"
_fr_done comprehension
assert_eq "fresh review: with no paraphrase the paraphrase row fails" "False|no paraphrase recorded for this tasks.md" "$(_fr_row "fresh reader's paraphrase")"
_fr_para
assert_exit "fresh review: every lens and the paraphrase pass the plan gate" 0 "$TEMPER" gate plan
assert_eq "fresh review: the plan question shows the reader's paraphrase" "1" \
  "$(nx "int('A reader with no context took it as: the demo runs twice | a demo is one shell step. Approve the plan' in d['ask']['question']['question'])")"

# --- 3. A blocker fails the gate; Revise the plan runs the Plan agent again with it; an edited tasks.md makes the review stale ---
_fr_find high "[readiness] Task 1: the case names no expected value"; _fr_find low "[comprehension] the word demo is not defined"
assert_eq "fresh review: an open high finding fails the blockers row and names it" \
  "False|1 open: #5 [readiness] Task 1: the case names no expected value" "$(_fr_row 'no open plan blockers')"
assert_eq "fresh review: the plan question offers Revise the plan first, and the accept question" "Revise the plan (Recommended)|Accept a finding|More options|1" \
  "$(nx "'|'.join(o['label'] for o in d['ask']['options']) + '|' + str(int(d['ask']['accept']['options'][0]['calls'][0].endswith(\"evidence accept --stage plan --id 5 --reason '{reason}'\")))")"
"$TEMPER" state redo plan --reason "fresh review" >/dev/null 2>&1
assert_eq "fresh review: after Revise the plan the Plan agent runs with the findings to answer" "temper:temper-plan|1|1" \
  "$(nx "a = d['agents'][0]; a['type'] + '|' + str(int('Fresh review findings to answer' in a['prompt'])) + '|' + str(int('#5 [high] [readiness] Task 1' in a['prompt']))")"
echo "- an expected value" >> .temper/specs/demo/tasks.md
assert_eq "fresh review: an edited tasks.md makes the review stale" \
  "False|tasks.md changed after the fresh review; it runs again on the new text" "$(_fr_row 'fresh review ran')"
assert_eq "fresh review: a finding against the old tasks.md no longer counts" "True|0 open blockers" "$(_fr_row 'no open plan blockers')"
assert_eq "fresh review: the stale review is launched again on the new tasks.md" "temper:temper-plan-review" "$(nx "d['agents'][0]['type']")"

# --- 4. A risk H plan gets two independent reviewers, unless plan.fresh-review-twice is false ---
_fr_plan; "$TEMPER" state set risk H >/dev/null 2>&1
assert_eq "fresh review: a risk H plan needs instance B too" \
  "False|not run: readiness A, zoom-out A, comprehension A, readiness B, zoom-out B, comprehension B; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"
assert_eq "fresh review: next launches A and B in one action, and only the first marks the launch" "2|Instance: A.|Instance: B.|1|0" \
  "$(nx "a = d['agents']; '|'.join([str(len(a)), 'Instance: A.' if 'Instance: A.' in a[0]['prompt'] else '?', 'Instance: B.' if 'Instance: B.' in a[1]['prompt'] else '?', str(len(a[0].get('before', []))), str(len(a[1].get('before', [])))])")"
printf 'plan:\n  fresh-review-twice: false\n' >> .claude/temper.config
assert_eq "fresh review: plan.fresh-review-twice false needs instance A only" \
  "False|not run: readiness A, zoom-out A, comprehension A; a reviewer that recorded no completion row did not review" "$(_fr_row 'fresh review ran')"

# --- 5. A contest must cite something the reviewer could read; an escalation needs a reason; both leave the finding open ---
_fr_plan; mkdir -p src; printf 'alpha() { echo a; }\n' > src/a.sh
_fr_done readiness; _fr_done zoom-out; _fr_done comprehension; _fr_para
_fr_find high "[zoom-out] src/a.sh: a new helper where one exists"
assert_eq "contest: no citation is refused, and the refusal names escalate" "1|1" \
  "$("$TEMPER" evidence contest --stage plan --id 5 --cite '' --reason 'it is intentional' >/dev/null 2>&1; echo $?)|$("$TEMPER" evidence contest --stage plan --id 5 --cite src/nothing.sh --reason x 2>&1 | grep -c 'no file src/nothing.sh.*escalate')"
assert_exit "contest: a path outside the project is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite ../outside.sh --reason x
assert_exit "contest: a line the file does not have is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:9 --reason x
assert_exit "contest: a symbol the file does not hold is refused" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:beta --reason x
assert_exit "contest: a row with no severity is refused" 1 "$TEMPER" evidence contest --stage plan --id 1 --cite src/a.sh --reason x
assert_exit "contest: a citation the reviewer could read is recorded" 0 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh:alpha --reason "alpha is the helper it names"
assert_eq "contest: the finding stays open and the gate names the citation" \
  "False|1 open: #5 [zoom-out] src/a.sh: a new helper where one exists (contested: src/a.sh:alpha)" "$(_fr_row 'no open plan blockers')"
assert_eq "contest: the accept question marks it and offers the citation as the first reason" "[contested] [zoom-out] src/a.sh: a new helper where one exists|Contested with evidence: src/a.sh:alpha" \
  "$(nx "o = d['ask']['accept']['options'][0]; o['description'] + '|' + o['reason_question']['options'][0]['label']")"
assert_exit "escalate: a reason is required" 1 "$TEMPER" evidence escalate --stage plan --id 5 --reason "  "
assert_exit "escalate: with a reason it is recorded" 0 "$TEMPER" evidence escalate --stage plan --id 5 --reason "the team agreed on this in the design meeting"
assert_eq "escalate: the gate names it as the person's to decide" \
  "False|1 open: #5 [zoom-out] src/a.sh: a new helper where one exists (escalated: only the person knows)" "$(_fr_row 'no open plan blockers')"
"$TEMPER" evidence accept --stage plan --id 5 --reason "the team agreed" >/dev/null 2>&1
assert_exit "escalate: the person's accept passes the plan gate" 0 "$TEMPER" gate plan
assert_exit "contest: an accepted finding cannot be contested" 1 "$TEMPER" evidence contest --stage plan --id 5 --cite src/a.sh --reason x
"$TEMPER" evidence add --stage review --claim 'src/a.sh:1 echo is unquoted' --severity critical >/dev/null 2>&1
assert_exit "contest: a review finding is contested the same way" 0 "$TEMPER" evidence contest --stage review --id 1 --cite src/a.sh:1 --reason "line 1 quotes nothing that can split"
assert_eq "contest: a contested review finding still blocks the review gate" "1" "$("$TEMPER" gate review >/dev/null 2>&1; echo $?)"

# --- 6. Spec drift: a finished spec compared with the tree as it is now; read only, never a gate ---
setup; rm -rf .git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T
mkdir -p src unit; printf 'a\n' > src/a.sh; printf 'b\n' > src/b.sh; printf 'd\n' > src/demo.sh; printf 't\n' > unit/a_test.sh
cat > .temper/specs/demo/plan.md <<'EOF'
## Files to Create
| File | Purpose |
|------|---------|
| `src/a.sh` | a |
| `src/b.sh` | b |
EOF
sed -i 's/^  Test: true$/  Test: bash unit\/a_test.sh/' .temper/specs/demo/intent.md
echo '{}' > .temper/specs/demo/gate-ledger.json
assert_eq "drift: a spec with no committed ledger is skipped" "[]" "$("$TEMPER" drift --json)"
git add -A >/dev/null 2>&1; git commit -qm "the finished run" >/dev/null 2>&1
assert_eq "drift: a spec the tree still matches has no drift" "## demo|No drift detected" \
  "$("$TEMPER" drift | sed -n '3p;4p' | sed 's/ (since .*//' | paste -sd'|' -)"
rm src/b.sh unit/a_test.sh; printf 'a2\n' > src/a.sh; git add -A >/dev/null 2>&1; git commit -qm "later work" >/dev/null 2>&1
assert_eq "drift: a missing planned file, a test that is gone and a file changed since are each named" \
  "src/b.sh|unit/a_test.sh|first|src/a.sh:1" \
  "$("$TEMPER" drift --json | python3 -c "import json,sys; r=json.load(sys.stdin)[0]; print('|'.join([r['missing'][0], r['tests_gone'][0]['file'], r['tests_gone'][0]['scenario'], '%s:%d' % (r['changed'][0]['file'], r['changed'][0]['commits'])]))")"
assert_exit "drift: it is information, never a failure" 0 "$TEMPER" drift

# --- 7. The plugin lists the brief, and the brief is read only on the CLI's rows ---
assert_eq "plugin.json lists the fresh reviewer's brief" "1" "$(grep -c '"./agents/plan-review.md"' "$REPO_ROOT/.claude-plugin/plugin.json")"
assert_eq "the fresh reviewer has no write tool" "tools: Read, Glob, Grep, Bash" "$(grep '^tools:' "$REPO_ROOT/agents/plan-review.md")"
