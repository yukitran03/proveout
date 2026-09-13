import Link from 'next/link';
import { JOB_ESCROW, PRECOMPILE, WORK_ORACLE, EXPLORER, short } from '../lib/chain';

export default function Home() {
  const deployed = Boolean(JOB_ESCROW);

  return (
    <main className="wrap">
      <section style={{ paddingTop: 16 }}>
        <div className="eyebrow">Creditcoin CC3 · Attestcoin readability</div>
        <h1>
          Money moves when the work is proved —<br />
          and anyone can prove it failed.
        </h1>
        <p className="lede">
          A job escrow on Creditcoin that releases or refunds based on an event that happened on
          Ethereum Sepolia, verified on-chain by the Attestcoin Block Prover precompile inside a
          single Creditcoin transaction. No oracle operator. No arbiter. Nobody pressing approve.
        </p>
        <p style={{ marginTop: 26, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <Link className="btn" href="/console">
            Open the console
          </Link>
          <a
            className="btn ghost"
            href="https://github.com/"
            target="_blank"
            rel="noreferrer"
          >
            Read the contracts
          </a>
        </p>
      </section>

      <section>
        <h2>How it works</h2>
        <div className="grid3">
          <div className="card">
            <span className="step-n">STEP 01</span>
            <h3>Freeze the criteria</h3>
            <p>
              The buyer locks USDC on Creditcoin against a job whose acceptance criteria are hashed
              before any work starts. The builder stakes a bond. Nothing in the contract can move
              that hash afterwards.
            </p>
          </div>
          <div className="card">
            <span className="step-n">STEP 02</span>
            <h3>Prove what happened</h3>
            <p>
              The outcome is emitted as an event on Sepolia. Attestcoin proves that transaction
              inside one synchronous Creditcoin call — including its receipt status, so a reverted
              transaction cannot pass as a success.
            </p>
          </div>
          <div className="card">
            <span className="step-n">STEP 03</span>
            <h3>Settle, or be challenged</h3>
            <p>
              A proved completion pays the builder. A proved failure refunds the buyer — and pays
              whoever submitted it a bounty out of the builder's bond. Anyone can be that person.
            </p>
          </div>
        </div>
      </section>

      <section>
        <h2>The difference</h2>
        <div className="note n-go">
          A passport built from evidence the borrower submits about themselves is a CV, not a credit
          report. ProveOut does not ask whether you did well — it lets <b>anyone</b> prove that you
          failed, and pays them for doing it.
        </div>
        <p className="lede" style={{ fontSize: 15 }}>
          The usual shape of a cross-chain settlement system is that the party who benefits watches
          for their own good news and submits it. Nobody submits their own failure. A design like
          that does not need to censor bad news — bad news simply never arrives, because the only
          party watching has no reason to send it.
        </p>
      </section>

      <section>
        <h2>The gate that matters</h2>
        <pre>{`// The precompile proves a transaction was INCLUDED in a block.
// A reverted transaction is in the block too.
EvmV1Decoder.ReceiptFields memory receipt = ...;
if (receipt.receiptStatus != 1) revert ReceiptNotSuccessful(receipt.receiptStatus);`}</pre>
        <p className="lede" style={{ fontSize: 14.5 }}>
          Without that line, a builder sends a completion call that reverts, proves its inclusion
          completely honestly, and is paid for work that never happened. Every proof involved would
          be genuine.
        </p>
      </section>

      <section>
        <h2>On-chain</h2>
        <div className="tablewrap">
          <table>
            <tbody>
              <tr>
                <th>Block Prover precompile</th>
                <td className="mono">
                  <a href={`${EXPLORER}/address/${PRECOMPILE}`} target="_blank" rel="noreferrer">
                    {PRECOMPILE}
                  </a>
                </td>
              </tr>
              <tr>
                <th>Creditcoin CC3 Testnet</th>
                <td className="mono">chain id 102031</td>
              </tr>
              <tr>
                <th>Source chain</th>
                <td className="mono">Ethereum Sepolia · Attestcoin chain key 1</td>
              </tr>
              <tr>
                <th>JobEscrow</th>
                <td className="mono">
                  {deployed ? (
                    <a href={`${EXPLORER}/address/${JOB_ESCROW}`} target="_blank" rel="noreferrer">
                      {JOB_ESCROW}
                    </a>
                  ) : (
                    <span className="badge b-mute">not deployed yet</span>
                  )}
                </td>
              </tr>
              <tr>
                <th>WorkOracle (Sepolia)</th>
                <td className="mono">
                  {WORK_ORACLE ? (
                    <a
                      href={`https://sepolia.etherscan.io/address/${WORK_ORACLE}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {short(WORK_ORACLE, 10)}
                    </a>
                  ) : (
                    <span className="badge b-mute">not deployed yet</span>
                  )}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2>What this does not do</h2>
        <div className="note n-warn">
          <b>Attestcoin proves inclusion, not exclusion.</b> It can prove a transaction happened. It
          cannot prove no transaction happened. ProveOut therefore does not make hiding a failure
          impossible — it makes it <b>detectable and expensive</b>. That is the whole promise of the
          challenge mechanism, and not a word more.
        </div>
        <div className="note n-dead">
          Testnet only, unaudited. The settlement asset is a demo token with an open mint and no
          value. The bond ratio is a demo parameter, not an economic result.
        </div>
      </section>

      <footer>
        ProveOut · built for BUIDL CTC 2026 Fall, track AI · Apache-2.0 · settlement on Creditcoin
        CC3 Testnet, proofs by Attestcoin Protocol.
      </footer>
    </main>
  );
}
