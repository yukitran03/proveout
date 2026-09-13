import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * `root` is pinned because there are two lockfiles above this directory (the worker's and
 * this app's). Left to infer, the bundler can pick the parent and put the build output
 * somewhere `next start` will not look.
 */
export default {
  reactStrictMode: true,
  turbopack: { root: dirname(fileURLToPath(import.meta.url)) },
};
