import { useOnboarding } from './useOnboarding'
import { OnboardingStep1Connect } from './OnboardingStep1Connect'
import { OnboardingStep2Tags } from './OnboardingStep2Tags'
import { OnboardingStep3Categories } from './OnboardingStep3Categories'

export function OnboardingPage() {
  const { state, loading, error, advanceStep } = useOnboarding()

  if (loading) return <OnboardingShell><div className="text-fg-muted">Carregando…</div></OnboardingShell>
  if (error) return <OnboardingShell><div className="text-danger">Erro: {error}</div></OnboardingShell>

  const step = state?.current_step ?? 1

  const handleComplete = () => {
    window.location.href = '/'
  }

  return (
    <OnboardingShell step={step}>
      {step === 1 && <OnboardingStep1Connect onAdvance={() => advanceStep(2)} />}
      {step === 2 && <OnboardingStep2Tags onAdvance={() => advanceStep(3)} />}
      {step === 3 && <OnboardingStep3Categories onComplete={handleComplete} />}
    </OnboardingShell>
  )
}

function OnboardingShell({ step, children }: { step?: number; children: React.ReactNode }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-bg">
      <div className="w-full max-w-md px-6 flex flex-col gap-8">
        {step != null && <OnboardingProgress step={step} />}
        {children}
      </div>
    </div>
  )
}

function OnboardingProgress({ step }: { step: number }) {
  return (
    <div className="flex gap-1.5" aria-label={`Passo ${step} de 3`}>
      {[1, 2, 3].map((n) => (
        <div
          key={n}
          className={`h-1 flex-1 rounded-full ${n <= step ? 'bg-violet' : 'bg-border'}`}
        />
      ))}
    </div>
  )
}
