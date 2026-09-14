import Link from 'next/link';
import {
  CC3_CHAIN_ID,
  EXPLORER,
  JOB_ESCROW,
  PRECOMPILE,
  REPO_URL,
  SEPOLIA_EXPLORER,
  SOURCE_CHAIN_KEY,
  SOURCE_REGISTRY,
  TEST_USDC,
  TX,
  WORK_ORACLE,
  short,
  usdc,
} from '../lib/chain';

function Hash({ hash, sepolia = false }: { hash: string; sepolia?: boolean }) {
  return (
    <a href={`${sepolia ? SEPOLIA_EXPLORER : EXPLORER}/tx/${hash}`} target="_blank" rel="noreferrer">
      {hash}
    </a>
  );
}

export default function Home() {
  const deployed = Boolean(JOB_ESCROW);
  const hasRun = Boolean(TX?.release && TX?.challenge && TX?.replay);

  return (
    <>
      <section>
        <p className="eyebrow">Creditcoin CC3 Testnet · Attestcoin readability</p>
        <h1>Money moves when the work is proved.</h1>
        <p>
          A job escrow that releases or refunds on the strength of an event that happened on another
          chain, verified by the Attestcoin Block Prover inside a single Creditcoin transaction. No
          cross-chain oracle operator. No arbiter. Nobody pressing approve.
        </p>
        <div className="actions">
          <Link className="btn" href="/verify">
            Verify a proof yourself
          </Link>
          <Link className="btn ghost" href="/console">
            Open the console
          </Link>
          {REPO_URL ? (
            <a className="btn ghost" href={REPO_URL} target="_blank" rel="noreferrer">
              Read the contracts
            </a>
          ) : null}
        </div>
      </section>

      {hasRun ? (
        <section>
          <p className="eyebrow">On chain, not on a slide</p>
          <h2>Four transactions that settle the argument.</h2>
          <p>
            Real transactions against the live Block Prover. Open any of them in the explorer, or
            run the same verification yourself on the <Link href="/verify">verify page</Link>.
          </p>

          <div className="evidence">
            <article className="ev proved">
              <div className="head">
                <span className="n">01</span>
                <span className="badge b-proved">Released</span>
              </div>
              <p className="claim">
                A proved <code>WorkCompleted</code> paid the builder{' '}
                <b>{usdc(TX!.release!.paidToBuilder)} tUSDC</b>, the payout plus the bond returned.
                The escrow checked the source event, its emitter, its chain and the receipt status
                before releasing anything.
              </p>
              <div className="stack-sm">
                <div className="hashline">
                  <span className="k">Settlement</span>
                  <Hash hash={TX!.release!.settlementTx} />
                </div>
                <div className="hashline">
                  <span className="k">Source</span>
                  <Hash hash={TX!.release!.sourceTx} sepolia />
                </div>
              </div>
            </article>

            <article className="ev refused">
              <div className="head">
                <span className="n">02</span>
                <span className="badge b-refused">Refunded by a stranger</span>
              </div>
              <p className="claim">
                A proved <code>WorkFailed</code>, carried to Creditcoin by{' '}
                <a
                  className="mono"
                  href={`${EXPLORER}/address/${TX!.challenge!.challenger}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {short(TX!.challenge!.challenger, 8)}
                </a>
                , a wallet that is <b>neither the buyer nor the builder</b>. The buyer was refunded{' '}
                {usdc(TX!.challenge!.refundedToBuyer)} tUSDC and that wallet was paid a{' '}
                <b>{usdc(TX!.challenge!.bountyToChallenger)} tUSDC bounty</b> out of the
                builder&rsquo;s bond. This is the one nobody else proves.
              </p>
              <div className="stack-sm">
                <div className="hashline">
                  <span className="k">Settlement</span>
                  <Hash hash={TX!.challenge!.settlementTx} />
                </div>
                <div className="hashline">
                  <span className="k">Source</span>
                  <Hash hash={TX!.challenge!.sourceTx} sepolia />
                </div>
              </div>
            </article>

            <article className="ev refused">
              <div className="head">
                <span className="n">03</span>
                <span className="badge b-refused">Reverted, on purpose</span>
              </div>
              <p className="claim">
                The proof that paid the builder in 01, submitted a second time. It reverted with{' '}
                <code>Query already processed</code>. The query id is derived by the precompile from
                the verified Merkle path, so a replay cannot be dressed up as a new proof.
              </p>
              <div className="hashline">
                <span className="k">Settlement</span>
                <Hash hash={TX!.replay!.settlementTx} />
              </div>
            </article>

            {TX?.selfCertify ? (
              <article className="ev refused">
                <div className="head">
                  <span className="n">04</span>
                  <span className="badge b-refused">Refused at the source</span>
                </div>
                <p className="claim">
                  The builder calling <code>reportCompleted</code> for their own job, trying to
                  certify work nobody checked. The source chain refused it, before any proof could
                  exist. <code>isReporter(builder)</code> is{' '}
                  <b>{String(TX.selfCertify.builderIsReporter)}</b>. An earlier version of this
                  oracle had no access control at all, which made every gate downstream decorative.
                </p>
                <div className="stack-sm">
                  <div className="hashline">
                    <span className="k">Refused with</span>
                    <span>{TX.selfCertify.revertReason}</span>
                  </div>
                  <div className="hashline">
                    <span className="k">Source</span>
                    <Hash hash={TX.selfCertify.sourceTx} sepolia />
                  </div>
                </div>
              </article>
            ) : null}
          </div>
        </section>
      ) : null}

      <section>
        <p className="eyebrow">How a job runs</p>
        <h2>Freeze, prove, settle.</h2>
        <div className="cols">
          <div className="col">
            <span className="n">01</span>
            <h3>Freeze</h3>
            <p>
              The buyer locks USDC against a job whose acceptance criteria are hashed before any
              work starts. The builder stakes a bond. Nothing in the contract can change that hash
              afterwards.
            </p>
          </div>
          <div className="col">
            <span className="n">02</span>
            <h3>Prove</h3>
            <p>
              The outcome is emitted as an event on Ethereum Sepolia. Attestcoin proves that
              transaction on Creditcoin, receipt and logs included, in one synchronous call.
            </p>
          </div>
          <div className="col">
            <span className="n">03</span>
            <h3>Settle</h3>
            <p>
              A proved completion pays the builder. A proved failure refunds the buyer and pays
              whoever carried it a bounty out of the bond. Verification and payout happen in the
              same transaction.
            </p>
          </div>
        </div>
      </section>

      <section>
        <p className="eyebrow">The difference</p>
        <p className="pull">Evidence that only the winner submits is not evidence.</p>
        <p>
          The usual shape of a cross-chain settlement system is that the party who benefits watches
          for their own good news and submits it. A worker sees the repayment and posts it. A builder
          finishes the job and posts the receipt. Nobody posts their own failure.
        </p>
        <p>
          Such a system does not need to censor bad news. Bad news simply never arrives, because the
          only party watching has no reason to send it.
        </p>
        <p className="strong">
          <code>challengeFailure</code> is callable by any address on earth, and it pays. The bounty
          comes out of the bond of the party that failed, so the cost of being caught falls on
          whoever failed. The party who stands to lose cannot suppress the outcome, because they are
          not the only one who can carry it.
        </p>
      </section>

      <section>
        <p className="eyebrow">What is actually trusted</p>
        <h2>We do not claim to have removed the source of the fact.</h2>
        <p>
          Attestcoin proves what the source chain said. Who is allowed to speak on the source chain
          is an application decision, and pretending otherwise would be the kind of claim that falls
          apart under one question. Here, <code>WorkOracle</code> has a named reporter set, and a
          builder cannot certify their own work: transaction 04 above is that refusal, on chain.
        </p>
        <p>
          What ProveOut removes is everything between the fact and the money. No relayer you have to
          trust. No arbiter. No approval step. And once an outcome exists on the source chain, the
          party it goes against cannot stop it reaching the escrow, because carrying it is open to
          everyone and paying for it is automatic.
        </p>
      </section>

      <section>
        <p className="eyebrow">The gate that matters</p>
        <h2>Inclusion is not success.</h2>
        <pre>
          <code>{`EvmV1Decoder.ReceiptFields memory receipt = ...;
if (receipt.receiptStatus != 1)
    revert ReceiptNotSuccessful(receipt.receiptStatus);`}</code>
        </pre>
        <p>
          The precompile proves a transaction was included in a block. A reverted transaction is in
          the block too. Without this check a builder sends a completion call, lets it revert, proves
          that inclusion completely honestly, and is paid for work that never happened. Every proof
          in that attack is genuine.
        </p>
        <p className="tiny">
          You can see both answers separately on the <Link href="/verify">verify page</Link>: whether
          the precompile accepted the proof, and whether the transaction it proves actually succeeded.
        </p>
      </section>

      <section>
        <p className="eyebrow">Deployed</p>
        <h2>Addresses, if you want to check.</h2>
        <div className="keyvals">
          <div className="kv">
            <dt>Block Prover precompile</dt>
            <dd>
              <a href={`${EXPLORER}/address/${PRECOMPILE}`} target="_blank" rel="noreferrer">
                {PRECOMPILE}
              </a>
            </dd>
          </div>
          <div className="kv">
            <dt>JobEscrow, Creditcoin CC3</dt>
            <dd>
              {deployed ? (
                <a href={`${EXPLORER}/address/${JOB_ESCROW}`} target="_blank" rel="noreferrer">
                  {JOB_ESCROW}
                </a>
              ) : (
                <span className="badge b-mute">not deployed</span>
              )}
            </dd>
          </div>
          <div className="kv">
            <dt>SourceRegistry, Creditcoin CC3</dt>
            <dd>
              <a href={`${EXPLORER}/address/${SOURCE_REGISTRY}`} target="_blank" rel="noreferrer">
                {SOURCE_REGISTRY}
              </a>
            </dd>
          </div>
          <div className="kv">
            <dt>TestUSDC, Creditcoin CC3</dt>
            <dd>
              <a href={`${EXPLORER}/address/${TEST_USDC}`} target="_blank" rel="noreferrer">
                {TEST_USDC}
              </a>
            </dd>
          </div>
          <div className="kv">
            <dt>WorkOracle, Ethereum Sepolia</dt>
            <dd>
              <a href={`${SEPOLIA_EXPLORER}/address/${WORK_ORACLE}`} target="_blank" rel="noreferrer">
                {WORK_ORACLE}
              </a>
            </dd>
          </div>
          <div className="kv">
            <dt>Chain</dt>
            <dd>
              Creditcoin CC3 Testnet, id {CC3_CHAIN_ID}. Source: Ethereum Sepolia, Attestcoin chain
              key {SOURCE_CHAIN_KEY}.
            </dd>
          </div>
        </div>
      </section>

      <section>
        <p className="eyebrow">Boundaries</p>
        <h2>What this does not do.</h2>
        <ul className="limits">
          <li>
            <b>Attestcoin proves inclusion, not exclusion.</b> It can prove a transaction happened.
            It cannot prove that none happened. So ProveOut does not make hiding a failure
            impossible. It makes hiding one detectable and expensive. That is the whole promise of
            the challenge mechanism, and not a word more.
          </li>
          <li>
            <b>The source oracle is trusted within its own scope.</b> Whoever holds a reporter role
            decides what is provable. ProveOut narrows trust to one named contract with a named
            reporter set. It does not eliminate it, and no proof system can.
          </li>
          <li>
            <b>TestUSDC is not USDC.</b> A six decimal demo token with an open mint and no value.
          </li>
          <li>
            <b>Testnet only, and unaudited.</b> Nothing here has had a security review.
          </li>
          <li>
            <b>The bond ratio is a demo parameter</b>, not a modelled economic result. Whether 20
            percent of the job value makes challenging worthwhile is a question this project has not
            answered.
          </li>
          <li>
            <b>Only transaction types 0 and 2 are accepted.</b> Those are the two the shipped decoder
            fully decodes. Anything else is rejected loudly rather than decoded on a guess.
          </li>
        </ul>
      </section>

      <footer>
        <p className="tiny">
          ProveOut. Built for BUIDL CTC 2026 Fall, track AI. Apache-2.0. Settlement on Creditcoin CC3
          Testnet, proofs by Attestcoin Protocol.
        </p>
      </footer>
    </>
  );
}
