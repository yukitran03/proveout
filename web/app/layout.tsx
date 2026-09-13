import type { Metadata } from 'next';
import Link from 'next/link';
import { EXPLORER } from '../lib/chain';
import './globals.css';

export const metadata: Metadata = {
  title: 'ProveOut',
  description:
    'Job escrow on Creditcoin CC3, released or refunded by an Ethereum Sepolia event proved on chain by Attestcoin. No oracle operator, no arbiter.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400;500&family=Geist:wght@400;500;600&display=swap"
        />
      </head>
      <body>
        <div className="wrap">
          <header className="topbar">
            <Link className="brand" href="/">
              ProveOut
            </Link>
            <nav>
              <Link href="/">Overview</Link>
              <Link href="/console">Console</Link>
              <Link href="/verify">Verify</Link>
              <a href={EXPLORER} target="_blank" rel="noreferrer">
                Explorer
              </a>
            </nav>
          </header>
          {children}
        </div>
      </body>
    </html>
  );
}
