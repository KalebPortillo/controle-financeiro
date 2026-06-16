import { useEffect, useRef } from 'react'
import { getCableConsumer } from './cable'

/**
 * Assina um canal do Action Cable escopado pelo workspace ativo e entrega cada
 * mensagem ao handler. Reúne o esqueleto comum dos hooks de tempo real
 * (subscribe → received → unsubscribe no cleanup) — cada hook só fornece o
 * nome do canal e o que fazer com a mensagem.
 *
 * O handler fica num ref: pode ser uma closure nova a cada render (lê estado
 * fresco) sem reabrir o WebSocket. A subscription só é recriada quando muda o
 * canal ou o workspace.
 */
export function useChannelSubscription<TMessage>(
  channel: string,
  workspaceId: string | null | undefined,
  onMessage: (data: TMessage) => void
) {
  const handlerRef = useRef(onMessage)

  // Mantém o ref apontando pro handler mais recente sem reabrir a subscription.
  useEffect(() => {
    handlerRef.current = onMessage
  })

  useEffect(() => {
    if (!workspaceId) return

    const subscription = getCableConsumer().subscriptions.create(
      { channel, workspace_id: workspaceId },
      {
        received(data: TMessage) {
          handlerRef.current(data)
        },
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [channel, workspaceId])
}
