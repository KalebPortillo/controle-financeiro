import { useQueryClient } from '@tanstack/react-query'
import { useChannelSubscription } from '../api/useChannelSubscription'
import { dropFromInbox } from './useInbox'

type TransactionUpdatedMessage = {
  event: string
  id: string
  status: string
}

/**
 * Assina o TransactionsChannel (RF2.3) e reflete decisões de outros membros em
 * tempo real: quando alguém consolida/rejeita um gasto (na web ou no Telegram),
 * o item some da minha inbox sem refresh. Evita a tela velha do "semáforo" no
 * uso simultâneo (casal). Escopado pelo workspace ativo.
 */
export function useTransactionsChannel(workspaceId: string | null | undefined) {
  const qc = useQueryClient()

  useChannelSubscription<TransactionUpdatedMessage>('TransactionsChannel', workspaceId, (data) => {
    if (data?.event !== 'transaction_updated') return
    // Saiu de "pending" (consolidado/rejeitado por outro canal) → tira da inbox.
    if (data.status !== 'pending') dropFromInbox(qc, [data.id])
  })
}
