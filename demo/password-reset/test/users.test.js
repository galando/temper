'use strict'

const test = require('node:test')
const assert = require('node:assert')
const { createUser, findUser, reset } = require('../src/users')

test.beforeEach(() => reset())

test('creates and finds a user', () => {
  createUser('ada@example.com', 'hash')
  assert.strictEqual(findUser('ada@example.com').email, 'ada@example.com')
})

test('refuses a duplicate user', () => {
  createUser('ada@example.com', 'hash')
  assert.throws(() => createUser('ada@example.com', 'hash'), /user exists/)
})

test('refuses an invalid email', () => {
  assert.throws(() => createUser('nope', 'hash'), /valid email/)
})
