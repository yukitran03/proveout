import { chromium } from 'playwright';
import { statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = dirname(HERE);
const OUT = join(ROOT, 'web', 'public', 'ProveOut-deck.pdf');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto(pathToFileURL(join(HERE, 'slides.html')).href, { waitUntil: 'networkidle' });
// Give the webfonts a moment; a deck set in the fallback stack looks like a different project.
await page.waitForTimeout(1500);
await page.pdf({
  path: OUT,
  width: '1280px',
  height: '720px',
  printBackground: true,
  pageRanges: '1-12',
});
await browser.close();

console.log(`PDF written: ${OUT} (${Math.round(statSync(OUT).size / 1024)} KB)`);
