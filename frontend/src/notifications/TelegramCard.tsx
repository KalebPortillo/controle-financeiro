import { useState } from 'react'
import { Send } from 'lucide-react'
import { Card, CardBody, CardHeader } from '../components/Card'
import { Button } from '../components/Button'
import {
  useTelegramLink,
  useCreateTelegramLink,
  useUnlinkTelegram,
} from './useTelegramLink'

/**
 * Cartão "Telegram" (RF17, /mais): vincula o grupo do casal pra receber os
 * avisos por lá. Fluxo: Conectar → abre o deep-link (startgroup) → card faz
 * polling até o webhook confirmar o vínculo.
 */
export function TelegramCard() {
  const [waiting, setWaiting] = useState(false)
  const { data } = useTelegramLink(waiting)
  const createLink = useCreateTelegramLink()
  const unlink = useUnlinkTelegram()

  if (data?.linked && waiting) setWaiting(false)

  async function onConnect() {
    const { deep_link } = await createLink.mutateAsync()
    window.open(deep_link, '_blank', 'noopener')
    setWaiting(true)
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="font-sans text-sm font-medium">Notificações no Telegram</h2>
        <p className="text-xs text-muted-foreground">
          Avisos de sync, gastos novos e recorrentes atrasadas no grupo de vocês.
        </p>
      </CardHeader>

      <CardBody className="pt-0 space-y-3">
        {data?.linked ? (
          <div className="flex items-center justify-between gap-3">
            <div className="leading-tight min-w-0">
              <div className="text-xs font-medium text-foreground truncate" data-testid="telegram-status">
                Vinculado ao grupo {data.chat_title ?? '—'}
              </div>
              {data.linked_at && (
                <div className="text-[11px] text-muted-foreground">
                  desde {new Date(data.linked_at).toLocaleDateString('pt-BR')}
                </div>
              )}
            </div>
            <Button
              variant="outline"
              size="md"
              onClick={() => unlink.mutate()}
              disabled={unlink.isPending}
              data-testid="telegram-unlink"
            >
              Desvincular
            </Button>
          </div>
        ) : waiting ? (
          <p className="text-xs text-muted-foreground" data-testid="telegram-waiting">
            Aguardando vinculação… No Telegram, escolha o grupo e envie o comando
            que aparece ao adicionar o bot.
          </p>
        ) : (
          <Button
            size="md"
            onClick={onConnect}
            disabled={createLink.isPending}
            data-testid="telegram-connect"
          >
            <Send size={14} />
            {createLink.isPending ? 'Gerando link…' : 'Conectar Telegram'}
          </Button>
        )}
      </CardBody>
    </Card>
  )
}
