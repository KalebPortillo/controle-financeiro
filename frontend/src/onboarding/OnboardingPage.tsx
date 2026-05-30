import { useEffect } from 'react'
import { useNavigate } from 'react-router'
import { OnboardingShell } from './OnboardingShell'
import { OnboardingStep1Connect } from './OnboardingStep1Connect'
import { useOnboarding } from './useOnboarding'

/**
 * Container da rota /onboarding (RF22).
 *
 * Lê o estado atual do backend e renderiza o passo correspondente.
 * Fatia 2: só passo 1 (Connect). Passos 2 e 3 entram na Fatia 4.
 */
export function OnboardingPage() {
  const { data, isLoading, isError } = useOnboarding()
  const navigate = useNavigate()

  // Estado terminal — sai do fluxo.
  useEffect(() => {
    if (data?.status === 'completed' || data?.status === 'skipped') {
      navigate('/inbox', { replace: true })
    }
  }, [data?.status, navigate])

  if (isLoading) {
    return (
      <div
        role="status"
        className="min-h-screen flex items-center justify-center text-xs text-muted-foreground"
      >
        Carregando…
      </div>
    )
  }

  if (isError || !data) {
    return (
      <main className="min-h-screen flex items-center justify-center px-4">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium">Não foi possível carregar o onboarding</p>
          <p className="text-xs text-muted-foreground">Verifique sua conexão e recarregue.</p>
        </div>
      </main>
    )
  }

  // not_started vem com current_step=0, mas visualmente é o passo 1 (conectar).
  const step = !data.current_step || data.current_step < 1 ? 1 : data.current_step

  return (
    <OnboardingShell currentStep={step}>
      {step === 1 && <OnboardingStep1Connect state={data} />}
      {step === 2 && <Stub label="Passo 2 — Tags" />}
      {step === 3 && <Stub label="Passo 3 — Categorias" />}
    </OnboardingShell>
  )
}

function Stub({ label }: { label: string }) {
  return (
    <div className="border border-dashed border-border rounded-md p-6 text-center text-sm text-muted-foreground">
      {label} — em construção (Fatia 4)
    </div>
  )
}
