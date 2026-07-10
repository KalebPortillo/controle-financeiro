import { Repeat } from 'lucide-react'
import { toast } from 'sonner'
import { ApiError } from '../api/client'
import {
  useCreateRecurrenceFromTransaction,
  useExcludeTransaction,
} from '../recurrences/useRecurrences'
import type { InboxTransaction } from './useInbox'

/**
 * RF9.7 — marca um gasto consolidado como recorrente e mostra, no detalhe,
 * quando ele já pertence a uma recorrência (com a opção de removê-lo do grupo).
 * O backend semeia a recorrência a partir do gasto (descritor + palpite de
 * cadência/valor) e agrupa os relacionados. Só faz sentido para débitos.
 */
export function RecurringSection({ transaction: t }: { transaction: InboxTransaction }) {
  const create = useCreateRecurrenceFromTransaction()
  const exclude = useExcludeTransaction(t.recurrence?.id ?? '')
  if (t.direction !== 'debit') return null

  const markRecurring = async () => {
    try {
      await create.mutateAsync(t.id)
      toast.success('Marcada como recorrente', {
        description: 'Gastos parecidos foram agrupados em Recorrentes',
      })
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : 'Erro ao marcar como recorrente')
    }
  }

  const removeFromRecurrence = async () => {
    try {
      await exclude.mutateAsync(t.id)
      toast.success('Removida da recorrência')
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : 'Erro ao remover da recorrência')
    }
  }

  // Já está em uma recorrência: sinaliza e permite tirar do grupo.
  if (t.recurrence) {
    return (
      <div className="mt-2 pt-3.5 border-t border-border flex items-center justify-between gap-2">
        <span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
          <Repeat size={13} className="text-accent" /> Está em Recorrentes
        </span>
        <button
          type="button"
          onClick={removeFromRecurrence}
          disabled={exclude.isPending}
          data-testid={`remove-recurring-${t.id}`}
          className="text-sm text-muted-foreground hover:text-foreground hover:underline disabled:opacity-50"
        >
          Remover
        </button>
      </div>
    )
  }

  return (
    <div className="mt-2 pt-3.5 border-t border-border">
      <button
        type="button"
        onClick={markRecurring}
        disabled={create.isPending}
        data-testid={`mark-recurring-${t.id}`}
        className="inline-flex items-center gap-1.5 text-sm text-foreground hover:underline disabled:opacity-50"
      >
        <Repeat size={13} className="text-muted-foreground" /> Marcar como recorrente
      </button>
    </div>
  )
}
