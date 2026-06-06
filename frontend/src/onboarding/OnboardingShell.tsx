import { useState } from 'react'
import { useNavigate } from 'react-router'
import { WalletLogo } from '../components/WalletLogo'
import { Button } from '../components/Button'
import { StepIndicator, type Step } from './StepIndicator'
import { useSkipOnboarding } from './useOnboarding'

const STEPS: readonly Step[] = [
  { id: 'connect',  label: 'Conectar' },
  { id: 'analysis', label: 'Análise'  },
  { id: 'tags',     label: 'Tags'     },
]

/**
 * Container do fluxo de onboarding (RF22).
 * - Header com logo + botão "Pular onboarding"
 * - Step indicator
 * - Slot pro conteúdo do passo atual
 * - Container max-w-2xl pra manter foco
 *
 * Não tem AppLayout (sem sidebar/topbar/bottomnav) — RF22.5 design spec.
 */
export function OnboardingShell({
  currentStep,
  children,
}: {
  currentStep: number
  children: React.ReactNode
}) {
  const navigate = useNavigate()
  const skip = useSkipOnboarding()
  const [confirming, setConfirming] = useState(false)

  const handleSkipAll = async () => {
    await skip.mutateAsync()
    navigate('/inbox', { replace: true })
  }

  return (
    <div className="min-h-screen bg-background text-foreground">
      {/* Header */}
      <header className="flex items-center justify-between px-4 py-3 border-b border-border">
        <WalletLogo />
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setConfirming(true)}
          disabled={skip.isPending}
          data-testid="skip-onboarding"
        >
          Pular onboarding
        </Button>
      </header>

      {/* Main */}
      <main className="max-w-2xl mx-auto px-4 py-8 space-y-8">
        <StepIndicator steps={STEPS} current={currentStep} />
        {children}
      </main>

      {/* Confirmação de skip total */}
      {confirming && (
        <div
          className="fixed inset-0 bg-background/80 flex items-center justify-center px-4 z-50"
          role="dialog"
          aria-modal="true"
        >
          <div className="max-w-sm w-full bg-card border border-border rounded-md p-5 space-y-4">
            <div className="space-y-1">
              <p className="font-medium text-sm">Pular o onboarding?</p>
              <p className="text-xs text-muted-foreground">
                Você pode rodar de novo depois pela seção "Mais".
              </p>
            </div>
            <div className="flex justify-end gap-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setConfirming(false)}
                disabled={skip.isPending}
              >
                Voltar
              </Button>
              <Button
                variant="primary"
                size="sm"
                onClick={handleSkipAll}
                disabled={skip.isPending}
                data-testid="skip-onboarding-confirm"
              >
                {skip.isPending ? 'Pulando…' : 'Pular agora'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
