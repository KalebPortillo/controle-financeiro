import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { getCableConsumer } from '../api/cable'
import {
  bankConnectionsKey,
  type BankConnection,
  type BankConnectionsList,
  type ConnectionsSummary,
} from './useBankConnections'

type ConnectionUpdatedMessage = {
  event: string
  bank_connection: BankConnection
}

// Espelha o summary agregado do backend (error inclui expired).
function summarize(connections: BankConnection[]): ConnectionsSummary {
  return {
    total:     connections.length,
    connected: connections.filter((c) => c.status === 'connected').length,
    syncing:   connections.filter((c) => c.status === 'syncing').length,
    error:     connections.filter((c) => c.status === 'error' || c.status === 'expired').length,
  }
}

/**
 * Assina o BankConnectionsChannel (RF21.3) e funde cada `connection_updated`
 * no cache do TanStack Query — o painel reflete o progresso do sync em tempo
 * real, sem polling. Escopado pelo workspace ativo.
 */
export function useBankConnectionsChannel(workspaceId: string | null | undefined) {
  const qc = useQueryClient()

  useEffect(() => {
    if (!workspaceId) return

    const subscription = getCableConsumer().subscriptions.create(
      { channel: 'BankConnectionsChannel', workspace_id: workspaceId },
      {
        received(data: ConnectionUpdatedMessage) {
          if (data?.event !== 'connection_updated') return
          qc.setQueryData<BankConnectionsList>(bankConnectionsKey, (prev) => {
            if (!prev) return prev
            const exists = prev.connections.some((c) => c.id === data.bank_connection.id)
            const connections = exists
              ? prev.connections.map((c) =>
                  c.id === data.bank_connection.id ? data.bank_connection : c
                )
              : [ ...prev.connections, data.bank_connection ]
            return { connections, summary: summarize(connections) }
          })
        },
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [workspaceId, qc])
}
