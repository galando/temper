# Password reset demo

A tiny Node project (no dependencies, Node 20 or later) for the Temper demo and for the
manual checklist in `docs/mods-testing.md`. It has an in memory user store and three
passing tests. The task is to add password reset tokens.

## Run it

Copy the folder out of the Temper clone so the demo never touches the clone's git history:

```bash
cp -R demo/password-reset /tmp/password-reset-demo
cd /tmp/password-reset-demo
git init -q && git add -A && git commit -qm "start"
npm test                      # three tests pass
claude --plugin-dir <path to your Temper clone>
```

Then, in the session:

```
/temper:temper Add password reset: generate a one time token for a user that expires after one hour, and refuse an expired or reused token
```

Expect, in order: an intent to approve (press 1), a plan to approve (press 1), a build
that starts with a failing test, a review, and a check that runs `npm test`. While
Claude is still in Intent or Plan, try asking it to edit `src/users.js`: Temper refuses
the write and says what to do next.

The task is small on purpose: it finishes in a few minutes.
