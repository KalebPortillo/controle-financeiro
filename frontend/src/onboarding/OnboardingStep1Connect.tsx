import { useEffect } from 'react'
import { Building2, Upload } from 'lucide-react'
import { Button } from '../components/Button'
import { ConnectBankButton } from '../bank/ConnectBankButton'
import { useStartOnboarding, type OnboardingState } from './useOnboarding'

/**
 * Passo 1 do onboarding (RF22.5.1–5.4) — conectar fonte de dados.
 * Quando o sync termina, o backend transiciona connecting→analyzing e o
 * frontend avança automaticamente pro passo 2 (análise IA).
 */
export function OnboardingStep1Connect({ state }: { state: OnboardingState }) {
  const start = useStartOnboarding()

  // Marca como connecting na primeira vez que o usuário chega aqui.
  // Idempotente do lado do backend.
  useEffect(() => {
    if (state.status === 'not_started') {
      start.mutate()
    }
  }, [state.status, start])

  return (
    <div className="space-y-6" data-testid="onboarding-step-1">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Conectar sua conta</h1>
        <p className="text-sm text-muted-foreground">
          A gente vai buscar seus gastos pra pré-categorizar tudo com IA antes
          de você revisar.
        </p>
      </div>

      <div className="space-y-3">
        <ConnectBankCard />
        <ImportCsvCardDisabled />
      </div>
    </div>
  )
}

function ConnectBankCard() {
  return (
    <div className="border border-border rounded-md p-4">
      <div className="flex items-start gap-3">
        <div className="h-9 w-9 rounded-md bg-accent/10 text-accent flex items-center justify-center shrink-0">
          <Building2 size={18} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">Conectar banco via Pluggy</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Conexão segura. Suportamos os principais bancos brasileiros.
          </p>
          <div className="mt-3">
            <ConnectBankButton />
          </div>
        </div>
      </div>
    </div>
  )
}

function ImportCsvCardDisabled() {
  return (
    <div className="border border-border rounded-md p-4 opacity-60">
      <div className="flex items-start gap-3">
        <div className="h-9 w-9 rounded-md bg-muted text-muted-foreground flex items-center justify-center shrink-0">
          <Upload size={18} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">Importar arquivo</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Em breve — CSV e OFX exportados do seu banco.
          </p>
          <div className="mt-3">
            <Button variant="outline" size="sm" disabled>
              Em breve
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}

