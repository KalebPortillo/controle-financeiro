type Props = { className?: string; size?: number }

/**
 * Marca do PortilhoWallet — um veleiro ("portilho" = pequeno porto). Casco,
 * mastro e bujarrona herdam a cor via `currentColor` (use com `text-foreground`);
 * a vela mestra carrega o único acento (`var(--accent)`, que flipa por tema).
 * Source: design-system/project/assets/logo.svg.
 */
export function WalletLogo({ className = '', size = 28 }: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 32 32"
      fill="currentColor"
      width={size}
      height={size}
      className={className}
      aria-label="PortilhoWallet"
    >
      <rect x="14.6" y="4.6" width="1.8" height="17.4" fill="currentColor" />
      <path d="M17.4 5.4 24.4 19H17.4z" fill="var(--accent)" />
      <path d="M13.8 8.6 9 19h4.8z" fill="currentColor" />
      <path d="M5 21.6h22l-2.6 5.2a2 2 0 0 1-1.8 1.1H9.4a2 2 0 0 1-1.8-1.1z" fill="currentColor" />
    </svg>
  )
}
