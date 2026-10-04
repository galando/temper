# Tasks: Password reset tokens

## Task 1: A token that works once [SEQUENTIAL]

- [ ] Write a failing test, then add `resetToken` and `useToken` in `src/users.js`
- **Files:** `src/users.js`, `test/users.test.js`
- **Traced to:** AC-01
- **Validate:** `npm test`

## Task 2: A token that expires after one hour [SEQUENTIAL: after Task 1]

- [ ] Write a failing test, then refuse a token older than one hour
- **Files:** `src/users.js`, `test/users.test.js`
- **Traced to:** AC-02
- **Validate:** `npm test`
