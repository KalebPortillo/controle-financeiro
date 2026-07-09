import { Repeat } from 'lucide-react'
import { toast } from 'sonner'
import { ApiError } from '../api/client'
import { useCreateRecurrenceFromTransaction } from '../recurrences/useRecurrences'
import type { InboxTransaction } from './useInbox'

/**
 * RF9.7 — marca um gasto consolidado como recorrente. O backend semeia a
 * recorrência a partir do gasto (descritor + palpite de cadência/valor) e já
 * agrupa os relacionados; itens avulsos podem ser removidos no detalhe da
 * recorrência. Só faz sentido para débitos (gastos).
 */
export function RecurringSection({ transaction: t }: { transaction: InboxTransaction }) {
  const create = useCreateRecurrenceFromTransaction()
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
