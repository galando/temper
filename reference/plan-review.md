---
description: "Interactive HTML plan review, local or shared, with inline comments"
---

# HTML Plan Review

**Goal:** Generate a self-contained HTML page from plan.md + tasks.md that supports interactive review with inline comments (Google Doc-style), either on your own machine or shared with other reviewers by link.

Two plan gate options use this page:

- **Open HTML review**: render to a local file and open it. One reviewer, comments come back as a JSON file.
- **Share HTML review**: publish the page as a Claude artifact so other people can review it (see [Sharing](#sharing)). Without the `Artifact` tool, offer **Open HTML review** instead.

## Template

The HTML template is at `${CLAUDE_PLUGIN_ROOT}/templates/plan-review.html`. It contains:
- All CSS inline (dark and light theme, responsive down to phone width)
- All JS inline (comment system, copy/export, markdown rendering)
- No external dependencies (no CDN, no build tools)
- XSS-safe: all comment text is escaped before rendering
- A shared mode that switches on by itself when the page runs where a shared store exists (a published Claude artifact). Anywhere else it works from the page alone.

## HTML Generation

Never fill the template by hand. `${CLAUDE_PLUGIN_ROOT}/scripts/plan_review.py` does it deterministically, escapes every value for the place it lands in, and splits sections the same way every time:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/plan_review.py" render ".temper/specs/{feature}"
# writes .temper/specs/{feature}/review.html and prints its path
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/plan_review.py" render ".temper/specs/{feature}" \
  --target artifact -o ".temper/review-artifact-{feature}.html"
```

- Sections come from `plan.md` then `tasks.md`, split at each `## ` heading (headings inside code fences are ignored). Text before the first heading becomes its own section when it has content.
- `--feature "Name"` overrides the display name (default: the `# ` heading of plan.md, else the spec directory name).
- `--target artifact` writes the fragment the Artifact tool expects (title, style, body; no `<!doctype>`, `<html>`, `<head>` or `<body>` wrapper). Write it to the project's `.temper` folder, outside the spec directory, so a shared page is never committed with the spec. Every output goes in the project, never in the plugin folder, and `{feature}` is the spec's slug: letters (either case), digits, '.', '_' and '-', starting with a letter or digit, never containing '..' or '/'. A ticket key prefix such as `PROJ-123-login` is a valid slug.

### Section Schema

```json
[
  {
    "title": "Architecture",
    "source": "plan.md",
    "content": "## Architecture\n\n...markdown content..."
  },
  {
    "title": "Task 1: Create Pack",
    "source": "tasks.md",
    "content": "## Task 1: Create Pack\n\n...markdown content..."
  }
]
```

## Comment Schema

Comments are serialized to `review-comments.json`:

```json
{
  "version": 1,
  "feature": "{feature-slug}",
  "comments": [
    {
      "id": "c1709000000000",
      "target": "Architecture",
      "type": "task-change|scenario-change|plan-change|general-note",
      "text": "User's comment text",
      "author": "Optional reviewer name",
      "timestamp": "{ISO}",
      "resolved": false
    }
  ],
  "review_completed": true,
  "completed_at": "{ISO}",
  "reviewers_done": ["Optional reviewer name"]
}
```

`author` and `reviewers_done` are optional: the page fills them only when a reviewer typed a name.

## Orchestrator Integration

After the reviewer is done, get the comments into `.temper/specs/{feature}/review-comments.json` (how depends on the option; see below), then:

1. Read the JSON file
2. For each comment:
   - `task-change` → update tasks.md section matching `target`
   - `scenario-change` → update intent.md scenario matching `target`
   - `plan-change` → update plan.md section matching `target`
   - `general-note` → add it to plan.md under a `## Review Notes` heading (create the
     heading at the end of plan.md when it is missing), one bullet per note. Never
     write it into `.temper/build-state.json`: the CLI owns that file
3. Show what changed
4. Return to Plan gate

### Local: Open HTML review

1. Render and open `review.html`.
2. The reviewer clicks "Done Reviewing". The browser downloads `review-comments.json` (and the page also shows the JSON in a box with a Copy button, for browsers that block downloads).
3. The user places the file at `.temper/specs/{feature}/review-comments.json`, or pastes the JSON when asked.

## Sharing

Sharing sends the plan text to a service outside this machine. Before publishing, tell the user exactly where it will go and who can read it, and publish only after they confirm. A plan names files, internal design and sometimes people.

Share HTML review has one path, the Claude artifact, and comments come back automatically.

### Claude artifact

Use it when the `Artifact` tool is in your tool list.

1. Load the `artifact-design` and `artifact-capabilities` skills if they are listed; follow their page contract.
2. Render with `--target artifact` (command above).
3. Publish with the Artifact tool: `file_path` = the rendered file, `capabilities: {db: {}}`, `icon: "review"`, and a one-sentence `description` (for example "Plan review for {feature}"). Do not pass a `title`; the page carries its own.
4. The artifact is private until the user shares it. Tell the user: open the artifact's Share menu and give reviewers **Contributor** access. Viewers and Commenters can read but cannot save comments (their page then falls back to Copy comments).
5. Do one functional check as the skill asks: list the `comments` collection once with `ArtifactData` (empty is correct) and tell the user in one line what you checked.
6. Show an `AskUserQuestion` gate: **"Comments are in"** / **"Skip the review"**.
7. On "Comments are in", read both collections with `ArtifactData` (`list` on `comments`, then `list` on `done`), save the documents' bodies as `{"comments": [...], "done": [...]}` in a temp file, and normalize:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/plan_review.py" merge --feature "{feature}" \
     -o ".temper/specs/{feature}/review-comments.json" "{temp file}"
   ```
   Report how many comments came back and which reviewers marked themselves done (`reviewers_done`), then apply them as above.
8. Leave the artifact in place unless the user asks to delete it.

### Without the Artifact tool

Say so, and offer **Open HTML review** (local) instead. Never invent another hosting route.

## Browser Compatibility

- Chrome/Edge 90+, Firefox 90+, Safari 15+
- No polyfills needed
- Copy uses the clipboard API with a select-and-copy fallback; the file download is a convenience, not the only way out

## Security

- All comment text, including other reviewers' comments in a shared review, is escaped via `textContent`/`escapeHtml`, never inserted as markup
- Markdown rendering only applies to plan content (injected by `plan_review.py`, which JSON-escapes it for the script block)
- No external resources loaded (fully self-contained)
- Shared-review data is untrusted: `plan_review.py merge` drops empty comments and coerces unknown types to `general-note` before anything is applied
- Nothing leaves the machine before the user confirms. After that, the artifact's shared store carries reviewers' comments, and `ArtifactData` reads them back
