// resetService.js — password reset request handling.
//
// SEEDED DEFECT (do not fix without updating evals/fixtures/password-reset/SEEDED_DEFECT.md):
// there is no rate limiting on reset requests. A user can request unlimited resets,
// which is exactly the gap the intent.md scenario "Rate limiting on reset requests"
// describes and no test in test/ exercises.

const resetTokens = new Map();

function requestReset(email, now = Date.now()) {
  if (!email || !email.includes('@')) {
    throw new Error('invalid email');
  }
  const token = `${email}:${now}`;
  resetTokens.set(token, { email, issuedAt: now, expiresAt: now + 15 * 60 * 1000 });
  return { token, status: 202 };
}

function isTokenValid(token, now = Date.now()) {
  const entry = resetTokens.get(token);
  if (!entry) return false;
  return now <= entry.expiresAt;
}

module.exports = { requestReset, isTokenValid };
