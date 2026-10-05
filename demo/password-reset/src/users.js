'use strict'

// A tiny in memory user store. The demo adds password reset on top of it.
const users = new Map()

function createUser(email, passwordHash) {
  if (typeof email !== 'string' || !email.includes('@')) throw new Error('a valid email is required')
  if (users.has(email)) throw new Error('user exists')
  const user = { email, passwordHash }
  users.set(email, user)
  return user
}

function findUser(email) {
  return users.get(email) ?? null
}

function reset() {
  users.clear()
}

module.exports = { createUser, findUser, reset }
