# Quality Pack

**Version:** 1.0.0
**Last Updated:** 2025-03-09

## Quality Rules (WARN if violated)
- Functions should have a single responsibility
- Methods should not exceed 30 lines (excluding blank lines and comments)
- Classes/modules should not exceed 300 lines
- Avoid deeply nested code (max 3 levels of nesting)
- No duplicated logic — extract shared code into reusable functions
- Variable and function names should be descriptive and self-documenting
- Avoid magic numbers — use named constants
- Return early from functions to reduce nesting

## Conventions (SUGGEST improvements)
- Prefer composition over inheritance
- Prefer immutable data structures where possible
- Group related functions/methods together
- Keep public API surface minimal
