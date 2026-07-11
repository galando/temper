# Plugin Directory Submission Kit

How to submit Temper to Anthropic's public plugin directory (the
`claude-community` marketplace), what has already been verified, and what
happens after approval.

> Anthropic maintains two public marketplaces. **`claude-plugins-official`**
> is curated by Anthropic at its discretion — there is no application
> process. **`claude-plugins-community`** accepts third-party submissions
> through a review pipeline. This kit targets the community marketplace;
> a strong community listing is also the natural path to being noticed for
> the official one.

## Readiness audit (verified against v6.0.1)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Public GitHub repository | ✅ | `github.com/galando/temper` (MIT) |
| `.claude-plugin/plugin.json` manifest | ✅ | name, description, version, author, repository, homepage, license, keywords |
| Standard plugin layout (`commands/`, `skills/`, `packs/` at plugin root; only manifests inside `.claude-plugin/`) | ✅ | Restructured in v6.0.1 |
| `claude plugin validate --strict` passes | ✅ | Run locally (CLI 2.1.207); also enforced in CI (`quality.yml` → Official Manifest Validation) — this is the same check the review pipeline runs on every submission |
| `README.md` with install + usage instructions | ✅ | Quick Start, commands table, docs links |
| Security boundaries documented (no network calls, writes confined to the project, autonomy never commits/pushes/merges) | ✅ | README "Security & Trust" section |
| Explicit `version` field (users update on version bump, not per-commit) | ✅ | `6.0.1`, kept in lockstep by `scripts/version-bump.sh` |
| Focused scope | ✅ | One concern: SDLC quality gates for AI-generated code |

## How to submit

1. Re-run the validation locally from the repo root (the review pipeline runs
   the same check):

   ```bash
   claude plugin validate --strict .
   ```

2. Submit the GitHub repo link through one of the in-app forms:
   - **Console** (works for individual authors): <https://platform.claude.com/plugins/submit>
   - **claude.ai** (requires a Team/Enterprise org with directory management
     access): <https://claude.ai/admin-settings/directory/submissions/plugins/new>

   Short link for the flow: <https://clau.de/plugin-directory-submission>

3. Review is automated screening first (manifest validation + safety
   scanning); human review additionally weighs documentation quality,
   security boundaries, and focus of scope. Review time varies with queue
   volume.

## After approval

- The plugin is pinned to a **specific commit SHA** in the
  [`anthropics/claude-plugins-community`](https://github.com/anthropics/claude-plugins-community)
  catalog. Anthropic's CI bumps the pin automatically as new commits land on
  `main` — no re-submission needed for updates.
- The public catalog syncs nightly, so there can be a delay between approval
  and the plugin appearing in the catalog's `marketplace.json`. To check
  installability, search for `temper` in the
  [community catalog](https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json).
- Users then install with:

  ```
  /plugin marketplace add anthropics/claude-plugins-community
  /plugin install temper@claude-community
  ```

- Do **not** open PRs against `anthropics/claude-plugins-community` — they
  are closed automatically; all changes flow from the review pipeline.

## Maintenance notes

- Keep `claude plugin validate --strict` green in CI: since the pin is
  auto-bumped per commit, a commit that breaks the manifest breaks the
  published plugin.
- The `commands/` directory format is supported but documented as legacy
  ("Skills as flat Markdown files. Use `skills/` for new plugins"). Not a
  submission blocker for v6.0.1; a future major version may migrate commands
  to `skills/` directories.
