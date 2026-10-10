// Usage: node render.js stills t1,t2,...   |   node render.js frames
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs');
(async () => {
  const mode = process.argv[2];
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await page.goto('file://' + path.join(__dirname, 'video.html'));
  await page.evaluate(() => window.ready);
  const out = path.join(__dirname, mode === 'stills' ? 'stills' : 'frames');
  fs.mkdirSync(out, { recursive: true });
  const times = mode === 'stills'
    ? process.argv[3].split(',').map(Number)
    : Array.from({ length: 22 * 30 }, (_, i) => i / 30);
  for (let i = 0; i < times.length; i++) {
    await page.evaluate(t => window.render(t), times[i]);
    const name = mode === 'stills' ? `t${times[i].toFixed(2)}.png` : `f${String(i).padStart(4, '0')}.png`;
    await page.screenshot({ path: path.join(out, name) });
  }
  await browser.close();
})();
