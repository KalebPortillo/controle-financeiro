import { useState } from 'react'
import { PluggyConnect } from 'react-pluggy-connect'
import { Button } from '../components/Button'
import { useAppConfig } from '../api/useAppConfig'
import {
  useConnectToken,
  useCreateBankConnection,
  defaultHistorySince,
  type BankConnection,
} from './useBankConnections'

/**
 * Botão "Conectar banco" + fluxo do widget Pluggy Connect.
 *
 * 1. Clique → busca connect_token no backend.
 * 2. Token chega → renderiza o widget (iframe Pluggy).
 * 3. Widget onSuccess({ item }) → POST /bank_connections com o item.id.
 * 4. Fecha o widget + dispara onConnected (pai atualiza lista).
 *
 * includeSandbox liga os bancos de teste fora de produção (RF1 dev usa o
 * "Pluggy Bank" sandbox com user-ok/password-ok).
 */
export function ConnectBankButton({
  onConnected,
}: {
  onConnected?: (connection: BankConnection) => void
}) {
  const connectToken = useConnectToken()
  const createConnection = useCreateBankConnection()
  const { data: appConfig } = useAppConfig()
  const [token, setToken] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)

  const start = async () => {
    setFeedback(null)
    try {
      setToken(await connectToken.mutateAsync())
    } catch {
      setFeedback('Não foi possível iniciar a conexão. Tente de novo.')
    }
  }

  const handleSuccess = async (data: { item: { id: string } }) => {
    setToken(null)
    try {
      const connection = await createConnection.mutateAsync({
        itemId: data.item.id,
        historySince: defaultHistorySince(),
      })
      setFeedback('Banco conectado')
      onConnected?.(connection)
    } catch {
      setFeedback('Conexão criada no banco, mas falhou ao salvar. Tente sincronizar.')
    }
  }

  const busy = connectToken.isPending || createConnection.isPending

  return (
    <>
      <Button
        onClick={start}
        disabled={busy}
        data-testid="connect-bank-button"
      >
        {busy ? 'Conectando…' : 'Conectar banco'}
      </Button>

      {feedback && (
        <p className="text-xs text-muted-foreground mt-2" data-testid="connect-bank-feedback">
          {feedback}
        </p>
      )}

      {token && (
        <PluggyConnect
          connectToken={token}
          // Sandbox-vs-real vem do backend por RAILS_ENV (não de build-time).
          // Em staging: sandbox ligado + connectorIds restrito aos de teste.
          // Em prod: sem sandbox e sem whitelist (todos os bancos reais).
          includeSandbox={appConfig?.pluggy.include_sandbox ?? false}
          connectorIds={appConfig?.pluggy.connector_ids ?? undefined}
          onSuccess={handleSuccess}
          onClose={() => setToken(null)}
          onError={() => {
            setToken(null)
            setFeedback('Conexão cancelada ou falhou.')
          }}
        />
      )}
    </>
  )
}
