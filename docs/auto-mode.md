# Auto mode and the steps it can refuse

Claude Code's auto mode can refuse a call it judges to be a change of its own permissions or of a protected file. Temper's steps
that edit a file the run depends on, or that record a decision, are the ones that can be refused. Each one has a CLI call that
replaces the edit, so the file is written by the CLI and the step cannot be refused for being a hand edit. When a step is refused
anyway, the person runs the `!` command below in the prompt; the CLI does the rest.

| The step | What auto mode can refuse | The call that replaces it |
|---|---|---|
| The Context check of Plan | An edit of the `reviewed:` line of the Context Map | `temper plan review --answer '<choice>'` (the CLI writes `- reviewed: human`) |
| Skipping a failed check | `temper override` | `! temper override <stage> --reason '<why>'` |
| Clearing the run | `temper state clear` | `! temper state clear` |
| A manual task's confirmation | `temper task confirm` | `! temper task confirm <N> --by '<your name>'`, then `! temper task gate <N> --model person` |
| Accepting a covered task | `temper task accept` | `! temper task accept <N> --reason '<why>'` |
| A small change | `temper adhoc open` | `! temper adhoc open --stage <stage> --reason '<why>'`, then `! temper adhoc close` |

This is why the CLI writes the `reviewed:` line and Plan never does: a model that edits the line has made the person's decision for
them, and a mod that lets the edit through would count an answer nobody gave.

With the mod off, every phase works the same; the mod adds the band, the pane and its write guards. Nothing falls back silently.
