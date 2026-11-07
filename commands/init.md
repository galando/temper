---
description: "Set up a project for Temper: seed .claude/temper.config and the .temper/ folder (idempotent)"
---

# Temper: Set Up This Project

**Goal:** seed `.claude/temper.config` and scaffold `.temper/`. Safe to run any number of times:
an existing config is never overwritten. `/temper:temper` creates `.temper/specs/` by itself, so
this command is for choosing the settings up front.

This edition installs no hook and changes no git setting. The native commit gate (a pre-commit
hook that refuses a commit while a gate is red) is part of the full edition on GitHub
(galando/temper).

## Steps

1. **The project folder.** When the current folder is the home folder, stop and say: "This
   folder is not a project folder. Run /temper:init from a project folder." When it is inside the plugin folder
   (`${CLAUDE_PLUGIN_ROOT}`), stop the same way. Write nothing in either case.

2. **Config, `.claude/temper.config`.**
   - It exists: say "Temper config already present" and leave it as it is.
   - It is missing: detect the stack (`pom.xml` or `build.gradle`: Java; `package.json`: Node;
     `pyproject.toml` or `setup.py`: Python; `go.mod`: Go; `Cargo.toml`: Rust). Ask header
     `Packs`, question "Which quality packs should Temper apply?", with `multiSelect` on,
     options "quality, tdd, security, git, performance (the default)", "api-design",
     "architecture-depth". Then write the file:

     ```yaml
     # Temper (Markdown edition). Keys: reference/run-state.md in the plugin.
     stack: {detected, or auto}
     packs: [{the chosen packs}]
     review:
       block-on: [critical]
       confidence-threshold: 0.7
     check:
       coverage-threshold: 80
     phases:
       design: true
     loops:
       max-per-type: 2
     ```

     Say "Created .claude/temper.config."

3. **Scaffold.** Create `.temper/specs/` when it is missing. Write nothing else there.

4. **Version control.** When the project has a `.gitignore`, say whether it ignores `.temper/`.
   Temper's spec folders are the record of each change and are meant to be committed; only
   the person changes `.gitignore`, so offer it as a question when it ignores them (header
   `Specs`, options "Commit the spec folders" which removes that line, and "Keep them local").

5. **Report** in a short list what was created and what was already there, and the next step:
   `/temper:temper "<feature>"`.
