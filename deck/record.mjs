import { chromium } from 'playwright';
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Records the demo in one continuous page context, so the output is a single file and needs
 * no ffmpeg to stitch. Captions are injected as an overlay before each scene rather than
 * spoken, which keeps the video legible without audio and without a voice track to re-record
 * when a number changes.
 *
 * Explorer pages are third-party and sometimes slow. Every navigation is allowed to fail
 * without taking the recording down: a missing scene is better than no video.
 */

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = dirname(HERE);
const OUTDIR = join(ROOT, 'web', 'public');
const RAW = join(HERE, '.rec');

const SITE = 'https://proveout.vercel.app';
const CC3 = 'https://creditcoin-testnet.blockscout.com/tx';
const SEP = 'https://sepolia.etherscan.io/tx';

const RUN = JSON.parse(
  readFileSync(join(ROOT, 'deployments', 'e2e-results.json'), 'utf8'),
).scenarios;
const TX = {
  release: RUN.release.settlementTx,
  challenge: RUN.challenge.settlementTx,
  replay: RUN.replay.settlementTx,
  selfCertify: RUN.selfCertify.sourceTx,
  delivery: RUN.delivery?.settlementTx,
  deliverySource: RUN.delivery?.sourceTx,
  verifySource: RUN.release.sourceTx,
};

if (existsSync(RAW)) rmSync(RAW, { recursive: true, force: true });
mkdirSync(RAW, { recursive: true });
mkdirSync(OUTDIR, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1280, height: 720 },
  recordVideo: { dir: RAW, size: { width: 1280, height: 720 } },
  deviceScaleFactor: 1,
});
const page = await context.newPage();

const CAPTION_CSS = `
#pv-cap{position:fixed;left:0;right:0;bottom:0;z-index:2147483647;
  background:linear-gradient(to top, rgba(10,10,10,.94) 62%, rgba(10,10,10,0));
  color:#fff;padding:34px 56px 40px;font-family:Geist,ui-sans-serif,system-ui,sans-serif;
  pointer-events:none}
#pv-cap .k{font-family:"Geist Mono",ui-monospace,Menlo,monospace;font-size:14px;
  letter-spacing:.22em;text-transform:uppercase;color:#9aa4ad;margin-bottom:10px}
#pv-cap .t{font-size:34px;font-weight:600;line-height:1.2;letter-spacing:-.02em;max-width:56ch}
#pv-cap .s{font-size:19px;color:#c8ced4;margin-top:10px;max-width:70ch;line-height:1.4}
`;

async function caption(kicker, text, sub = '') {
  await page
    .evaluate(
      ({ kicker, text, sub, css }) => {
        let style = document.getElementById('pv-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'pv-style';
          style.textContent = css;
          document.head.appendChild(style);
        }
        let el = document.getElementById('pv-cap');
        if (!el) {
          el = document.createElement('div');
          el.id = 'pv-cap';
          document.body.appendChild(el);
        }
        el.innerHTML =
          `<div class="k">${kicker}</div><div class="t">${text}</div>` +
          (sub ? `<div class="s">${sub}</div>` : '');
      },
      { kicker, text, sub, css: CAPTION_CSS },
    )
    .catch(() => {});
}

async function scene(url, ms, kicker, text, sub = '', after) {
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45_000 });
    await page.waitForTimeout(2500);
  } catch {
    console.warn(`  skipped (navigation failed): ${url}`);
    return;
  }
  await caption(kicker, text, sub);
  if (after) await after().catch(() => {});
  await page.waitForTimeout(ms);
  console.log(`  scene done: ${kicker}`);
}

console.log('recording...');

await scene(
  SITE,
  15_000,
  'ProveOut · Creditcoin CC3 Testnet',
  'Money moves when the work is proved, and anyone can prove it failed.',
  'A job escrow settled by an Ethereum Sepolia event, verified on Creditcoin by the Attestcoin Block Prover. No oracle operator. No arbiter.',
);

await scene(
  `${SITE}/console`,
  16_000,
  'Live from the chain',
  'Every row is read from chain logs when the page loads.',
  'No indexer, no cache, no fixtures. One job released, one refunded, and the vault balance rule still holds.',
);

await scene(
  `${CC3}/${TX.release}`,
  18_000,
  'Transaction 1 of 5 · released',
  'A proved WorkCompleted paid the builder 1,200 tUSDC.',
  'The escrow checked the emitting contract, its chain id, the frozen criteria hash and the receipt status before releasing anything.',
);

await scene(
  `${CC3}/${TX.challenge}`,
  26_000,
  'Transaction 2 of 5 · the one that matters',
  'A THIRD WALLET proved WorkFailed. Buyer refunded 1,100 tUSDC, that wallet paid a 100 tUSDC bounty.',
  'Sent from 0xA0356B80…92Ea, which is neither the buyer nor the builder. The bounty comes out of the bond of whoever failed, so the party who stands to lose cannot suppress the outcome.',
);

await scene(
  `${CC3}/${TX.replay}`,
  16_000,
  'Transaction 3 of 5 · replay refused',
  'The same proof submitted twice. Reverted: Query already processed.',
  'The query id is derived by the precompile from the verified Merkle path, not from anything the caller hands in.',
);


if (TX.delivery) {
  await scene(
    `${CC3}/${TX.delivery}`,
    26_000,
    'Transaction 4 of 5 · no oracle at all',
    'Settled by WETH. Not by us, not by a reporter, not by anyone with a stake in the job.',
    'The acceptance criterion was an on-chain delivery: the builder had to move at least 0.001 WETH to the buyer on Sepolia. Canonical WETH9 said it happened, and WETH has never heard of this project. Nobody can emit that Transfer without actually moving the tokens.',
  );
}

await scene(
  `${SEP}/${TX.selfCertify}`,
  18_000,
  'Transaction 5 of 5 · refused at the source',
  'The builder tried to certify their own job. NotReporter, refused on Sepolia.',
  'An earlier version of our oracle had no access control, which made every gate downstream decorative. We would rather show you this than have you find it.',
);

await scene(
  `${SITE}/verify`,
  30_000,
  'Check it yourself, no wallet',
  'Paste any Sepolia transaction hash. It calls the real precompile on Creditcoin.',
  'verify() is a view function, so this exercises the real verification path against real attestation state for free.',
  async () => {
    await page.fill('#txhash', TX.verifySource);
    await page.click('button[type="submit"]');
    await page.waitForTimeout(9000);
    await caption(
      'Precompile verified',
      'verified: true · receiptStatus: 1',
      'Two separate answers: the transaction was in the block, and the transaction succeeded. Conflating those is how an escrow gets paid with a proof that is genuine and meaningless.',
    );
  },
);

await scene(
  SITE,
  16_000,
  'What this does NOT do',
  'Attestcoin proves inclusion, not exclusion.',
  'It cannot prove that no transaction happened, so hiding a failure is made detectable and expensive, not impossible. The source oracle is trusted within its own scope. Testnet only, unaudited. · proveout.vercel.app · github.com/yukitran03/proveout',
);

await page.close();
await context.close();
await browser.close();

const files = readdirSync(RAW).filter((f) => f.endsWith('.webm'));
if (files.length === 0) throw new Error('no video was produced');
const src = join(RAW, files[0]);
const dest = join(OUTDIR, 'demo.webm');
if (existsSync(dest)) rmSync(dest);
renameSync(src, dest);
rmSync(RAW, { recursive: true, force: true });
console.log(`video written: ${dest} (${Math.round(statSync(dest).size / 1024)} KB)`);
