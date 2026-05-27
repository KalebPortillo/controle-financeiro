type Props = { className?: string; size?: number }

/**
 * Wallet logo do Controle Financeiro. Mono, herda cor via currentColor —
 * use com `text-foreground` ou `text-accent` pra pintar.
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
      aria-label="Controle Financeiro"
    >
      <path d="M6 8 H 21 L 28 15 V 25 A 3 3 0 0 1 25 28 H 6 A 3 3 0 0 1 3 25 V 11 A 3 3 0 0 1 6 8 Z" />
      <circle cx="22.5" cy="19" r="2.25" fill="var(--card)" />
    </svg>
  )
}
