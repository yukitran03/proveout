import {
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

function StatusBadge({ status }: { status: number }) {
  const cls =
    status === 3 ? 'b-go' : status === 4 ? 'b-dead' : status === 2 ? 'b-warn' : 'b-mute';
  return <span className={`badge ${cls}`}>{STATUS[status] ?? 'unknown'}</span>;
}

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
    <main className="wrap">
      <section style={{ paddingTop: 8 }}>
        <div className="eyebrow">Live from Creditcoin CC3 Testnet</div>
        <h1 style={{ fontSize: 32 }}>Escrow console</h1>
        <p className="lede" style={{ fontSize: 15.5 }}>
          Every row is read from chain logs at request time. There is no indexer, no cache and no
          fixture file behind this page: it shows what the chain says, or it shows nothing.
        </p>
      </section>

      {!JOB_ESCROW && (
        <div className="note n-warn">
          <b>No deployment configured.</b> Set <span className="mono">NEXT_PUBLIC_JOB_ESCROW</span>{' '}
          once the contracts are deployed to CC3 Testnet. This page deliberately shows nothing rather
          than sample data — a console that invents rows is worse than an empty one.
        </div>
      )}

      {error && (
        <div className="note n-dead">
          <b>Could not read the chain.</b> <span className="mono">{error}</span>
        </div>
      )}

      {vault && (
        <section>
          <div className="grid3">
            <div className="stat">
              <div className="k">Taken into escrow</div>
              <div className="v">{usdc(vault.totalIn)} tUSDC</div>
            </div>
            <div className="stat">
              <div className="k">Paid out</div>
              <div className="v">{usdc(vault.totalOut)} tUSDC</div>
            </div>
            <div className="stat">
              <div className="k">Vault invariant</div>
              <div className="v" style={{ color: vault.solvent ? 'var(--go)' : 'var(--dead)' }}>
                {vault.solvent ? 'HOLDS' : 'BROKEN'}
              </div>
            </div>
          </div>
          <p style={{ color: 'var(--ink-3)', fontSize: 13, marginTop: 10 }}>
            Bond {vault.bondBps / 100}% of the job amount · challenger takes {vault.bountyBps / 100}%
            of that bond · invariant is{' '}
            <span className="mono">balance + paidOut &gt;= takenIn</span>, an inequality so an
            unsolicited transfer into the vault cannot wedge it.
          </p>
        </section>
      )}

      <section>
        <h2>Jobs</h2>
        {JOB_ESCROW && jobs.length === 0 && !error && (
          <div className="note n-warn">
            No <span className="mono">JobCreated</span> events in the scanned range yet.
          </div>
        )}
        {jobs.length > 0 && (
          <div className="tablewrap">
            <table>
              <thead>
                <tr>
                  <th>Job</th>
                  <th>Status</th>
                  <th>Amount</th>
                  <th>Bond</th>
                  <th>Builder</th>
                  <th>Deadline</th>
                  <th>Created</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((j) => (
                  <tr key={j.jobId}>
                    <td className="mono">{short(j.jobId, 8)}</td>
                    <td>
                      <StatusBadge status={j.status} />
                    </td>
                    <td className="mono">{usdc(j.amount)}</td>
                    <td className="mono">{usdc(j.bond)}</td>
                    <td className="mono">
                      <a
                        href={`${EXPLORER}/address/${j.builder}`}
                        target="_blank"
                        rel="noreferrer"
                      >
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
        )}
      </section>

      <section>
        <h2>How a job settles</h2>
        <div className="grid3">
          <div className="card">
            <span className="step-n">ACTION 0</span>
            <h3>Release</h3>
            <p>
              Prove <span className="mono">WorkCompleted</span> from the registered Sepolia oracle,
              inside the deadline, in a transaction whose receipt status is 1. The builder is paid
              the amount and gets the bond back.
            </p>
          </div>
          <div className="card">
            <span className="step-n">ACTION 1</span>
            <h3>Challenge</h3>
            <p>
              Prove <span className="mono">WorkFailed</span> for the job. Callable by any address,
              at any time, including after the deadline. The buyer is refunded and the submitter
              takes a bounty from the bond.
            </p>
          </div>
          <div className="card">
            <span className="step-n">FALLBACK</span>
            <h3>Refund</h3>
            <p>
              After the deadline with no release, the buyer takes back the amount and the bond. The
              release and refund windows never overlap, so there is no ordering race.
            </p>
          </div>
        </div>
      </section>

      <footer>
        Reading <span className="mono">{JOB_ESCROW ? short(JOB_ESCROW, 10) : 'no contract'}</span> on
        Creditcoin CC3 Testnet (chain id 102031).
      </footer>
    </main>
  );
}
