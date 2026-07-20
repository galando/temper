# Seeded defect: missing wiring

**Stack:** react-ts (minimal — no build tooling needed for the eval, just the source)

**What's wrong:** `src/components/NotificationBell.tsx` is a complete, correct
component — it takes a `notifications` prop and renders an unread count. But
`src/App.tsx` (the app shell) never imports or renders it. Both scenarios in
`intent.md` describe user-visible behavior in "the dashboard header" — neither is
reachable, because the component isn't mounted anywhere. This is the "missing wiring"
failure pattern from the README: code correct, integration missing.

**Which gate should catch it:** `/temper:review`'s intent-validation step
(`reference/review.md`) — it should notice that `NotificationBell` has no importer
(a grep for `NotificationBell` outside its own file turns up nothing) and mark the
intent verdict as `not_met` or `partial`, not `satisfied`. This is exactly the class
of defect blast-radius/consumer-tracing is meant to catch.

**Pass condition for this fixture:** `/temper:review` (or the Review stage of
`/temper`) reports `NotificationBell` as unused/unmounted, or the intent verdict as
`partial`/`not_met` rather than `satisfied`. See `evals/run-fixture.sh`.
