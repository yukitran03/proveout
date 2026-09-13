import type { Metadata } from 'next';
import Link from 'next/link';
import './globals.css';

export const metadata: Metadata = {
  title: 'ProveOut — escrow settled by proof',
  description:
    'Job escrow on Creditcoin CC3, released or refunded by a Sepolia event proved on-chain by Attestcoin. No oracle operator, no arbiter.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <nav>
          <div className="inner">
            <Link className="brand" href="/">
              ProveOut
            </Link>
            <span className="spacer" />
            <Link className="link" href="/">
              Overview
            </Link>
            <Link className="link" href="/console">
              Console
            </Link>
            <a
              className="link"
              href="https://creditcoin-testnet.blockscout.com"
              target="_blank"
              rel="noreferrer"
            >
              Explorer ↗
            </a>
          </div>
        </nav>
        {children}
      </body>
    </html>
  );
}
