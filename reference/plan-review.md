---
description: "Interactive HTML plan review — browser-based review with inline comments"
---

# HTML Plan Review

**Goal:** Generate a self-contained HTML file from plan.md + tasks.md that supports interactive browser-based review with inline comments (Google Doc-style).

## Template

The HTML template is at `templates/plan-review.html`. It contains:
- All CSS inline (dark theme, responsive)
- All JS inline (comment system, export, markdown rendering)
- No external dependencies (no CDN, no build tools)
- XSS-safe: all user input is escaped before rendering

## HTML Generation

The orchestrator generates the HTML file by:

1. Read `templates/plan-review.html`
2. Read `.temper/specs/{feature}/plan.md` — split into sections by `##` headers
3. Read `.temper/specs/{feature}/tasks.md` — split into sections by `## Task` headers
4. Replace template placeholders:
   - `{{FEATURE_NAME}}` → human-readable feature name
   - `{{FEATURE_SLUG}}` → slug from build-state.json
   - `{{SECTIONS_JSON}}` → JSON array of `{ title, source, content }` objects
5. Write to `.temper/specs/{feature}/review.html`

### Section Schema

```json
[
  {
    "title": "Architecture",
    "source": "plan.md",
    "content": "## Architecture\n\n...markdown content..."
  },
  {
    "title": "Task 1 — Create Pack",
    "source": "tasks.md",
    "content": "## Task 1 — Create Pack\n\n...markdown content..."
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
      "timestamp": "{ISO}",
      "resolved": false
    }
  ],
  "review_completed": true,
  "completed_at": "{ISO}"
}
```

## Orchestrator Integration

After the user clicks "Done Reviewing" in the HTML:

1. Browser downloads `review-comments.json`
2. User places the file at `.temper/specs/{feature}/review-comments.json`
3. Orchestrator reads the JSON file
4. For each comment:
   - `task-change` → update tasks.md section matching `target`
   - `scenario-change` → update intent.md scenario matching `target`
   - `plan-change` → update plan.md section matching `target`
   - `general-note` → add as context note to build-state.json
5. Show what changed
6. Return to Plan gate

## Browser Compatibility

- Chrome/Edge 90+, Firefox 90+, Safari 15+
- No polyfills needed
- Uses standard File API for JSON download
- No server-side component

## Security

- All user input (comments) is escaped via `textContent` assignment (never `innerHTML` with user data)
- Markdown rendering only applies to plan content (injected by orchestrator, trusted)
- No external resources loaded (fully self-contained)
