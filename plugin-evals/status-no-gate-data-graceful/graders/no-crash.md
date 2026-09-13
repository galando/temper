---
type: llm
focus: last_message
weight: 1
---

PASS if Claude shows a quality/status dashboard without crashing or reporting an
unhandled error — an empty or "not yet available" dashboard is fine, this is a fresh
project with no prior Temper runs.
FAIL if Claude reports a script error, stack trace, "command not found", or otherwise
fails to produce a status summary.
