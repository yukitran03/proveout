import { PRECOMPILE, TX } from '../../lib/chain';
import VerifyPanel from './VerifyPanel';

export const dynamic = 'force-dynamic';

export const metadata = { title: 'Verify a proof' };

export default function VerifyPage() {
  const presets = [
    TX?.release?.sourceTx ? { label: 'our WorkCompleted', hash: TX.release.sourceTx } : null,
    TX?.challenge?.sourceTx ? { label: 'our WorkFailed', hash: TX.challenge.sourceTx } : null,
  ].filter(Boolean) as { label: string; hash: string }[];

  return (
    <>
      <section>
        <p className="eyebrow">Do not take our word for it</p>
        <h1>Verify a proof yourself.</h1>
        <p>
          Paste any Ethereum Sepolia transaction hash. This page fetches a Merkle and continuity
          proof for it, then calls the Attestcoin Block Prover precompile at{' '}
          <code>{PRECOMPILE}</code> on Creditcoin and shows you what comes back, including the
          receipt status and every event log recovered from the proved bytes.
        </p>
        <p className="tiny">
          No wallet, no signature, nothing spent. The precompile&rsquo;s <code>verify</code> is a
          view function, so this exercises the real verification path against real attestation state
          for free. It is the same call the escrow makes before it moves any money.
        </p>
      </section>

      <section>
        <VerifyPanel presets={presets} />
      </section>

      <section>
        <p className="eyebrow">What you are looking at</p>
        <h2>Two answers, not one.</h2>
        <div className="cols">
          <div className="col">
            <span className="n">ANSWER 1</span>
            <h3>Was it in the block</h3>
            <p>
              That is what the precompile settles, by checking a Merkle path into the block and a
              continuity chain back to an attested endpoint. It is the hard cryptographic part, and
              it is the part Attestcoin does for you.
            </p>
          </div>
          <div className="col">
            <span className="n">ANSWER 2</span>
            <h3>Did it succeed</h3>
            <p>
              A separate question, and the one that is easy to skip. A reverted transaction is in
              the block too. Any escrow that treats inclusion as success can be paid with a proof
              that is completely genuine and completely meaningless.
            </p>
          </div>
          <div className="col">
            <span className="n">ANSWER 3</span>
            <h3>Who said it</h3>
            <p>
              Neither answer tells you whether the contract that emitted a log is one you trust, or
              which chain it was on. Those are application decisions, and they are what the escrow
              checks after this call returns.
            </p>
          </div>
        </div>
      </section>
    </>
  );
}
