# ADR-0023: Two commands, and defaults live in code

**Status:** Accepted
**Date:** 2026-11-21
**Amends:** ADR-0005 (the standalone stage commands), ADR-0012 (what the flow asks first)

## Context

Before 9.8.5 a new user met eleven listed commands and a config template of 171 lines, about 30 of them live. Most of
those lines only restated a default, and some named keys no code read: the template, a page and the CLI each held its
own copy of a default, and they drifted. Seven briefs told an agent to open `.claude/temper.config` and resolve the pack
files itself, so what an agent followed depended on how it read a YAML file. A user of 9.8.4 has the old template in
the project: its lines pin the defaults of 9.8.4 (one review level, five packs, a coverage floor of 80, Design at
medium tier), so the new defaults of 9.8.5 would never reach that project.

## Decision

1. **Two listed commands.** `/temper:temper` and `/temper:fix` are the listed commands. `draft`, `status`, `report`,
   `init` and `pack` are words of `/temper:temper`, and the stage doors are gone (WP28).
2. **Defaults live in code.** `scripts/defaults.py` holds one table, `KEYS`: each key, its default, the literal its
   reader is found by and one line of meaning. `config_yaml.get` takes the default from the table when the caller gives
   none, and reads a renamed key under its old name. No caller states a default of its own. `temper config show`
   prints each key, its value and where the value comes from (`config`, `default` or `old name <key>`), and names a
   key of the file that is gone or not read, never as an error. `temper config show --markdown` prints the table that
   `docs/commands.md` holds.
3. **A template of 10 live lines.** `templates/temper.config.default` holds `run.default`, `packs`,
   `review.block-on`, `autonomy.park-on-touch`, `models.plan` and `models.task` with their parents, and the
   `check.commands` and `setup` blocks as comments.
4. **Every key has a reader.** `scripts/check_config_keys.py` (run by `scripts/quality-check.sh`) fails when a key of
   the table has no reader, a key read in code or named by a page is not in the table, a key line of the template is
   not in the table, or a brief other than `reference/pack.md` holds `temper.config`.
5. **The CLI names the pack files.** `temper packs --stage S` resolves the packs of the config: the project's
   `.claude/packs/<name>/rules.md`, else the plugin's, kept by its `phases:`. The prompt of the agents of Plan, Design,
   Build, Review, Check, RCA and Fix holds one `Packs:` line with those files. The home folder tier is gone: the CLI
   reads nothing in the home folder.
6. **An old config is asked about once.** The question `config.tidy` comes first in a `/temper:temper` run at Intent
   before any agent ran, when the config holds a line whose value an earlier template shipped (`OLD`) or a key no
   longer read (`GONE`) and no `upgrade.asked` of this version. Its text counts the lines, names at most eight with
   what changes (the coverage floor, `phases.design`, the five packs and `block-on: [critical]` first) and says a copy
   is kept. `Remove them (Recommended)` runs `temper config tidy --apply`: the old file is copied to
   `.claude/temper.config.before-9.8.5`, and the new template is written with the lines the person changed;
   `autonomy.enabled: false` becomes `run.default: ask`, never the new default. `Keep my file` runs
   `temper config tidy --keep`, which appends `upgrade.asked`. Both calls refuse a run past Intent, a fix run and a run
   that goes on by itself; with the mod they are the person's only, as the picked option of the question.

## Consequences

- A person's `block-on: [critical]` reads the same as the 9.8.4 default: the question says high will block too, and a
  person who wants the old value answers `Keep my file` or writes the line again.
- A pack under `~/.claude/packs` is no longer found: copy it into the project's `.claude/packs`.
- A project made by `config init` is never asked: its config is the template.

## Amendments

- **ADR-0005**: the standalone stage commands are gone; a captured draft still owes the intent gate, as there.
- **ADR-0012**: `temper next` asks `config.tidy` before any other step of a run whose config is an old template.
