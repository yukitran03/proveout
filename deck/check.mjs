import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** Proves the deck and the video are not blank, rather than assuming a 200 means content. */
const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '.check');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

// Slides, straight from source.
await page.goto(pathToFileURL(join(HERE, 'slides.html')).href, { waitUntil: 'networkidle' });
await page.waitForTimeout(1200);
const slides = await page.locator('section').count();
const texts = await page.locator('section').evaluateAll((els) =>
  els.map((e) => (e.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 58)),
);
console.log(`slides: ${slides}`);
texts.forEach((t, i) => console.log(`  ${String(i + 1).padStart(2)} ${t}`));
const empty = texts.filter((t) => t.length < 12).length;
console.log(empty === 0 ? 'no blank slides' : `WARNING: ${empty} slide(s) look blank`);
await page.locator('section').nth(7).screenshot({ path: join(OUT, 'slide-08.png') });

// A frame out of the recording, to prove it is not a black rectangle.
await page.setContent(
  `<body style="margin:0;background:#000">
     <video id="v" width="1280" height="720" src="https://proveout.vercel.app/demo.webm"></video>
   </body>`,
);
await page.waitForTimeout(1500);
const frame = await page.evaluate(async () => {
  const v = document.getElementById('v');
  await new Promise((r) => {
    v.addEventListener('loadeddata', r, { once: true });
    setTimeout(r, 25000);
  });
  v.currentTime = 75; // mid-way, inside the challenge scene
  await new Promise((r) => {
    v.addEventListener('seeked', r, { once: true });
    setTimeout(r, 15000);
  });
  const c = document.createElement('canvas');
  c.width = 320;
  c.height = 180;
  const g = c.getContext('2d');
  g.drawImage(v, 0, 0, 320, 180);
  const d = g.getImageData(0, 0, 320, 180).data;
  let sum = 0;
  let nonBlack = 0;
  for (let i = 0; i < d.length; i += 4) {
    const l = (d[i] + d[i + 1] + d[i + 2]) / 3;
    sum += l;
    if (l > 24) nonBlack++;
  }
  return {
    duration: Math.round(v.duration),
    meanLuma: Math.round(sum / (d.length / 4)),
    nonBlackPct: Math.round((nonBlack / (d.length / 4)) * 100),
  };
});
console.log(`video: ${frame.duration}s, mean luma ${frame.meanLuma}, ${frame.nonBlackPct}% non-black`);
console.log(frame.nonBlackPct > 40 ? 'video has picture' : 'WARNING: video frame looks blank');

await browser.close();
