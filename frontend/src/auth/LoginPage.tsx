import { Card, CardBody } from '../components/Card'
import { buttonClass } from '../components/buttonClass'
import { WalletLogo } from '../components/WalletLogo'

/**
 * Tela de login. Card centralizado, Linear-style. Botão é um <a> que envia
 * o browser pra /api/v1/auth/google_oauth2 — o middleware OmniAuth no Rails
 * cuida do handshake e redireciona pra raiz com a sessão setada.
 */
export function LoginPage({ error }: { error?: string | null }) {
  return (
    <main className="min-h-screen bg-background text-foreground flex items-center justify-center px-4">
      <Card className="w-full max-w-sm">
        <CardBody className="flex flex-col items-center gap-5 py-8">
          <WalletLogo size={36} className="text-foreground" />
          <div className="text-center space-y-1">
            <h1 className="font-display text-lg font-semibold tracking-tight">
              Portilho<span className="text-accent">Wallet</span>
            </h1>
            <p className="text-xs text-muted-foreground">
              Visão compartilhada dos seus gastos do casal
            </p>
          </div>

          {error && (
            <div
              role="alert"
              className="w-full rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 text-xs text-destructive"
            >
              Não foi possível entrar. Tente novamente.
            </div>
          )}

          <a
            href="/api/v1/auth/google_oauth2"
            data-testid="google-login"
            className={buttonClass({ size: 'lg', className: 'w-full' })}
          >
            Entrar com Google
          </a>

          <p className="text-[11px] text-muted-foreground text-center leading-relaxed">
            Acesso por convite — só os emails autorizados pelo workspace conseguem entrar.
          </p>
        </CardBody>
      </Card>
    </main>
  )
}
