#!/usr/bin/env node
/**
 * Publishes the web console and points the stable alias at what was just published.
 *
 * Vercel gives every deployment its own hashed hostname and does not move a project alias
 * on its own, so a plain `vercel --prod` leaves `proveout.vercel.app` serving the previous
 * build. Every link in the README, the deck and the video guide points at the alias, so
 * that gap is the difference between a judge seeing this work and seeing an old one.
 *
 * The alias host is read from the deployment record rather than typed here, for the same
 * reason every other address on the site is: one place to change it.
 *
 * ON THE TOKEN. It is read from ~/.config/hackathon-sprint/vercel.env, outside every
 * repository, and is never printed.
 *
 * It has to be passed as `--token`: this pinned CLI does not read VERCEL_TOKEN from the
 * environment, which was checked rather than assumed. So it does land in the child
 * process's command line, where another process on this machine could read it. That is a
 * real residual exposure and the reason the token is worth rotating after the sprint.
 *
 * What is avoided is worse: no `shell: true` anywhere here, so arguments are passed as an
 * argv array rather than concatenated into a command string, which would leave the token
 * unescaped and subject to shell interpretation.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
/** Pinned as a devDependency and invoked through node, so there is no npx lookup,
 *  no network fetch per deploy, and no platform-specific shim to find. */
const VERCEL_BIN = join(ROOT, 'node_modules', 'vercel', 'dist', 'vc.js');

function die(message) {
  console.error(`\n${message}\n`);
  process.exit(1);
}

function readToken() {
  if (process.env.VERCEL_TOKEN) return process.env.VERCEL_TOKEN.trim();
  const path = join(homedir(), '.config', 'hackathon-sprint', 'vercel.env');
  if (!existsSync(path)) {
    die(
      `No Vercel token.\n` +
        `  Put it at ${path} as VERCEL_TOKEN=... (chmod 600), or export VERCEL_TOKEN.\n` +
        `  Never commit it.`,
    );
  }
  const line = readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .find((l) => l.startsWith('VERCEL_TOKEN='));
  if (!line) die(`${path} has no VERCEL_TOKEN= line.`);
  return line.slice('VERCEL_TOKEN='.length).trim().replace(/^["']|["']$/g, '');
}

function aliasHost() {
  const record = join(ROOT, 'deployments', 'cc3-testnet.json');
  if (!existsSync(record)) die('No deployment record. Run `npm run deploy` first.');
  const { webUrl } = JSON.parse(readFileSync(record, 'utf8'));
  if (!webUrl) die('deployments/cc3-testnet.json has no webUrl.');
  return webUrl.replace(/^https?:\/\//, '').replace(/\/$/, '');
}

if (!existsSync(VERCEL_BIN)) die('vercel is not installed. Run `npm install`.');

const token = readToken();

/** No `shell: true`: arguments stay arguments instead of being concatenated into a string. */
function vercel(args) {
  return execFileSync(process.execPath, [VERCEL_BIN, ...args, '--token', token], {
    cwd: ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
  });
}

async function check(url) {
  try {
    return (await fetch(url, { redirect: 'follow' })).status;
  } catch {
    return 0;
  }
}

const host = aliasHost();
console.log(`publishing web/ and aliasing to ${host}`);

const out = vercel(['--yes', '--prod', '--cwd', 'web']);
const deployed = out.match(/https:\/\/[a-z0-9-]+\.vercel\.app/g)?.pop();
if (!deployed) die(`Could not find the deployment URL in the Vercel output:\n${out}`);
console.log(`  deployed ${deployed}`);

vercel(['alias', 'set', deployed.replace(/^https:\/\//, ''), host]);
console.log(`  aliased  https://${host}`);

let bad = 0;
for (const url of [`https://${host}/`, `https://${host}/console`]) {
  const status = await check(url);
  console.log(`  ${status === 200 ? 'ok  ' : 'FAIL'} ${status} ${url}`);
  if (status !== 200) bad++;
}
if (bad) die(`${bad} page(s) did not return 200.`);
console.log('\nlive.');
