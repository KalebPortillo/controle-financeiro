import { CreditCard, Landmark, type LucideIcon } from 'lucide-react'

const KIND_ICON: Record<string, LucideIcon> = {
  credit_card: CreditCard,
  checking: Landmark,
}

const KIND_LABEL: Record<string, string> = {
  credit_card: 'cartão',
  checking: 'conta',
}

/**
 * Fonte do gasto (RF2.7): ícone + instituição + tipo da conta —
 * ex.: [cartão] "Nubank · cartão", [conta] "Inter · conta". Cai para o
 * account_name quando não há instituição mapeada (ex.: conta manual).
 */
export function AccountTag({
  kind,
  institutionLabel,
  accountName,
  size = 12,
}: {
  kind: 'checking' | 'credit_card' | null
  institutionLabel: string | null
  accountName: string | null
  size?: number
}) {
  const Icon = (kind && KIND_ICON[kind]) ?? Landmark
  const source = institutionLabel ?? accountName ?? '—'
  const label = kind ? `${source} · ${KIND_LABEL[kind]}` : source

  return (
    <span className="inline-flex items-center gap-1.5 min-w-0" data-testid="account-tag">
      <Icon size={size} className="shrink-0" />
      <span className="truncate">{label}</span>
    </span>
  )
}
