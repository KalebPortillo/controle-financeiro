import { CreditCard, Landmark, type LucideIcon } from 'lucide-react'
import type { InboxTransaction } from './useInbox'

const KIND_ICON: Record<string, LucideIcon> = {
  credit_card: CreditCard,
  checking: Landmark,
}

type Source = Pick<
  InboxTransaction,
  'account_kind' | 'institution_label' | 'account_name' | 'account_institution_name' | 'account_brand' | 'account_last_digits' | 'card_last_digits'
>

/**
 * Fonte do gasto (RF2.7): ícone + banco + cartão/conta —
 *   cartão: "Nubank · Mastercard 5190" (banco · bandeira dígitos)
 *   conta:  "Inter · conta corrente"
 * Banco = nome real do conector (account_institution_name); cai para o
 * institution_label e depois o account_name quando faltar. Os dígitos preferem
 * o cartão DA COMPRA (card_last_digits — cartões virtuais Nubank), caindo pro
 * número da conta (account_last_digits).
 */
export function AccountTag({ t, size = 12 }: { t: Source; size?: number }) {
  const Icon = (t.account_kind && KIND_ICON[t.account_kind]) ?? Landmark
  const bank = t.account_institution_name ?? t.institution_label ?? t.account_name ?? '—'

  let detail: string
  if (t.account_kind === 'credit_card') {
    const brand = t.account_brand ?? 'cartão'
    const last4 = t.card_last_digits ?? t.account_last_digits
    detail = last4 ? `${brand} ${last4}` : brand
  } else if (t.account_kind === 'checking') {
    detail = 'conta corrente'
  } else {
    detail = ''
  }

  return (
    <span className="inline-flex items-center gap-1.5 min-w-0" data-testid="account-tag">
      <Icon size={size} className="shrink-0" />
      <span className="truncate">{detail ? `${bank} · ${detail}` : bank}</span>
    </span>
  )
}
