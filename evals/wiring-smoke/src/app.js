function createApp() {
  return {
    ping() {
      return { status: 'ok' };
    },
  };
}

module.exports = { createApp };
