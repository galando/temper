---
type: regex
target:
  source: file
  path: .temper/evidence/review.json
pattern: 'firstNItems|off.?by.?one|out.of.bound|i\s*<=\s*n'
flags: 'i'
match: contains
weight: 2
---
