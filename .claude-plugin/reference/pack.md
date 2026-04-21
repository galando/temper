---
description: "Manage quality packs: view, toggle, create, quick-create launchers, configure links and phases"
---

# Pack: Quality Pack Manager

**Goal:** Display all defined quality packs with their enable/disable status, link targets, phase scoping, and connection health. Allow users to toggle packs, create new packs, quick-create launcher packs, and configure links and phases.

---

## Pack Resolution: Three-Tier System (v4.3.0)

Quality packs resolve from three tiers in priority order. Higher tiers shadow lower ones.

```
Priority 1 (highest) → .claude/packs/{name}/rules.md           (project-local)
Priority 2           → ~/.claude/packs/{name}/rules.md          (global / user-wide)
Priority 3 (lowest)  → $CLAUDE_PLUGIN_ROOT/.claude/packs/{name}/rules.md  (built-in)
```

**Why:** Teams ship project-specific packs in the repo. Users create global packs across all projects. Built-in packs provide defaults.

**Resolution:** When the same pack name exists in multiple tiers, only the highest-priority version is loaded. Project-local always wins over global, which always wins over built-in.

### Pack Discovery Algorithm

Scan all three tiers, deduplicate by name (highest priority wins):

```
Step 1: Scan built-in packs
  For each directory in $CLAUDE_PLUGIN_ROOT/.claude/packs/ (excluding stacks/):
    - If {name}/rules.md exists → add to manifest with scope: "built-in"

Step 2: Scan global packs
  For each directory in ~/.claude/packs/ (excluding stacks/):
    - If {name}/rules.md exists → add to manifest with scope: "global"
    - If name already in manifest → replace (global shadows built-in)

Step 3: Scan project-local packs
  For each directory in .claude/packs/ (excluding stacks/):
    - If {name}/rules.md exists → add to manifest with scope: "project"
    - If name already in manifest → replace (project shadows all)
```

---

## Cached Pack Manifest (v4.4.0)

Pack discovery results are cached to `.temper/pack-manifest.json` for instant subsequent loads.

### Cache Behavior

- **First run:** Full filesystem scan of all three tiers → write manifest
- **Subsequent runs:** Load from cache (near-instant)
- **Cache is rebuilt when:**
  1. `temper.config` file modified (project or global) — check mtime
  2. Pack directories added or removed in any tier — check directory listing
  3. Manifest `version` field doesn't match expected schema version
  4. Any pack's `rules.md` file modified — check mtime of each rules_path

### Manifest Structure

```json
{
  "version": 1,
  "last_built": "2026-04-20T10:00:00Z",
  "config_mtime": "2026-04-20T09:30:00Z",
  "packs": [
    {
      "name": "quality",
      "enabled": true,
      "scope": "built-in",
      "phases": "all",
      "link": null,
      "connected": null,
      "rules_path": "$CLAUDE_PLUGIN_ROOT/.claude/packs/quality/rules.md",
      "rule_summary": "Code quality: method length, DRY, naming"
    },
    {
      "name": "tdd",
      "enabled": true,
      "scope": "built-in",
      "phases": ["build"],
      "link": null,
      "connected": null,
      "rules_path": "$CLAUDE_PLUGIN_ROOT/.claude/packs/tdd/rules.md",
      "rule_summary": "TDD: RED-GREEN-REFACTOR enforcement"
    }
  ]
}
```

### Manifest Operations

**Read manifest:**
1. Check `.temper/pack-manifest.json` exists
2. If not: run full discovery, write manifest, return
3. If exists: load, check staleness conditions
4. If stale: run full discovery, overwrite manifest, return
5. If fresh: return cached manifest

**Invalidate manifest:**
- After toggling packs (enabled status changed)
- After creating a new pack
- After modifying pack link or phases config

---

## Pack Configuration Schema (v4.3.0)

### Extended Config Format

The `packs:` field in `.claude/temper.config` now supports objects with `name`, `link`, and `phases`:

```yaml
packs:
  - name: quality                        # Simple format (no link, all phases)
  - name: tdd
    phases: [build]                      # Only during build phase
  - name: security
    phases: [review, check]              # Only during review and check
  - name: api-standards
    link: plugin://my-api-linter         # Links to an installed plugin
  - name: sec-review
    link: skill://security-review        # Links to a skill
  - name: git                            # Simple format
```

### Backward Compatibility

Simple string format still works:
```yaml
packs:
  - quality
  - tdd
```
This is equivalent to:
```yaml
packs:
  - name: quality
  - name: tdd
```

### Parsing Note

When reading `packs:`, each entry can be either a **string scalar** (simple format) or a **mapping** with `name` key (extended format). Parser must check type:
- If string → treat as `{name: <value>, phases: "all", link: null}`
- If mapping → read `name` (required), `phases` (default: "all"), `link` (default: null)

---

## Phase Scoping (v4.3.0)

Packs can be restricted to specific Temper phases. Only packs scoped to the current phase are loaded.

### Available Phases

`plan`, `design`, `build`, `review`, `check`, `fix`

### Default Behavior

If `phases` is omitted or set to `all`, the pack activates during every phase.

### Phase Filtering

When a stage starts:
1. Read current phase from the command being executed (e.g., `/temper:build` → phase = "build")
2. Filter manifest packs: only include packs where `phases` is "all" or contains the current phase
3. Load filtered packs' rules + any linked context

---

## Pack-Plugin/Skill Linking (v4.3.0)

Packs can link to external plugins or skills. When a pack loads during a Temper phase, the linked resource's instructions are **included in the AI prompt context** alongside the pack's own rules.

### Link Format

- `plugin://{name}` — Links to an installed Claude Code plugin
- `skill://{name}` — Links to a skill (SKILL.md or command-based)

### What Linking Does

This is **context injection, not code execution.** When a linked pack loads:
1. The pack's own `rules.md` is read
2. The linked resource's content is located and read
3. Both are included in the AI's prompt context for that phase

### Connection Health Validation

When a pack has a link, validate the target exists:

**Plugin links (`plugin://`):**
1. Read `~/.claude/plugins/installed_plugins.json`
2. Find the plugin by name
3. Verify the install path exists on disk
4. If found → `connected: true`; if not → `connected: false`

**Skill links (`skill://`):**
1. Search resolution chain (see "Command-Based Skill Linking" below)
2. If any source found → `connected: true`; if none → `connected: false`

**Health states:**
| Status | Meaning | Display |
|--------|---------|---------|
| `connected: true` | Link target found | `connected` |
| `connected: false` | Link target missing | `not found` |
| `null` | No link configured | `—` |

**Graceful degradation:** If a link target is missing, the pack's own rules still load. Show a warning but do not block work. This prevents a removed plugin from blocking all Temper usage.

---

## Plugin/Skill Filesystem Discovery (v4.4.0)

Automatic discovery of all linkable targets from the filesystem. Used by quick-create launcher packs and pack linking.

### Discovery Scan (Execute These Steps at Runtime)

**Step 1: Discover installed plugins**

Use Bash to read the plugin registry:
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
    plugins = data.get('plugins', data)
    for key, entries in (plugins.items() if isinstance(plugins, dict) else []):
        name = key.split('@')[0]  # 'safety-net@cc-marketplace' -> 'safety-net'
        latest = entries[-1] if entries else {}
        install_path = latest.get('installPath', '')
        print(f'plugin://{name}  {install_path}')
"
```

**Step 2: Discover plugin skills and commands**

For each plugin found in Step 1, check its `installPath` for skills and commands:
```bash
# Replace {install_path} with the actual path from Step 1
find {install_path}/skills -name "SKILL.md" 2>/dev/null
find {install_path}/commands -name "*.md" 2>/dev/null
```

Each `SKILL.md` found becomes `skill://{directory_name}`. Each command `.md` becomes `skill://{stem}` (fallback only).

**Step 3: Discover project-local skills**

```bash
find .claude/skills -name "SKILL.md" 2>/dev/null
```

Each becomes `skill://{parent_directory_name}`.

**Step 4: Discover global skills**

```bash
find ~/.claude/skills -name "SKILL.md" 2>/dev/null
```

Each becomes `skill://{parent_directory_name}`.

**Step 5: Discover command-based skills (fallback)**

```bash
ls .claude/commands/*.md 2>/dev/null
ls ~/.claude/commands/*.md 2>/dev/null
```

Each `.md` file becomes `skill://{stem}` — BUT only if the name wasn't already found in Steps 2-4 (deduplication).

### Deduplication

If a skill name is found via `SKILL.md` in any source, the command-based fallback is skipped for that name.

### Discovery Sources Summary

| Source | What's Found | Link Format |
|--------|-------------|-------------|
| `~/.claude/plugins/installed_plugins.json` | Installed plugins | `plugin://{name}` |
| `{plugin installPath}/skills/*/SKILL.md` | Plugin skills | `skill://{name}` |
| `.claude/skills/*/SKILL.md` | Project-local skills | `skill://{name}` |
| `~/.claude/skills/*/SKILL.md` | Global skills | `skill://{name}` |
| `.claude/commands/*.md` (fallback) | Command-based skills | `skill://{command-name}` |
| `~/.claude/commands/*.md` (fallback) | Global command-based skills | `skill://{command-name}` |
| `{plugin installPath}/commands/*.md` (fallback) | Plugin commands | `skill://{command-name}` |

---

## Command-Based Skill Linking (v4.4.0)

Skills defined as markdown command files (`.claude/commands/*.md`) are valid link targets alongside traditional `SKILL.md` files.

### Resolution Order for `skill://{name}`

1. `.claude/skills/{name}/SKILL.md` — standard skill file
2. `~/.claude/skills/{name}/SKILL.md` — global skill file
3. `{plugin_path}/skills/{name}/SKILL.md` — plugin skill file
4. `.claude/commands/{name}.md` — **command-based fallback**
5. `{plugin_path}/commands/{name}.md` — plugin command fallback

Return the content from the first source that exists.

---

## Execution

### Step 1: Discover Packs (Three-Tier + Cache)

Read or build the pack manifest:

1. Check `.temper/pack-manifest.json` — load if fresh, rebuild if stale
2. If rebuilding: scan all three tiers, resolve links, check connection health
3. Read `.claude/temper.config` for enabled status and extended config (links, phases)
4. Merge manifest with config: apply enabled/disabled, links, phases

### Step 2: Display Pack Status

Show the pack list with all columns:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PACK — Quality Pack Manager                                      v4.4.0 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  NAME            STATUS  PHASES     LINK                CONNECTED        │
│  ────────────── ─────── ────────── ─────────────────── ──────────────── │
│  quality          ON     all        —                   —                │
│  tdd              ON     build      —                   —                │
│  security         ON     review,check —                 —                │
│  git              ON     all        —                   —                │
│  api-standards    OFF    all        plugin://api-linter  connected       │
│  sec-review       OFF    all        skill://sec-review  not found       │
│                                                                          │
│  6 packs total (4 enabled, 2 disabled)                                   │
│  Manifest cached: 2026-04-20T10:00:00Z                                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Step 3: User Action (AskUserQuestion-Driven UX)

Use AskUserQuestion with structured options:

```
AskUserQuestion:
  question: "What would you like to do?"
  options:
    - label: "Toggle packs on/off"
      description: "Select packs to enable or disable."
    - label: "Quick-create launcher pack"
      description: "Wrap a plugin or skill as a BLOCK-level pack. Fast path — no codebase scan."
    - label: "Configure pack (link, phases)"
      description: "Set link target or phase scoping for an existing pack."
    - label: "Done"
      description: "Exit pack manager. Use 'Other' to request a full interactive pack builder."
  multiSelect: false
```

If the user wants the full interactive pack builder (codebase scan + interview), they select "Other" and type "add new pack" or "create pack from scratch".

### Step 4: Toggle Packs

If the user selects "Toggle packs on/off":

1. Show a multi-select AskUserQuestion listing all packs with their current status:

```
AskUserQuestion:
  question: "Select packs to enable (deselect to disable):"
  options:
    - label: "quality (ON)"
      description: "Code quality: method length, DRY, naming"
    - label: "tdd (ON)"
      description: "TDD: RED-GREEN-REFACTOR"
    - label: "security (ON)"
      description: "Security: OWASP Top 10"
    - label: "git (ON)"
      description: "Git: conventional commits, branching"
  multiSelect: true
```

2. Update `.claude/temper.config`:
   - Preserve all config fields unchanged
   - Update `packs:` list to exactly the packs the user selected (keeping link/phases config if present)
3. Invalidate manifest cache
4. Show updated status
5. Return to Step 3

### Step 5: Quick-Create Launcher Pack

If the user selects "Quick-create launcher pack":

**5a: Discover linkable targets**

You MUST execute these scans using the Bash tool before showing any options. Collect results into a list, then filter out targets already linked to existing packs.

Run these commands and collect all output:

```bash
# 1. Installed plugins (parse name@source -> name, get installPath)
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
    plugins = data.get('plugins', data)
    for key, entries in (plugins.items() if isinstance(plugins, dict) else []):
        name = key.split('@')[0]
        latest = entries[-1] if entries else {}
        ipath = latest.get('installPath', '')
        print(f'PLUGIN|{name}|{ipath}')
"

# 2. Plugin skills (for each plugin installPath found above)
find {each_plugin_installPath}/skills -name "SKILL.md" 2>/dev/null

# 3. Project skills
find .claude/skills -name "SKILL.md" 2>/dev/null

# 4. Global skills
find ~/.claude/skills -name "SKILL.md" 2>/dev/null

# 5. Project commands (fallback, skip names already found as skills)
ls .claude/commands/*.md 2>/dev/null

# 6. Global commands (fallback)
ls ~/.claude/commands/*.md 2>/dev/null

# 7. Plugin commands (for each plugin installPath)
find {each_plugin_installPath}/commands -name "*.md" 2>/dev/null
```

After collecting all results:
1. Build a deduplicated list of `{type}://{name}` targets
2. Remove any targets already linked to a pack in `temper.config` (check each pack's `link:` field)
3. The remaining targets are available for quick-create

**5b: User selects target**
Show ALL discovered targets (after filtering). Paginate in groups of 4 since AskUserQuestion supports max 4 options:

If <= 4 targets found, show all in one AskUserQuestion:
```
AskUserQuestion:
  question: "Select the target to wrap as a launcher pack (1/1):"
  options:
    - label: "plugin://my-api-linter"
      description: "Installed plugin — {description}"
    - label: "skill://security-review"
      description: "Project skill — {path}"
    - label: "skill://production-review"
      description: "Command-based skill — .claude/commands/production-review.md"
    - label: "skill://temper-core"
      description: "Project skill — .claude/skills/temper-core/SKILL.md"
  multiSelect: false
```

If > 4 targets found, show in pages of 4. First 3 slots are targets, 4th slot is "More..." if additional pages remain:
```
AskUserQuestion:
  question: "Select the target to wrap as a launcher pack (page {N}/{total}):"
  options:
    - label: "plugin://my-api-linter"
      description: "Installed plugin — {description}"
    - label: "plugin://safety-net"
      description: "Installed plugin — {description}"
    - label: "skill://security-review"
      description: "Project skill — {path}"
    - label: "More targets..."
      description: "Show next {remaining} targets"
  multiSelect: false
```

On "More targets..." → show next page. Continue until user selects a target.
On the last page, all 4 slots are targets (no "More..." option).

**5c: User provides pack name**
Ask via "Other" free-text: "Enter a name for the launcher pack (lowercase, hyphens only, e.g., api-enforcer):"

Pack name constraints: lowercase alphanumeric with hyphens, matching directory name requirements. If free-text input is not available, generate a default from the link target (e.g., `plugin://my-api-linter` becomes `my-api-linter`).

**5d: Generate launcher template**
Create `.claude/packs/{pack-name}/rules.md`:

```markdown
# {Pack Name}
> Launcher pack — enforces {link_type}://{link_name}

## Mandatory Rules (BLOCK if violated)
- MUST use {link_type}://{link_name} for all work
- MUST follow all instructions defined by the linked resource
- MUST NOT bypass or ignore the linked resource's rules
```

**5e: Update config**
Add to `.claude/temper.config` packs list:
```yaml
  - name: {pack-name}
    link: {link_type}://{link_name}
```

**5f: Invalidate manifest and report**

```
┌─────────────────────────────────────────────────────────────┐
│ LAUNCHER PACK CREATED — {Pack Name}                         │
├─────────────────────────────────────────────────────────────┤
│ Location: .claude/packs/{pack-name}/rules.md                │
│ Link:     {link_type}://{link_name}                         │
│ Severity: BLOCK (guarantees linked resource is always used) │
│ Status:   ENABLED (added to temper.config)                  │
└─────────────────────────────────────────────────────────────┘
```

Return to Step 3.

### Step 6: Configure Pack (Link, Phases)

If the user selects "Configure pack (link, phases)":

**6a: Select pack**
Show all packs as options:

```
AskUserQuestion:
  question: "Which pack would you like to configure?"
  options:
    - label: "quality"
      description: "Link: none | Phases: all"
    - label: "tdd"
      description: "Link: none | Phases: build"
    ...
  multiSelect: false
```

**6b: Choose what to configure**
```
AskUserQuestion:
  question: "What would you like to configure for {pack-name}?"
  options:
    - label: "Set link target"
      description: "Link this pack to a plugin or skill for context injection."
    - label: "Set phase scoping"
      description: "Restrict this pack to specific phases."
    - label: "Both"
      description: "Configure link and phases together."
  multiSelect: false
```

**6c: Set link** — Execute the same discovery scans as Step 5a (plugins, skills, commands). Show ALL discovered targets with same pagination as Step 5b. Include both `plugin://` and `skill://` targets from all discovery sources.
**6d: Set phases** — Show phase options:
```
AskUserQuestion:
  question: "Which phases should {pack-name} be active in?"
  options:
    - label: "All phases"
      description: "Active during every Temper phase."
    - label: "build only"
      description: "Only during /temper:build."
    - label: "review and check"
      description: "Only during /temper:review and /temper:check."
  multiSelect: false
```

For arbitrary phase combinations not covered by presets, the user can type them via "Other" (e.g., "plan, build, fix"). Available phases: `plan`, `design`, `build`, `review`, `check`, `fix`.

**6e: Update config and invalidate manifest**
Return to Step 3.

### Step 7: Add New Pack (Full Builder)

If the user selects "Add new pack", run the interactive pack builder methodology from v3.0.0:

#### 7a: Scan Codebase (via Explore subagent)

Launch an Explore subagent:

```
Scan this codebase to discover existing patterns and conventions.

For each area, report:
1. What pattern is used (with example file:line)
2. How consistently it's used (X/Y files)
3. Any inconsistencies (alternative patterns found)

AREAS TO SCAN:

1. API DESIGN
   - Response format (envelope? flat? mixed?)
   - Error handling (custom codes? generic exceptions?)
   - Pagination style (cursor? offset?)
   - URL patterns (REST conventions?)

2. DATA ACCESS
   - ORM/query pattern (repository? direct queries? ORM?)
   - Transaction handling
   - Connection management

3. ERROR HANDLING
   - Custom error types/codes?
   - Logging patterns (structured? unstructured?)
   - Error propagation strategy

4. TESTING
   - Test framework and patterns
   - Coverage level (estimate from test file count vs source count)
   - Test naming conventions
   - Mock/stub patterns

5. CODE STYLE
   - Average method length
   - Class/module size
   - Dependency injection pattern
   - Naming conventions

6. SECURITY
   - Input validation patterns
   - Authentication/authorization approach
   - Secret management

7. GIT/WORKFLOW
   - Branch naming patterns (from git log)
   - Commit message style (from git log)

RETURN FORMAT:

For each area, return:
AREA: {name}
  Pattern: {what most code does}
  Consistency: {X/Y files}
  Alternative: {if any inconsistency found}
  Example: {file:line}
```

#### 7b: Interactive Interview

Present findings to the user and ask about each area. Use AskUserQuestion for structured choices. Keep to 5-10 questions total.

#### 7c: Conflict Resolution

When competing patterns detected with similar prevalence (within 20%):

```
AskUserQuestion:
  question: "CONFLICT: {Pattern A} ({X}%) vs {Pattern B} ({Y}%). Which should be the standard?"
  options:
    - label: "Pattern A"
      description: "{description} — {X/Y} files"
    - label: "Pattern B"
      description: "{description} — {Z/Y} files"
    - label: "Allow both"
      description: "Document when to use each."
    - label: "Defer"
      description: "Skip this rule for now."
  multiSelect: false
```

#### 7d: Generate Pack

Ask for pack name. Create `.claude/packs/{pack-name}/rules.md`:

```markdown
# {Pack Name} Engineering Standards

Generated by Temper on {date}
Based on scan of {project name}

## Mandatory Rules (BLOCK if violated)
{rules from interview marked as blocking}

## Quality Rules (WARN if violated)
{rules from interview marked as warning}

## Conventions (SUGGEST improvements)
{rules from interview marked as suggestions}

## Architectural Constraints (BLOCK if violated)
{architectural patterns from interview}
```

#### 7e: Enable and Validate

1. Update `.claude/temper.config` to add the new pack
2. Invalidate manifest cache
3. Report creation summary

### Step 8: Done

When the user selects "Done":
1. Show final configuration
2. Invalidate manifest if any changes were made
3. Exit

```
Current pack configuration (.claude/temper.config):
  quality     ON    phases: all
  tdd         ON    phases: build
  security    ON    phases: review, check
  git         ON    phases: all

Run /temper:review or /temper:check to use these packs.
```

---

## Config File Format

### Simple Format (backward compatible)

```yaml
packs:
  - quality
  - tdd
  - security
  - git
```

### Extended Format (v4.3.0+)

```yaml
packs:
  - name: quality
  - name: tdd
    phases: [build]
  - name: security
    phases: [review, check]
  - name: api-standards
    link: plugin://my-api-linter
  - name: git
```

---

## Pack Rules Format

Each pack's `rules.md` follows this structure:

```markdown
# {Pack Name}

## Mandatory Rules (BLOCK if violated)
- Rule that stops the build if broken

## Quality Rules (WARN if violated)
- Rule that flags but doesn't block

## Conventions (SUGGEST improvements)
- Nice-to-have patterns
```

---

## Built-in Packs

| Pack | Purpose | Default Gate Levels |
|------|---------|---------------------|
| `quality` | Code quality: method length, DRY, naming | WARN / SUGGEST |
| `tdd` | RED-GREEN-REFACTOR enforcement, scenario coverage | BLOCK / WARN |
| `security` | OWASP Top 10, secrets management | BLOCK / WARN |
| `git` | Conventional commits, branch naming | WARN / SUGGEST |

---

## Pack Loading During Phases

When any Temper phase starts, packs are loaded as follows:

```
1. Read or build pack manifest (cached in .temper/pack-manifest.json)
2. Filter by enabled status (from temper.config)
3. Filter by current phase (from phases field)
4. For each active pack:
   a. Read rules.md from highest-priority tier
   b. If link exists, resolve and read linked resource
   c. Check connection health for linked packs
   d. Include all content in AI prompt context
5. Report loaded packs (names + any warnings) at phase start
```
