---
type: llm
focus: last_message
weight: 1
---

PASS if the response confirms Temper setup completed for this project — for example
mentioning the config was created, `.temper/` was scaffolded, and/or the commit gate
(pre-commit hook) was installed.
FAIL if the response reports an error, refuses, or gives no indication setup succeeded.
