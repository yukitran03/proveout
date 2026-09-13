import {
  CC3_CHAIN_ID,
  EXPLORER,
  JOB_ESCROW,
  STATUS,
  fetchJobs,
  fetchVault,
  short,
  usdc,
  type JobRow,
} from '../../lib/chain';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

const BADGE_FOR: Record<number, string> = { 3: 'b-proved', 4: 'b-refused', 2: 'b-pending' };

export default async function Console() {
  let jobs: JobRow[] = [];
  let vault: Awaited<ReturnType<typeof fetchVault>> = null;
  let error: string | null = null;

  if (JOB_ESCROW) {
    try {
      [jobs, vault] = await Promise.all([fetchJobs(), fetchVault()]);
    } catch (e: any) {
      error = e?.shortMessage ?? e?.message ?? 'failed to read Creditcoin CC3';
    }
  }

  return (
    <>
      <section>
        <p className="eyebrow">Live from Creditcoin CC3 Testnet</p>
        <h1>Escrow ledger</h1>
        <p>
          Every figure below is read from chain logs when this page loads. No indexer, no cache, no
          fixture file. It shows what the chain says, or it shows nothing.
        </p>
      </section>

      {!JOB_ESCROW ? (
        <section>
          <div className="note caution">
            <b>No deployment configured.</b>
            Run <code>npm run finalize</code> after deploying. This page shows nothing rather than
            sample rows, because a console that invents data is worse than an empty one.
          </div>
        </section>
      ) : null}

      {error ? (
        <section>
          <div className="note limit">
            <b>Could not read the chain.</b>
            <span className="mono">{error}</span>
          </div>
        </section>
      ) : null}

      {vault ? (
        <section>
          <p className="eyebrow">Vault</p>
          <h2>What went in, what went out.</h2>
          <div className="stats">
            <div className="stat">
              <div className="k">Taken into escrow</div>
              <div className="v">{usdc(vault.totalIn)}</div>
            </div>
            <div className="stat">
              <div className="k">Paid out</div>
              <div className="v">{usdc(vault.totalOut)}</div>
            </div>
            <div className="stat">
              <div className="k">Balance rule</div>
              <div
                className="v"
                style={{ color: vault.solvent ? 'var(--proved)' : 'var(--refused)' }}
              >
                {vault.solvent ? 'HOLDS' : 'BROKEN'}
              </div>
            </div>
          </div>
          <p className="tiny">
            Builder bond is {vault.bondBps / 100} percent of the job amount. A successful challenger
            takes {vault.bountyBps / 100} percent of that bond. The rule is{' '}
            <code>balance + paidOut &gt;= takenIn</code>, an inequality rather than an equality, so
            an unsolicited transfer into the vault cannot wedge it.
          </p>
        </section>
      ) : null}

      <section>
        <p className="eyebrow">Jobs</p>
        <h2>Every job this escrow has held.</h2>

        {JOB_ESCROW && jobs.length === 0 && !error ? (
          <div className="note caution">
            <b>Nothing yet.</b>
            No <code>JobCreated</code> events in the scanned range.
          </div>
        ) : null}

        {jobs.length > 0 ? (
          <div className="tablewrap">
            <table>
              <thead>
                <tr>
                  <th>Job</th>
                  <th>Status</th>
                  <th style={{ textAlign: 'right' }}>Amount</th>
                  <th style={{ textAlign: 'right' }}>Bond</th>
                  <th>Builder</th>
                  <th>Deadline</th>
                  <th>Opened</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((j) => (
                  <tr key={j.jobId}>
                    <td className="mono">{short(j.jobId, 8)}</td>
                    <td>
                      <span className={`badge ${BADGE_FOR[j.status] ?? 'b-mute'}`}>
                        {STATUS[j.status] ?? 'unknown'}
                      </span>
                    </td>
                    <td className="num">{usdc(j.amount)}</td>
                    <td className="num">{usdc(j.bond)}</td>
                    <td className="mono">
                      <a href={`${EXPLORER}/address/${j.builder}`} target="_blank" rel="noreferrer">
                        {short(j.builder)}
                      </a>
                    </td>
                    <td className="mono">
                      {new Date(j.deadline * 1000).toISOString().slice(0, 16).replace('T', ' ')}
                    </td>
                    <td className="mono">
                      <a href={`${EXPLORER}/tx/${j.createdTx}`} target="_blank" rel="noreferrer">
                        {short(j.createdTx)}
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </section>

      <section>
        <p className="eyebrow">How a job leaves escrow</p>
        <h2>Three exits, and only one of them needs you.</h2>
        <div className="cols">
          <div className="col">
            <span className="n">ACTION 0</span>
            <h3>Release</h3>
            <p>
              Prove <code>WorkCompleted</code> from the registered Sepolia oracle, inside the
              deadline, in a transaction whose receipt status is 1. The builder is paid the amount
              and gets the bond back.
            </p>
          </div>
          <div className="col">
            <span className="n">ACTION 1</span>
            <h3>Challenge</h3>
            <p>
              Prove <code>WorkFailed</code> for the job. Callable by any address, at any time,
              including after the deadline. The buyer is refunded and the submitter takes a bounty
              from the bond.
            </p>
          </div>
          <div className="col">
            <span className="n">FALLBACK</span>
            <h3>Refund</h3>
            <p>
              After the deadline with no release, the buyer takes back the amount and the bond. The
              release and refund windows never overlap, so there is no ordering race.
            </p>
          </div>
        </div>
      </section>

      <footer>
        <p className="tiny">
          Reading <span className="mono">{JOB_ESCROW ? short(JOB_ESCROW, 10) : 'no contract'}</span>{' '}
          on Creditcoin CC3 Testnet, chain id {CC3_CHAIN_ID}.
        </p>
        <p className="tiny">
          Interface adapted from{' '}
          <a href="https://github.com/hien-p/nymspace" target="_blank" rel="noreferrer">
            nymspace
          </a>{' '}
          by Maverick Trinh, MIT.
        </p>
      </footer>
    </>
  );
}
