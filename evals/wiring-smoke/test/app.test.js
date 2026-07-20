const test = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');

test('ping returns ok status', () => {
  const app = createApp();
  assert.deepStrictEqual(app.ping(), { status: 'ok' });
});
