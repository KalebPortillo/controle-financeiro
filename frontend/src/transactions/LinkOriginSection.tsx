import { useState } from 'react'
import { Link2, Search } from 'lucide-react'
import { Money } from '../components/Money'
import { useDebounced } from '../app/useDebounced'
import { useLinkCandidates, useLinkTransaction } from './useTransactionLinks'
import { RELATION_LABEL } from './relationType'
import { displayTitle, formatDayMonth } from './display'
import type { InboxTransaction, RelatedItem } from './useInbox'

const TYPES: RelatedItem['relation_type'][] = ['iof', 'fee', 'interest', 'adjustment']

/**
 * RF23 Fase 3 — vínculo manual: marca ESTA transação (satélite órfão: tarifa,
 * juros, ajuste, IOF não detectado) como relacionada a um gasto de origem.
 * Escolhe o tipo, busca a origem na mesma conta e vincula. Some quando a
 * transação já tem uma origem (já é satélite) — aí a origem aparece na seção
 * "Relacionadas".
 */
export function LinkOriginSection({ transaction: t }: { transaction: InboxTransaction }) {
  const [open, setOpen] = useState(false)
  const [type, setType] = useState<RelatedItem['relation_type']>('fee')
  const [q, setQ] = useState('')
  const debouncedQ = useDebounced(q, 250)
  const { data: candidates, isLoading } = useLinkCandidates(t.id, debouncedQ, open)
  const link = useLinkTransaction()

  // Já é satélite de algum gasto? Não oferece vincular de novo.
  const alreadyLinked = (t.related ?? []).some((r) => r.role === 'origin')
  if (alreadyLinked) return null

  const pick = (originId: string) =>
    link.mutate(
      { id: t.id, origin_id: originId, relation_type: type },
      { onSuccess: () => setOpen(false) },
    )

  return (
    <div className="mt-2 pt-3.5 border-t border-border space-y-2" data-testid="link-origin-section">
      {!open && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="inline-flex items-center gap-1.5 text-sm text-foreground hover:underline"
          data-testid="link-origin-open"
        >
          <Link2 size={13} /> Vincular a um gasto de origem
        </button>
      )}

      {open && (
        <div className="space-y-2.5">
          <div className="flex items-center gap-1.5">
            {TYPES.map((rt) => (
              <button
                key={rt}
                type="button"
                onClick={() => setType(rt)}
                data-testid={`link-type-${rt}`}
                className={`h-7 px-2.5 rounded-md border text-xs transition-colors ${
                  type === rt
                    ? 'border-accent bg-accent/10 text-accent'
                    : 'border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {RELATION_LABEL[rt]}
              </button>
            ))}
          </div>

          <div className="relative flex items-center">
            <Search size={13} className="absolute left-2.5 text-muted-foreground pointer-events-none" />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Buscar o gasto de origem…"
              data-testid="link-origin-search"
              aria-label="Buscar gasto de origem"
              className="h-8 w-full rounded-md border border-input bg-background pl-8 pr-2 text-sm text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
            />
          </div>

          {isLoading && <p className="text-xs text-muted-foreground">Buscando…</p>}
          {!isLoading && (candidates?.length ?? 0) === 0 && (
            <p className="text-xs text-muted-foreground" data-testid="link-origin-empty">
              Nenhum gasto encontrado nesta conta.
            </p>
          )}
          <ul className="space-y-1.5 max-h-56 overflow-y-auto">
            {candidates?.map((c) => (
              <li key={c.id}>
                <button
                  type="button"
                  onClick={() => pick(c.id)}
                  disabled={link.isPending}
                  data-testid={`link-candidate-${c.id}`}
                  className="w-full flex items-center justify-between gap-2 rounded-md border border-border px-3 py-2 text-left hover:bg-muted disabled:opacity-50"
                >
                  <span className="min-w-0">
                    <span className="block text-sm truncate">{displayTitle(c)}</span>
                    <span className="block text-[11px] text-muted-foreground tabular-nums">
                      {formatDayMonth(c.occurred_at)}
                    </span>
                  </span>
                  <Money cents={c.amount_cents} className="text-sm shrink-0" />
                </button>
              </li>
            ))}
          </ul>

          <button
            type="button"
            onClick={() => setOpen(false)}
            className="text-xs text-muted-foreground hover:text-foreground underline"
          >
            Cancelar
          </button>
        </div>
      )}
    </div>
  )
}
