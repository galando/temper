# Pull requests at Commit

This page is the only place Temper pushes or calls `gh`. It runs inside the Commit steps of `/temper:temper`, after the record
commit and before `temper state clear`, only when the person chose **Commit and open PR** or **Commit and open stacked PRs** at the
Check question (the CLI keeps the choice: `state get pr` is `one` or `stacked`). An armed run never gets here, and `/temper:fix`
never does. Every pull request is a **draft**: Temper never runs `gh pr ready` and never removes the draft state. `gh` takes the
repository from `origin`; never write an owner or a repository name, and never read, store, print or set a token.

## Capture

Before `temper state clear`, note these four things (the state is gone after it):

1. `base_sha`: `temper state get base_sha`, else `git merge-base HEAD <default branch>`.
2. `branch`: `git branch --show-current`.
3. The default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (without `origin/`), else
   `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, else `main`.
4. The spec path: `temper state get spec_path`.

## Preconditions (they never fail the commit)

`command -v gh`, `gh auth status`, `git remote get-url origin` and a named branch. When any one fails, keep the commit, print the
fallback commands and stop; the person runs them:

```
git push -u origin <branch>
gh pr create --head <branch> --base <default branch> --title '<title>' --body-file <path> --draft
```

## The body

Write it to a file from `mktemp`: the first one to three sentences of the Problem section of `intent.md`, verbatim; each
acceptance criterion with its `Validate:` line; the spec path on the branch; `git diff --stat <base_sha>..<tip>`; and the summary
of the gate ledger (`temper report`).

## One PR

```
git push -u origin <branch>
gh pr create --head <branch> --base <default branch> --title '<subject>' --body-file <file> --draft
```

Report a row `PR: <url>`.

## Stacked PRs

The parts: `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pr_parts.py parts <base_sha> <slug>` prints one part per Build group, cut at the
group merge commits; a group that changed only comments joins its neighbour. With fewer than two parts, open one PR instead.
Confirm the proposal in one question (the part, the group title, the merge short SHA of each): **Create stacked PRs
(Recommended)** or **Open one PR instead**.

- Part k below N gets a branch `<branch>-part-<k>` at its merge commit (`git branch <branch>-part-<k> <merge sha>`); part N is the
  feature branch itself, so its tip is what Check proved.
- Push each branch, then `gh pr create --head <part branch> --base <base> --title '<subject>' --body-file <file> --draft`. Part 1's
  base is the default branch; part k's base is the branch of part k minus one.
- Each body starts `Part k of N` and links the PR before it.
- When part k fails, stop: report the pull requests already open and print the commands for parts k to N.
- Report a row `PR k/N: <url>` for each. Never rewrite history: every commit keeps the SHA Build gave it.

## The review-readiness skill

When the session lists a skill named `review-readiness` (`state get commit_path` is `skill`), run its Steps 1 to 5 in place of the
steps above, once per part: scope, capabilities, repository checks, commit and code review, and the draft pull request. Stop
before any step that would mark the request ready. After each part, record the verdict and print the report again so the Commit
panel shows the rows:

```
temper evidence add --stage commit --claim 'readiness: {PASS|FAIL}, part {k} of {N}'
temper report
```

With no such skill, the question offered to install it or to skip it with a reason; a skip records
`readiness: unavailable, skipped by you: {reason}` and these steps run. Temper never vendors anyone's skill.
