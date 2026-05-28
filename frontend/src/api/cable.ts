import { createConsumer, type Consumer } from '@rails/actioncable'

/**
 * Consumer singleton do Action Cable. Conecta em /cable (mesmo host; o Vite
 * faz proxy em dev). A autenticação é via cookie de sessão — o browser manda
 * o cookie no handshake do WebSocket automaticamente, sem header extra.
 */
let consumer: Consumer | null = null

export function getCableConsumer(): Consumer {
  if (!consumer) consumer = createConsumer('/cable')
  return consumer
}
