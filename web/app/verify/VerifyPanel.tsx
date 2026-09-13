'use client';

import { useState } from 'react';

type Log = { emitter: string; topics: string[]; data: string };
type Result = {
  txHash: string;
  verified: boolean;
  precompile: string;
  chainKey: number;
  headerNumber: number;
  txIndex: number;
  merkleSiblings: number;
  continuityRoots: number;
  provedBytes: number;
  latestAttestedHeight: number | null;
  txType: number;
  receiptStatus: number;
  gasUsed: string;
  logs: Log[];
};

export default function VerifyPanel({ presets }: { presets: { label: string; hash: string }[] }) {
  const [hash, setHash] = useState(presets[0]?.hash ?? '');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function verify(target = hash) {
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const res = await fetch('/api/verify', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ txHash: target.trim() }),
      });
      const body = await res.json();
      if (!res.ok) setError(body.error ?? 'Verification failed.');
      else setResult(body as Result);
    } catch {
      setError('Could not reach the verifier.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <form
        className="verifybar"
        onSubmit={(e) => {
          e.preventDefault();
          if (!busy) verify();
        }}
      >
        <label className="sronly" htmlFor="txhash">
          Sepolia transaction hash
        </label>
        <input
          id="txhash"
          className="field mono"
          value={hash}
          spellCheck={false}
          autoComplete="off"
          placeholder="0x… a Sepolia transaction hash"
          onChange={(e) => setHash(e.target.value)}
        />
        <button className="btn" type="submit" disabled={busy || hash.trim().length === 0}>
          {busy ? 'Proving…' : 'Verify on chain'}
        </button>
      </form>

      {presets.length > 0 ? (
        <div className="presets">
          <span className="tiny">Try one of ours:</span>
          {presets.map((p) => (
            <button
              key={p.hash}
              type="button"
              className="chip"
              disabled={busy}
              onClick={() => {
                setHash(p.hash);
                verify(p.hash);
              }}
            >
              {p.label}
            </button>
          ))}
        </div>
      ) : null}

      {busy ? (
        <div className="note">
          <b>Working.</b>
          Fetching a Merkle and continuity proof from the proof builder, then calling the
          precompile. A few seconds.
        </div>
      ) : null}

      {error ? (
        <div className="note limit">
          <b>No proof.</b>
          {error}
        </div>
      ) : null}

      {result ? (
        <div className={`ev ${result.verified && result.receiptStatus === 1 ? 'proved' : 'refused'}`}>
          <div className="head">
            <span className="badge b-proved" style={{ opacity: result.verified ? 1 : 0.35 }}>
              {result.verified ? 'Precompile verified' : 'Not verified'}
            </span>
            <span className={`badge ${result.receiptStatus === 1 ? 'b-proved' : 'b-refused'}`}>
              receiptStatus {result.receiptStatus}
            </span>
            <span className="badge b-mute">tx type {result.txType}</span>
          </div>

          <p className="claim">
            {result.verified ? (
              <>
                Creditcoin verified this Ethereum Sepolia transaction against block{' '}
                <b>{result.headerNumber.toLocaleString()}</b> at index <b>{result.txIndex}</b>, using{' '}
                {result.merkleSiblings} Merkle siblings and {result.continuityRoots} continuity roots
                over {result.provedBytes.toLocaleString()} proved bytes.{' '}
                {result.receiptStatus === 1
                  ? 'The receipt says it succeeded, so an escrow may act on it.'
                  : 'The receipt says it reverted. It was still included in the block, which is exactly why inclusion alone must never be treated as success.'}
              </>
            ) : (
              <>The precompile refused this proof.</>
            )}
          </p>

          <dl className="keyvals">
            <div className="kv">
              <dt>Precompile</dt>
              <dd>{result.precompile}</dd>
            </div>
            <div className="kv">
              <dt>Source chain key</dt>
              <dd>{result.chainKey} (Ethereum Sepolia)</dd>
            </div>
            <div className="kv">
              <dt>Gas used</dt>
              <dd>{Number(result.gasUsed).toLocaleString()}</dd>
            </div>
            {result.latestAttestedHeight ? (
              <div className="kv">
                <dt>Latest attested height</dt>
                <dd>{result.latestAttestedHeight.toLocaleString()}</dd>
              </div>
            ) : null}
          </dl>

          {result.logs.length > 0 ? (
            <div className="stack-sm">
              <p className="tiny">
                {result.logs.length} event log{result.logs.length === 1 ? '' : 's'} recovered from the
                proved receipt. Indexed parameters are in <code>topics</code>, everything else in{' '}
                <code>data</code>.
              </p>
              {result.logs.map((l, i) => (
                <div className="logcard" key={i}>
                  <div className="hashline">
                    <span className="k">Emitter</span>
                    <span>{l.emitter}</span>
                  </div>
                  {l.topics.map((t, j) => (
                    <div className="hashline" key={j}>
                      <span className="k">topic{j}</span>
                      <span>{t}</span>
                    </div>
                  ))}
                  {l.data && l.data !== '0x' ? (
                    <div className="hashline">
                      <span className="k">data</span>
                      <span>{l.data}</span>
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
          ) : (
            <p className="tiny">This transaction emitted no logs.</p>
          )}
        </div>
      ) : null}
    </div>
  );
}
