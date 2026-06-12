import { Download, Share, SquarePlus, Smartphone } from 'lucide-react'
import { Card, CardBody, CardHeader } from '../components/Card'
import { Button } from '../components/Button'
import { useInstallPrompt } from './useInstallPrompt'

/**
 * Card "Instalar app" — adiciona o PWA à tela inicial do celular. No
 * Android/Chrome usa o prompt nativo; no iOS, onde não há prompt programático,
 * mostra as instruções manuais (Compartilhar → Adicionar à Tela de Início).
 * Some quando o app já está rodando instalado (standalone).
 */
export function InstallAppCard() {
  const { isStandalone, isIOS, canPrompt, promptInstall } = useInstallPrompt()

  if (isStandalone) return null

  return (
    <Card>
      <CardHeader>
        <h2 className="font-sans text-sm font-medium flex items-center gap-2">
          <Smartphone size={16} className="text-accent" />
          Instalar app
        </h2>
        <p className="text-xs text-muted-foreground">
          Adicione à tela inicial pra abrir como um app, em tela cheia e sem a barra do navegador.
        </p>
      </CardHeader>
      <CardBody className="pt-0">
        {canPrompt ? (
          <Button onClick={promptInstall} data-testid="install-pwa">
            <Download size={16} />
            Instalar
          </Button>
        ) : isIOS ? (
          <ol className="space-y-2 text-sm text-muted-foreground">
            <li className="flex items-center gap-2">
              <Share size={16} className="shrink-0 text-foreground" />
              Toque em Compartilhar na barra do Safari
            </li>
            <li className="flex items-center gap-2">
              <SquarePlus size={16} className="shrink-0 text-foreground" />
              Escolha Adicionar à Tela de Início
            </li>
          </ol>
        ) : (
          <p className="text-sm text-muted-foreground">
            No menu do navegador, escolha Instalar app ou Adicionar à tela inicial.
          </p>
        )}
      </CardBody>
    </Card>
  )
}
