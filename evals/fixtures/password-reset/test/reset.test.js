// reset.test.js — covers the happy path and token expiry only.
//
// SEEDED DEFECT: no test here exercises rate limiting, because resetService.js has none.
// This is the gap /temper:check's scenario-coverage verification (reference/check.md)
// should catch against the "Rate limiting on reset requests" scenario in
// .temper/specs/password-reset/intent.md.

const test = require('node:test');
const assert = require('node:assert/strict');
const { requestReset, isTokenValid } = require('../src/resetService');

test('requestReset issues a token for a valid email', () => {
  const { token, status } = requestReset('user@example.com', 1000);
  assert.equal(status, 202);
  assert.ok(isTokenValid(token, 1000));
});

test('requestReset rejects an invalid email', () => {
  assert.throws(() => requestReset('not-an-email', 1000));
});

test('token expires after 15 minutes', () => {
  const { token } = requestReset('user@example.com', 1000);
  assert.equal(isTokenValid(token, 1000 + 16 * 60 * 1000), false);
});

// NOTE: no test for "3 resets in 10 minutes -> 4th rejected with 429" — that scenario
// exists in intent.md but nothing here (or in resetService.js) implements/covers it.
